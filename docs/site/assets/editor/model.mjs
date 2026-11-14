import {t} from './i18n.mjs?v=l10n-1';
// Browser-side authoring checks mirror the SDK's coordinate-linear topology rules.
// The Swift importer remains the authoritative validator for installed snapshots.
export const MAX_BYTES = 5_000_000;
export const MAX_VERTICES = 10_000;
export const clone = value => JSON.parse(JSON.stringify(value));
const fail = message => { throw new Error(message); };
const same = (a, b) => a[0] === b[0] && a[1] === b[1];
const cross = (a, b, c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
function orient(a,b,c) {
  const scale = Math.max(Math.abs(b[0]-a[0])+Math.abs(b[1]-a[1]),1e-300)*Math.max(Math.abs(c[0]-a[0])+Math.abs(c[1]-a[1]),1e-300);
  const value = cross(a,b,c);
  return Math.abs(value) <= (64*Number.EPSILON+1e-18)*scale ? 0 : Math.sign(value);
}
function onSegment(p,a,b) {
  const dx=Math.abs(b[0]-a[0]), dy=Math.abs(b[1]-a[1]);
  const tolerance=64*Number.EPSILON*Math.max(dx+dy,1e-300)+1e-18*(dx+dy+1);
  return orient(a,b,p)===0 && p[0]>=Math.min(a[0],b[0])-tolerance && p[0]<=Math.max(a[0],b[0])+tolerance && p[1]>=Math.min(a[1],b[1])-tolerance && p[1]<=Math.max(a[1],b[1])+tolerance;
}
function intersects(a,b,c,d) {
  const [o1,o2,o3,o4]=[orient(a,b,c),orient(a,b,d),orient(c,d,a),orient(c,d,b)];
  return (o1!==o2 && o3!==o4) || onSegment(c,a,b) || onSegment(d,a,b) || onSegment(a,c,d) || onSegment(b,c,d);
}
function ringsIntersect(a,b) {
  for(let i=0;i<a.length-1;i++) for(let j=0;j<b.length-1;j++) if(intersects(a[i],a[i+1],b[j],b[j+1])) return true;
  return false;
}
export function classify(p,ring) {
  let inside=false;
  for(let i=0,j=ring.length-2;i<ring.length-1;j=i++) {
    const a=ring[i],b=ring[j];
    if(onSegment(p,a,b)) return 'boundary';
    if((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]) inside=!inside;
  }
  return inside?'inside':'outside';
}
export function validateRing(ring, label=t('Ring')) {
  if(!Array.isArray(ring) || ring.length<4 || ring.length>1001) fail(t`${label}: use 3–1,000 vertices plus closure.`);
  for(const p of ring) if(!Array.isArray(p) || p.length!==2 || !p.every(Number.isFinite) || Math.abs(p[0])>180 || Math.abs(p[1])>90) fail(t`${label}: positions must be [longitude, latitude] in valid ranges.`);
  if(!same(ring[0],ring.at(-1))) fail(t`${label}: ring must repeat its first position at the end.`);
  for(let i=0;i<ring.length-1;i++) {
    if(same(ring[i],ring[i+1])) fail(t`${label}: consecutive duplicate vertices are not allowed.`);
    if(Math.abs(ring[i][0]-ring[i+1][0])>180+1e-12) fail(t`${label}: split antimeridian crossings into separate polygons.`);
  }
  if(ring.slice(2,-1).every(p=>orient(ring[0],ring[1],p)===0)) fail(t`${label}: vertices must not all lie on one line.`);
  const n=ring.length-1;
  for(let i=0;i<n;i++) for(let j=i+1;j<n;j++) {
    if(j===i+1 || (i===0 && j===n-1)) continue;
    if(intersects(ring[i],ring[i+1],ring[j],ring[j+1])) fail(t`${label}: edges must not cross or touch themselves.`);
  }
  return ring;
}
export function polygons(feature) {
  return feature.geometry.type==='Polygon' ? [feature.geometry.coordinates] : feature.geometry.coordinates;
}
export function validateGeometry(geometry, label=t('Fence')) {
  if(!geometry || !['Polygon','MultiPolygon'].includes(geometry.type)) fail(t`${label}: only Polygon and MultiPolygon geometries are supported.`);
  const parts=geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;
  if(!Array.isArray(parts)||!parts.length) fail(t`${label}: geometry needs a polygon.`);
  let count=0;
  for(const [pi,rings] of parts.entries()) {
    if(!Array.isArray(rings)||!rings.length) fail(t`${label}: polygon needs an outer ring.`);
    for(const [ri,ring] of rings.entries()) {
      validateRing(ring,t`${label}, part ${pi+1}, ring ${ri+1}`);
      count+=ring.length-1;
      if(count>MAX_VERTICES) fail(t`Keep the snapshot within ${MAX_VERTICES.toLocaleString()} vertices.`);
      if(ri===0) continue;
      if(ring.slice(0,-1).some(p=>classify(p,rings[0])!=='inside') || ringsIntersect(ring,rings[0]) || rings[0].slice(0,-1).some(p=>classify(p,ring)==='inside')) fail(t`${label}: holes must be strictly inside the outer ring and not touch it.`);
      for(let j=1;j<ri;j++) if(ringsIntersect(ring,rings[j]) || classify(ring[0],rings[j])!=='outside' || classify(rings[j][0],ring)!=='outside') fail(t`${label}: holes must not overlap, nest or touch.`);
    }
  }
  return count;
}
export function validateSnapshot(value) {
  if(!value||value.type!=='FeatureCollection'||value.geofenceSchema!==1) fail(t('Use a SheepFence FeatureCollection with geofenceSchema: 1.'));
  const data=value.dataset;
  if(!data || typeof data.id!=='string' || !data.id.trim()) fail(t('Dataset ID is required.'));
  if(!Number.isSafeInteger(data.revision)||data.revision<1) fail(t('Revision must be a positive safe integer.'));
  const date=typeof data.generatedAt==='string'?new Date(data.generatedAt):new Date(NaN);
  if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(data.generatedAt)||!Number.isFinite(date.getTime())||date.toISOString().slice(0,19)!==data.generatedAt.slice(0,19)) fail(t('generatedAt must be a valid UTC date ending in Z.'));
  if(!Array.isArray(value.features)||value.features.length>100) fail(t('Use at most 100 fence features.'));
  const ids=new Set(); let total=0;
  for(const f of value.features) {
    if(!f||f.type!=='Feature'||typeof f.id!=='string'||!f.id.trim()) fail(t('Every feature needs a nonempty string ID.'));
    if(ids.has(f.id)) fail(t`Duplicate feature ID: ${f.id}`);
    ids.add(f.id);
    const p=f.properties;
    if(!p||Array.isArray(p)||typeof p!=='object') fail(t`${f.id}: properties must be an object.`);
    if(p.name!==undefined && typeof p.name!=='string') fail(t`${f.id}: name must be text.`);
    if(p.enabled!==undefined && typeof p.enabled!=='boolean') fail(t`${f.id}: enabled must be true or false.`);
    if(p.priority!==undefined && !Number.isSafeInteger(p.priority)) fail(t`${f.id}: priority must be a safe integer.`);
    total+=validateGeometry(f.geometry,f.id);
    if(total>MAX_VERTICES) fail(t`Keep the snapshot within ${MAX_VERTICES.toLocaleString()} vertices.`);
  }
  if(new TextEncoder().encode(JSON.stringify(value)).length>MAX_BYTES) fail(t('Snapshot exceeds the standard SDK 5 MB limit.'));
  return {regions:value.features.length,vertices:total};
}
export function freshSnapshot() {
  return {type:'FeatureCollection',geofenceSchema:1,dataset:{id:'com.example.fences',revision:1,generatedAt:new Date().toISOString()},features:[]};
}
export function closeRing(points) {
  const ring=clone(points);
  if(ring.length && !same(ring[0],ring.at(-1))) ring.push([...ring[0]]);
  return ring;
}
export function readImport(text, currentDataset) {
  if(new TextEncoder().encode(text).length>MAX_BYTES) fail(t('Import is larger than 5 MB.'));
  let value;
  try { value=JSON.parse(text); } catch { fail(t('The file is not valid JSON.')); }
  // Plain polygon GeoJSON receives explicit SDK metadata; unsupported features fail as a whole.
  const sdk=value?.geofenceSchema!==undefined;
  if(!sdk) {
    if(value?.type==='Feature') value={type:'FeatureCollection',features:[value]};
    if(value?.type!=='FeatureCollection'||!Array.isArray(value.features)) fail(t('Import a GeoJSON Feature or FeatureCollection.'));
    value.geofenceSchema=1;
    value.dataset=clone(currentDataset || freshSnapshot().dataset);
    const used=new Set(value.features.map(f=>String(f.id??'')).filter(Boolean));
    value.features=value.features.map((feature,i)=>{
      const f=clone(feature);
      if(f.id===undefined || f.id===null || f.id==='') {
        let id=`fence-${i+1}`; while(used.has(id)) id+='-new'; used.add(id); f.id=id;
      } else if(typeof f.id==='number' && Number.isSafeInteger(f.id)) f.id=String(f.id);
      f.properties=f.properties??{};
      return f;
    });
  }
  validateSnapshot(value);
  return value;
}
export function serialize(value) {
  validateSnapshot(value);
  const text=JSON.stringify(value,null,2)+'\n';
  if(new TextEncoder().encode(text).length>MAX_BYTES) fail(t('Formatted export exceeds 5 MB. Reduce the number of vertices.'));
  return text;
}
