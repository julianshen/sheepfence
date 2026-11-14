import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {translator} from '../../docs/site/assets/editor/i18n.mjs';
const messages=JSON.parse(readFileSync(new URL('../../docs/site/assets/editor/messages.json',import.meta.url)));
test('catalogs have identical keys and preserve interpolation placeholders',()=>{
  assert.deepEqual(Object.keys(messages.ja).sort(),Object.keys(messages['zh-Hant']).sort());
  for(const catalog of Object.values(messages))for(const [source,value] of Object.entries(catalog)){
    assert.ok(value.trim());
    assert.deepEqual((value.match(/\{\d+\}/g)||[]).sort(),(source.match(/\{\d+\}/g)||[]).sort(),source);
  }
});
test('translations preserve arbitrary names, IDs and placeholder-like user data',()=>{
  for(const locale of ['zh-Hant','ja']){
    const t=translator(messages[locale]), name='<b>Fence {1} 日本語</b>';
    assert.ok(t`Delete fence “${name}”? You can undo this.`.includes(name));
    assert.notEqual(t('Dataset ID'),'Dataset ID');
    assert.equal(t('com.example.fences'),'com.example.fences');
    assert.equal(t('toString'),'toString');
    assert.equal(t`Unknown ${name}`,`Unknown ${name}`);
  }
});
test('English messages and templates remain unchanged without a catalog',()=>{
  const t=translator();assert.equal(t('Dataset ID'),'Dataset ID');assert.equal(t`Vertex ${3}`,'Vertex 3');
});
test('every literal translation call has both translations',()=>{
  for(const file of ['editor','model','places']){
    const source=readFileSync(new URL(`../../docs/site/assets/editor/${file}.mjs`,import.meta.url),'utf8');
    for(const match of source.matchAll(/\bt\('([^']+)'\)/g)){
      for(const catalog of Object.values(messages))assert.ok(Object.hasOwn(catalog,match[1]),`${file}: ${match[1]}`);
    }
  }
});
