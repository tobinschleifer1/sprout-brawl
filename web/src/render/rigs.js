import * as THREE from '../../vendor/three.module.js';
import { instantiate as instantiateModel, hasModel } from './models.js';

// Procedural placeholder rigs: primitive shapes that read as each character's silhouette,
// posed every frame from the fighter's state. No animation assets needed.

const PI = Math.PI;
const mat = (color, opts = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.85, metalness: 0, flatShading: true, transparent: true, ...opts });
function mesh(geo, m) { const o = new THREE.Mesh(geo, m); o.castShadow = true; o.receiveShadow = false; return o; }
const box = (w, h, d, m) => mesh(new THREE.BoxGeometry(w, h, d), m);
const sphere = (r, m, seg = 9) => mesh(new THREE.SphereGeometry(r, seg, seg), m);
const cyl = (rt, rb, h, m, seg = 9) => mesh(new THREE.CylinderGeometry(rt, rb, h, seg), m);
const cone = (r, h, m, seg = 8) => mesh(new THREE.ConeGeometry(r, h, seg), m);
function rest(o, p = [0, 0, 0], r = [0, 0, 0], s = [1, 1, 1]) { o.position.set(...p); o.rotation.set(...r); o.scale.set(...s); o.userData.rest = { p: [...p], r: [...r], s: [...s] }; return o; }
function resetRest(o) { const R = o.userData.rest; if (!R) return; o.position.set(...R.p); o.rotation.set(...R.r); o.scale.set(...R.s); }

function paletteFor(char, skin) {
  if (skin > 0 && char.skins[skin - 1]) return char.skins[skin - 1];
  return char.palette;
}

// Standard humanoid frame. Returns { rig, parts } with rest transforms; height in studs.
function humanoid(P, opts) {
  const s = opts.scale, mats = P.mats;
  const rig = new THREE.Group();
  const hip = 1.2 * s;
  const body = rest(new THREE.Group(), [0, hip, 0]);
  const torso = rest(opts.torso || box(1.5 * s, 2.0 * s, 1.1 * s, mats.secondary), [0, 1.05 * s, 0]);
  body.add(torso);
  const head = rest(opts.head || sphere(0.95 * s, mats.primary), [0, 2.95 * s, 0]);
  body.add(head);
  const armGeo = () => cyl(0.22 * s, 0.26 * s, 1.5 * s, opts.armMat || mats.secondary);
  const armL = rest(new THREE.Group(), [0, 1.9 * s, -0.75 * s]); const aL = armGeo(); aL.position.y = -0.7 * s; armL.add(aL);
  const armR = rest(new THREE.Group(), [0, 1.9 * s, 0.75 * s]); const aR = armGeo(); aR.position.y = -0.7 * s; armR.add(aR);
  const handL = rest(sphere(0.3 * s, opts.handMat || mats.primary, 7), [0, -1.45 * s, 0]); armL.add(handL);
  const handR = rest(sphere(0.3 * s, opts.handMat || mats.primary, 7), [0, -1.45 * s, 0]); armR.add(handR);
  body.add(armL, armR);
  rig.add(body);
  const legGeo = () => cyl(0.26 * s, 0.3 * s, 1.15 * s, opts.legMat || mats.tertiary);
  const legL = rest(new THREE.Group(), [0, hip, -0.4 * s]); const lL = legGeo(); lL.position.y = -0.6 * s; legL.add(lL);
  const legR = rest(new THREE.Group(), [0, hip, 0.4 * s]); const lR = legGeo(); lR.position.y = -0.6 * s; legR.add(lR);
  if (!opts.noLegs) rig.add(legL, legR);
  // eyes
  const eyeM = mat('#1E2A1B', { roughness: 0.4 });
  const eyeW = mat('#FFFFFF', { roughness: 0.4 });
  const ey = (opts.eyeY ?? 3.0) * s, ex = (opts.eyeX ?? 0.75) * s, ez = (opts.eyeZ ?? 0.32) * s;
  for (const z of [-ez, ez]) {
    const w = rest(sphere(0.19 * s, eyeW, 6), [ex, ey, z]); const p = rest(sphere(0.1 * s, eyeM, 5), [ex + 0.14 * s, ey, z]);
    head.add(w, p);
  }
  return { rig, body, torso, head, armL, armR, legL, legR, handL, handR, s };
}

function bubble(rig, s) {
  const b = mesh(new THREE.SphereGeometry(3.2 * s, 14, 12), mat('#9FD1E8', { opacity: 0.35, roughness: 0.2, emissive: '#3FA0B0', emissiveIntensity: 0.3 }));
  b.castShadow = false; b.position.y = 2.4 * s; b.visible = false;
  rig.add(b);
  return b;
}

