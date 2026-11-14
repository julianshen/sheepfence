export function runRoadExpansion(snapshot,index,roads,limit,signal){
  return new Promise((resolve,reject)=>{
    if(signal.aborted){reject(new DOMException('Cancelled','AbortError'));return;}
    const worker=new Worker(new URL('./road-worker.mjs?v=roads-1',import.meta.url),{type:'module'});let timer;
    const finish=(error,result)=>{clearTimeout(timer);signal.removeEventListener('abort',abort);worker.terminate();error?reject(error):resolve(result);};
    const abort=()=>finish(new DOMException('Cancelled','AbortError'));signal.addEventListener('abort',abort,{once:true});
    worker.onmessage=({data})=>data.error?finish(new Error(data.error)):finish(null,data.result);
    worker.onerror=()=>finish(new Error('roadInvalid'));
    timer=setTimeout(()=>finish(new Error('roadComplexity')),15000);
    try{worker.postMessage({snapshot,index,roads,limit});}catch(error){finish(error);}
  });
}
