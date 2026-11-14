import * as bundled from '../vendor/polygon-clipping/polygon-clipping.umd.js';
import {clone,polygons,validateGeometry,validateSnapshot} from './model.mjs?v=roads-1';
const clip=bundled.default??globalThis.polygonClipping;
const ROAD_TYPES=new Set(['motorway','trunk','primary','secondary','tertiary','unclassified','residential','living_street','service','motorway_link','trunk_link','primary_link','secondary_link','tertiary_link']);
const fail=code=>{throw new Error(code);};
const signedArea=r=>{const o=r[0];return r.slice(0,-1).reduce((a,p,i)=>a+(p[0]-o[0])*(r[i+1][1]-o[1])-(r[i+1][0]-o[0])*(p[1]-o[1]),0)/2;};
const area=multi=>multi.reduce((sum,rings)=>sum+rings.reduce((n,r,i)=>n+(i?-1:1)*Math.abs(signedArea(r)),0),0);
const cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);

export function roadSearch(geometry,limit){
  validateGeometry(geometry);
  if(!Number.isFinite(limit)||limit<25||limit>1000)fail('roadLimit');
  const parts=geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;
  const points=parts.flat(2);if(points.length>1200)fail('roadComplexity');
  const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
  const west=Math.min(...xs),east=Math.max(...xs),south=Math.min(...ys),north=Math.max(...ys);
  if(Math.max(Math.abs(south),Math.abs(north))>80||east-west>1)fail('roadRange');
  const origin=[(west+east)/2,(south+north)/2],scale=[111320*Math.cos(origin[1]*Math.PI/180),111320];
  if((east-west)*scale[0]>2000||(north-south)*scale[1]>2000)fail('roadRange');
  const margin=limit+50,bbox=[south-margin/scale[1],west-margin/scale[0],north+margin/scale[1],east+margin/scale[0]];
  if(bbox[1]<-180||bbox[3]>180)fail('roadRange');
  return {bbox,origin,scale,limit};
}
export function roadQuery(search){
  const {bbox}=search;
  if(!Array.isArray(bbox)||bbox.length!==4||!bbox.every(Number.isFinite)||bbox[0]>=bbox[2]||bbox[1]>=bbox[3]||bbox[0]<-90||bbox[2]>90||bbox[1]<-180||bbox[3]>180)fail('roadRange');
  return `[out:json][timeout:15][maxsize:8388608];way[highway~"^(${[...ROAD_TYPES].join('|')})$"][area!=yes][bridge!~"^(yes|viaduct|movable|cantilever|covered|trestle|aqueduct)$"][tunnel!=yes](${bbox.map(n=>n.toFixed(7)).join(',')});out geom;`;
}
function roadFaces(data,search){
  if(!data||data.remark||!Array.isArray(data.elements)||data.elements.length>600)fail('roadIncomplete');
  const nodes=new Map(),edges=new Map(), {bbox,origin,scale}=search;
  const inside=p=>p[0]>=bbox[1]&&p[0]<=bbox[3]&&p[1]>=bbox[0]&&p[1]<=bbox[2];
  const project=p=>[(p[0]-origin[0])*scale[0],(p[1]-origin[1])*scale[1]];
  for(const way of data.elements){
    const t=way.tags??{};
    if(way.type!=='way'||!ROAD_TYPES.has(t.highway)||t.area==='yes'||(t.bridge&&t.bridge!=='no')||(t.tunnel&&t.tunnel!=='no')||(t.layer!==undefined&&t.layer!=='0')||['driveway','parking_aisle'].includes(t.service))continue;
    if(!Number.isSafeInteger(way.id)||!Array.isArray(way.nodes)||way.nodes.length<2||way.nodes.length!==way.geometry?.length)fail('roadIncomplete');
    const points=way.geometry.map(p=>{if(!p||!Number.isFinite(p.lon)||!Number.isFinite(p.lat)||Math.abs(p.lon)>180||Math.abs(p.lat)>90)fail('roadIncomplete');return [p.lon,p.lat];});
    for(let i=0;i<points.length;i++){
      const id=way.nodes[i];if(!Number.isSafeInteger(id)||id<=0)fail('roadIncomplete');
      if(!inside(points[i]))continue;
      const existing=nodes.get(id);
      if(existing&&(existing.geo[0]!==points[i][0]||existing.geo[1]!==points[i][1]))fail('roadTopology');
      if(!existing)nodes.set(id,{geo:points[i],p:project(points[i]),adj:new Set()});
    }
    for(let i=1;i<points.length;i++){
      const a=way.nodes[i-1],b=way.nodes[i];if(a===b||!inside(points[i-1])||!inside(points[i]))continue;
      if(points[i-1][0]===points[i][0]&&points[i-1][1]===points[i][1])fail('roadTopology');
      const key=a<b?`${a}:${b}`:`${b}:${a}`;
      if(!edges.has(key))edges.set(key,{a,b,ways:new Set()});edges.get(key).ways.add(way.id);
      nodes.get(a).adj.add(b);nodes.get(b).adj.add(a);
    }
    if(edges.size>3000||nodes.size>4000)fail('roadComplexity');
  }
  // Real OSM node IDs establish connectivity. Never invent a junction at an overpass.
  const segments=[...edges.values()];
  const on=(a,b,p)=>Math.abs(cross(a,b,p))<1e-7&&p[0]>=Math.min(a[0],b[0])-1e-8&&p[0]<=Math.max(a[0],b[0])+1e-8&&p[1]>=Math.min(a[1],b[1])-1e-8&&p[1]<=Math.max(a[1],b[1])+1e-8;
  for(let i=0;i<segments.length;i++)for(let j=i+1;j<segments.length;j++){
    const u=segments[i],v=segments[j],a=nodes.get(u.a).p,b=nodes.get(u.b).p,c=nodes.get(v.a).p,d=nodes.get(v.b).p;
    const shared=u.a===v.a||u.a===v.b||u.b===v.a||u.b===v.b;
    if(shared){
      const otherU=(u.a===v.a||u.a===v.b)?b:a,otherV=(v.a===u.a||v.a===u.b)?d:c;
      if(on(a,b,otherV)||on(c,d,otherU))fail('roadTopology');
      continue;
    }
    if(Math.max(a[0],b[0])<Math.min(c[0],d[0])||Math.max(c[0],d[0])<Math.min(a[0],b[0])||Math.max(a[1],b[1])<Math.min(c[1],d[1])||Math.max(c[1],d[1])<Math.min(a[1],b[1]))continue;
    if((cross(a,b,c)*cross(a,b,d)<0&&cross(c,d,a)*cross(c,d,b)<0)||on(a,b,c)||on(a,b,d)||on(c,d,a)||on(c,d,b))fail('roadTopology');
  }
  // Remove graph bridges, including dead-end streets, before walking bounded faces.
  let clock=0;const entered=new Map(),low=new Map(),bridges=[];
  function visit(id,parent){entered.set(id,++clock);low.set(id,clock);
    for(const other of nodes.get(id).adj){if(other===parent)continue;
      if(!entered.has(other)){visit(other,id);low.set(id,Math.min(low.get(id),low.get(other)));if(low.get(other)>entered.get(id))bridges.push([id,other]);}
      else low.set(id,Math.min(low.get(id),entered.get(other)));
    }
  }
  for(const id of nodes.keys())if(!entered.has(id))visit(id,null);
  for(const [a,b] of bridges){nodes.get(a).adj.delete(b);nodes.get(b).adj.delete(a);}
  const sorted=new Map([...nodes].map(([id,n])=>[id,[...n.adj].sort((a,b)=>Math.atan2(nodes.get(a).p[1]-n.p[1],nodes.get(a).p[0]-n.p[0])-Math.atan2(nodes.get(b).p[1]-n.p[1],nodes.get(b).p[0]-n.p[0]))]));
  const visited=new Set(),faces=[];
  for(const [start,list] of sorted)for(const first of list){
    if(visited.has(`${start}:${first}`))continue;
    let a=start,b=first;const ring=[],wayIDs=new Set();
    do{
      const key=`${a}:${b}`;if(visited.has(key)||ring.length>6000)fail('roadTopology');visited.add(key);ring.push(nodes.get(a).p);
      const edge=edges.get(a<b?`${a}:${b}`:`${b}:${a}`);for(const id of edge.ways)wayIDs.add(id);
      const around=sorted.get(b),index=around.indexOf(a),next=around[(index-1+around.length)%around.length];a=b;b=next;
    }while(a!==start||b!==first);
    ring.push(ring[0]);
    if(signedArea(ring)>0.01)faces.push({geometry:[[ring]],wayIDs:[...wayIDs]});
    if(faces.length>200)fail('roadComplexity');
  }
  if(!faces.length)fail('roadNoEnclosure');
  // Disconnected nested loops define holes in the enclosing face, not overlapping blocks.
  faces.sort((a,b)=>area(a.geometry)-area(b.geometry));
  return faces.map((face,i)=>{
    const children=faces.slice(0,i).filter(other=>!clip.difference(other.geometry,face.geometry).length);
    return {...face,wayIDs:[...new Set([...face.wayIDs,...children.flatMap(f=>f.wayIDs)])],geometry:children.length?clip.difference(face.geometry,...children.map(f=>f.geometry)):face.geometry};
  });
}
function bufferShells(shells,limit){
  limit-=0.0001; // Keep generated-buffer rounding inside the requested distance.
  const pieces=[...shells];
  for(const [ring] of shells)for(let i=0;i<ring.length-1;i++){
    const a=ring[i],b=ring[i+1],dx=b[0]-a[0],dy=b[1]-a[1],length=Math.hypot(dx,dy);if(!length)continue;
    const nx=-dy/length*limit,ny=dx/length*limit;
    pieces.push([[[a[0]+nx,a[1]+ny],[b[0]+nx,b[1]+ny],[b[0]-nx,b[1]-ny],[a[0]-nx,a[1]-ny],[a[0]+nx,a[1]+ny]]]);
    // Inscribed circles make the local-distance limit conservative, never larger than requested.
    const circle=Array.from({length:32},(_,j)=>[a[0]+limit*Math.cos(j*Math.PI/16),a[1]+limit*Math.sin(j*Math.PI/16)]);circle.push(circle[0]);pieces.push([circle]);
  }
  // Quantize only this temporary distance envelope, not fence or OSM coordinates.
  const rounded=pieces.map(rings=>rings.map(r=>r.map(p=>p.map(n=>Math.round(n*1e6)/1e6))));
  return clip.union(...rounded);
}
export function expandToRoads(snapshot,index,data,limit){
  validateSnapshot(snapshot);const feature=snapshot.features[index];if(!feature)fail('roadSelection');
  const search=roadSearch(feature.geometry,limit),{origin,scale}=search;
  const project=p=>[(p[0]-origin[0])*scale[0],(p[1]-origin[1])*scale[1]],unproject=p=>[p[0]/scale[0]+origin[0],p[1]/scale[1]+origin[1]];
  const original=polygons(feature).map(rings=>rings.map(r=>r.map(project)));
  const originalFilled=clip.union(...original),faces=roadFaces(data,search);
  const selected=faces.filter(face=>area(clip.intersection(face.geometry,originalFilled))>1e-8);
  if(!selected.length)fail('roadNoEnclosure');
  let expanded=clip.union(...selected.map(f=>f.geometry));
  if(clip.difference(originalFilled,expanded).length)fail('roadNoEnclosure');
  const holes=original.flatMap(r=>r.slice(1).map(h=>[h]));
  if(holes.length){const exclusions=clip.difference(clip.union(...holes),originalFilled);if(exclusions.length)expanded=clip.difference(expanded,exclusions);}
  const allowed=bufferShells(original.map(r=>[r[0]]),limit);
  if(clip.difference(expanded,allowed).length)fail('roadTooFar');
  const before=area(originalFilled),after=area(expanded);
  if(after-before<0.01)fail('roadUnchanged');
  const coordinates=expanded.map(rings=>rings.map(r=>r.map(unproject)));
  const next=clone(snapshot),result=next.features[index];result.geometry=coordinates.length===1?{type:'Polygon',coordinates:coordinates[0]}:{type:'MultiPolygon',coordinates};
  // A modified feature is no longer an unmodified OSM object. Preserve its provenance separately.
  const properties=result.properties;
  if(properties.source==='OpenStreetMap'){
    properties.originalSource={source:properties.source,osm_type:properties.osm_type,osm_id:properties.osm_id,source_url:properties.source_url};
    for(const key of ['source','osm_type','osm_id','source_url'])delete properties[key];
  }
  const wayIDs=[...new Set(selected.flatMap(f=>f.wayIDs))].sort((a,b)=>a-b);
  properties.roadAlignment={source:'OpenStreetMap',method:'surrounding-road-centerlines',wayIDs,maximumExpansionMeters:limit};
  for(const [key,value] of [['attribution','© OpenStreetMap contributors'],['license','ODbL-1.0']]){
    const current=typeof properties[key]==='string'?properties[key]:'';properties[key]=current.includes(value)?current:current?current+'; '+value:value;
  }
  delete result.bbox;validateSnapshot(next);
  return {snapshot:next,index,addedSquareMeters:Math.round(after-before),roadCount:wayIDs.length};
}
