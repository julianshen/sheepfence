import test from 'node:test';
import assert from 'node:assert/strict';
import {expandToRoads,roadSearch,roadQuery} from '../../docs/site/assets/editor/roads.mjs';
import {freshSnapshot,clone,validateSnapshot} from '../../docs/site/assets/editor/model.mjs';
const p=(x,y)=>[x/111320,y/111320];
const ring=(x,y,size)=>[p(x,y),p(x+size,y),p(x+size,y+size),p(x,y+size),p(x,y)];
function input(rings=[ring(-20,-20,40)]){return {...freshSnapshot(),features:[{type:'Feature',id:'fence',properties:{name:'Fence',enabled:false,priority:7},geometry:{type:'Polygon',coordinates:rings}}]};}
function network(lines,tags={}){
 const ids=new Map();let next=1;
 return {elements:lines.map((points,i)=>({type:'way',id:i+1,tags:{highway:'residential',...tags},nodes:points.map(v=>{const key=v.join(',');if(!ids.has(key))ids.set(key,next++);return ids.get(key);}),geometry:points.map(([x,y])=>({lon:x/111320,lat:y/111320}))}))};
}
const outer=[[-100,-100],[0,-100],[100,-100],[100,100],[0,100],[-100,100],[-100,-100]];
const resultArea=f=>{const parts=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;return parts.reduce((n,rings)=>n+rings.reduce((s,r,j)=>s+(j?-1:1)*Math.abs(r.slice(0,-1).reduce((a,p,i)=>a+p[0]*r[i+1][1]-r[i+1][0]*p[1],0)/2),0),0)*111320**2;};
test('expands to surrounding centerlines, preserves ID/properties and does not mutate source',()=>{
 const source=input(),before=clone(source),result=expandToRoads(source,0,network([outer]),150);
 assert.deepEqual(source,before);assert.equal(result.snapshot.features[0].id,'fence');assert.equal(result.snapshot.features[0].properties.enabled,false);assert.equal(result.snapshot.features[0].properties.priority,7);assert(Math.abs(resultArea(result.snapshot.features[0])-40000)<0.01);assert.equal(result.addedSquareMeters,38400);validateSnapshot(result.snapshot);
});
test('preserves holes, other fences and original dataset metadata',()=>{
 const source=input([ring(-20,-20,40),ring(-5,-5,10)]);source.features.push({...clone(source.features[0]),id:'other'});
 const result=expandToRoads(source,0,network([outer]),150).snapshot;
 assert.equal(result.features[0].geometry.coordinates.length,2);assert(Math.abs(resultArea(result.features[0])-39900)<0.01);assert.deepEqual(result.features[1],source.features[1]);assert.deepEqual(result.dataset,source.dataset);
});
test('fence spanning a mapped junction expands to the union of adjacent road blocks',()=>{
 const result=expandToRoads(input(),0,network([outer,[[0,-100],[0,100]]]),150);
 assert(Math.abs(resultArea(result.snapshot.features[0])-40000)<0.01);
});
test('a fence wholly within one block does not expand across its adjacent road',()=>{
 const result=expandToRoads(input([ring(-60,-10,20)]),0,network([outer,[[0,-100],[0,100]]]),150);
 assert(Math.abs(resultArea(result.snapshot.features[0])-20000)<0.01);
});
test('dead ends do not prevent a complete block boundary',()=>{
 const result=expandToRoads(input(),0,network([outer,[[0,-100],[0,-50]]]),150);assert(Math.abs(resultArea(result.snapshot.features[0])-40000)<0.01);
});
test('nested disconnected road loops choose the nearest enclosing block',()=>{
 const inner=[[-40,-40],[40,-40],[40,40],[-40,40],[-40,-40]];
 const result=expandToRoads(input(),0,network([outer,inner]),150);assert(Math.abs(resultArea(result.snapshot.features[0])-6400)<0.01);
});
test('missing roads, disconnected crossings and partial responses fail without changing data',()=>{
 const source=input(),before=clone(source);
 assert.throws(()=>expandToRoads(source,0,network([outer.slice(0,-1)]),150),/roadNoEnclosure/);
 assert.throws(()=>expandToRoads(source,0,network([outer,[[-150,0],[150,0]]]),150),/roadTopology/);
 assert.throws(()=>expandToRoads(source,0,{elements:[],remark:'timeout'},150),/roadIncomplete/);
 const bad=network([outer]);bad.elements[0].nodes.pop();assert.throws(()=>expandToRoads(source,0,bad,150),/roadIncomplete/);assert.deepEqual(source,before);
});
test('bridges, tunnels, elevated roads, paths and driveways are not ground road boundaries',()=>{
 for(const tags of [{bridge:'yes'},{bridge:'viaduct'},{tunnel:'building_passage'},{layer:'1'},{highway:'footway'},{service:'driveway'},{area:'yes'}])assert.throws(()=>expandToRoads(input(),0,network([outer],tags),150),/roadNoEnclosure/);
});
test('expansion limit is checked against the whole result, not just its bounding box',()=>{
 const far=[[-180,-180],[180,-180],[180,180],[-180,180],[-180,-180]];
 assert.throws(()=>expandToRoads(input(),0,network([far]),150),/roadTooFar/);
});
test('search is bounded, rejects unsupported input and encodes only a numeric bbox',()=>{
 const geometry=input().features[0].geometry,search=roadSearch(geometry,150),q=roadQuery(search);assert.match(q,/out geom/);assert.match(q,/residential/);assert.doesNotMatch(q,/fence|Feature|coordinates/);
 for(const limit of [NaN,0,1001,'100'])assert.throws(()=>roadSearch(geometry,limit),/roadLimit/);
 assert.throws(()=>roadSearch({type:'Polygon',coordinates:[ring(0,0,2100)]},150),/roadRange/);
 assert.throws(()=>roadQuery({bbox:[0,0,1,'x']}),/roadRange/);
});
test('OSM provenance is preserved without claiming the expanded shape is an original OSM object',()=>{
 const source=input();Object.assign(source.features[0].properties,{source:'OpenStreetMap',osm_id:9,osm_type:'way',source_url:'https://www.openstreetmap.org/way/9'});
 const props=expandToRoads(source,0,network([outer]),150).snapshot.features[0].properties;
 assert.equal(props.source,undefined);assert.equal(props.originalSource.osm_id,9);assert.equal(props.roadAlignment.method,'surrounding-road-centerlines');assert.equal(props.license,'ODbL-1.0');
});
test('multiple separated parts expand independently without joining across roads',()=>{
 const source=input();source.features[0].geometry={type:'MultiPolygon',coordinates:[[ring(-120,-10,20)],[ring(100,-10,20)]]};
 const left=[[-150,-50],[-50,-50],[-50,50],[-150,50],[-150,-50]],right=[[50,-50],[150,-50],[150,50],[50,50],[50,-50]];
 const result=expandToRoads(source,0,network([left,right]),100).snapshot.features[0];assert.equal(result.geometry.type,'MultiPolygon');assert.equal(result.geometry.coordinates.length,2);assert(Math.abs(resultArea(result)-20000)<0.01);
});
test('a road block wholly inside an existing hole is not filled',()=>{
 const source=input([ring(-30,-30,60),ring(-20,-20,40)]),inner=[[-10,-10],[10,-10],[10,10],[-10,10],[-10,-10]];
 const result=expandToRoads(source,0,network([outer,inner]),150).snapshot.features[0];assert.equal(result.geometry.coordinates.length,2);assert(Math.abs(resultArea(result)-38400)<0.01);
});
