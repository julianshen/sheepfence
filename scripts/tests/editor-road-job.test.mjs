import test from 'node:test';
import assert from 'node:assert/strict';
import {runRoadExpansion} from '../../docs/site/assets/editor/road-job.mjs';
function workers(t){const original=globalThis.Worker,created=[];globalThis.Worker=class{constructor(url,options){this.options=options;created.push(this);}postMessage(data){this.data=data;}terminate(){this.terminated=true;}};t.after(()=>{if(original===undefined)delete globalThis.Worker;else globalThis.Worker=original;});return created;}
test('road worker produces a preview result and terminates after delivery',async t=>{
 const created=workers(t),promise=runRoadExpansion({},0,{elements:[]},150,new AbortController().signal);assert.equal(created[0].options.type,'module');assert.equal(created[0].data.limit,150);
 created[0].onmessage({data:{result:{snapshot:{},index:0}}});assert.deepEqual(await promise,{snapshot:{},index:0});assert(created[0].terminated);
});
test('road worker abort stops calculation and rejects without a preview',async t=>{
 const created=workers(t),controller=new AbortController(),promise=runRoadExpansion({},0,{},150,controller.signal);controller.abort();await assert.rejects(promise,{name:'AbortError'});assert(created[0].terminated);
 await assert.rejects(runRoadExpansion({},0,{},150,controller.signal),{name:'AbortError'});assert.equal(created.length,1);
});
test('geometry and worker loading failures reject atomically',async t=>{
 const created=workers(t);let promise=runRoadExpansion({},0,{},150,new AbortController().signal);created[0].onmessage({data:{error:'roadNoEnclosure'}});await assert.rejects(promise,/roadNoEnclosure/);assert(created[0].terminated);
 promise=runRoadExpansion({},0,{},150,new AbortController().signal);created[1].onerror();await assert.rejects(promise,/roadInvalid/);assert(created[1].terminated);
});