const BUILDERS = {
  thornlock(P, s) {
    const H = humanoid(P, { scale: s, torso: cyl(0.55 * s, 0.7 * s, 2.1 * s, P.mats.secondary), armMat: P.mats.secondary, legMat: P.mats.tertiary, head: sphere(0.8 * s, P.mats.primary, 8), eyeY: 2.9, eyeX: 0.62 });
    // petals ring
    const petals = new THREE.Group();
    for (let i = 0; i < 7; i++) {
      const a = (i / 7) * PI * 2;
      const p = rest(mesh(new THREE.SphereGeometry(0.45 * s, 7, 6), P.mats.primary), [Math.cos(a) * 0.7 * s, 2.95 * s + Math.sin(a) * 0.7 * s, 0], [0, 0, 0], [0.7, 1, 1.3]);
      petals.add(p);
    }
    H.body.add(petals);
    // sepal
    H.body.add(rest(cone(0.55 * s, 0.6 * s, P.mats.secondary, 6), [0, 2.1 * s, 0], [PI, 0, 0]));
    // thorns on torso
    for (let i = 0; i < 5; i++) H.torso.add(rest(cone(0.12 * s, 0.35 * s, P.mats.tertiary, 5), [0.55 * s, (-0.8 + i * 0.4) * s, (i % 2 ? 0.3 : -0.3) * s], [0, 0, -PI / 2]));
    // vines trailing from hands
    const vines = [];
    for (const hand of [H.handL, H.handR]) {
      const chain = [];
      let parent = hand;
      for (let i = 0; i < 4; i++) {
        const seg = rest(sphere(0.2 * s * (1 - i * 0.12), P.mats.secondary, 6), [0, -0.5 * s, 0]);
        parent.add(seg); chain.push(seg); parent = seg;
      }
      vines.push(chain);
    }
    return { ...H, extra: { petals, vines }, height: 5.0 };
  },
  capnspore(P, s) {
    const H = humanoid(P, { scale: s, torso: cyl(0.75 * s, 0.85 * s, 2.0 * s, P.mats.secondary), armMat: P.mats.secondary, legMat: P.mats.secondary, head: cyl(0.6 * s, 0.7 * s, 1.1 * s, P.mats.secondary, 10), eyeY: 3.0, eyeX: 0.55 });
    const cap = rest(mesh(new THREE.SphereGeometry(1.7 * s, 12, 8, 0, PI * 2, 0, PI / 2), P.mats.primary), [0, 3.15 * s, 0], [0, 0, 0.18]);
    const gills = rest(cyl(1.65 * s, 1.2 * s, 0.35 * s, P.mats.accent, 12), [0, 3.05 * s, 0], [0, 0, 0.18]);
    H.body.add(cap, gills);
    // coat
    const coat = rest(box(1.75 * s, 1.6 * s, 1.35 * s, P.mats.tertiary), [0, 0.9 * s, 0]);
    H.torso.add(rest(coat, [-0.1 * s, -0.1 * s, 0]));
    H.torso.add(rest(box(0.3 * s, 1.2 * s, 0.5 * s, P.mats.accent), [0.75 * s, 0.3 * s, 0.35 * s], [0, 0, 0.2]));
    H.torso.add(rest(box(0.3 * s, 1.2 * s, 0.5 * s, P.mats.accent), [0.75 * s, 0.3 * s, -0.35 * s], [0, 0, 0.2]));
    return { ...H, extra: { cap, gills }, height: 4.8 };
  },
  sunbeam(P, s) {
    const stem = cyl(0.35 * s, 0.5 * s, 2.4 * s, P.mats.tertiary);
    const H = humanoid(P, { scale: s, torso: stem, armMat: P.mats.tertiary, legMat: P.mats.tertiary, head: cyl(1.05 * s, 1.05 * s, 0.5 * s, P.mats.secondary, 14), eyeY: 3.05, eyeX: 0.3, eyeZ: 0.36 });
    H.head.rotation.z = PI / 2; H.head.userData.rest.r = [0, 0, PI / 2];
    const petals = new THREE.Group();
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * PI * 2;
      const p = rest(box(0.2 * s, 1.1 * s, 0.5 * s, P.mats.primary), [0, Math.cos(a) * 1.45 * s, Math.sin(a) * 1.45 * s], [-a, 0, 0]);
      petals.add(p);
    }
    petals.position.y = 2.95 * s; H.body.add(petals);
    // leaves as extra on the stem
    H.torso.add(rest(box(0.15 * s, 0.5 * s, 1.3 * s, P.mats.tertiary), [0.2 * s, -0.3 * s, 0.7 * s], [0.4, 0, 0]));
    H.torso.add(rest(box(0.15 * s, 0.5 * s, 1.3 * s, P.mats.tertiary), [0.2 * s, 0.4 * s, -0.7 * s], [-0.4, 0, 0]));
    return { ...H, extra: { petals }, height: 6.6 };
  },
  kelpin(P, s) {
    const rig = new THREE.Group();
    const body = rest(new THREE.Group(), [0, 0.6 * s, 0]);
    const segs = [];
    let parent = body;
    for (let i = 0; i < 6; i++) {
      const seg = rest(new THREE.Group(), [0, i === 0 ? 0 : 0.75 * s, 0]);
      const w = (1.6 - i * 0.12) * s;
      const m = rest(box(0.5 * s, 0.8 * s, w, P.mats.primary), [0, 0.4 * s, 0]);
      seg.add(m); parent.add(seg); parent = seg; segs.push(seg);
    }
    const head = segs[5];
    const eyeW = mat('#FFFFFF', { roughness: 0.4 }), eyeM = mat('#1E2A1B');
    for (const z of [-0.35 * s, 0.35 * s]) { head.add(rest(sphere(0.2 * s, eyeW, 6), [0.28 * s, 0.5 * s, z])); head.add(rest(sphere(0.1 * s, eyeM, 5), [0.42 * s, 0.5 * s, z])); }
    // net bits
    for (let i = 0; i < 3; i++) segs[i + 1].add(rest(box(0.6 * s, 0.08 * s, 1.5 * s, P.mats.secondary), [0.05 * s, 0.5 * s, 0], [0.5 + i * 0.3, 0, 0]));
    const holdfast = rest(cyl(0.9 * s, 1.2 * s, 0.6 * s, P.mats.accent, 8), [0, 0.3 * s, 0]);
    rig.add(holdfast, body);
    // arms = two fronds
    const armL = rest(new THREE.Group(), [0, 2.2 * s, -0.7 * s]); const armR = rest(new THREE.Group(), [0, 2.2 * s, 0.7 * s]);
    for (const a of [armL, armR]) { const f = box(0.25 * s, 1.5 * s, 0.5 * s, P.mats.primary); f.position.y = -0.7 * s; a.add(f); }
    segs[2].add(armL, armR);
    return { rig, body, torso: segs[0], head, armL, armR, legL: null, legR: null, handL: null, handR: null, s, extra: { segs }, height: 5.6, noLegs: true };
  },
  cacto(P, s) {
    const rig = new THREE.Group();
    const body = rest(new THREE.Group(), [0, 0.5 * s, 0]);
    const barrel = rest(mesh(new THREE.SphereGeometry(1.7 * s, 12, 10), P.mats.primary), [0, 1.9 * s, 0], [0, 0, 0], [1, 1.25, 1]);
    body.add(barrel);
    // ribs
    for (let i = 0; i < 8; i++) { const a = (i / 8) * PI * 2; barrel.add(rest(box(0.12 * s, 3.1 * s, 0.25 * s, P.mats.accent), [Math.cos(a) * 1.62 * s, 0, Math.sin(a) * 1.62 * s], [0, -a, 0])); }
    const spines = [];
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * PI * 2, y = (i % 3 - 1) * 0.9 * s;
      const sp = rest(cone(0.09 * s, 0.6 * s, P.mats.secondary, 5), [Math.cos(a) * 1.75 * s, y, Math.sin(a) * 1.75 * s], [0, 0, 0]);
      sp.lookAt(new THREE.Vector3(Math.cos(a) * 4, y, Math.sin(a) * 4)); sp.rotateX(PI / 2); sp.userData.rest.r = [sp.rotation.x, sp.rotation.y, sp.rotation.z];
      barrel.add(sp); spines.push(sp);
    }
    const flower = rest(new THREE.Group(), [0, 4.05 * s, 0]);
    for (let i = 0; i < 6; i++) { const a = (i / 6) * PI * 2; flower.add(rest(mesh(new THREE.SphereGeometry(0.3 * s, 6, 5), P.mats.tertiary), [Math.cos(a) * 0.35 * s, 0, Math.sin(a) * 0.35 * s], [0, 0, 0], [1, 0.6, 1])); }
    flower.add(rest(sphere(0.22 * s, mat('#F4C531'), 6), [0, 0.1 * s, 0]));
    body.add(flower);
    const eyeW = mat('#FFFFFF', { roughness: 0.4 }), eyeM = mat('#1E2A1B');
    for (const z of [-0.5 * s, 0.5 * s]) { barrel.add(rest(sphere(0.22 * s, eyeW, 6), [1.5 * s, 0.6 * s, z])); barrel.add(rest(sphere(0.11 * s, eyeM, 5), [1.68 * s, 0.6 * s, z])); }
    const armL = rest(new THREE.Group(), [0.4 * s, 2.3 * s, -1.5 * s]); const armR = rest(new THREE.Group(), [0.4 * s, 2.3 * s, 1.5 * s]);
    for (const a of [armL, armR]) { const g = cyl(0.3 * s, 0.35 * s, 1.1 * s, P.mats.primary); g.position.y = -0.5 * s; a.add(g); }
    body.add(armL, armR);
    const feetM = P.mats.accent;
    const legL = rest(new THREE.Group(), [0, 0.5 * s, -0.6 * s]); const legR = rest(new THREE.Group(), [0, 0.5 * s, 0.6 * s]);
    for (const l of [legL, legR]) { const g = cyl(0.35 * s, 0.4 * s, 0.5 * s, feetM); g.position.y = -0.25 * s; l.add(g); }
    rig.add(body, legL, legR);
    return { rig, body, torso: barrel, head: flower, armL, armR, legL, legR, handL: null, handR: null, s, extra: { barrel, spines, flower }, height: 5.8 };
  },
  duststorm(P, s) {
    const rig = new THREE.Group();
    const body = rest(new THREE.Group(), [0, 0.7 * s, 0]);
    const ball = rest(new THREE.Group(), [0, 1.6 * s, 0]);
    const core = mesh(new THREE.IcosahedronGeometry(1.35 * s, 1), P.mats.primary); core.material = mat(P.pal.primary, { opacity: 0.9 });
    const wire = new THREE.Mesh(new THREE.IcosahedronGeometry(1.6 * s, 1), new THREE.MeshStandardMaterial({ color: P.pal.secondary, wireframe: true, transparent: true }));
    const wire2 = new THREE.Mesh(new THREE.IcosahedronGeometry(1.75 * s, 0), new THREE.MeshStandardMaterial({ color: P.pal.accent, wireframe: true, transparent: true }));
    ball.add(core, wire, wire2);
    body.add(ball);
    const eyeW = mat('#FFFFFF', { roughness: 0.4 }), eyeM = mat('#1E2A1B');
    const face = rest(new THREE.Group(), [0, 1.7 * s, 0]);
    for (const z of [-0.45 * s, 0.45 * s]) { face.add(rest(sphere(0.24 * s, eyeW, 6), [1.25 * s, 0.2 * s, z])); face.add(rest(sphere(0.12 * s, eyeM, 5), [1.45 * s, 0.2 * s, z])); }
    body.add(face);
    const legL = rest(new THREE.Group(), [0, 0.7 * s, -0.4 * s]); const legR = rest(new THREE.Group(), [0, 0.7 * s, 0.4 * s]);
    for (const l of [legL, legR]) { const g = cyl(0.1 * s, 0.14 * s, 0.7 * s, P.mats.secondary); g.position.y = -0.35 * s; l.add(g); }
    const armL = rest(new THREE.Group(), [0.3 * s, 1.5 * s, -1.2 * s]); const armR = rest(new THREE.Group(), [0.3 * s, 1.5 * s, 1.2 * s]);
    for (const a of [armL, armR]) { const g = cyl(0.1 * s, 0.12 * s, 1.0 * s, P.mats.secondary); g.position.y = -0.45 * s; a.add(g); }
    body.add(armL, armR);
    rig.add(body, legL, legR);
    return { rig, body, torso: ball, head: face, armL, armR, legL, legR, handL: null, handR: null, s, extra: { ball, wire, wire2 }, height: 4.2 };
  },
  mycel(P, s) {
    const H = humanoid(P, { scale: s, torso: mesh(new THREE.CapsuleGeometry(0.8 * s, 1.0 * s, 4, 8), P.mats.primary), armMat: P.mats.primary, legMat: P.mats.primary, head: sphere(0.85 * s, P.mats.primary, 8), eyeY: 2.95, eyeX: 0.68 });
    const caps = [];
    const capAt = (p, r) => { const g = new THREE.Group(); g.add(rest(cyl(0.12 * s, 0.15 * s, 0.5 * s, P.mats.accent), [0, 0.2 * s, 0])); g.add(rest(mesh(new THREE.SphereGeometry(r * s, 8, 6, 0, PI * 2, 0, PI / 2), P.mats.secondary), [0, 0.42 * s, 0])); rest(g, p); return g; };
    caps.push(capAt([0, 3.7 * s, 0], 0.5), capAt([0.2 * s, 3.3 * s, 0.6 * s], 0.32), capAt([-0.1 * s, 3.4 * s, -0.6 * s], 0.28));
    for (const c of caps) H.body.add(c);
    const threads = [];
    for (let i = 0; i < 6; i++) {
      const t = rest(cyl(0.05 * s, 0.03 * s, 1.4 * s, P.mats.accent, 4), [-0.3 * s, 0.2 * s, (i - 2.5) * 0.28 * s], [0, 0, 0.5 + (i % 2) * 0.4]);
      t.position.y = 0.2 * s; H.torso.add(t); threads.push(t);
    }
    return { ...H, extra: { caps, threads }, height: 4.8 };
  },
  frostbud(P, s) {
    const H = humanoid(P, { scale: s, torso: cyl(0.4 * s, 0.5 * s, 2.2 * s, P.mats.tertiary), armMat: P.mats.tertiary, legMat: P.mats.tertiary, head: cyl(0.25 * s, 0.95 * s, 1.3 * s, P.mats.secondary, 8), eyeY: 2.7, eyeX: 0.55, eyeZ: 0.3 });
    const petals = new THREE.Group();
    for (let i = 0; i < 3; i++) {
      const a = (i / 3) * PI * 2 + PI / 6;
      petals.add(rest(box(0.5 * s, 1.1 * s, 0.35 * s, P.mats.primary), [Math.cos(a) * 0.8 * s, 2.55 * s, Math.sin(a) * 0.8 * s], [0, -a, 0.25]));
    }
    H.body.add(petals);
    H.body.add(rest(sphere(0.3 * s, P.mats.accent, 6), [0, 3.7 * s, 0]));
    H.torso.add(rest(box(0.12 * s, 0.4 * s, 1.4 * s, P.mats.tertiary), [0.1 * s, -0.4 * s, 0.6 * s], [0.5, 0, 0]));
    H.torso.add(rest(box(0.12 * s, 0.4 * s, 1.4 * s, P.mats.tertiary), [0.1 * s, 0.1 * s, -0.6 * s], [-0.5, 0, 0]));
    return { ...H, extra: { petals }, height: 5.0 };
  },
};

