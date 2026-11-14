import {clone,classify,validateGeometry,MAX_BYTES} from './model.mjs';

const same=(a,b)=>a[0]===b[0]&&a[1]===b[1];
function positions(geometry) {
  if(!Array.isArray(geometry)||geometry.length<2)throw new Error('Incomplete boundary geometry.');
  return geometry.map(p=>{
    if(!p||!Number.isFinite(p.lon)||!Number.isFinite(p.lat))throw new Error('Incomplete boundary coordinates.');
    return [p.lon,p.lat];
  });
}
// Stitch complete OSM way members by shared endpoints, allowing reversed ways.
function stitch(lines) {
  const pending=lines.map(clone),rings=[];
  while(pending.length){
    let ring=pending.shift();
    while(!same(ring[0],ring.at(-1))){
      const i=pending.findIndex(line=>same(ring.at(-1),line[0])||same(ring.at(-1),line.at(-1)));
      if(i<0)throw new Error('Boundary contains unclosed or incomplete members.');
      let line=pending.splice(i,1)[0];if(!same(ring.at(-1),line[0]))line.reverse();
      ring.push(...line.slice(1));
      if(ring.length>1001)throw new Error('Boundary exceeds the editor vertex limit.');
    }
    rings.push(ring);
  }
  return rings;
}
function osmGeometry(element){
  if(element.type==='way')return {type:'Polygon',coordinates:[positions(element.geometry)]};
  if(element.type!=='relation'||!['multipolygon','boundary'].includes(element.tags?.type)||!Array.isArray(element.members))throw new Error('No polygon boundary.');
  const outer=[],inner=[];
  for(const member of element.members){
    if(member.type==='node'&&['label','admin_centre'].includes(member.role))continue;
    if(member.type!=='way'||!['outer','inner',''].includes(member.role??''))throw new Error('Unsupported boundary member.');
    (member.role==='inner'?inner:outer).push(positions(member.geometry));
  }
  const shells=stitch(outer).map(ring=>[ring]);if(!shells.length)throw new Error('No outer boundary.');
  for(const hole of stitch(inner)){
    const containers=shells.filter(rings=>classify(hole[0],rings[0])==='inside');
    if(containers.length!==1)throw new Error('Ambiguous or invalid hole.');
    containers[0].push(hole);
  }
  return shells.length===1?{type:'Polygon',coordinates:shells[0]}:{type:'MultiPolygon',coordinates:shells};
}
export function containsPoint(geometry,point){
  const parts=geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;
  return parts.some(rings=>classify(point,rings[0])!=='outside'&&rings.slice(1).every(hole=>classify(point,hole)==='outside'));
}
function ringArea(ring){
  const o=ring[0];let area=0;
  for(let i=0;i<ring.length-1;i++)area+=(ring[i][0]-o[0])*(ring[i+1][1]-o[1])-(ring[i+1][0]-o[0])*(ring[i][1]-o[1]);
  return Math.abs(area/2);
}
function area(geometry){
  const parts=geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;
  return parts.reduce((total,rings)=>total+ringArea(rings[0])-rings.slice(1).reduce((n,r)=>n+ringArea(r),0),0);
}
export function placeFromResponse(data,point){
  if(!data||data.remark||!Array.isArray(data.elements)||data.elements.length>500)throw new Error('The boundary service returned incomplete data. Try again later or draw the fence manually.');
  const candidates=[];
  for(const element of data.elements){
    const tags=element.tags??{};
    const physical=['amenity','leisure','tourism','historic','landuse','shop','office','man_made'].some(key=>tags[key]);
    if(tags.boundary==='administrative'||tags.indoor!==undefined||tags.room!==undefined||!(tags.building&&tags.building!=='no'||tags.name&&physical))continue;
    if(!Number.isSafeInteger(element.id)||element.id<=0)continue;
    try{
      const geometry=osmGeometry(element);validateGeometry(geometry);
      if(!containsPoint(geometry,point))continue;
      const size=area(geometry);
      // Avoid unexpectedly adding an entire enormous landmass or regional boundary.
      const squareMeters=size*111320**2*Math.max(0.01,Math.cos(point[1]*Math.PI/180));
      if(squareMeters>25_000_000)continue;
      const name=typeof tags.name==='string'&&tags.name.trim()?tags.name.trim():`Building ${element.id}`;
      candidates.push({size,feature:{type:'Feature',id:`osm-${element.type}-${element.id}`,properties:{
        name,enabled:true,priority:0,source:'OpenStreetMap',osm_type:element.type,osm_id:element.id,
        source_url:`https://www.openstreetmap.org/${element.type}/${element.id}`,
        attribution:'© OpenStreetMap contributors',license:'ODbL-1.0'
      },geometry}});
    }catch{/* A malformed candidate must not discard another complete enclosing place. */}
  }
  candidates.sort((a,b)=>a.size-b.size||a.feature.id.localeCompare(b.feature.id));
  if(!candidates.length)throw new Error('No usable mapped place boundary contains that point. Try the center of a building or draw a fence manually.');
  return candidates[0].feature;
}
export function boundaryQuery(lat,lon){
  if(!Number.isFinite(lat)||!Number.isFinite(lon)||Math.abs(lat)>85||Math.abs(lon)>180)throw new Error('Choose a valid map location.');
  return `[out:json][timeout:15][maxsize:8388608];is_in(${lat.toFixed(6)},${lon.toFixed(6)})->.areas;(way(pivot.areas)[name][!boundary][!indoor][!room];rel(pivot.areas)[name][type=multipolygon][!indoor][!room];way(pivot.areas)[building][!indoor][!room];rel(pivot.areas)[building][!indoor][!room];);out geom;`;
}
async function limitedJSON(response){
  if(Number(response.headers.get('content-length'))>MAX_BYTES){
    await response.body?.cancel();
    throw new Error('Boundary response exceeds 5 MB. Draw a smaller fence manually.');
  }
  const reader=response.body?.getReader();if(!reader)throw new Error('The boundary service returned no data.');
  const chunks=[];let total=0;
  try{
    while(true){const {done,value}=await reader.read();if(done)break;total+=value.byteLength;if(total>MAX_BYTES)throw new Error('Boundary response exceeds 5 MB.');chunks.push(value);}
  }catch(error){await reader.cancel().catch(()=>{});throw error;}finally{reader.releaseLock();}
  const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  try{return JSON.parse(new TextDecoder().decode(bytes));}catch{throw new Error('The boundary service returned invalid data. Try again later.');}
}
export class PlaceLookup {
  constructor({endpoint,minimumIntervalMs=2000,timeoutMs=20000},fetcher=globalThis.fetch,now=()=>Date.now()){
    if(!Number.isFinite(minimumIntervalMs)||!Number.isFinite(timeoutMs)||timeoutMs<=0)throw new Error('Invalid boundary service configuration.');
    const url=new URL(endpoint);if(url.protocol!=='https:'||url.username||url.password)throw new Error('Boundary service must use HTTPS.');
    this.endpoint=url;this.interval=Math.max(2000,minimumIntervalMs);this.timeout=Math.max(1,Math.min(30000,timeoutMs));
    this.fetcher=fetcher.bind(globalThis);this.now=now;this.lastStart=-Infinity;this.cache=new Map();this.busy=false;
  }
  async lookup(lat,lon,signal){
    const query=boundaryQuery(lat,lon),key=`${lat.toFixed(6)},${lon.toFixed(6)}`;
    if(signal?.aborted)throw new DOMException('Cancelled','AbortError');
    const cached=this.cache.get(key);
    if(cached&&this.now()-cached.savedAt<300000)return placeFromResponse(cached.data,[lon,lat]);
    if(this.busy)throw new Error('A place lookup is already running.');
    if(this.now()-this.lastStart<this.interval)throw new Error('Please wait a moment before adding another place.');
    this.busy=true;this.lastStart=this.now();
    const controller=new AbortController();let timedOut=false;
    const cancel=()=>controller.abort();signal?.addEventListener('abort',cancel,{once:true});
    const timer=setTimeout(()=>{timedOut=true;controller.abort();},this.timeout);
    try{
      const url=new URL(this.endpoint);url.searchParams.set('data',query);
      const response=await this.fetcher(url,{signal:controller.signal,headers:{Accept:'application/json'},credentials:'omit',referrerPolicy:'strict-origin-when-cross-origin'});
      if(response.status===429)throw new Error('The boundary service is busy. Please wait before trying again.');
      if(!response.ok)throw new Error(`Boundary lookup failed (${response.status}). Try again later or draw manually.`);
      const data=await limitedJSON(response);
      if(controller.signal.aborted)throw new DOMException('Cancelled','AbortError');
      if(!data.remark&&Array.isArray(data.elements)){
        if(this.cache.size>=50)this.cache.delete(this.cache.keys().next().value);
        this.cache.set(key,{data,savedAt:this.now()});
      }
      return placeFromResponse(data,[lon,lat]);
    }catch(error){
      if(timedOut)throw new Error('Place lookup timed out. Try again later or draw the fence manually.');
      if(signal?.aborted)throw new DOMException('Cancelled','AbortError');
      if(error instanceof TypeError)throw new Error('Boundary service unavailable. Check your connection or draw the fence manually.');
      throw error;
    }finally{clearTimeout(timer);signal?.removeEventListener('abort',cancel);this.busy=false;}
  }
}
