import test from 'node:test';
import assert from 'node:assert/strict';
import {boundaryQuery,placeFromResponse,PlaceLookup} from '../../docs/site/assets/editor/places.mjs';
const point=[10.005,20.005];
const ring=(x=10,y=20,s=0.01)=>[{lon:x,lat:y},{lon:x+s,lat:y},{lon:x+s,lat:y+s},{lon:x,lat:y+s},{lon:x,lat:y}];
const way=(id=1,geometry=ring(),tags={building:'yes',name:'Library'})=>({type:'way',id,tags,geometry});
const response=elements=>({elements});
const endpoint='https://example.com/interpreter';

test('query is point-scoped and excludes administrative areas and indoor rooms',()=>{
 const q=boundaryQuery(20.005,10.005);assert.match(q,/is_in\(20.005000,10.005000\)/);assert.match(q,/\[!indoor\]\[!room\]/);assert.match(q,/building/);
 for(const value of [NaN,Infinity,'0);out;'])assert.throws(()=>boundaryQuery(value,10));
});
test('selects smallest physical containing place, ignoring rooms and unrelated geometry',()=>{
 const result=placeFromResponse(response([way(2,ring(9,19,2),{name:'Park',leisure:'park'}),way(),way(3,ring(10.004,20.004,0.002),{name:'Room',indoor:'room',building:'yes'}),way(4,ring(11,21),{name:'Elsewhere',building:'yes'})]),point);
 assert.equal(result.id,'osm-way-1');assert.equal(result.properties.name,'Library');assert.equal(result.properties.license,'ODbL-1.0');
});
test('does not invent bounds for point, line, no-data or outside responses',()=>{
 for(const elements of [[],[{type:'node',id:1,lat:20,lon:10,tags:{name:'Cafe',amenity:'cafe'}}],[way(1,ring(11,21))],[way(1,ring().slice(0,3))]])assert.throws(()=>placeFromResponse(response(elements),point),/No usable/);
 assert.throws(()=>placeFromResponse({elements:[way()],remark:'runtime timeout'},point),/incomplete/);
});
test('stitches reversed relation members and preserves a hole',()=>{
 const outer=ring(),inner=ring(10.006,20.006,0.001);
 const relation={type:'relation',id:7,tags:{type:'multipolygon',building:'yes',name:'Campus'},members:[{type:'way',role:'outer',geometry:outer.slice(0,3)},{type:'way',role:'outer',geometry:outer.slice(2).reverse()},{type:'way',role:'inner',geometry:inner}]};
 const result=placeFromResponse(response([relation]),point);assert.equal(result.geometry.coordinates.length,2);
 assert.throws(()=>placeFromResponse(response([relation]),[10.0065,20.0065]),/No usable/);
 relation.members.pop();relation.members.pop();assert.throws(()=>placeFromResponse(response([relation]),point),/No usable/);
});
test('handles disconnected MultiPolygon parts without dropping one',()=>{
 const relation={type:'relation',id:7,tags:{type:'multipolygon',building:'yes'},members:[{type:'way',role:'outer',geometry:ring()},{type:'way',role:'outer',geometry:ring(11,21)}]};
 const result=placeFromResponse(response([relation]),point);assert.equal(result.geometry.type,'MultiPolygon');assert.equal(result.geometry.coordinates.length,2);
});
test('skips invalid candidates and refuses giant enclosing places',()=>{
 assert.equal(placeFromResponse(response([way(2,ring().slice(0,3)),way()]),point).id,'osm-way-1');
 assert.throws(()=>placeFromResponse(response([way(2,ring(9,19,2))]),point),/No usable/);
});
test('caches repeated lookups and rate-limits different points',async()=>{
 let calls=0,time=1000;
 const lookup=new PlaceLookup({endpoint},async url=>{calls++;assert.match(String(url),/data=/);return Response.json(response([way()]));},()=>time);
 await lookup.lookup(point[1],point[0]);await lookup.lookup(point[1],point[0]);assert.equal(calls,1);
 await assert.rejects(lookup.lookup(20.004,10.004),/wait a moment/);time+=2001;await lookup.lookup(20.004,10.004);assert.equal(calls,2);
});
test('handles HTTP errors and bad JSON without caching failures',async()=>{
 for(const [code,expected]of [[429,/busy/],[503,/503/]]){
  const lookup=new PlaceLookup({endpoint},async()=>new Response('',{status:code}));await assert.rejects(lookup.lookup(20,10),expected);assert.equal(lookup.cache.size,0);
 }
 const invalid=new PlaceLookup({endpoint},async()=>new Response('<html>'));await assert.rejects(invalid.lookup(20,10),/invalid data/);
});
test('cancellation prevents a late result from being returned or cached',async()=>{
 let release;const deferred=new Promise(r=>{release=r;});const abort=new AbortController();
 const lookup=new PlaceLookup({endpoint},async()=>{await deferred;return Response.json(response([way()]));});
 const promise=lookup.lookup(point[1],point[0],abort.signal);abort.abort();release();await assert.rejects(promise,{name:'AbortError'});assert.equal(lookup.cache.size,0);assert.equal(lookup.busy,false);
});
test('timeout terminates lookup and releases busy state',async()=>{
 const lookup=new PlaceLookup({endpoint,timeoutMs:10},async(url,{signal})=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')))));
 await assert.rejects(lookup.lookup(20,10),/timed out/);assert.equal(lookup.busy,false);
});
test('rejects oversized responses before parsing',async()=>{
 const lookup=new PlaceLookup({endpoint},async()=>new Response('{}',{headers:{'content-length':'5000001'}}));await assert.rejects(lookup.lookup(20,10),/5 MB/);
 const streamed=new PlaceLookup({endpoint},async()=>new Response(' '.repeat(5000001)));await assert.rejects(streamed.lookup(20,10),/5 MB/);
});
test('concurrent requests do not start a second transport',async()=>{
 let release,calls=0;const pending=new Promise(r=>{release=r;});
 const lookup=new PlaceLookup({endpoint},async()=>{calls++;await pending;return Response.json(response([way()]));});
 const first=lookup.lookup(point[1],point[0]);await assert.rejects(lookup.lookup(20.004,10.004),/already running/);release();await first;assert.equal(calls,1);
});

test('live White House fixture resolves to its real mapped footprint',async()=>{
 const {readFile}=await import('node:fs/promises');
 const data=JSON.parse(await readFile(new URL('./fixtures/white-house-overpass.json',import.meta.url),'utf8'));
 const found=placeFromResponse(data,[-77.0365,38.8977]);
 assert.equal(found.properties.name,'White House');assert.equal(found.id,'osm-relation-19761182');assert.equal(found.geometry.type,'Polygon');
 assert.ok(found.geometry.coordinates[0].length>4);
});
