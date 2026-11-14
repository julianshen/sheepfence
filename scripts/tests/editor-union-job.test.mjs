import test from 'node:test';
import assert from 'node:assert/strict';
import {runUnion} from '../../docs/site/assets/editor/union-job.mjs';
function fakeWorker(t){
 const original=globalThis.Worker, instances=[];
 globalThis.Worker=class{constructor(url,options){this.url=url;this.options=options;this.terminated=false;instances.push(this);}postMessage(data){this.data=data;}terminate(){this.terminated=true;}};
 t.after(()=>{if(original===undefined)delete globalThis.Worker;else globalThis.Worker=original;});return instances;
}
test('union job returns worker result and terminates its worker',async t=>{
 const workers=fakeWorker(t),controller=new AbortController(),promise=runUnion({features:[]},['a','b'],'a',controller.signal);
 const worker=workers[0];assert.equal(worker.options.type,'module');assert.deepEqual(worker.data.ids,['a','b']);
 worker.onmessage({data:{result:{snapshot:{},index:0}}});assert.deepEqual(await promise,{snapshot:{},index:0});assert(worker.terminated);
});
test('abort stops in-flight computation and never creates a worker for an already cancelled job',async t=>{
 const workers=fakeWorker(t),controller=new AbortController(),promise=runUnion({},['a','b'],'a',controller.signal);
 controller.abort();await assert.rejects(promise,{name:'AbortError'});assert(workers[0].terminated);
 await assert.rejects(runUnion({},['a','b'],'a',controller.signal),{name:'AbortError'});assert.equal(workers.length,1);
});
test('worker calculation and loading failures reject without a partial result',async t=>{
 const workers=fakeWorker(t);
 for(const kind of ['calculation','load']){
  const promise=runUnion({},['a','b'],'a',new AbortController().signal),worker=workers.at(-1);
  if(kind==='load')worker.onerror();else worker.onmessage({data:{error:true}});
  await assert.rejects(promise,/unionFailed/);assert(worker.terminated);
 }
});
