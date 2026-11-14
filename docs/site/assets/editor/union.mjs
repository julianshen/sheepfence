import * as bundled from '../vendor/polygon-clipping/polygon-clipping.umd.js';
import {clone,validateSnapshot} from './model.mjs?v=roads-1';
// The unchanged upstream UMD bundle exposes CommonJS in Node and a global in browsers/workers.
const clipping=bundled.default ?? globalThis.polygonClipping;

export function unionFences(snapshot, ids, propertiesFrom) {
  validateSnapshot(snapshot);
  const chosen=new Set(ids);
  if(chosen.size<2||chosen.size!==ids.length)throw new Error('Choose at least two different fences.');
  const inputs=snapshot.features.filter(f=>chosen.has(f.id));
  if(inputs.length!==chosen.size||!chosen.has(propertiesFrom))throw new Error('Union selection is no longer valid.');
  const source=inputs.find(f=>f.id===propertiesFrom);
  const coordinates=clipping.union(...inputs.map(f=>f.geometry.coordinates));
  if(!coordinates.length)throw new Error('Union produced no boundary.');
  let n=1;while(snapshot.features.some(f=>f.id===`union-${n}`))n++;
  const properties={name:source.properties.name??source.id,enabled:source.properties.enabled??true,priority:source.properties.priority??0,
    unionSources:inputs.map(f=>({id:f.id,properties:clone(f.properties)}))};
  // Preserve attribution visibly in exports without claiming the merged shape is an original OSM object.
  for(const key of ['attribution','license']){
    const values=[...new Set(inputs.map(f=>f.properties[key]).filter(v=>typeof v==='string'&&v))];
    if(values.length)properties[key]=values.join('; ');
  }
  const merged={type:'Feature',id:`union-${n}`,properties,geometry:coordinates.length===1?
    {type:'Polygon',coordinates:coordinates[0]}:{type:'MultiPolygon',coordinates}};
  const next=clone(snapshot), index=snapshot.features.findIndex(f=>chosen.has(f.id));
  next.features=next.features.filter(f=>!chosen.has(f.id));
  next.features.splice(index,0,merged);
  // Authoring limits and topology checks apply equally to computed geometry. Never commit invalid output.
  validateSnapshot(next);
  return {snapshot:next,index};
}
