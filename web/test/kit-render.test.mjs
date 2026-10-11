import assert from 'node:assert/strict';
import { buildLoadout } from '../src/data/loadout.js';
import { KIT_PARTS, KIT_PRESETS, encodeKit, presetKit } from '../src/data/avatarKit.js';
import { posedFighter } from '../src/render2d/preview.js';
import { channelsFor } from '../src/render2d/channels.js';
import { weaponPose } from '../src/render2d/weapons2d.js';
import { AVATARS, kitCodeOf, registerAvatar } from '../src/data/avatars.js';

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

// Full detail is the jointed rig (rig.js), drawn far leg (thigh, shin), near leg, pelvis, far arm
// (upper, forearm), torso, head, near arm. `T` is a moment of the idle where the breathing has the
// body well off its rest height, so a foot that rode the bob would be caught.
const T = 0.7;
const ch = channelsFor(fighter, T), wp = weaponPose(fighter, T);
assert.ok(Math.abs(ch.bob) > 0.05, `the test's moment has too little bob (${ch.bob}) to tell a planted foot from one riding it`);
const paintAt = (ppu, t) => { const target=canvas(); view.drawFighterInto(target.ctx,fighter,t,{ppu,x:200,y:200}); return target.ctx; };
const full = paintAt(20, T);
assert.equal(full.images.length,11,'the jointed rig draws two thighs, two shins, pelvis, two upper arms, two forearms, torso, head');
assert.ok(full.images.every((d)=>d.smooth===false),'pixel art always uses nearest-neighbour sampling');
assert.ok(!full.fills.some((d)=>Math.abs(d.w-fighter.r*1.6)<0.0001 && Math.abs(d.h-fighter.h*.36)<0.0001),
  'kit torso replaces the block torso and its mark');
assert.ok(!full.fills.some((d)=>Math.abs(d.w-fighter.r*.42)<0.0001 && Math.abs(d.h-fighter.h*.34)<0.0001),
  'kit legs replace block limbs');
const [farThigh, farShin, nearThigh, nearShin, , farUpper, farFore, torso, head, nearUpper, nearFore] = full.images;
const dims = (d, id) => d.src.width === KIT_PARTS[id].w && d.src.height === KIT_PARTS[id].h;
for (const [d, id] of [[farThigh,'thigh'],[nearThigh,'thigh'],[farShin,'shin'],[nearShin,'shin'],[farUpper,'upperarm'],[nearUpper,'upperarm'],[farFore,'forearm'],[nearFore,'forearm'],[head,'head'],[torso,'torso']])
  assert.ok(dims(d, id), `${id} is drawn in its place in the order, from its own cut of the art`);
for (const [a, b, id] of [[farThigh,nearThigh,'thigh'],[farShin,nearShin,'shin'],[farUpper,nearUpper,'upper arm'],[farFore,nearFore,'forearm']]) {
  assert.notEqual(a.src,b.src,`the far ${id} uses a separate raster`);
  assert.notDeepEqual(a.src.ctx.fills.map((d)=>d.fill),b.src.ctx.fills.map((d)=>d.fill),`the far ${id} is colour darkened, not made transparent`);
}

// The head's point at (ox,oy) is the HEAD joint.
const hs = fighter.r*1.15/12;
const neck = point(head.m,head.x+KIT_PARTS.head.ox*hs,head.y+KIT_PARTS.head.oy*hs);
assert.ok(Math.abs(neck.y-(200-20*(fighter.h*.34+ch.bob+fighter.h*.44*ch.sy*Math.cos(ch.lean))))<2,'head joint lands at the rig neck');
// A segment's joint is its frame's origin; its far end is `span` cells down the limb (the image is
// drawn flipped, so down the limb is +y in the image's frame).
const rootOf = (d) => point(d.m, 0, 0);
const tipOf = (d, id) => point(d.m, 0, KIT_PARTS[id].span * d.h / d.src.height);
const near = (p, q, tol, what) => assert.ok(Math.hypot(p.x - q.x, p.y - q.y) < tol, `${what}: (${p.x}, ${p.y}) against (${q.x}, ${q.y})`);
// The joints hold: each upper segment ends exactly where its lower one hangs from.
for (const [u, l, what] of [[farThigh,farShin,'far knee'],[nearThigh,nearShin,'near knee'],[farUpper,farFore,'far elbow'],[nearUpper,nearFore,'near elbow']])
  near(tipOf(u, u === farThigh || u === nearThigh ? 'thigh' : 'upperarm'), rootOf(l), 1e-9, what);
