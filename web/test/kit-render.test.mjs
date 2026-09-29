import assert from 'node:assert/strict';
import { buildLoadout } from '../src/data/loadout.js';
import { KIT_PARTS, KIT_PRESETS, encodeKit, presetKit } from '../src/data/avatarKit.js';
import { posedFighter } from '../src/render2d/preview.js';

const mul = (a, b) => ({ a: a.a*b.a+a.c*b.b, b: a.b*b.a+a.d*b.b,
  c: a.a*b.c+a.c*b.d, d: a.b*b.c+a.d*b.d, e: a.a*b.e+a.c*b.f+a.e, f: a.b*b.e+a.d*b.f+a.f });
const ident = () => ({ a:1,b:0,c:0,d:1,e:0,f:0 });
const point = (m,x,y) => ({ x:m.a*x+m.c*y+m.e, y:m.b*x+m.d*y+m.f });
let canvases = [];
function canvas() {
  const cv = { width:480, height:270, style:{}, getBoundingClientRect:()=>({ width:480,height:270 }) };
  let m = ident(), alpha = 1, fill = '#000', smooth = true;
  const stack = [], images = [], fills = [];
  const ctx = new Proxy({ images, fills }, {
    get(t,k) {
      if (k === 'save') return () => stack.push([m,alpha,fill,smooth]);
      if (k === 'restore') return () => { [m,alpha,fill,smooth] = stack.pop(); };
      if (k === 'translate') return (x,y) => { m=mul(m,{...ident(),e:x,f:y}); };
      if (k === 'scale') return (x,y) => { m=mul(m,{a:x,b:0,c:0,d:y,e:0,f:0}); };
      if (k === 'rotate') return (v) => { m=mul(m,{a:Math.cos(v),b:Math.sin(v),c:-Math.sin(v),d:Math.cos(v),e:0,f:0}); };
      if (k === 'setTransform') return (a,b,c,d,e,f) => { m={a,b,c,d,e,f}; };
      if (k === 'getTransform') return () => m;
      if (k === 'drawImage') return (src,x,y,w,h) => images.push({src,x,y,w,h,m:{...m},smooth});
      if (k === 'fillRect') return (x,y,w,h) => fills.push({x,y,w,h,fill,alpha,m:{...m}});
      if (k === 'createLinearGradient' || k === 'createRadialGradient') return () => ({ addColorStop() {} });
      if (k === 'measureText') return () => ({width:10});
      if (k === 'globalAlpha') return alpha;
      if (k === 'fillStyle') return fill;
      if (k === 'imageSmoothingEnabled') return smooth;
      if (k in t) return t[k];
      return () => {};
    },
    set(t,k,v) { if(k==='globalAlpha') alpha=v; else if(k==='fillStyle') fill=v; else if(k==='imageSmoothingEnabled') smooth=v; else t[k]=v; return true; },
  });
  cv.getContext = () => ctx; cv.ctx = ctx; canvases.push(cv); return cv;
}
globalThis.document = { createElement: () => canvas() };
globalThis.window = { devicePixelRatio:1 };
const { Renderer2D } = await import('../src/render2d/renderer2d.js');
const code = encodeKit(presetKit(KIT_PRESETS.find((p) => p.id === 'knight')));
const fighter = posedFighter(buildLoadout(code,'Sword'),null,0,{state:'idle'});
const view = new Renderer2D(canvas());
const paint = (ppu) => { const target=canvas(); view.drawFighterInto(target.ctx,fighter,0,{ppu,x:200,y:200}); return target.ctx; };

const full = paint(20);
assert.equal(full.images.length,7,'kit rig draws two legs, pelvis, two arms, torso, head');
assert.ok(full.images.every((d)=>d.smooth===false),'pixel art always uses nearest-neighbour sampling');
assert.ok(!full.fills.some((d)=>Math.abs(d.w-fighter.r*1.6)<0.0001 && Math.abs(d.h-fighter.h*.36)<0.0001),
  'kit torso replaces the block torso and its mark');
assert.ok(!full.fills.some((d)=>Math.abs(d.w-fighter.r*.42)<0.0001 && Math.abs(d.h-fighter.h*.34)<0.0001),
  'kit legs replace block limbs');

// The head's point at (ox,oy) is the HEAD joint; the leg's foot reaches the floor.
const head = full.images.find((d)=>d.src.width===KIT_PARTS.head.w);
assert.ok(head,'head image exists');
const hs = fighter.r*1.15/12;
const neck = point(head.m,head.x+KIT_PARTS.head.ox*hs,head.y+KIT_PARTS.head.oy*hs);
assert.ok(Math.abs(neck.y-(200-20*fighter.h*.78))<2,'head joint lands at the rig neck');
const legs = full.images.filter((d)=>d.src.width===KIT_PARTS.leg.w);
assert.equal(legs.length,2);
const feet = legs.map((d)=>point(d.m,d.x,d.y+d.h).y);
assert.ok(feet.every((y)=>Math.abs(y-200)<8),'kit feet sit near the standing block rig floor');
assert.notEqual(legs[0].src,legs[1].src,'far leg uses a separate raster');
const arms = full.images.filter((d)=>d.src.width===KIT_PARTS.arm.w);
assert.notEqual(arms[0].src,arms[1].src,'far arm uses a separate raster');
assert.notDeepEqual(legs[0].src.ctx.fills.map((d)=>d.fill),legs[1].src.ctx.fills.map((d)=>d.fill),
  'far leg is colour darkened, not made transparent');

const half = paint(5);
assert.equal(half.images.length,7);
assert.ok(half.images.some((d)=>d.src.width===Math.ceil(KIT_PARTS.head.w/2)),'low zoom uses half detail');
assert.ok(full.images.some((d)=>d.src.width===KIT_PARTS.head.w),'near zoom uses full detail');
assert.equal(paint(20).images[0].src,full.images[0].src,'raster is reused between frames');

const classic = posedFighter(buildLoadout('Classic','Sword'),null,0,{state:'idle'});
const target=canvas(); view.drawFighterInto(target.ctx,classic,0,{ppu:20,x:200,y:200});
assert.equal(target.ctx.images.length,0,'preset keeps the original block body');
assert.ok(target.ctx.fills.some((d)=>Math.abs(d.w-fighter.r*1.6)<0.0001),'preset still draws its block torso');
console.log('PASS kit renderer: seven jointed cached sprites, shaded far limbs, LOD and legacy block body');
