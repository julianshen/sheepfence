import {unionFences} from './union.mjs?v=union-1';
self.onmessage=({data})=>{
  try{self.postMessage({result:unionFences(data.snapshot,data.ids,data.propertiesFrom)});}
  catch{self.postMessage({error:true});}
};