// The hand is the grip: the near forearm ends exactly where renderer2d hangs the weapon - the
// shoulder plus 0.30h x ext along the weapon's angle, in the torso's frame (whose transform the
// torso image carries, under its own flip).
const tm = mul(torso.m, { a:1,b:0,c:0,d:-1,e:0,f:0 });
const HIP = fighter.h*0.34, SHO = fighter.h*0.70, AL = fighter.h*0.30*(ch.armR.ext||1);
const gripAt = point(tm, fighter.r*0.55 + Math.cos(wp.angle)*AL, (SHO-HIP) + Math.sin(wp.angle)*AL);
near(tipOf(nearFore,'forearm'), gripAt, 1e-9, 'the hand is on the grip');
// Running too: the run writes its arm swing into armR.x, which the weapon never had - an armed arm
// that kept it swung a hand-width off its own grip.
{
  const runner = posedFighter(buildLoadout(code,'Sword'),null,0,{state:'run',vx:22,onGround:true});
  for (const t of [0.1, 0.45, 0.8]) {
    runner.frameCount = Math.round(t * 60);
    const rc = channelsFor(runner, t), rw = weaponPose(runner, t);
    assert.ok(t !== 0.45 || Math.abs(rc.armR.x) > 0.1, `the run's arm swing is too small at this moment (${rc.armR.x}) to test`);
    const target = canvas(); view.drawFighterInto(target.ctx, runner, t, { ppu: 20, x: 200, y: 200 });
    const im = target.ctx.images, rtm = mul(im[7].m, { a:1,b:0,c:0,d:-1,e:0,f:0 });
    const RAL = runner.h*0.30*(rc.armR.ext||1);
    near(tipOf(im[10],'forearm'), point(rtm, runner.r*0.55 + Math.cos(rw.angle)*RAL, (SHO-HIP) + Math.sin(rw.angle)*RAL), 1e-9, `a running hand is on the grip (t ${t})`);
  }
}
// Drawn the way Roblox can draw it: every limb segment's transform is a rotation and a scale, never a
// shear (a Frame cannot shear, so a sheared web segment is a picture the Roblox build cannot match).
// Across poses that lean, squash and spin - a recovery squeezes the torso to an eighth of its width
// - with the joints and the grip held in each.
{
  const L = buildLoadout(code,'Sword');
  const poses = [['recovery',false,3],['recovery',false,6],['idle',true,0],['run',true,0],['landing',true,1],['hitstun',false,2],['jumpsquat',true,3],['air',false,5]];
  for (const [state, onGround, sf] of poses) {
    const pf = posedFighter(L, null, sf, { state, onGround, vx: state === 'run' ? 22 : 0, frameCount: 17 });
    pf.move = null; pf.moveId = null; pf.sf = sf;
    const pc = channelsFor(pf, 0.3), pw = weaponPose(pf, 0.3);
    const target = canvas(); view.drawFighterInto(target.ctx, pf, 0.3, { ppu: 20, x: 200, y: 200 });
    const im = target.ctx.images;
    assert.equal(im.length, 11, `${state} ${sf}: the jointed body`);
    const segs = { 0:'thigh', 1:'shin', 2:'thigh', 3:'shin', 5:'upperarm', 6:'forearm', 9:'upperarm', 10:'forearm' };
    for (const [i, id] of Object.entries(segs)) {
      const m = im[i].m, skew = Math.abs(m.a*m.c + m.b*m.d) / (Math.hypot(m.a,m.b) * Math.hypot(m.c,m.d));
      assert.ok(skew < 1e-9, `${state} ${sf}: the ${id} is drawn sheared (${skew}), which Roblox cannot draw`);
    }
    for (const [u, l, uid] of [[0,1,'thigh'],[2,3,'thigh'],[5,6,'upperarm'],[9,10,'upperarm']]) near(tipOf(im[u], uid), rootOf(im[l]), 1e-9, `${state} ${sf}: a joint`);
    const ptm = mul(im[7].m, { a:1,b:0,c:0,d:-1,e:0,f:0 }), PAL = pf.h*0.30*(pc.armR.ext||1);
    near(tipOf(im[10],'forearm'), point(ptm, pf.r*0.55 + Math.cos(pw.angle)*PAL, (SHO-HIP) + Math.sin(pw.angle)*PAL), 1e-9, `${state} ${sf}: the hand on the grip`);
    // And at half detail: one-piece limbs (far leg, near leg, pelvis, far arm, torso, head, near arm),
    // shear-free, the near arm ending on the grip. A half raster's rows are drawn twice as tall.
    const small = canvas(); view.drawFighterInto(small.ctx, pf, 0.3, { ppu: 5, x: 200, y: 200 });
    const hm = small.ctx.images;
    assert.equal(hm.length, 7, `${state} ${sf}: the half-detail body`);
    for (const i of [0, 1, 3, 6]) {
      const m = hm[i].m, skew = Math.abs(m.a*m.c + m.b*m.d) / (Math.hypot(m.a,m.b) * Math.hypot(m.c,m.d));
      assert.ok(skew < 1e-9, `${state} ${sf}: a half-detail limb is drawn sheared (${skew})`);
    }
    const htm = mul(hm[4].m, { a:1,b:0,c:0,d:-1,e:0,f:0 });
    near(point(hm[6].m, 0, KIT_PARTS.arm.span * hm[6].h / (hm[6].src.height * 2)),
      point(htm, pf.r*0.55 + Math.cos(pw.angle)*PAL, (SHO-HIP) + Math.sin(pw.angle)*PAL), 1e-9, `${state} ${sf}: the half-detail hand on the grip`);
  }
}
// And the elbow bends at rest: the elbow is off the straight line from shoulder to hand.
const sh = rootOf(nearUpper), el = tipOf(nearUpper,'upperarm'), hd = tipOf(nearFore,'forearm');
assert.ok(Math.abs((hd.x-sh.x)*(el.y-sh.y)-(hd.y-sh.y)*(el.x-sh.x))/Math.hypot(hd.x-sh.x,hd.y-sh.y) > 2,'the front arm has an elbow at rest');
// The feet are planted: each shin ends where the one-piece leg's foot would without the bob - on
// the floor, lifted only by the stance's leg angle - not riding the breathing.
for (const [d, rot, what] of [[farShin, ch.legL, 'far'], [nearShin, ch.legR, 'near']])
  assert.ok(Math.abs(tipOf(d,'shin').y - (200 - 20*HIP*(1-Math.cos(rot)))) < 1e-9, `the ${what} foot is planted (bob ${ch.bob})`);

