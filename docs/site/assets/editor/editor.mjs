import {t} from './i18n.mjs?v=l10n-1';
import {clone,freshSnapshot,closeRing,polygons,validateSnapshot,readImport,serialize,MAX_BYTES} from './model.mjs?v=l10n-1';
import {PlaceLookup} from './places.mjs?v=l10n-1';
const $=id=>document.getElementById(id);
const STORAGE='sheepfence-studio-v1';
let snapshot=freshSnapshot(), selected=-1, part=0, ringIndex=0, vertex=-1;
let activeLookup=null, placeService=null, editGeneration=0, selectionTimer=null;
let drawing=null, past=[], future=[], datasetDirty=false, featureDirty=false;
const message=(text,error=false)=>{$('status').textContent=text;$('status').classList.toggle('error',error);};
function ready(allowDrawing=false) {
  if(datasetDirty||featureDirty){message(t('Apply your dataset or fence properties first.'),true);return false;}
  if(drawing&&!allowDrawing){message(t('Finish or cancel the current boundary first.'),true);return false;}
  return true;
}
let restoreMessage=t('Ready. Double-click a mapped place to add its boundary, or draw a fence.');
try {
  const saved=localStorage.getItem(STORAGE);
  if(saved){snapshot=readImport(saved);selected=snapshot.features.length?0:-1;restoreMessage=t('Restored your local draft. Download a copy to keep a backup.');}
} catch {restoreMessage=t('Local draft could not be restored. Import your downloaded backup to continue.');}
if(!window.L){message(t('The map library could not load. Reload the page to try again.'),true);throw new Error('Leaflet unavailable');}
const map=L.map('map',{doubleClickZoom:false,worldCopyJump:false,maxBounds:[[-90,-180],[90,180]],maxBoundsViscosity:1}).setView([25.033,121.5654],15);
const tiles=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{
  attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>',
  maxZoom:19,noWrap:true,updateWhenIdle:true,keepBuffer:1
}).addTo(map);
tiles.on('tileerror',()=>{$('map-notice').hidden=false;});
const shapes=L.featureGroup().addTo(map),handles=L.layerGroup().addTo(map),draftLayers=L.layerGroup().addTo(map);
const feature=()=>snapshot.features[selected];
const currentRing=()=>feature()?polygons(feature())[part]?.[ringIndex]:null;
const latlng=point=>[point[1],point[0]];
function point(ll){return [Number(ll.lng.toFixed(8)),Number(ll.lat.toFixed(8))];}
function save(){
  try{localStorage.setItem(STORAGE,JSON.stringify(snapshot));$('save-status').textContent=t('Draft saved on this device');}
  catch{$('save-status').textContent=t('Draft not saved — download a backup');}
}
function commit(next,text,options={}){
  try{validateSnapshot(next);}catch(error){message(error.message,true);return false;}
  invalidateLookup();
  past.push(clone(snapshot));if(past.length>30)past.shift();future=[];
  snapshot=next;
  if(options.select!==undefined)selected=options.select;
  if(selected>=snapshot.features.length)selected=snapshot.features.length-1;
  vertex=-1;datasetDirty=false;featureDirty=false;
  save();render();message(text);return true;
}
function ringEdit(change,text){
  if(!ready())return;
  const next=clone(snapshot),rings=polygons(next.features[selected]);
  const open=rings[part][ringIndex].slice(0,-1);change(open);
  rings[part][ringIndex]=closeRing(open);
  if(!commit(next,text))renderMap();
}
function render(){
  $('dataset-id').value=snapshot.dataset.id;$('revision').value=snapshot.dataset.revision;
  $('dataset-unsaved').hidden=true;$('feature-unsaved').hidden=true;
  $('count').textContent=snapshot.features.length;
  $('empty').hidden=!!snapshot.features.length;
  $('fence-list').replaceChildren();
  snapshot.features.forEach((f,i)=>{
    const button=document.createElement('button');button.className='fence-item';button.type='button';button.setAttribute('aria-pressed',String(i===selected));
    const swatch=document.createElement('span');swatch.className='swatch';if(f.properties.enabled===false)swatch.style.background='#9daca1';
    const body=document.createElement('span'),title=document.createElement('strong'),subtitle=document.createElement('small');
    title.textContent=f.properties.name||f.id;subtitle.textContent=`${f.id} · ${f.geometry.type}${f.properties.enabled===false?' · '+t('disabled'):''}`;
    body.append(title,subtitle);button.append(swatch,body);button.addEventListener('click',()=>selectFence(i));$('fence-list').append(button);
  });
  $('feature-panel').hidden=!feature();
  if(feature()){
    const f=feature();$('feature-id').value=f.id;$('feature-name').value=f.properties.name??f.id;
    $('priority').value=f.properties.priority??0;$('enabled').checked=f.properties.enabled!==false;
    const parts=polygons(f);if(!parts[part])part=0;if(!parts[part][ringIndex])ringIndex=0;
    $('ring').replaceChildren();
    parts.forEach((rings,pi)=>rings.forEach((r,ri)=>{
      const option=document.createElement('option');option.value=`${pi}:${ri}`;
      option.textContent=t`Part ${pi+1} · ${ri===0?t('Outer boundary'):t`Hole ${ri}`} · ${r.length-1} vertices`;
      option.selected=pi===part&&ri===ringIndex;$('ring').append(option);
    }));
    $('remove-ring').disabled=parts.length===1&&ringIndex===0;
  }
  for(const form of ['dataset-form','feature-form']) for(const control of $(form).elements) control.disabled=!!drawing;
  $('undo').disabled=!past.length||!!drawing;$('redo').disabled=!future.length||!!drawing;
  for(const id of ['quick-add','draw','hole','part','delete','new','import','export','preview','ring'])$(id).disabled=!!drawing;
  const stats=validateSnapshot(snapshot);$('stats').textContent=t`${stats.regions} fences · ${stats.vertices.toLocaleString()} vertices`;
  renderMap();renderVertex();renderDraft();
}
function selectFence(index){if(!ready())return;selected=index;part=0;ringIndex=0;vertex=-1;render();message(t('Drag vertices to edit. Changes are checked before they are saved.'));}
function renderMap(){
  shapes.clearLayers();handles.clearLayers();
  snapshot.features.forEach((f,i)=>{
    const layer=L.geoJSON(f,{interactive:!drawing,style:{color:i===selected?'#184e3b':'#598b6a',weight:i===selected?3:2,fillColor:i===selected?'#73ac74':'#99b5a0',fillOpacity:f.properties.enabled===false?0.08:0.24,dashArray:f.properties.enabled===false?'5 5':null}}).addTo(shapes);
    layer.on('click',e=>{
      L.DomEvent.stopPropagation(e);clearTimeout(selectionTimer);
      selectionTimer=setTimeout(()=>selectFence(i),250);
    });
    layer.on('dblclick',e=>{
      if(f.properties.source!=='OpenStreetMap')return;
      L.DomEvent.stopPropagation(e);clearTimeout(selectionTimer);
      if(!ready())return;
      selectFence(i);message(t`“${f.properties.name||f.id}” is already in this dataset. Selected the existing fence.`);
    });
    const name=document.createElement('span');name.textContent=f.properties.name||f.id;layer.bindTooltip(name,{sticky:true});
  });
  const ring=currentRing();if(!ring||drawing)return;
  const points=ring.slice(0,-1);
  points.forEach((p,i)=>{
    const marker=L.marker(latlng(p),{draggable:true,icon:L.divIcon({className:`vertex${vertex===i?' selected':''}`,iconSize:[15,15],iconAnchor:[7.5,7.5]}),title:t`Vertex ${i+1}`,keyboard:true}).addTo(handles);
    marker.on('click',e=>{L.DomEvent.stopPropagation(e);if(!ready())return;vertex=i;renderVertex();});
    marker.on('dragstart',()=>{vertex=i;});
    marker.on('dragend',()=>{if(!ready()){renderMap();return;}const moved=point(marker.getLatLng());ringEdit(open=>{open[i]=moved;},t`Moved vertex ${i+1}.`);});
    const next=points[(i+1)%points.length];
    const midpoint=[(p[0]+next[0])/2,(p[1]+next[1])/2];
    const insert=L.marker(latlng(midpoint),{icon:L.divIcon({className:'midpoint',html:'+',iconSize:[17,17],iconAnchor:[8.5,8.5]}),title:t`Insert vertex after ${i+1}`,keyboard:true}).addTo(handles);
    insert.on('click',e=>{L.DomEvent.stopPropagation(e);ringEdit(open=>open.splice(i+1,0,midpoint),t('Inserted a vertex.'));});
  });
}
function renderVertex(){
  const p=currentRing()?.[vertex];$('vertex-panel').hidden=!p||vertex<0;
  if(p&&vertex>=0){$('vertex-title').textContent=t`Vertex ${vertex+1}`;$('vertex-lat').value=p[1];$('vertex-lng').value=p[0];}
}
function startDraw(kind){
  if(!ready())return;if(kind!=='fence'&&!feature())return;
  if(kind==='fence'&&snapshot.features.length>=100){message(t('This editor supports up to 100 fences per snapshot.'),true);return;}
  invalidateLookup();
  drawing={kind,points:[]};vertex=-1;render();
  message(t('Click at least three map points, then choose Finish boundary. Escape cancels.'));
}
function renderDraft(){
  draftLayers.clearLayers();$('draw-panel').hidden=!drawing;
  map.getContainer().style.cursor=drawing?'crosshair':'';
  if(!drawing)return;
  const pts=drawing.points.map(latlng);
  $('draw-title').textContent={fence:t('Drawing a new fence'),hole:t('Drawing a hole'),part:t('Drawing a polygon part')}[drawing.kind];
  $('draw-instruction').textContent=t`${pts.length} vertices · Click to add; finish to close the boundary.`;
  $('finish').disabled=pts.length<3;$('undo-point').disabled=!pts.length;
  if(pts.length>1)L.polyline(pts,{color:'#916d21',weight:2,dashArray:'5 5',interactive:false}).addTo(draftLayers);
  if(pts.length>2)L.polygon(pts,{color:'#916d21',weight:1,fillColor:'#e5c779',fillOpacity:0.2,interactive:false}).addTo(draftLayers);
  pts.forEach(p=>L.marker(p,{interactive:false,icon:L.divIcon({className:'draft-vertex',iconSize:[11,11],iconAnchor:[5.5,5.5]})}).addTo(draftLayers));
}
map.on('click',e=>{
  if(!drawing)return;
  if(drawing.points.length>=1000){message(t('A boundary can have at most 1,000 vertices.'),true);return;}
  const nextPoint=point(e.latlng),last=drawing.points.at(-1);
  if(e.originalEvent?.detail>1 || (last&&last[0]===nextPoint[0]&&last[1]===nextPoint[1]))return;
  drawing.points.push(nextPoint);renderDraft();
});

