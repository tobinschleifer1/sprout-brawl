import assert from 'node:assert/strict';
import { KIT_CATEGORIES, KIT_COLOURS, DEFAULT_KIT, decodeKit, encodeKit } from '../src/data/avatarKit.js';
import { KitDraft, cleanKitName, webKitCode, readKitCharacters, writeKitCharacters,
  saveKitCharacter, deleteKitCharacter, KIT_STORE_KEY } from '../src/ui/kitCharacters.js';

const memory = new Map();
const store = { get: (k) => memory.get(k) || null, set: (k,v) => { memory.set(k,v); return true; } };
let roster = readKitCharacters(store);
assert.equal(roster.characters.length,1);
const draft = new KitDraft();
assert.ok(draft.part('hair', KIT_CATEGORIES.find((c)=>c.id==='hair').options[1].id));
draft.colour('hair',3);
const saved = saveKitCharacter(roster,"Ada <script> O'Brien",draft.code,null,true);
assert.ok(saved.ok);
roster = saved.roster;
assert.ok(writeKitCharacters(roster,store));
roster = readKitCharacters(store);
assert.equal(roster.characters[1].code,draft.code,'kit code survives storage round trip');
assert.equal(roster.characters[1].name,"Ada script O'Brien",'name is cleaned and preserves apostrophes');
assert.equal(cleanKitName('  A*B   C  '),'AB C');
assert.equal(deleteKitCharacter(roster,roster.characters[0].code).roster.characters.length,1);
assert.equal(deleteKitCharacter({characters:[roster.characters[0]],wearing:roster.wearing},roster.characters[0].code).ok,false);
memory.set(KIT_STORE_KEY,'{');
assert.equal(readKitCharacters(store).characters[0].code,encodeKit(DEFAULT_KIT),'bad JSON recovers');
memory.set(KIT_STORE_KEY,JSON.stringify({characters:[{name:'<bad>',code:'k1%%%%'}],wearing:'k1%%%%'}));
assert.equal(decodeKit(readKitCharacters(store).characters[0].code).parts.build,DEFAULT_KIT.parts.build,'bad digits recover');

const earned = KIT_CATEGORIES.flatMap((c)=>c.options.filter((o)=>o.unlock).map((o)=>({c,o})));
assert.equal(earned.length,2);
for (const {c,o} of earned) {
  const code = encodeKit({parts:{...DEFAULT_KIT.parts,[c.id]:o.id},colours:DEFAULT_KIT.colours});
  assert.notEqual(webKitCode(code),code,'earned part is removed from imported code');
  assert.equal(new KitDraft().part(c.id,o.id),false,'earned part cannot be chosen');
}

const history = new KitDraft();
const first = history.code;
history.randomPart('head',()=>0);
const second = history.code;
assert.notEqual(second,first,'random part changes the selected part');
assert.ok(history.undo()); assert.equal(history.code,first);
assert.ok(history.redo()); assert.equal(history.code,second);
history.locks.add('head');
history.locks.add('hair'); history.locks.add('facialHair'); history.locks.add('brows');
const before = decodeKit(history.code);
history.randomise(()=>0.99);
const after = decodeKit(history.code);
assert.equal(after.parts.head,before.parts.head,'locked part stays');
assert.equal(after.colours.hair,before.colours.hair,'colour stays when all painted parts are locked');
assert.ok(!KIT_CATEGORIES.some((c)=>c.options.find((o)=>o.id===after.parts[c.id])?.unlock),'randomise excludes earned parts');
assert.ok(KIT_COLOURS.some((c)=>after.colours[c.id]!==before.colours[c.id]),'randomise changes unlocked paint');

// Drive the actual menu keyboard handler, with only DOM painting stubbed.
const node = () => ({ innerHTML:'', classList:{remove(){},add(){},contains(){return false}}, appendChild(){}, addEventListener(){},
  querySelector(){return null},querySelectorAll(){return []} });
globalThis.document = { createElement:node, hidden:false, body:{} };
globalThis.localStorage = { getItem:(k)=>memory.get(k)||null, setItem:(k,v)=>memory.set(k,v) };
globalThis.window = { addEventListener(){}, confirm:()=>true, devicePixelRatio:1 };
globalThis.requestAnimationFrame = () => 1;
globalThis.cancelAnimationFrame = () => {};
const { Menus } = await import('../src/ui/menus.js');
const menu = new Menus({appendChild(){}},{});
menu._kitOpen(); menu.kitGroup='body'; menu.kitCategory='build';
const key = (code,ctrlKey=false) => { const ev={code,ctrlKey,target:{tagName:'BUTTON'},preventDefault(){this.prevented=true}}; menu._kitKey(ev); return ev; };
const start = menu.kitDraft.code;
assert.ok(key('ArrowRight').prevented);
assert.notEqual(menu.kitDraft.code,start,'right arrow selects an option');
assert.ok(key('ArrowDown').prevented);
assert.equal(menu.kitCategory,'head','down arrow selects a part');
assert.ok(key('KeyE').prevented);
assert.equal(menu.kitGroup,'face','E switches tabs');
assert.equal(menu.kitCategory,'eyes','a tab opens on its first matching category');
assert.ok(key('KeyQ').prevented);
assert.equal(menu.kitGroup,'body','Q switches tabs back');
assert.equal(menu.kitCategory,'build');
assert.ok(key('KeyR').prevented);
assert.ok(key('KeyZ',true).prevented,'Ctrl+Z reaches undo');
assert.ok(key('KeyY',true).prevented,'Ctrl+Y reaches redo');
assert.ok(key('Escape').prevented);
assert.equal(menu.screen,'kit','Escape closes after asking about changes');
menu.show('setup');
const enter={code:'Enter',target:document.body,preventDefault(){this.prevented=true}};
menu._kitKey(enter);
assert.ok(enter.prevented);
assert.equal(menu.config.slots[1].type,'kb2','keyboard 2 can join from the select screen');
Object.defineProperty(globalThis,'navigator',{configurable:true,value:{getGamepads:()=>[
  {buttons:Array.from({length:16},(_,i)=>({pressed:i===0}))},
]}});
menu._pollMenuPads();
assert.equal(menu.config.slots[2].type,'pad0','gamepad A joins the next open slot');
menu.hide();
console.log('PASS kit characters: storage, sanitising, locks, earned parts, undo/redo and menu keyboard');