export function buildRig(char, skin = 0, opts = {}) {
  if (hasModel(char)) {
    const rig = instantiateModel(char, skin, opts);
    if (rig) return rig;
  }
  const pal = paletteFor(char, skin);
  const mats = { primary: mat(pal.primary), secondary: mat(pal.secondary), tertiary: mat(pal.tertiary), accent: mat(pal.accent) };
  const s = char.height / 5;
  const built = (BUILDERS[char.rig] || BUILDERS.thornlock)({ mats, pal }, s);
  const rig = built.rig;
  const bub = bubble(rig, s);
  const allMats = new Set();
  rig.traverse((o) => { if (o.material) allMats.add(o.material); });
  rig.userData = { ...built, bubble: bub, mats: [...allMats].filter((m) => m !== bub.material), char, pal, parts: [] };
  rig.traverse((o) => { if (o.userData.rest) rig.userData.parts.push(o); });
  return rig;
}

// ---------- posing ----------
function attackChannels(ch, f) {
  const m = f.move; if (!m) return;
  const st = f.startupEff, act = m.active, rec = m.recovery, mf = f.mf;
  const inStartup = mf <= st, inActive = mf > st && mf <= st + act;
  const k = inStartup ? mf / Math.max(1, st) : inActive ? 1 : Math.max(0, 1 - (mf - st - act) / Math.max(1, rec));
  const id = m.id || '';
  const cat = id.startsWith('LightNeutral') ? 'jab' : id.startsWith('LightSide') || id === 'ItemSwing' ? 'side' : id === 'LightDown' ? 'down' : id === 'AirNeutral' ? 'nair' : id === 'AirForward' ? 'fair' : id === 'AirDown' ? 'dair' : id === 'SigSide' ? 'sigside' : id === 'SigDown' ? 'sigdown' : id === 'CounterBurst' ? 'burst' : id === 'ItemSpray' ? 'spray' : 'jab';
  const F = PI / 2; // arm forward
  if (m.kind === 'counter') { ch.armL.z = 0.9; ch.armR.z = -0.9; ch.sy = 0.92; ch.sx = 1.08; ch.tint = '#3E4F2E'; return; }
  switch (cat) {
    case 'jab': ch.armR.z = inStartup ? -0.4 * k : inActive ? F : F * k; ch.lean = inActive ? 0.15 : 0.05 * k; break;
    case 'side': ch.armR.z = inStartup ? -0.9 * k : inActive ? F + 0.2 : F * k; ch.armL.z = inActive ? -0.6 : 0.2; ch.lean = inStartup ? -0.25 * k : 0.35 * k; ch.sx = inActive ? 1.12 : 1; break;
    case 'down': ch.sy = 0.7; ch.sx = 1.2; ch.lean = 0.3; ch.legR = inActive ? 1.3 : 0.4 * k; ch.armR.z = inActive ? 0.5 : 0; ch.armL.z = 0.6; break;
    case 'nair': ch.spinY = (mf / (st + act + rec)) * PI * 4; ch.armL.z = 1.4; ch.armR.z = -1.4; ch.legL = 0.5; ch.legR = -0.5; break;
    case 'fair': ch.armR.z = inStartup ? -1.0 * k : inActive ? F : F * k; ch.lean = 0.4 * k; ch.legL = -0.5; ch.legR = -0.7; break;
    case 'dair': if (inStartup) { ch.armL.z = 2.8 * k; ch.armR.z = -2.8 * k; ch.sy = 0.9; } else { ch.armL.z = 0.2; ch.armR.z = -0.2; ch.sy = 1.15; ch.sx = 0.9; ch.head = 0.4; } break;
    case 'sigside':
      if (inStartup) { ch.lean = -0.45 * k; ch.armR.z = -1.4 * k; ch.sx = 1 - 0.1 * k; ch.sy = 1 + 0.1 * k; ch.tint = k > 0.7 ? '#FFFFFF' : null; }
      else if (inActive) { ch.lean = 0.5; ch.armR.z = F + 0.3; ch.armL.z = -0.8; ch.sx = 1.2; ch.sy = 0.95; }
      else { ch.lean = 0.5 * k; ch.armR.z = (F + 0.3) * k; ch.sx = 1 + 0.2 * k; }
      break;
    case 'sigdown':
      if (inStartup) { ch.sy = 1 - 0.3 * k; ch.sx = 1 + 0.2 * k; ch.armL.z = 0.6; ch.armR.z = -0.6; ch.tint = k > 0.7 ? '#FFFFFF' : null; }
      else if (inActive) { ch.sy = 1.25; ch.sx = 1.15; ch.armL.z = 3.0; ch.armR.z = -3.0; ch.bob = 0.3; }
      else { ch.sy = 1 + 0.25 * k; ch.sx = 1 + 0.15 * k; ch.armL.z = 3.0 * k; ch.armR.z = -3.0 * k; }
      break;
    case 'burst': ch.sx = 1.3; ch.sy = 1.3; ch.armL.z = 1.6; ch.armR.z = -1.6; ch.tint = '#FFFFFF'; break;
    case 'spray': ch.armR.z = F; ch.lean = 0.1; ch.bob = Math.sin(mf * 0.8) * 0.05; break;
  }
  if (m.charge && mf === st && f.charge > 0) { const p = Math.sin(f.charge * 0.5) * 0.04; ch.sx += p; ch.sy -= p; ch.tint = '#FFF6DC'; }
}