function invalidateLookup(){
  editGeneration++;
  if(activeLookup){activeLookup.controller.abort();activeLookup=null;}
  $('cancel-lookup').hidden=true;$('quick-add').disabled=!!drawing;
}
function cancelLookup(){invalidateLookup();message(t('Place lookup cancelled. Existing fences are unchanged.'));}
async function getPlaceService(signal){
  if(placeService)return placeService;
  const response=await fetch(new URL('./places-config.json',import.meta.url),{signal});
  if(!response.ok)throw new Error(t('Place lookup configuration could not load. Try reloading the editor.'));
  const config=await response.json();
  if(signal.aborted)throw new DOMException('Cancelled','AbortError');
  placeService=new PlaceLookup(config);return placeService;
}
async function quickAdd(ll){
  clearTimeout(selectionTimer);
  if(!ready())return;
  if(map.getZoom()<15){message(t('Zoom in to a building or place before double-clicking to add its boundary.'),true);return;}
  if(activeLookup){message(t('A place lookup is running. Cancel it before choosing another place.'));return;}
  if(snapshot.features.length>=100){message(t('This snapshot already has 100 fences.'),true);return;}
  const operation={controller:new AbortController(),generation:editGeneration};activeLookup=operation;
  $('cancel-lookup').hidden=false;$('quick-add').disabled=true;
  message(t('Finding the mapped boundary at this point…'));
  const configTimeout=setTimeout(()=>operation.controller.abort(),25000);
  try{
    const service=await getPlaceService(operation.controller.signal);
    const found=await service.lookup(ll.lat,ll.lng,operation.controller.signal);
    if(activeLookup!==operation||operation.generation!==editGeneration)return;
    if(!ready())return;
    const duplicate=snapshot.features.findIndex(f=>f.id===found.id||(f.properties.osm_type===found.properties.osm_type&&f.properties.osm_id===found.properties.osm_id));
    if(duplicate>=0){selectFence(duplicate);message(t`“${found.properties.name}” is already in this dataset. Selected the existing fence.`);return;}
    const next=clone(snapshot);next.features.push(found);part=0;ringIndex=0;
    if(commit(next,t`Added “${found.properties.name}” from OpenStreetMap. Review its boundary; Undo removes it.`,{select:next.features.length-1})){
      map.fitBounds(L.geoJSON(found).getBounds(),{padding:[60,60],maxZoom:18});
    }
  }catch(error){
    if(activeLookup===operation)message(error.name==='AbortError'?t('Place lookup stopped. Try again or draw the fence manually.'):error.message,true);
  }finally{
    clearTimeout(configTimeout);
    if(activeLookup===operation){activeLookup=null;$('cancel-lookup').hidden=true;$('quick-add').disabled=!!drawing;}
  }
}
map.on('dblclick',e=>{
  if(drawing||e.originalEvent?.target?.closest?.('.leaflet-marker-icon'))return;
  quickAdd(e.latlng);
});
$('quick-add').onclick=()=>quickAdd(map.getCenter());
$('cancel-lookup').onclick=cancelLookup;

