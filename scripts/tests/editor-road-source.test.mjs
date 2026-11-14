import test from 'node:test';
import assert from 'node:assert/strict';
import {RoadLookup} from '../../docs/site/assets/editor/road-source.mjs';
const endpoint='https://example.com/interpreter',search={bbox:[20,10,20.001,10.001]},signal=()=>new AbortController().signal;
test('road lookup sends only a bounded query, caches and rate limits requests',async()=>{
 let calls=0,time=1000;const service=new RoadLookup({endpoint},async(url,options)=>{calls++;assert.match(url.searchParams.get('data'),/20.0000000,10.0000000,20.0010000,10.0010000/);assert.equal(options.credentials,'omit');return Response.json({elements:[]});},()=>time);
 await service.lookup(search,signal());await service.lookup(search,signal());assert.equal(calls,1);
 await assert.rejects(service.lookup({bbox:[21,10,21.001,10.001]},signal()),/roadBusy/);time+=300001;await service.lookup(search,signal());assert.equal(calls,2);
});
test('HTTP, malformed, partial and excessive responses are rejected',async()=>{
 for(const response of [new Response('',{status:500}),new Response('',{status:429}),new Response('not json'),Response.json({remark:'timeout',elements:[]}),Response.json({elements:Array(601).fill({})}),new Response('',{headers:{'content-length':'5000001'}})]){
 const service=new RoadLookup({endpoint},async()=>response);await assert.rejects(service.lookup(search,signal()));assert.equal(service.cache.size,0);assert.equal(service.busy,false);
 }
});
test('streamed responses enforce byte limits without trusting Content-Length',async()=>{
 const response=new Response(new ReadableStream({start(c){c.enqueue(new Uint8Array(5000001));c.close();}}));
 const service=new RoadLookup({endpoint},async()=>response);await assert.rejects(service.lookup(search,signal()),/roadIncomplete/);
});
test('cancellation discards a late transport result and prevents caching',async()=>{
 let deliver;const service=new RoadLookup({endpoint},()=>new Promise(r=>deliver=r)),controller=new AbortController();
 const request=service.lookup(search,controller.signal);controller.abort();deliver(Response.json({elements:[]}));await assert.rejects(request,{name:'AbortError'});assert.equal(service.cache.size,0);assert.equal(service.busy,false);
});
test('timeout aborts transport and releases in-flight state',async()=>{
 const service=new RoadLookup({endpoint,timeoutMs:5},(_,options)=>new Promise((_,reject)=>options.signal.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')))));
 await assert.rejects(service.lookup(search,signal()),/roadTimeout/);assert.equal(service.busy,false);
});
test('rejects insecure or invalid configuration and already cancelled requests',async()=>{
 for(const config of [{endpoint:'http://example.com'},{endpoint:'https://user:secret@example.com'},{endpoint,timeoutMs:NaN}])assert.throws(()=>new RoadLookup(config));
 const service=new RoadLookup({endpoint},()=>assert.fail('must not fetch')),controller=new AbortController();controller.abort();await assert.rejects(service.lookup(search,controller.signal),{name:'AbortError'});
});
