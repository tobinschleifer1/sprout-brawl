// Does the renderer actually draw?
//
// This exists because of a bug the other 118 assertions were structurally blind to: `_stage()`
// referenced an undefined `m` in its hazard block, so every hazard draw threw a ReferenceError,
// aborted the frame before fighters and `_present()` ran, and froze the visible screen for 13-34%
// of a match on three of six stages — while the simulation carried on underneath. Every test
// passed, because not one of them rendered a frame.
//
// The fix is not clever: run the real renderer against a stub canvas, on every stage, at every
// hazard phase, and fail on any thrown error. A test suite for a game has to draw at least once.
import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { STAGES } from '../src/data/stages/index.js';
import { HAZARDS } from '../src/engine/hazards.js';

// Read the registry rather than a hand-written list, so a hazard added later cannot be silently
// left out of the only test that draws it.
const HAZARD_KEYS = Object.keys(HAZARDS);

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// A canvas 2D context that records nothing and refuses nothing. Any real error in the drawing code
// surfaces as a thrown exception rather than being swallowed.
function stubCtx() {
  const noop = () => {};
  return new Proxy({}, {
    get(target, prop) {
      if (prop === 'canvas') return { width: 480, height: 270 };
      // Both gradient factories. The radial one was missing, and the day something in the paint
      // path started using it the stub threw for every stage at frame 0.
      if (prop === 'createLinearGradient' || prop === 'createRadialGradient') return () => ({ addColorStop: noop });
      if (prop === 'measureText') return () => ({ width: 10 });
      if (prop === 'getImageData') return () => ({ data: new Uint8ClampedArray(4) });
      if (prop in target) return target[prop];
      return noop;
    },
    set(target, prop, value) { target[prop] = value; return true; },
  });
}

function stubCanvas() {
  return {
    width: 480, height: 270,
    getContext: () => stubCtx(),
    getBoundingClientRect: () => ({ width: 960, height: 540, top: 0, left: 0 }),
    style: {},
  };
}

// The renderer reaches for `document` and `window` at construction.
globalThis.document = { createElement: () => stubCanvas() };
globalThis.window = { devicePixelRatio: 1, addEventListener: () => {} };

const { Renderer2D } = await import('../src/render2d/renderer2d.js');

// ---- 1. every stage draws, at every hazard phase, without throwing ----
for (const data of STAGES) {
  const view = new Renderer2D(stubCanvas());
  const m = makeMatch({ stageId: data.id, loadouts: [['Classic', 'Sword'], ['Noir', 'Blasters'], ['Ember', 'Scythe'], ['Moss', 'Grimoire']] });
  m.itemsOn = true;
  m.fighters.forEach((f) => { f.isBot = true; f.botLevel = 'hard'; });
  view.setStage(m.stage);
  skipCountdown(m);

  const phasesSeen = new Set();
  let error = null, frames = 0;
  // 40 seconds covers the longest hazard cycle in the roster (Undertow's 34-second tide)
  for (let i = 0; i < 60 * 40 && !error; i++) {
    m.step();
    for (const e of m.events) { try { view.handle(e, m); } catch (err) { error = `handle(${e.type}): ${err.message}`; } }
    m.events.length = 0;
    const v = m.stage.visual || {};
    for (const key of HAZARD_KEYS) {
      if (v[key]) phasesSeen.add(`${key}:${v[key].phase || (v[key].active ? 'active' : v[key].warn ? 'warn' : 'on')}`);
    }
    try { view.frame(m, 1 / 60, i / 60, false); frames++; }
    catch (err) { error = `frame ${i}: ${err.message}`; }
  }
  const expected = data.hazards.length;
  check(`${data.name}: renders every frame`, !error,
    error ? `THREW — ${error}` : `${frames} frames drawn, hazard states exercised: ${[...phasesSeen].join(', ') || 'none (no hazards)'}${expected && !phasesSeen.size ? ' — WARNING: stage declares a hazard that never drew' : ''}`);
}