map.on('moveend',()=>{const p=map.getCenter();$('coordinates').textContent=`${p.lat.toFixed(5)}, ${p.lng.toFixed(5)}`;});
$('draw').onclick=()=>startDraw('fence');$('hole').onclick=()=>startDraw('hole');$('part').onclick=()=>startDraw('part');
$('undo-point').onclick=()=>{drawing.points.pop();renderDraft();};
$('cancel-draw').onclick=()=>{drawing=null;render();message(t('Boundary cancelled. Existing fences are unchanged.'));};
$('finish').onclick=()=>{
  if(!drawing)return;
  const next=clone(snapshot),closed=closeRing(drawing.points);let index=selected;
  if(drawing.kind==='fence'){
    let n=1;while(next.features.some(f=>f.id===`fence-${n}`))n++;
    next.features.push({type:'Feature',id:`fence-${n}`,properties:{name:t`Fence ${n}`,enabled:true,priority:0},geometry:{type:'Polygon',coordinates:[closed]}});index=next.features.length-1;
  }else if(drawing.kind==='hole'){polygons(next.features[selected])[part].push(closed);}
  else{
    const g=next.features[selected].geometry;
    if(g.type==='Polygon'){g.coordinates=[g.coordinates];g.type='MultiPolygon';}
    g.coordinates.push([closed]);
  }
  try{validateSnapshot(next);}catch(error){message(error.message+' '+t('Use Undo point or Cancel to correct it.'),true);return;}
  drawing=null;part=0;ringIndex=0;commit(next,t('Boundary saved. Select its fence to edit properties or vertices.'),{select:index});
};
$('dataset-form').addEventListener('input',()=>{
  invalidateLookup();datasetDirty=true;$('dataset-unsaved').hidden=false;
  for(const control of $('feature-form').elements)control.disabled=true;
});
$('feature-form').addEventListener('input',()=>{
  invalidateLookup();featureDirty=true;$('feature-unsaved').hidden=false;
  for(const control of $('dataset-form').elements)control.disabled=true;
});
$('dataset-form').onsubmit=e=>{
  e.preventDefault();if(drawing){message(t('Finish or cancel the boundary first.'),true);return;}
  if(featureDirty){message(t('Apply fence properties first.'),true);return;}
  const next=clone(snapshot);next.dataset.id=$('dataset-id').value.trim();next.dataset.revision=Number($('revision').value);
  commit(next,t('Dataset properties saved.'));
};
$('feature-form').onsubmit=e=>{
  e.preventDefault();if(drawing||!feature())return;if(datasetDirty){message(t('Apply dataset properties first.'),true);return;}
  const next=clone(snapshot),f=next.features[selected];f.id=$('feature-id').value.trim();f.properties={...f.properties,name:$('feature-name').value,priority:Number($('priority').value),enabled:$('enabled').checked};
  commit(next,t('Fence properties saved.'));
};
$('bump').onclick=()=>{if(!ready())return;const next=clone(snapshot);next.dataset.revision++;next.dataset.generatedAt=new Date().toISOString();commit(next,t('Revision incremented. The new snapshot is ready for publication.'));};
$('ring').onchange=()=>{
  if(!ready()){ $('ring').value=`${part}:${ringIndex}`;return;}
  [part,ringIndex]=$('ring').value.split(':').map(Number);vertex=-1;renderMap();renderVertex();
};
$('vertex-form').onsubmit=e=>{e.preventDefault();const i=vertex;ringEdit(open=>{open[i]=[Number($('vertex-lng').value),Number($('vertex-lat').value)];},t('Vertex coordinates updated.'));};
$('remove-vertex').onclick=()=>{const i=vertex;if(i>=0)ringEdit(open=>open.splice(i,1),t('Vertex removed.'));};
$('remove-ring').onclick=()=>{
  if(!ready()||!feature())return;if(!confirm(t('Remove this boundary? Removing an outer boundary also removes its holes.')))return;
  const next=clone(snapshot),g=next.features[selected].geometry,parts=polygons(next.features[selected]);
  if(ringIndex>0)parts[part].splice(ringIndex,1);else parts.splice(part,1);
  if(g.type==='MultiPolygon'&&parts.length===1){g.type='Polygon';g.coordinates=parts[0];}
  part=0;ringIndex=0;commit(next,t('Boundary removed.'));
};
$('delete').onclick=()=>{
  if(!ready()||!feature()||!confirm(t`Delete fence “${feature().id}”? You can undo this.`))return;
  const next=clone(snapshot);next.features.splice(selected,1);part=0;ringIndex=0;commit(next,t('Fence deleted.'));
};
$('undo').onclick=()=>{
  if(!ready()||!past.length)return;invalidateLookup();future.push(clone(snapshot));snapshot=past.pop();selected=Math.min(selected,snapshot.features.length-1);part=0;ringIndex=0;vertex=-1;save();render();message(t('Undid the last change.'));
};
$('redo').onclick=()=>{
  if(!ready()||!future.length)return;invalidateLookup();past.push(clone(snapshot));snapshot=future.pop();selected=Math.min(selected,snapshot.features.length-1);part=0;ringIndex=0;vertex=-1;save();render();message(t('Redid the change.'));
};
$('new').onclick=()=>{if(!ready()||!confirm(t('Start a new dataset? Download your current snapshot to keep a separate copy. You can undo this.')))return;part=0;ringIndex=0;commit(freshSnapshot(),t('New dataset started.'),{select:-1});};
function fit(){if(snapshot.features.length)map.fitBounds(shapes.getBounds(),{padding:[40,40],maxZoom:18});else message(t('Draw or import a fence first.'));}
$('fit').onclick=fit;
$('go-form').onsubmit=e=>{
  e.preventDefault();const values=$('go-coordinates').value.trim().split(/[,\s]+/).map(Number);
  if(values.length!==2||!values.every(Number.isFinite)||Math.abs(values[0])>85||Math.abs(values[1])>180){message(t('Enter latitude, longitude (latitude −85 to 85; longitude −180 to 180).'),true);return;}
  map.setView(values,17);message(t('Map moved to the requested coordinates.'));
};
$('locate').onclick=()=>{
  if(!navigator.geolocation){message(t('Location is not supported in this browser.'),true);return;}
  $('locate').disabled=true;message(t('Waiting for your browser location permission…'));
  navigator.geolocation.getCurrentPosition(position=>{
    $('locate').disabled=false;map.setView([position.coords.latitude,position.coords.longitude],16);
    message(t('Map centered on your location. This does not create or save a fence point.'));
  },()=>{$('locate').disabled=false;message(t('Location unavailable. Enter coordinates in the Go field instead.'),true);},{timeout:10000,maximumAge:60000});
};
$('import').onclick=()=>{if(ready()){invalidateLookup();$('file').click();}};
$('file').onchange=async()=>{
  const file=$('file').files[0];$('file').value='';if(!file||!ready())return;
  if(file.size>MAX_BYTES){message(t('Import is larger than 5 MB.'),true);return;}
  try{
    const next=readImport(await file.text(),snapshot.dataset);
    if(!ready())return;
    if(snapshot.features.length&&!confirm(t('Replace the current dataset with this file? Download first to keep a separate copy. You can undo this import.')))return;
    part=0;ringIndex=0;
    if(commit(next,t('Imported snapshot. Increment its revision before installing an edited version.'),{select:next.features.length?0:-1}))fit();
  }catch(error){message(t`Import rejected: ${error.message} Current fences are unchanged.`,true);}
};
function download(){
  if(!ready())return;
  try{
    const text=serialize(snapshot);
    if(!snapshot.features.length&&!confirm(t('Export an empty dataset? Installing a higher revision removes all its existing regions.')))return;
    const url=URL.createObjectURL(new Blob([text],{type:'application/geo+json'}));
    const a=document.createElement('a');a.href=url;a.download=`${snapshot.dataset.id.replace(/[^a-zA-Z0-9._-]/g,'_')}-v${snapshot.dataset.revision}.geojson`;a.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);message(t('Snapshot downloaded. Import it with installSnapshot(from:) or installSnapshot(data:).'));
  }catch(error){message(error.message,true);}
}
$('export').onclick=download;$('download-preview').onclick=download;
$('preview').onclick=()=>{if(!ready())return;try{$('json-preview').value=serialize(snapshot);$('preview-dialog').showModal();}catch(error){message(error.message,true);}};
$('close-preview').onclick=()=>$('preview-dialog').close();
$('copy').onclick=async()=>{
  try{await navigator.clipboard.writeText($('json-preview').value);$('copy').textContent=t('Copied');setTimeout(()=>{$('copy').textContent=t('Copy JSON');},1500);}
  catch{$('json-preview').focus();$('json-preview').select();message(t('Clipboard unavailable. Select and copy the preview manually.'),true);}
};
document.addEventListener('keydown',e=>{
  if(e.key==='Escape'&&activeLookup){cancelLookup();return;}
  if(e.key==='Escape'&&drawing){$('cancel-draw').click();return;}
  if(/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))return;
  if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();$(e.shiftKey?'redo':'undo').click();}
});
window.addEventListener('beforeunload',e=>{if(drawing||datasetDirty||featureDirty){e.preventDefault();e.returnValue='';}});
new ResizeObserver(()=>map.invalidateSize()).observe($('map'));
render();if(snapshot.features.length)fit();message(restoreMessage);
