// The combo steps' animations (COMBO in config.js; channels.js bodyCategory and weapons2d.js
// SWINGS), asserted on the poses themselves. channel-parity proves the Luau draws what the
// JavaScript draws; it cannot prove either draws a string that READS as a string. This does:
//
//   * every combo step resolves to its own body family - LightNeutral2 and 3 are not the jab
//     again, LightSide2 is not LightSide1 - and an air finisher is a slam iff it sends downward;
//   * consecutive links of every weapon's strings look different at contact, in the body and (for
//     swung weapons) in the weapon's angle;
//   * every new family's recovery comes back to rest, so a move never ends on a snap;
//   * a finisher holds its contact longer than the light that opens its string;
//   * the combo break has a pose of its own, flashing white as it bursts out.
import { makeMatch, skipCountdown } from './harness.mjs';
import { channelsFor, bodyCategory } from '../src/render2d/channels.js';
import { weaponPose } from '../src/render2d/weapons2d.js';
import { WEAPONS } from '../src/data/weapons/index.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const AIMED = new Set(['Blasters', 'Grimoire', 'Longbow']);   // weapons2d aims these rather than swinging them

const flat = (ch) => {
  const out = {};
  for (const [k, v] of Object.entries(ch)) {
    if (typeof v === 'number') out[k] = v;
    else if (v && typeof v === 'object') for (const [k2, v2] of Object.entries(v)) if (typeof v2 === 'number') out[`${k}.${k2}`] = v2;
  }
  return out;
};
// How different two poses are, over the channels a viewer reads a pose by.
const KEYS = ['armR.z', 'armL.z', 'lean', 'legR', 'legL', 'sx', 'sy', 'head', 'bob', 'armR.ext'];
const spinOf = (p) => { const s = ((p.spinY || 0) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI); return Math.min(s, 2 * Math.PI - s); };
const dist = (a, b) => KEYS.reduce((s, k) => s + Math.abs((a[k] ?? 0) - (b[k] ?? 0)), 0) + Math.abs(spinOf(a) - spinOf(b));

function fighterFor(weapon) {
  const m = makeMatch({ loadouts: [['Classic', weapon], ['Noir', 'Sword']] });
  skipCountdown(m);
  for (let i = 0; i < 120; i++) m.step();
  const f = m.fighters[0];
  f.onGround = true; f.platform = m.stage.main; f.vx = 0; f.vy = 0;
  return f;
}
// The pose and weapon angle `frac` of the way through a move's phase: 'strike' (the active frames)
// or 'end' (the last recovery frame).
function at(f, id, where) {
  f.setState('idle'); f.startMove(id);
  const m = f.move;
  f.mf = where === 'end' ? f.startupEff + m.active + m.recovery : f.startupEff + Math.max(1, Math.ceil(m.active / 2));
  return { body: flat(channelsFor(f, 0)), angle: weaponPose(f, 0).angle };
}
// The weapon's path through a move: where it is cocked, mid-strike, and at the end of the strike.
// Two links that hit the same spot rightly meet it at the same angle; what tells them apart is
// where the swing comes from and where it travels.
function path(f, id) {
  const angles = [];
  for (const k of ['cocked', 'mid', 'out']) {
    f.setState('idle'); f.startMove(id);
    const m = f.move;
    f.mf = k === 'cocked' ? f.startupEff : k === 'mid' ? f.startupEff + Math.max(1, Math.ceil(m.active / 2)) : f.startupEff + m.active;
    angles.push(weaponPose(f, 0).angle);
  }
  return angles;
}

// ---- 1. families ----
{
  const bad = [];
  for (const w of WEAPONS) {
    const M = w.moves;
    const cat = (id) => (M[id] ? bodyCategory({ ...M[id], id }) : null);
    if (cat('LightNeutral2') !== 'jab2' || cat('LightNeutral3') !== 'jab3' || cat('LightSide2') !== 'side2') bad.push(`${w.id}: string steps ${cat('LightNeutral2')}/${cat('LightNeutral3')}/${cat('LightSide2')}`);
    if (cat('Finisher') !== 'finisher') bad.push(`${w.id}: Finisher is ${cat('Finisher')}`);
    const want = M.AirFinisher.angle > 180 ? 'airslam' : 'airlaunch';
    if (cat('AirFinisher') !== want) bad.push(`${w.id}: AirFinisher at ${M.AirFinisher.angle} degrees is ${cat('AirFinisher')}, want ${want}`);
  }
  check('every combo step has its own body family', bad.length === 0, bad.length ? bad.join('; ') : `${WEAPONS.length} weapons: second and third jab, second side, finisher, and a slam or heave by angle`);
}