// ---- 2. a stage with a hazard must actually reach its active phase while drawing ----
for (const data of STAGES) {
  if (!data.hazards.length) continue;
  const view = new Renderer2D(stubCanvas());
  const m = makeMatch({ stageId: data.id, loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  view.setStage(m.stage);
  skipCountdown(m);
  const seen = new Set();
  for (let i = 0; i < 60 * 45; i++) {
    m.step();
    m.events.length = 0;
    const v = m.stage.visual || {};
    for (const key of HAZARD_KEYS) if (v[key]) seen.add(key);
    view.frame(m, 1 / 60, i / 60, false);
  }
  const declared = data.hazards.map((h) => h.type);
  const missing = declared.filter((t) => !seen.has(t));
  check(`${data.name}: its hazard reaches the renderer`, missing.length === 0,
    missing.length ? `declared ${declared.join(', ')} but ${missing.join(', ')} never produced a visual` : `${declared.join(', ')} drew`);
}

// ---- 3. the ultimates draw ----
{
  const { WEAPONS } = await import('../src/data/weapons/index.js');
  const { ULTIMATE } = await import('../src/config.js');
  const bad = [];
  for (const w of WEAPONS) {
    const view = new Renderer2D(stubCanvas());
    const m = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
    view.setStage(m.stage);
    skipCountdown(m);
    for (let i = 0; i < 200; i++) m.step();
    const a = m.fighters[0];
    a.x = -6; a.onGround = true; a.platform = m.stage.main; a.y = 0; a.setState('idle');
    a.ultCharge = ULTIMATE.hitsRequired; a.buffer.ult = 6;
    try {
      // Keep pressing the ultimate key: Deadeye is a stance that draws differently with each round
      // spent, and its recoil and empty-magazine frames are exactly where a drawing bug would hide.
      for (let i = 0; i < 260; i++) {
        if (i % 20 === 0) m._input.set('p0', { x: 0, y: 0, ult: true, anyPress: true, jump: false, light: false, heavy: false, dodge: false, guard: false, grab: false, taunt: false, pickup: false, jumpHeld: false, guardHeld: false, heavyHeld: false, lightHeld: false, downTap: false });
        else m._input.clear('p0');
        m.step();
        // Events must go THROUGH handle() here: the activation banner, the crater debris and the
        // soul-orb intake are all drawn from state that only handle() sets, so dropping the
        // events would leave the loudest half of every ultimate untested.
        for (const e of m.events) view.handle(e, m);
        m.events.length = 0;
        view.frame(m, 1 / 60, i / 60, false);
      }
    } catch (err) { bad.push(`${w.id}: ${err.message}`); }
  }
  check('every ultimate renders start to finish', bad.length === 0,
    bad.length ? bad.join('; ') : `${WEAPONS.length} ultimates drawn through windup, active and recovery`);
}

// ---- every stage theme has scenery, and every palette key it declares is actually painted ----
//
// Both halves of this check are for the same failure. Each of the six stages declared a
// `palette.glows` — a sun, a moon, a furnace mouth — and for the whole life of the project NOTHING
// READ IT: six deliberate light sources written down and thrown away, which is most of why the
// skies rendered as flat gradients. A stage theme with no entry in the scenery table fails the
// same way: the data is there, the drawing is not, and nothing says so.
{
  const { readFileSync } = await import('node:fs');
  const src = ['backdrop2d.js', 'renderer2d.js', 'ambient2d.js', 'hazards2d.js']
    .map((f) => readFileSync(new URL(`../src/render2d/${f}`, import.meta.url), 'utf8')).join('\n');
  const unread = new Set(), themeless = [];
  for (const d of STAGES) {
    if (!src.includes(`'${d.theme}'`)) themeless.push(`${d.name} (${d.theme})`);
    for (const key of Object.keys(d.palette)) {
      if (src.includes(`p.${key}`) || src.includes(`palette.${key}`) || src.includes(`.${key} ||`)) continue;
      unread.add(key);
    }
  }
  const bad = [...unread].map((k) => `palette.${k} is declared by the stages and read by no renderer`)
    .concat(themeless.map((t) => `${t} has no scenery bands — it renders as an empty sky`));
  check('every stage theme is drawn, and no palette key is dead data', bad.length === 0,
    bad.length ? bad.join('; ')
      : `${STAGES.length} themes all have scenery, and every palette key (${[...new Set(STAGES.flatMap((d) => Object.keys(d.palette)))].join(', ')}) is painted`);
}

// ---- the UI does not point at files that are not there ----
// The setup screen and the weapon roster both rendered `<img src="assets/ui/weapons/<id>.png">`,
// and the icons for the Battle Axe and the Warpike were never drawn - so the two newest weapons
// showed a broken image on the screen where you pick a weapon, from the day they shipped, and
// nothing anywhere said so. Both tiles are now painted by the weapon's own drawing code, and this
// makes sure no new reference to a missing file creeps back in.
{
  const { readFileSync, existsSync, readdirSync } = await import('node:fs');
  const files = readdirSync(new URL('../src/ui/', import.meta.url)).filter((f) => f.endsWith('.js'));
  const missing = [];
  for (const f of files) {
    const src = readFileSync(new URL(`../src/ui/${f}`, import.meta.url), 'utf8');
    for (const m of src.matchAll(/src="(assets\/[^"$]*)"/g)) {
      if (!existsSync(new URL(`../${m[1]}`, import.meta.url))) missing.push(`${f}: ${m[1]}`);
    }
    // A template that builds an asset path from a weapon or stage id has to be checked per id.
    for (const m of src.matchAll(/src="(assets\/[^"]*\$\{[^}]*\}[^"]*)"/g)) {
      const pattern = m[1];
      for (const w of WEAPONS) {
        const path = pattern.replace(/\$\{[^}]*\}/, w.id.toLowerCase());
        if (!existsSync(new URL(`../${path}`, import.meta.url))) missing.push(`${f}: ${path} (for ${w.id})`);
      }
    }
  }
  check('every asset the menus reference actually exists', missing.length === 0,
    missing.length ? `referenced but missing: ${[...new Set(missing)].join(', ')}`
      : `${files.length} UI files checked against the asset tree; weapon tiles are drawn from weapons2d.js rather than from per-weapon PNGs`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