export function channelsFor(f, t) {
  const ch = { lean: 0, bob: 0, sx: 1, sy: 1, spinY: 0, spinZ: 0, armL: { z: 0.25, x: 0 }, armR: { z: -0.25, x: 0 }, legL: 0, legR: 0, head: 0, opacity: 1, tint: null, rigRotZ: 0, yOff: 0, bubble: 0, visible: true, shakeX: 0 };
  const s = f.state, sf = f.sf;
  const runPhase = f.frameCount * 0.38;
  switch (s) {
    case 'idle': ch.bob = Math.sin(t * 3 + f.index) * 0.06; ch.armL.z = 0.3 + Math.sin(t * 3) * 0.05; ch.armR.z = -0.3 - Math.sin(t * 3) * 0.05; break;
    case 'run': { const sp = Math.min(1, Math.abs(f.vx) / f.char.runSpeed); ch.legL = Math.sin(runPhase) * 0.9 * sp; ch.legR = -Math.sin(runPhase) * 0.9 * sp; ch.armL.x = -Math.sin(runPhase) * 0.7 * sp; ch.armR.x = Math.sin(runPhase) * 0.7 * sp; ch.lean = 0.18 * sp; ch.bob = Math.abs(Math.sin(runPhase)) * 0.12 * sp; break; }
    case 'dash': ch.lean = 0.4; ch.legL = 0.9; ch.legR = -0.9; ch.armL.z = 0.8; ch.armR.z = -0.8; ch.sx = 1.1; ch.sy = 0.92; break;
    case 'jumpsquat': ch.sy = 0.8; ch.sx = 1.15; break;
    case 'air': case 'helpless': case 'recovery':
      if (f.vy > 6) { ch.sy = 1.08; ch.sx = 0.95; ch.armL.z = 2.5; ch.armR.z = -2.5; ch.legL = -0.6; ch.legR = -0.6; }
      else if (f.vy < -6) { ch.armL.z = 1.2; ch.armR.z = -1.2; ch.legL = 0.3; ch.legR = -0.2; ch.sy = f.fastFalling ? 1.1 : 1; }
      else { ch.armL.z = 1.6; ch.armR.z = -1.6; }
      if (s === 'helpless') { ch.spinY = t * 6; ch.armL.z = 2.2; ch.armR.z = -2.2; }
      if (s === 'recovery') { ch.spinY = sf * 0.6; ch.armL.z = 3; ch.armR.z = -3; ch.sy = 1.1; }
      break;
    case 'landing': if (sf <= 6) { ch.sy = 0.85; ch.sx = 1.1; } break;
    case 'attack': attackChannels(ch, f); if (!f.onGround) { ch.legL = 0.3; ch.legR = -0.3; } break;
    case 'hitstun': ch.lean = -0.5; ch.armL.z = 2.2; ch.armR.z = -2.0; ch.armL.x = Math.sin(sf) * 0.6; ch.head = -0.3; ch.shakeX = sf < 4 ? (sf % 2 ? 0.15 : -0.15) : 0; ch.legL = 0.5; ch.legR = -0.4; break;
    case 'knockdown': ch.rigRotZ = -PI / 2 + 0.1; ch.yOff = 0.7; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
    case 'tech': ch.opacity = 0.6; if (f.techRoll) ch.rigRotZ = -sf * 0.35; else { ch.sy = 0.85; ch.sx = 1.1; } break;
    case 'shield': case 'shielddrop': ch.sy = 0.88; ch.sx = 1.05; ch.armL.z = 0.9; ch.armR.z = -0.9; if (s === 'shield') ch.bubble = Math.max(0.25, f.shield / 50); break;
    case 'stunned': ch.lean = Math.sin(sf * 0.3) * 0.25; ch.head = Math.sin(sf * 0.5) * 0.3; ch.armL.z = 1.0; ch.armR.z = -1.0; ch.tint = sf % 12 < 6 ? '#F4C531' : null; break;
    case 'spotdodge': ch.opacity = 0.35; ch.sy = 0.9; ch.lean = -0.3; break;
    case 'airdodge': ch.opacity = 0.35; ch.spinZ = sf * 0.45; break;
    case 'ledge': ch.armL.z = 2.9; ch.armR.z = -2.9; ch.legL = 0.3; ch.legR = -0.2; ch.head = -0.3; ch.bob = Math.sin(t * 4) * 0.05; break;
    case 'ledgeaction': { const k = f.la?.kind; if (k === 'attack') { ch.armR.z = sf > 8 ? PI / 2 : -0.8; ch.lean = 0.3; } else if (k === 'roll') { ch.rigRotZ = -sf * 0.3 * f.facing; ch.opacity = 0.7; } else { ch.lean = -0.2; ch.armL.z = 1.4; ch.armR.z = -1.4; } break; }
    case 'grab': ch.armL.z = 1.4; ch.armR.z = -1.4; ch.lean = sf > 7 ? 0.3 : 0.1; if (sf > 7) { ch.armL.z = PI / 2; ch.armR.z = PI / 2; } break;
    case 'holding': ch.armL.z = PI / 2; ch.armR.z = PI / 2; ch.lean = 0.15; ch.sx = 1.05; break;
    case 'grabbed': ch.armL.z = 1.6; ch.armR.z = -1.6; ch.legL = Math.sin(sf * 0.6) * 0.8; ch.legR = -Math.sin(sf * 0.6) * 0.8; ch.head = -0.2; break;
    case 'groundpound': if (sf <= 8) { ch.sy = 0.8; ch.sx = 1.15; ch.armL.z = 2.9; ch.armR.z = -2.9; } else { ch.sy = 1.25; ch.sx = 0.85; ch.armL.z = 3.1; ch.armR.z = -3.1; ch.legL = 0; ch.legR = 0; } break;
    case 'tether': ch.armL.z = 2.9; ch.armR.z = -2.9; ch.sy = 1.15; ch.sx = 0.9; break;
    case 'frozen': ch.tint = '#A9D8F0'; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
    case 'taunt': ch.bob = Math.abs(Math.sin(sf * 0.25)) * 0.5; ch.spinY = sf * 0.15; ch.armL.z = 2.6 + Math.sin(sf * 0.5) * 0.4; ch.armR.z = -0.4; break;
    case 'ko': ch.visible = false; break;
    case 'respawn': ch.yOff = Math.sin(t * 4) * 0.3; ch.opacity = 0.85; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
  }
  if (f.tumbling && (s === 'air' || s === 'hitstun')) ch.rigRotZ = -f.frameCount * 0.3 * f.facing;
  if (f.invincible > 0 && s !== 'ledge' && s !== 'respawn' && f.frameCount % 6 < 3) ch.opacity *= 0.55;
  if (f.effects.chill.stacks > 0 && !ch.tint) ch.tint = ['#C9E6F5', '#A9D8F0', '#7FC0E6'][f.effects.chill.stacks - 1];
  if (f.hitlag > 0) ch.shakeX = (f.frameCount % 2 ? 0.12 : -0.12);
  return ch;
}

