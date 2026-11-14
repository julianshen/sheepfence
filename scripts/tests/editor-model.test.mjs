import test from 'node:test';
import assert from 'node:assert/strict';
import {clone,freshSnapshot,closeRing,validateRing,validateSnapshot,readImport,serialize} from '../../docs/site/assets/editor/model.mjs';
const square=(x=10,y=20,size=0.01)=>closeRing([[x,y],[x+size,y],[x+size,y+size],[x,y+size]]);
function sample(){const s=freshSnapshot();s.features=[{type:'Feature',id:'campus',properties:{name:'Campus',enabled:true,priority:0},geometry:{type:'Polygon',coordinates:[square()]}}];return s;}

test('export repeats closure, uses longitude first and has stable bytes',()=>{
 const s=sample(),text=serialize(s);assert.equal(text,serialize(s));
 const restored=JSON.parse(text);assert.deepEqual(restored.features[0].geometry.coordinates[0][0],[10,20]);
 assert.deepEqual(restored.features[0].geometry.coordinates[0].at(-1),[10,20]);
 assert.deepEqual(validateSnapshot(restored),{regions:1,vertices:4});
});
test('rejects crossing, touching, collinear, duplicate and unclosed boundaries',()=>{
 for(const ring of [closeRing([[0,0],[1,1],[0,1],[1,0]]),closeRing([[0,0],[1,0],[2,0]]),closeRing([[0,0],[1,0],[1,0],[0,1]]),[[0,0],[1,0],[1,1],[0,1]],closeRing([[0,0],[2,0],[2,2],[1,0],[0,2]])]) assert.throws(()=>validateRing(ring));
});
test('supports tiny noncollinear polygons and concave rings',()=>{
 validateRing(square(0,0,1e-8));validateRing(closeRing([[0,0],[3,0],[3,3],[1,1],[0,3]]));
});
test('rejects invalid coordinates and unsplit antimeridian',()=>{
 for(const p of [[181,0],[0,91],[true,0],[null,0],[1,2,3]])assert.throws(()=>validateRing(closeRing([p,[1,0],[0,1]])));
 assert.throws(()=>validateRing(closeRing([[179,0],[-179,0],[-179,1],[179,1]])),/antimeridian/);
});
test('valid holes and multipolygon parts survive import and export',()=>{
 const s=sample();s.features[0].geometry={type:'MultiPolygon',coordinates:[[square(),square(10.002,20.002,0.002)],[square(10.1,20.1)]]};
 assert.deepEqual(readImport(serialize(s)),s);assert.equal(validateSnapshot(s).vertices,12);
});
test('rejects holes outside, touching, crossing, overlapping or nested',()=>{
 for(const holes of [[square(11,20)],[square(10,20.002,0.002)],[square(10.009,20.002,0.002)],[square(10.002,20.002,0.004),square(10.003,20.003,0.002)],[square(10.002,20.002,0.003),square(10.004,20.003,0.003)]]){
  const s=sample();s.features[0].geometry.coordinates.push(...holes);assert.throws(()=>validateSnapshot(s),/holes/);
 }
});
test('metadata rejects duplicate IDs, unsafe revisions, invalid dates and property types',()=>{
 const mutations=[s=>s.features.push(clone(s.features[0])),s=>s.dataset.id='',s=>s.dataset.revision=0,s=>s.dataset.revision=1.5,s=>s.dataset.revision=Number.MAX_SAFE_INTEGER+1,s=>s.dataset.generatedAt='2026-02-30T00:00:00Z',s=>s.features[0].properties.enabled='true',s=>s.features[0].properties.priority=0.5,s=>s.features[0].properties.name=5];
 for(const change of mutations){const s=sample();change(s);assert.throws(()=>validateSnapshot(s));}
});
test('plain GeoJSON gets metadata and unique generated IDs without changing geometry',()=>{
 const source=sample();delete source.dataset;delete source.geofenceSchema;source.features.push({...clone(source.features[0]),id:'fence-1'});delete source.features[0].id;
 const converted=readImport(JSON.stringify(source),freshSnapshot().dataset);
 assert.equal(converted.geofenceSchema,1);assert.notEqual(converted.features[0].id,converted.features[1].id);
 assert.deepEqual(converted.features[0].geometry,source.features[0].geometry);
 const single=readImport(JSON.stringify({...sample().features[0],id:123}));assert.equal(single.features[0].id,'123');
});
test('invalid mixed import rejects as a whole and never mutates existing data',()=>{
 const original=sample(),text=serialize(original),bad=clone(original);bad.features.push({type:'Feature',id:'point',properties:{},geometry:{type:'Point',coordinates:[10,20]}});
 assert.throws(()=>readImport(JSON.stringify(bad),original.dataset),/Polygon/);assert.equal(serialize(original),text);
 assert.throws(()=>readImport('{broken'),/JSON/);
});
test('100 fences with 100 edges fit authoring limits',()=>{
 const s=freshSnapshot();for(let i=0;i<100;i++){
  const ring=closeRing(Array.from({length:100},(_,j)=>[10+i*0.02+0.005*Math.cos(j*2*Math.PI/100),20+0.005*Math.sin(j*2*Math.PI/100)]));
  s.features.push({type:'Feature',id:`f-${i}`,properties:{},geometry:{type:'Polygon',coordinates:[ring]}});
 }
 assert.equal(validateSnapshot(s).vertices,10000);assert.ok(serialize(s).length<5_000_000);
 s.features.push({...clone(s.features[0]),id:'too-many'});assert.throws(()=>validateSnapshot(s),/100/);
});
test('empty snapshot is valid and byte/ring limits fail explicitly',()=>{
 assert.equal(validateSnapshot(freshSnapshot()).regions,0);
 assert.throws(()=>readImport(' '.repeat(5_000_001)),/5 MB/);
 assert.throws(()=>validateRing(Array.from({length:1002},()=>[0,0])),/1,000/);
 const s=sample();s.features[0].properties.extra='x'.repeat(5_000_000);assert.throws(()=>serialize(s),/5 MB/);
});
test('plain GeoJSON cannot bypass schema or silently fix SDK IDs',()=>{
 const s=sample();s.features[0].id=123;assert.throws(()=>readImport(JSON.stringify(s)),/string ID/);
 const bad=sample();bad.geofenceSchema=2;assert.throws(()=>readImport(JSON.stringify(bad)),/geofenceSchema/);
});
