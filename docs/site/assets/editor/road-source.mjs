import {roadQuery} from './roads.mjs?v=roads-1';
import {limitedJSON} from './places.mjs?v=roads-1';
export class RoadLookup{
  constructor({endpoint,minimumIntervalMs=2000,timeoutMs=20000},fetcher=globalThis.fetch,now=()=>Date.now()){
    const url=new URL(endpoint);
    if(url.protocol!=='https:'||url.username||url.password||!Number.isFinite(minimumIntervalMs)||!Number.isFinite(timeoutMs)||timeoutMs<=0)throw new Error('roadConfiguration');
    this.endpoint=url;this.interval=Math.max(2000,minimumIntervalMs);this.timeout=Math.min(30000,timeoutMs);this.fetcher=fetcher.bind(globalThis);this.now=now;this.lastStart=-Infinity;this.busy=false;this.cache=new Map();
  }
  async lookup(search,signal){
    const query=roadQuery(search);
    if(signal.aborted)throw new DOMException('Cancelled','AbortError');
    const saved=this.cache.get(query);if(saved&&this.now()-saved.time<300000)return saved.data;
    if(this.busy||this.now()-this.lastStart<this.interval)throw new Error('roadBusy');
    this.busy=true;this.lastStart=this.now();const controller=new AbortController();let timedOut=false;
    const cancel=()=>controller.abort();signal.addEventListener('abort',cancel,{once:true});
    const timer=setTimeout(()=>{timedOut=true;controller.abort();},this.timeout);
    try{
      const url=new URL(this.endpoint);url.searchParams.set('data',query);
      const response=await this.fetcher(url,{signal:controller.signal,headers:{Accept:'application/json'},credentials:'omit',referrerPolicy:'strict-origin-when-cross-origin'});
      if(response.status===429)throw new Error('roadBusy');if(!response.ok)throw new Error('roadNetwork');
      let data;try{data=await limitedJSON(response);}catch{throw new Error('roadIncomplete');}
      if(controller.signal.aborted)throw new DOMException('Cancelled','AbortError');
      if(data.remark||!Array.isArray(data.elements)||data.elements.length>600)throw new Error('roadIncomplete');
      if(this.cache.size>=10)this.cache.delete(this.cache.keys().next().value);this.cache.set(query,{data,time:this.now()});return data;
    }catch(error){
      if(signal.aborted)throw new DOMException('Cancelled','AbortError');
      if(timedOut)throw new Error('roadTimeout');
      if(error instanceof TypeError)throw new Error('roadNetwork');throw error;
    }finally{clearTimeout(timer);signal.removeEventListener('abort',cancel);this.busy=false;}
  }
}