export function poseRig(rig, f, t) {
  const U = rig.userData;
  const ch = channelsFor(f, t);
  rig.visible = ch.visible && f.alive;
  if (!rig.visible) return;
  for (const p of U.parts) resetRest(p);
  rig.position.set(f.x + ch.shakeX, f.y + ch.yOff, 0);
  rig.rotation.set(0, f.facing > 0 ? 0 : PI, ch.rigRotZ);
  const b = U.body;
  b.rotation.z += -ch.lean; b.rotation.y += ch.spinY; b.rotation.x += ch.spinZ;
  b.position.y += ch.bob;
  b.scale.set(ch.sx, ch.sy, ch.sx);
  if (U.armL) { U.armL.rotation.z += ch.armL.z; U.armL.rotation.x += ch.armL.x; }
  if (U.armR) { U.armR.rotation.z += ch.armR.z; U.armR.rotation.x += ch.armR.x; }
  if (U.legL) { U.legL.rotation.z += ch.legL; }
  if (U.legR) { U.legR.rotation.z += ch.legR; }
  if (U.head) U.head.rotation.z += -ch.head;
  // materials
  for (const m of U.mats) { m.opacity = ch.opacity; }
  const tint = ch.tint ? new THREE.Color(ch.tint) : null;
  for (const m of U.mats) { m.emissive.set(tint ? tint : '#000000'); m.emissiveIntensity = tint ? 0.45 : 0; }
  U.bubble.visible = ch.bubble > 0;
  if (ch.bubble > 0) { const k = 0.5 + ch.bubble * 0.5; U.bubble.scale.set(k, k, k); U.bubble.material.opacity = 0.25 + ch.bubble * 0.2; }
  // character extras
  const E = U.extra || {};
  const sp = Math.min(1, Math.abs(f.vx) / f.char.runSpeed);
  if (E.vines) for (const chain of E.vines) chain.forEach((seg, i) => { seg.rotation.z += Math.sin(t * 5 + i) * 0.35 + (f.state === 'attack' ? 0.6 : 0) - f.vx * 0.01; });
  if (E.petals && f.char.rig === 'thornlock') { E.petals.rotation.x = t * 0.5; const bl = f.mech.bloomed ? 1.3 : 1; E.petals.scale.set(bl, bl, bl); }
  if (E.petals && f.char.rig === 'sunbeam') { E.petals.rotation.x = t * (f.mech.segments ? 1 + f.mech.segments : 0.3); const g = f.mech.segments / 3; E.petals.children.forEach((p) => { p.material.emissive.set('#F4C531'); p.material.emissiveIntensity = g * 0.6; }); }
  if (E.petals && f.char.rig === 'frostbud') E.petals.children.forEach((p, i) => { p.rotation.z += (f.state === 'attack' && f.move?.heavy ? 0.6 : 0) + Math.sin(t * 2 + i) * 0.08; });
  if (E.cap) { E.cap.scale.y = 1 + Math.sin(t * 3) * 0.03 - (f.state === 'jumpsquat' || f.state === 'landing' ? 0.2 : 0); if (f.mech.id === 'Fruiting') { const r = f.mech.ring / 100; E.cap.material.emissive.set('#E39B2C'); E.cap.material.emissiveIntensity = r >= 1 ? 0.6 + Math.sin(t * 8) * 0.2 : r * 0.3; } }
  if (E.segs) E.segs.forEach((seg, i) => { if (i > 0) seg.rotation.z += Math.sin(t * 2.5 + i * 0.7) * 0.12 - f.vx * 0.004 * (i / 5); });
  if (E.ball) { E.ball.rotation.z -= f.vx * 0.02; if (f.state === 'attack' && f.move?.id === 'LightSide1') E.ball.rotation.z -= 0.5 * f.facing; if (f.mech.ready) { E.wire.material.emissive.set('#F4C531'); E.wire.material.emissiveIntensity = 0.8; } else { E.wire.material.emissiveIntensity = 0; } }
  if (E.spines) E.spines.forEach((sp, i) => { const on = i < f.mech.spines * 12 / 5; sp.visible = on; });
  if (E.barrel && f.state === 'attack' && f.move?.id === 'LightSide1') E.barrel.rotation.z -= 0.6 * f.facing;
  if (E.caps) E.caps.forEach((c, i) => { c.rotation.z += Math.sin(t * 3 + i) * 0.1; });
  if (E.threads) E.threads.forEach((th, i) => { th.rotation.z += Math.sin(t * 4 + i) * 0.2 + sp * 0.5; });
}

