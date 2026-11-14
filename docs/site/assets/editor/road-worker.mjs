import {expandToRoads} from './roads.mjs?v=roads-1';
self.onmessage=({data})=>{
  try{self.postMessage({result:expandToRoads(data.snapshot,data.index,data.roads,data.limit)});}
  catch(error){self.postMessage({error:error.message.startsWith('road')?error.message:'roadInvalid'});}
};