// ---- 2. consecutive links look different ----
{
  const PAIRS = [['LightNeutral1', 'LightNeutral2'], ['LightNeutral2', 'LightNeutral3'], ['LightSide1', 'LightSide2'], ['LightNeutral3', 'Finisher'], ['LightNeutral2', 'Finisher']];
  const bodySame = [], weaponSame = [];
  let worstBody = Infinity, worstWeapon = Infinity;
  for (const w of WEAPONS) {
    const f = fighterFor(w.id);
    for (const [a, b] of PAIRS) {
      if (!w.moves[a] || !w.moves[b]) continue;
      // only pairs that are actually a link in this weapon's data
      const linked = Object.values(w.moves[a].chains || {}).includes(b) || Object.values(w.moves[a].finishers || {}).includes(b);
      if (!linked) continue;
      const pa = at(f, a, 'strike'), pb = at(f, b, 'strike');
      const d = dist(pa.body, pb.body);
      worstBody = Math.min(worstBody, d);
      if (d < 0.6) bodySame.push(`${w.id} ${a}>${b} (${d.toFixed(2)})`);
      if (!AIMED.has(w.id)) {
        const qa = path(f, a), qb = path(f, b);
        const dA = qa.reduce((s, v, i) => s + Math.abs(v - qb[i]), 0) * 180 / Math.PI;
        worstWeapon = Math.min(worstWeapon, dA);
        if (dA < 25) weaponSame.push(`${w.id} ${a}>${b} (${dA.toFixed(1)} deg)`);
      }
    }
  }
  check('consecutive links differ in the body at contact', bodySame.length === 0,
    bodySame.length ? `too alike: ${bodySame.join('; ')}` : `every link pair differs by ${worstBody.toFixed(2)} or more over ${KEYS.length} channels and the spin`);
  check('consecutive links swing the weapon differently', weaponSame.length === 0,
    weaponSame.length ? `same path: ${weaponSame.join('; ')}` : `swung weapons: every link's cocked, mid and end angles differ by ${worstWeapon.toFixed(1)} degrees or more in all from the link before`);
}

// ---- 3. every new family's recovery ends at rest ----
{
  const bad = [];
  for (const w of WEAPONS) {
    const f = fighterFor(w.id);
    for (const id of ['LightNeutral2', 'LightNeutral3', 'LightSide2', 'Finisher', 'AirFinisher']) {
      if (!w.moves[id]) continue;
      const p = at(f, id, 'end').body;
      const off = [];
      if (Math.abs(p['armR.z']) > 0.8) off.push(`armR ${p['armR.z'].toFixed(2)}`);
      if (Math.abs(p['armL.z']) > 0.8) off.push(`armL ${p['armL.z'].toFixed(2)}`);
      if (Math.abs(p.lean) > 0.15) off.push(`lean ${p.lean.toFixed(2)}`);
      if (spinOf(p) > 0.05) off.push(`spin ${spinOf(p).toFixed(2)}`);
      if (Math.abs(p.sy - 1) > 0.06 || Math.abs(p.sx - 1) > 0.06) off.push(`scale ${p.sx.toFixed(2)}x${p.sy.toFixed(2)}`);
      if (off.length) bad.push(`${w.id} ${id}: ${off.join(', ')}`);
    }
  }
  check('every combo step settles back to rest', bad.length === 0, bad.length ? bad.slice(0, 6).join('; ') : 'arms, lean, spin and squash all home on the last recovery frame - no snap when the move ends');
}

// ---- 4. a finisher holds its contact longer than the light opening its string ----
{
  const bad = [];
  for (const w of WEAPONS) {
    if (w.moves.Finisher.active <= w.moves.LightNeutral1.active) bad.push(`${w.id}: ${w.moves.Finisher.active} vs ${w.moves.LightNeutral1.active}`);
  }
  check('a finisher holds its contact longer than the opening light', bad.length === 0, bad.length ? bad.join('; ') : 'every finisher is active for more frames than its LightNeutral1');
}

// ---- 5. the break has its own pose ----
{
  const f = fighterFor('Sword');
  f.setState('idle'); const idle = flat(channelsFor(f, 0));
  f.setState('breakout'); f.sf = 1; const burst = flat(channelsFor(f, 0)); const flash = channelsFor(f, 0).tint;
  f.sf = 16; const late = flat(channelsFor(f, 0)); const lateTint = channelsFor(f, 0).tint;
  check('the combo break bursts out and settles', dist(burst, idle) > 2 && dist(late, idle) < dist(burst, idle) && flash === '#FFFFFF' && lateTint === null,
    `burst ${dist(burst, idle).toFixed(2)} from idle, settled ${dist(late, idle).toFixed(2)}; flash ${flash} then ${lateTint}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
