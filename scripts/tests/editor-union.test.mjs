import test from 'node:test';
import assert from 'node:assert/strict';
import {unionFences} from '../../docs/site/assets/editor/union.mjs';
import {freshSnapshot,serialize,readImport,validateSnapshot,clone} from '../../docs/site/assets/editor/model.mjs';
const box=(x,y,w,h=w)=>[[x,y],[x+w,y],[x+w,y+h],[x,y+h],[x,y]];
const feature=(id,rings,properties={})=>({type:'Feature',id,properties:{name:id,enabled:true,priority:0,...properties},geometry:{type:'Polygon',coordinates:rings}});
const snapshot=(...features)=>({...freshSnapshot(),features});
function area(g){return (g.type==='Polygon'?[g.coordinates]:g.coordinates).reduce((sum,rings)=>sum+rings.reduce((a,r,i)=>a+(i?-1:1)*Math.abs(r.slice(0,-1).reduce((n,p,j)=>n+p[0]*r[j+1][1]-r[j+1][0]*p[1],0)/2),0),0);}
test('overlap union removes interior edges, creates a fresh ID, preserves metadata and leaves input unchanged',()=>{
 const input=snapshot(feature('a',[box(0,0,2)],{source:'OpenStreetMap',osm_id:7,attribution:'© OpenStreetMap contributors',license:'ODbL-1.0'}),feature('b',[box(1,0,2)],{name:'Chosen',enabled:false,priority:8,custom:'value'}),feature('untouched',[box(10,0,1)]));
 const original=clone(input),{snapshot:output,index}=unionFences(input,['b','a'],'b');
 assert.deepEqual(input,original);assert.equal(index,0);assert.equal(output.features.length,2);
 const f=output.features[0];assert.equal(f.id,'union-1');assert.equal(f.geometry.type,'Polygon');assert.equal(area(f.geometry),6);assert.equal(f.geometry.coordinates[0].length,5);
 assert.equal(f.properties.name,'Chosen');assert.equal(f.properties.enabled,false);assert.equal(f.properties.priority,8);assert.equal(f.properties.source,undefined);assert.equal(f.properties.osm_id,undefined);
 assert.equal(f.properties.license,'ODbL-1.0');assert.equal(f.properties.unionSources[1].properties.custom,'value');assert.deepEqual(output.features[1],input.features[2]);assert.deepEqual(output.dataset,input.dataset);
 assert.deepEqual(readImport(serialize(output)),output);
});
test('disjoint areas remain separate MultiPolygon parts with holes',()=>{
 const input=snapshot(feature('a',[box(0,0,4),box(1,1,2)]),feature('b',[box(10,0,2)]));
 const f=unionFences(input,['a','b'],'a').snapshot.features[0];assert.equal(f.geometry.type,'MultiPolygon');assert.equal(f.geometry.coordinates.length,2);assert.equal(f.geometry.coordinates[0].length,2);assert.equal(area(f.geometry),16);
});
test('union can fill a hole and merge a shared edge',()=>{
 const input=snapshot(feature('a',[box(0,0,4),box(1,1,2)]),feature('b',[box(1,1,2)]),feature('c',[box(4,0,2,4)]));
 const f=unionFences(input,['a','b','c'],'a').snapshot.features[0];assert.equal(f.geometry.type,'Polygon');assert.equal(f.geometry.coordinates.length,1);assert.equal(area(f.geometry),24);
});
test('identical, contained and corner-touching polygons keep correct area',()=>{
 for(const [ring,expected] of [[box(0,0,2),4],[box(0.5,0.5,0.5),4],[box(2,2,1),5]]){
 const f=unionFences(snapshot(feature('a',[box(0,0,2)]),feature('b',[ring])),['a','b'],'a').snapshot.features[0];assert.equal(area(f.geometry),expected);
 }
});
test('MultiPolygon input and 100 regions preserve area and unique IDs',()=>{
 const inputs=Array.from({length:100},(_,i)=>feature(i===0?'union-1':String(i),[box(i/10,0,0.05)]));
 inputs[1].geometry={type:'MultiPolygon',coordinates:[[box(0.1,0,0.05)],[box(0.1,1,0.05)]]};
 const result=unionFences(snapshot(...inputs),inputs.map(f=>f.id),'union-1').snapshot;
 assert.equal(result.features[0].id,'union-2');assert.equal(result.features[0].geometry.coordinates.length,101);assert(Math.abs(area(result.features[0].geometry)-0.2525)<1e-10);validateSnapshot(result);
});
test('invalid or stale selections fail without changing the snapshot',()=>{
 const input=snapshot(feature('a',[box(0,0,2)]),feature('b',[box(1,0,2)])),original=clone(input);
 for(const [ids,from] of [[['a'],'a'],[['a','a'],'a'],[['a','missing'],'a'],[['a','b'],'missing']])assert.throws(()=>unionFences(input,ids,from));
 assert.deepEqual(input,original);
});
test('computed rings exceeding editor limits are rejected atomically',()=>{
 const circle=(x)=>{const points=Array.from({length:950},(_,i)=>[x+Math.cos(i*2*Math.PI/950),Math.sin(i*2*Math.PI/950)]);return [...points,points[0]];};
 const input=snapshot(feature('a',[circle(0)]),feature('b',[circle(1)])),original=clone(input);
 assert.throws(()=>unionFences(input,['a','b'],'a'),/1,000 vertices/);assert.deepEqual(input,original);
});