// ---------- skeletal posing ----------
// The Blender-built characters use the same animation channels as the primitive rigs; only the
// thing being rotated changes, from a Group to a bone.

const _dq = new THREE.Quaternion();
const _tmp = new THREE.Quaternion();
const _inv = new THREE.Quaternion();
const _e = new THREE.Euler();

// Rotate a bone by rig-space Euler angles, conjugated into the bone's own rest frame so the
// result does not depend on how Blender happened to orient that bone.
function boneRot(U, bone, x, y, z) {
  if (!bone) return;
  const r = U.rest.get(bone);
  const rw = U.restWorld.get(bone);
  if (!r || !rw) return;
  if (!x && !y && !z) { bone.quaternion.copy(r.q); return; }
  _e.set(x, y, z, 'XYZ');
  _dq.setFromEuler(_e);
  _inv.copy(rw).invert();
  _tmp.copy(_inv).multiply(_dq).multiply(rw);
  bone.quaternion.copy(r.q).multiply(_tmp);
}

// 0..1: how charged the character's unique mechanic is. Drives the accent glow.
function mechanicHeat(f) {
  const r = f.resource();
  if (!r) return 0;
  if (r.active) return 1;
  return Math.max(0, Math.min(1, r.value || 0));
}

export function poseModel(rig, f, t) {
  const U = rig.userData;
  const ch = channelsFor(f, t);
  rig.visible = ch.visible && f.alive;
  if (!rig.visible) return;

  for (const [bone, r] of U.rest) {
    bone.position.copy(r.p);
    bone.quaternion.copy(r.q);
    bone.scale.copy(r.s);
  }

  rig.position.set(f.x + ch.shakeX, f.y + ch.yOff, 0);
  rig.rotation.set(0, f.facing > 0 ? 0 : PI, ch.rigRotZ);

  const C = U.channels;
  // The torso carries lean, spin, bob and squash. Legs hang off the root, so the feet stay put.
  if (C.body) {
    boneRot(U, C.body, ch.spinZ, ch.spinY, -ch.lean);
    C.body.position.y += ch.bob;
    C.body.scale.set(ch.sx, ch.sy, ch.sx);
  }
  boneRot(U, C.torso, 0, 0, -ch.lean * 0.35);
  boneRot(U, C.head, 0, 0, -ch.head);
  boneRot(U, C.armL, ch.armL.x, 0, ch.armL.z);
  boneRot(U, C.armR, ch.armR.x, 0, ch.armR.z);
  boneRot(U, C.foreL, 0, 0, ch.armL.z * 0.35);
  boneRot(U, C.foreR, 0, 0, ch.armR.z * 0.35);
  boneRot(U, C.legL, 0, 0, ch.legL);
  boneRot(U, C.legR, 0, 0, ch.legR);
  boneRot(U, C.shinL, 0, 0, Math.max(0, -ch.legL) * 0.5);
  boneRot(U, C.shinR, 0, 0, Math.max(0, -ch.legR) * 0.5);

  // Trailing chains lag behind the body and swing with speed: Thornlock's vines, Kelpin's head
  // blades, Mycel's hyphal threads. Hand chains also reach forward on an attack.
  const swing = -f.vx * 0.012;
  const attacking = f.state === 'attack';
  const heavy = attacking && f.move && f.move.heavy;
  const airborne = !f.onGround;
  for (const chain of U.allChains || []) {
    const isHand = chain.key.endsWith('Hand_Vine');
    const dir = chain.side || 1;
    const phase = chain.key.length;                      // de-syncs the chains from each other
    chain.bones.forEach((bone, i) => {
      const lag = Math.sin(t * 4.2 + i * 0.75 + f.index + phase) * (0.10 + i * 0.045);
      const reach = isHand && attacking ? (0.30 + i * 0.12) * (heavy ? 1.6 : 1) : 0;
      const drift = airborne ? -0.10 * (i + 1) * Math.sign(f.vy || 1) : 0;
      boneRot(U, bone, lag * 0.4 * dir, 0, lag + swing * (1 + i * 0.35) + reach + drift);
    });
  }

  // Material state: opacity, hit tint, and the accent lighting up with the mechanic meter.
  const tint = ch.tint ? new THREE.Color(ch.tint) : null;
  for (const m of U.mats) {
    m.opacity = ch.opacity;
    m.transparent = ch.opacity < 1;
    if (m.userData.role === 'glow') continue;
    if (tint) { m.emissive.copy(tint); m.emissiveIntensity = 0.5; }
    else if (m.emissiveIntensity !== 0) { m.emissive.setHex(0x000000); m.emissiveIntensity = 0; }
  }
  const hot = mechanicHeat(f);
  for (const m of U.glowMats) {
    m.emissiveIntensity = 0.35 + hot * 0.9;
    m.opacity = ch.opacity;
    m.transparent = ch.opacity < 1;
  }
  for (const o of U.outlines) o.visible = ch.opacity > 0.55;
}

// One entry point: modelled characters take the skeletal path, everything else the primitive one.
export function pose(rig, f, t) {
  if (rig.userData && rig.userData.modelled) poseModel(rig, f, t);
  else poseRig(rig, f, t);
}
