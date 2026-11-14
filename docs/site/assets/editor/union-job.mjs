// Keep clipping off the UI thread. Each operation owns a worker; cancellation kills computation.
export function runUnion(snapshot,ids,propertiesFrom,signal){
  return new Promise((resolve,reject)=>{
    if(signal.aborted){reject(new DOMException('Cancelled','AbortError'));return;}
    const worker=new Worker(new URL('./union-worker.mjs?v=union-1',import.meta.url),{type:'module'});
    let timer;
    const finish=(error,result)=>{clearTimeout(timer);signal.removeEventListener('abort',abort);worker.terminate();error?reject(error):resolve(result);};
    const abort=()=>finish(new DOMException('Cancelled','AbortError'));
    signal.addEventListener('abort',abort,{once:true});
    worker.onmessage=({data})=>data.error?finish(new Error('unionFailed')):finish(null,data.result);
    worker.onerror=()=>finish(new Error('unionFailed'));
    timer=setTimeout(()=>finish(new Error('unionTimeout')),15000);
    try{worker.postMessage({snapshot,ids,propertiesFrom});}catch(error){finish(error);}
  });
}