const half = paint(5);
assert.equal(half.images.length,7,'a fighter too small for an elbow to read keeps the seven one-piece pieces');
// The half-detail feet are planted too, or they would jump as a fighter crosses the threshold.
{
  const hb = paintAt(5, T).images;
  for (const [d, rot, what] of [[hb[0], ch.legL, 'far'], [hb[1], ch.legR, 'near']])
    // a half-detail raster has half the rows, each drawn twice as tall: the limb's own length is unchanged
    assert.ok(Math.abs(point(d.m, 0, KIT_PARTS.leg.span * d.h / (d.src.height * 2)).y - (200 - 5*HIP*(1-Math.cos(rot)))) < 1e-9, `the ${what} half-detail foot is planted (bob ${ch.bob})`);
}
assert.ok(half.images.some((d)=>d.src.width===Math.ceil(KIT_PARTS.head.w/2)),'low zoom uses half detail');
assert.ok(full.images.some((d)=>d.src.width===KIT_PARTS.head.w),'near zoom uses full detail');
assert.equal(paintAt(20, T).images[0].src,full.images[0].src,'raster is reused between frames');

// The presets are kit characters under their old ids (character-rework-plan.md, phase 1): 'Classic'
// draws the eleven-piece kit body, exactly the rasters its own kit code draws - not the block body.
const drawn = (id) => { const t = canvas(); view.drawFighterInto(t.ctx, posedFighter(buildLoadout(id,'Sword'),null,0,{state:'idle'}),0,{ppu:20,x:200,y:200}); return t.ctx; };
const classic = drawn('Classic'), byCode = drawn(kitCodeOf('Classic'));
assert.equal(classic.images.length,11,'a preset draws as a kit character');
assert.ok(classic.images.every((d,i)=>d.src===byCode.images[i].src),'a preset draws exactly what its kit code draws');
for (const a of AVATARS) assert.equal(drawn(a.id).images.length,11,`${a.id} draws as a kit character`);
// A character from the original creator (the hand-drawing mode, kept whole) has no kit and keeps
// the block body.
registerAvatar({ id: 'legacy-test', name: 'Legacy', rig: 'avatar', features: { head: 'block', face: 'dot', hat: 'none', torso: 'belt' },
  palette: { primary: '#F2C94C', secondary: '#4A90D9', tertiary: '#2E5F8A', accent: '#FFF3D0', glow: '#8ED8FF' } });
const legacy = drawn('legacy-test');
assert.equal(legacy.images.length,0,'an original-creator character keeps the block body');
assert.ok(legacy.fills.some((d)=>Math.abs(d.w-fighter.r*1.6)<0.0001),'and its block torso');
console.log('PASS kit renderer: eleven jointed sprites at full detail - joints held, the hand on the grip, feet planted through the bob - seven at half detail, shaded far limbs, cached rasters; the presets draw as kits, original-creator characters keep the block body');
