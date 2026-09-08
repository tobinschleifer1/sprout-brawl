import * as THREE from '../../vendor/three.module.js';
import { scatter, spawnProp, PROP_SETS } from './props.js';

const mat = (color, opts = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.9, metalness: 0, flatShading: true, ...opts });
const flat = (color, opts = {}) => new THREE.MeshBasicMaterial({ color, ...opts });
function box(w, h, d, m, shadow = true) { const o = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m); o.castShadow = shadow; o.receiveShadow = true; return o; }
function mesh(geo, m, shadow = true) { const o = new THREE.Mesh(geo, m); o.castShadow = shadow; o.receiveShadow = shadow; return o; }
const rand = (seed) => { let s = seed; return () => { s = (s * 9301 + 49297) % 233280; return s / 233280; }; };
// Rock colour is derived from the ground tone rather than the small-platform accent colour, so a
// stage's stone always reads as stone even when its accent hue (moss green, terracotta) would not
// make sense scaled up to a whole support pillar.
function shade(hex, factor) { const c = new THREE.Color(hex); c.multiplyScalar(factor); return c; }

// ---------- painted sky ----------
// A vertical-gradient canvas with a couple of soft glow blobs, used as scene.background. This is
// what gives a stage a painted-sky look instead of a flat colour fill.
function skyTexture(stops, glows = []) {
  const c = document.createElement('canvas'); c.width = 8; c.height = 512;
  const ctx = c.getContext('2d');
  const grad = ctx.createLinearGradient(0, 0, 0, 512);
  for (const [t, col] of stops) grad.addColorStop(t, col);
  ctx.fillStyle = grad; ctx.fillRect(0, 0, 8, 512);
  for (const gl of glows) {
    const r = ctx.createRadialGradient(4, gl.y, 0, 4, gl.y, gl.r);
    r.addColorStop(0, gl.color); r.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.globalCompositeOperation = 'lighter';
    ctx.fillStyle = r; ctx.fillRect(0, Math.max(0, gl.y - gl.r), 8, gl.r * 2);
    ctx.globalCompositeOperation = 'source-over';
  }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

// ---------- grass-capped rock island ----------
// Every floating platform and the main stage are built from the same recipe: a bright grass cap,
// a dirt lip, and a chunky tapered rock underside with a few stray boulders and hanging roots.
// This replaces the old flat box-with-an-edge look with something that reads as a real chunk of
// land, the way a Brawlhalla-style floating platform does.
function island({ w, depth = 9, capH = 0.9, dirtH = 0.5, rockH = 2.6, grass, dirt, rock, rockDark, accent, seed = 1, roots = true, big = false, noRock = false, dress = null }) {
  const g = new THREE.Group();
  const rnd = rand(seed * 97 + 3);

  const cap = mesh(new THREE.BoxGeometry(w, capH, depth), mat(grass));
  cap.position.y = capH / 2;
  g.add(cap);
  // A rim band around the grass cap. It is deliberately SHORTER than the cap and centred lower,
  // so its top face sits well below the cap's top face: the previous version put both faces at
  // exactly the same height, and two coplanar surfaces z-fight and flicker as the camera moves.
  // That was the seam glitching across every platform on every stage.
  const rimH = capH * 0.34;
  const rim = mesh(new THREE.BoxGeometry(w * 1.03, rimH, depth * 1.03), mat(accent, { roughness: 1 }));
  rim.position.y = capH * 0.30;
  g.add(rim);

  const dirtLayer = mesh(new THREE.BoxGeometry(w * 0.97, dirtH, depth * 0.94), mat(dirt));
  dirtLayer.position.y = -dirtH / 2;
  g.add(dirtLayer);

  // A small floating island carries its own tapered rock underside. A stage's main platform
  // does not (noRock): it sits on a separate, wider support pillar built by the caller, sized to
  // match the dirt layer exactly so the two never show a seam or overlapping silhouette.
  if (!noRock) {
    const topR = Math.max(w, depth) * 0.62, botR = topR * 0.42;
    const rockGeo = new THREE.CylinderGeometry(topR, botR, rockH, 7, 1);
    rockGeo.scale((w / (topR * 2)) * 1.05, 1, (depth / (topR * 2)) * 1.05);
    const rockMesh = mesh(rockGeo, mat(rock));
    rockMesh.rotation.y = rnd() * Math.PI;
    rockMesh.position.y = -dirtH - rockH / 2 + 0.15;
    g.add(rockMesh);
  }

  const boulderCount = big ? 5 : 3;
  const boulderDrop = noRock ? dirtH * 0.4 : rockH * 0.55;
  for (let i = 0; i < boulderCount; i++) {
    const a = (i / boulderCount) * Math.PI * 2 + rnd() * 1.2;
    const r = 0.9 + rnd() * (big ? 1.4 : 0.8);
    const names = PROP_SETS.boulders;
    // scale boulders to the island they hang off, or a small platform ends up wearing a rock
    // several times its own size
    const boH = big ? r * 2.1 : Math.min(r * 1.15, rockH * 0.85);
    const bo = spawnProp(names[Math.floor(rnd() * names.length)], { height: boH, tint: rnd() > 0.5 ? rock : rockDark })
      || mesh(new THREE.IcosahedronGeometry(r, 0), mat(rnd() > 0.5 ? rock : rockDark));
    bo.position.set(Math.cos(a) * (w * 0.32 + rnd() * 0.4), -dirtH - boulderDrop - rnd() * (noRock ? r * 0.6 : rockH * 0.35), Math.sin(a) * (depth * 0.28));
    bo.rotation.set(rnd() * 6, rnd() * 6, rnd() * 6);
    g.add(bo);
  }
  if (roots) {
    for (let i = 0; i < (big ? 4 : 2); i++) {
      const x = (rnd() - 0.5) * w * 0.6;
      const len = 1.2 + rnd() * 1.8;
      const root = mesh(new THREE.CylinderGeometry(0.05, 0.1, len, 4), mat(accent, { roughness: 1 }));
      root.position.set(x, -dirtH - (noRock ? 0.3 : rockH * 0.4) - len / 2, (rnd() - 0.5) * depth * 0.3);
      root.rotation.z = (rnd() - 0.5) * 0.3;
      g.add(root);
    }
  }
  // ---- scenery on top: turf, flowers, mushrooms and the odd bush or pebble. Kept off the centre
  // lane on the main platform so it never hides a fighter's feet, and kept low everywhere so it
  // cannot be mistaken for standable geometry.
  if (dress) {
    const capTop = capH;
    const lane = big ? w * 0.16 : 0;
    const turfCount = Math.max(3, Math.round(w * (big ? 0.22 : 0.32)));
    for (const p of scatter({ set: 'turf', count: turfCount, w: w * 0.94, depth: depth * 0.55, height: [1.0, 1.9], tint: grass, rnd, y: capTop, zBias: depth * 0.16, avoidCentre: lane })) g.add(p);
    for (const p of scatter({ set: dress.flora || 'flowers', count: big ? 9 : 4, w: w * 0.9, depth: depth * 0.5, height: [0.9, 1.5], rnd, y: capTop, zBias: depth * 0.2, avoidCentre: lane })) g.add(p);
    if (dress.bushes !== false) {
      for (const p of scatter({ set: 'bushes', count: big ? 6 : 2, w: w * 0.88, depth: depth * 0.4, height: [1.9, 3.0], tint: grass, rnd, y: capTop, zBias: -depth * 0.3, avoidCentre: lane * 1.4 })) g.add(p);
    }
    for (const p of scatter({ set: 'pebbles', count: big ? 6 : 2, w: w * 0.9, depth: depth * 0.5, height: [0.5, 1.1], tint: rock, rnd, y: capTop, zBias: depth * 0.1, avoidCentre: lane })) g.add(p);
  }

  g.userData.dirtBottomY = -dirtH;
  return g;
}

// A soft, unlit silhouette shape for background scenery: castle towers, sea stacks, distant
// hills. MeshBasicMaterial reads as flat painted colour rather than lit geometry, which is what
// keeps a background layer from competing with the cast for attention.
function silhouette(geo, color, opacity = 1) {
  return mesh(geo, flat(color, { transparent: opacity < 1, opacity }), false);
}

function glowOrb(color, r, opacity = 0.9) {
  const g = new THREE.Group();
  g.add(silhouette(new THREE.SphereGeometry(r, 20, 16), color, opacity));
  g.add(silhouette(new THREE.SphereGeometry(r * 1.5, 16, 12), color, opacity * 0.25));
  return g;
}

// A tower: a tapered body plus a roof cone. The one recurring shape across every theme's distant
// architecture (castle spire, watchtower, lighthouse, sea stack) — only proportions change.
function tower(h, rTop, rBot, roofH, color, roofColor) {
  const g = new THREE.Group();
  g.add(silhouette(new THREE.CylinderGeometry(rTop, rBot, h, 8), color));
  const roof = silhouette(new THREE.ConeGeometry(rTop * 1.25, roofH, 8), roofColor || color);
  roof.position.y = h / 2 + roofH / 2;
  g.add(roof);
  return g;
}

// Builds and updates the visual stage from the runtime stage data.
export class StageView {
  constructor(scene, stage) {
    this.scene = scene; this.stage = stage;
    this.group = new THREE.Group();
    this.platMeshes = new Map();
    this.dynamic = {};
    const D = stage.data, P = D.palette;

    scene.background = skyTexture(P.skyStops || [[0, P.sky], [0.55, P.sky], [1, P.backdrop]], P.glows || []);
    scene.fog = new THREE.Fog(new THREE.Color(P.backdrop), 90, 340);

    const m = stage.main;
    // ---- main platform: the grass/dirt island recipe with `noRock`, sat on a single wide
    // support pillar sized to match the dirt layer exactly so the two pieces are flush — two
    // separately tapered rock shapes at the same joint is what caused the seam this replaces.
    const capH = 1.0, dirtH = 0.6, islandW = m.w + 1.5, islandD = 15;
    const rock = shade(P.ground, 2.05), rockDark = shade(P.ground, 1.35);
    const mainIsland = island({
      w: islandW, depth: islandD, capH, dirtH, big: true, noRock: true, roots: false, seed: 11,
      grass: P.groundTop, dirt: P.ground, rock, rockDark, accent: P.accent,
      dress: D.dress || {},
    });
    mainIsland.position.set(m.cx, m.top - capH, 0);
    this.group.add(mainIsland);

    const dirtBottomY = m.top - capH - dirtH;          // exact world Y of the dirt layer's underside
    const pillarTopR = islandW * 0.34, pillarBotR = pillarTopR * 0.22;
    const pillarH = Math.max(26, m.top - stage.blast.bottom + 8);
    const pillar = mesh(new THREE.CylinderGeometry(pillarTopR, pillarBotR, pillarH, 8), mat(rock, { roughness: 1 }), false);
    pillar.position.set(m.cx, dirtBottomY - pillarH / 2, -1.5);
    this.group.add(pillar);
    // strata: alternating light and dark bands down the pillar, each sized to the taper, plus a
    // few rocks clinging to it. One flat wedge of colour reads as a slab; layers read as stone.
    const strataRnd = rand(37);
    for (let i = 1; i <= 6; i++) {
      const k = i / 7;
      const r = pillarTopR * (1 - k) + pillarBotR * k;
      const band = mesh(new THREE.CylinderGeometry(r * 1.035, r * 1.02, pillarH * 0.055, 8),
        mat(i % 2 ? shade(P.ground, 2.5) : rockDark, { roughness: 1 }), false);
      band.position.set(m.cx, dirtBottomY - pillarH * k, -1.5);
      this.group.add(band);
      if (i <= 4) {
        const names = PROP_SETS.boulders;
        const rk = spawnProp(names[Math.floor(strataRnd() * names.length)], { height: 2.5 + strataRnd() * 3, tint: rock });
        if (rk) { rk.position.set(m.cx + (strataRnd() - 0.5) * r * 1.7, dirtBottomY - pillarH * k + 1, 4.5); this.group.add(rk); }
      }
    }

    // ---- floating platforms: same island recipe, smaller
    let seed = 5;
    for (const p of stage.platforms) {
      if (p.solid) continue;
      const isl = island({
        w: p.w, depth: 8.5, capH: 0.62, dirtH: 0.32, rockH: 1.7, seed: seed++,
        grass: P.groundTop, dirt: P.ground, rock, rockDark, accent: P.accent,
        dress: D.dress || {},
      });
      isl.position.y = -0.62; // island() builds its cap top at local y = capH; sink so p.top sits at cap top
      const holder = new THREE.Group(); holder.add(isl);
      this.group.add(holder); this.platMeshes.set(p, holder);
    }

    this._props(D, P);

    // ground far below for shadow catching and depth
    const floor = box(600, 2, 300, mat(P.backdrop, { roughness: 1 }), false);
    floor.position.set(0, stage.blast.bottom - 40, -60);
    floor.receiveShadow = true;
    this.group.add(floor);

    // blast zone outline (debug)
    const b = stage.blast;
    const geo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(b.left, b.bottom, 0), new THREE.Vector3(b.right, b.bottom, 0),
      new THREE.Vector3(b.right, b.top, 0), new THREE.Vector3(b.left, b.top, 0),
      new THREE.Vector3(b.left, b.bottom, 0),
    ]);
    this.blastLine = new THREE.Line(geo, new THREE.LineBasicMaterial({ color: '#DE621C', transparent: true, opacity: 0.6 }));
    this.blastLine.visible = false;
    this.group.add(this.blastLine);
    scene.add(this.group);
  }

  _props(D, P) {
    const g = this.group; const m = this.stage.main;
    const add = (o, x, y, z) => { o.position.set(x, y, z); g.add(o); return o; };

    if (D.props === 'greenhouse') {
      const frame = mat('#EAF2EE', { roughness: 0.5 });
      for (let i = -3; i <= 3; i++) add(box(1, 90, 1, frame, false), i * 30, 40, -34);
      add(box(190, 1, 1, frame, false), 0, 60, -34);
      add(box(190, 1, 1, frame, false), 0, 30, -34);
      add(box(190, 1, 1, frame, false), 0, 85, -34);
      const glass = mesh(new THREE.PlaneGeometry(200, 110), new THREE.MeshStandardMaterial({ color: '#D9EDF2', transparent: true, opacity: 0.5, roughness: 0.2 }), false);
      add(glass, 0, 45, -36);
      // soft distant hills, seen through the glass, for depth without competing with the cast
      add(silhouette(new THREE.CircleGeometry(60, 16, 0, Math.PI), '#BFE0D8', 0.55), -40, -6, -70);
      add(silhouette(new THREE.CircleGeometry(46, 16, 0, Math.PI), '#CDE8DE', 0.5), 55, -6, -76);
      const basket = mesh(new THREE.SphereGeometry(4, 9, 7, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), mat('#8C5A2B'));
      add(basket, 0, 30, -12);
      const leaves = mesh(new THREE.SphereGeometry(5, 8, 6), mat('#5FA85A'));
      add(leaves, 0, 32, -12);
      for (let i = 0; i < 4; i++) add(mesh(new THREE.CylinderGeometry(3, 2.4, 4, 8), mat('#C7603A')), -70 + i * 12, m.bottom - 10, -18);
      add(mesh(new THREE.CylinderGeometry(0.3, 0.3, 30, 6), mat('#8C5A2B')), 0, 45, -12);

    } else if (D.props === 'forest') {
      // a distant misty keep, well back and desaturated, framing the island without stealing
      // focus from the fight, the way the reference art scales its castle backdrops
      const towerTint = '#9FB4B0', roofTint = '#7E96A0';
      const keep = new THREE.Group();
      keep.add(tower(46, 8, 10, 12, towerTint, roofTint));
      const wingL = tower(30, 5, 6, 8, towerTint, roofTint); wingL.position.set(-14, -8, 4); keep.add(wingL);
      const wingR = tower(24, 4.5, 5.5, 7, towerTint, roofTint); wingR.position.set(13, -11, 6); keep.add(wingR);
      add(keep, 70, 44, -130);
      add(glowOrb('#EAF3E6', 14, 0.35), -60, 70, -150);
      // three depth bands of real trees, each smaller, hazier and further back than the last
      const treeNames = PROP_SETS.trees;
      const bands = [
        { z: -78, n: 10, h: [24, 32], tint: '#4C8348', spread: 230, y: -22 },
        { z: -120, n: 12, h: [19, 26], tint: '#79A38E', spread: 280, y: -26 },
        { z: -175, n: 14, h: [14, 20], tint: '#A3BFB2', spread: 340, y: -30 },
      ];
      let ts = 3;
      for (const band of bands) {
        for (let i = 0; i < band.n; i++) {
          ts = (ts * 9301 + 49297) % 233280; const r1 = ts / 233280;
          ts = (ts * 9301 + 49297) % 233280; const r2 = ts / 233280;
          const t = spawnProp(treeNames[Math.floor(r1 * treeNames.length)], {
            height: band.h[0] + r2 * (band.h[1] - band.h[0]), tint: band.tint });
          if (t) add(t, -band.spread / 2 + (i / (band.n - 1)) * band.spread + (r1 - 0.5) * 12, band.y, band.z);
        }
      }
      const log = mesh(new THREE.CylinderGeometry(4.5, 4.5, m.w + 6, 10), mat('#5A3F2A'));
      log.rotation.z = Math.PI / 2; add(log, m.cx, m.bottom + 3.5, 0);
      const logCap = mesh(new THREE.CylinderGeometry(4.6, 4.6, 0.6, 10), mat('#8A6A4A'));
      logCap.rotation.z = Math.PI / 2; add(logCap, m.x2 + 3.3, m.bottom + 3.5, 0);
      for (let i = 0; i < 12; i++) add(mesh(new THREE.SphereGeometry(1.5, 6, 5), mat('#8FB85A')), -60 + Math.random() * 120, m.bottom - 6 + Math.random() * 4, -10 - Math.random() * 20);

    } else if (D.props === 'compost') {
      const wood = mat('#7A5A3A');
      add(box(6, 26, 30, wood), m.x1 - 8, m.bottom + 6, -6);
      add(box(6, 26, 30, wood), m.x2 + 8, m.bottom + 6, -6);
      add(box(m.w + 22, 20, 5, wood), m.cx, m.bottom + 3, -18);
      for (let i = 0; i < 20; i++) add(mesh(new THREE.SphereGeometry(1.2 + Math.random() * 1.5, 6, 5), mat(['#E8862A', '#8A5A2A', '#7A9A3A', '#C9A227'][i % 4])), m.x1 + Math.random() * m.w, m.top + 0.4, -4 - Math.random() * 6);
      const fork = mesh(new THREE.CylinderGeometry(0.4, 0.4, 26, 6), mat('#5A3F2A')); fork.rotation.z = 0.3; add(fork, m.x2 - 6, m.top + 12, -8);
      // a distant garden shed roofline for depth behind the bins
      add(silhouette(new THREE.BoxGeometry(60, 24, 1), '#B49468', 0.5), -20, 24, -90);
      const shedRoof = silhouette(new THREE.ConeGeometry(36, 16, 4), '#8A6440', 0.5); shedRoof.rotation.y = Math.PI / 4;
      add(shedRoof, -20, 44, -90);
      this.dynamic.vents = (D.hazards.find((h) => h.type === 'vents')?.positions || []).map((x) => { const v = mesh(new THREE.CylinderGeometry(2.4, 2.4, 0.6, 10), mat('#3E2A1A', { emissive: '#E8862A', emissiveIntensity: 0 })); v.position.set(x, m.top + 0.1, 0); g.add(v); return v; });
      this.dynamic.steam = [];

    } else if (D.props === 'rooftop') {
      for (let i = 0; i < 12; i++) { const h = 40 + ((i * 37) % 70); const bld = box(14, h, 14, mat(i % 2 ? '#B87A5A' : '#8E6A5A'), false); add(bld, -150 + i * 27, h / 2 - 10, -90 - (i % 3) * 30); }
      add(glowOrb('#FFE7A8', 15, 0.75), 55, 78, -150);
      // distant watchtower silhouettes and a haze band across the skyline for real depth
      add(tower(58, 4, 6, 14, '#D9AE86', '#B8825E'), -95, 30, -140);
      add(tower(40, 3, 4.5, 10, '#D9AE86', '#B8825E'), 100, 20, -150);
      add(silhouette(new THREE.PlaneGeometry(500, 40), '#F4D9AE', 0.4), 0, 10, -120);
      add(box(m.w + 4, 2.5, 16, mat('#8A5A3A')), m.cx, m.top - 1, 0);
      this.dynamic.sprinkler = new THREE.Group();
      const head = mesh(new THREE.CylinderGeometry(1, 1, 3, 8), mat('#9FB3C8')); this.dynamic.sprinkler.add(head);
      const spray = mesh(new THREE.CylinderGeometry(1, 5, 60, 10, 1, true), new THREE.MeshStandardMaterial({ color: '#9FD1E8', transparent: true, opacity: 0.35 })); spray.position.y = -30;
      this.dynamic.sprinkler.add(spray); this.dynamic.sprinklerSpray = spray;
      this.dynamic.sprinkler.position.set(0, 75, 0); this.dynamic.sprinkler.visible = false; g.add(this.dynamic.sprinkler);

    } else if (D.props === 'desert') {
      add(box(120, 40, 30, mat('#C98A5A'), false), -160, 10, -120);
      add(box(90, 55, 30, mat('#B87A4A'), false), 150, 15, -120);
      // eroded spire silhouettes at three depths, warm and hazy toward the horizon
      add(tower(70, 6, 9, 4, '#D8A570', '#D8A570'), -60, 20, -150);
      add(tower(50, 5, 7, 3, '#E0B182', '#E0B182'), 40, 10, -170);
      add(tower(85, 7, 10, 5, '#CC9863', '#CC9863'), 110, 26, -190);
      add(glowOrb('#FFEFC8', 20, 0.55), -20, 90, -210);
      for (let i = 0; i < 5; i++) add(mesh(new THREE.DodecahedronGeometry(3 + i, 0), mat('#9A6A4A')), -70 + i * 35, m.bottom - 8, -20 - i * 6);
      add(box(m.w + 8, 3, 18, mat('#B8834A')), m.cx, m.top - 1.4, 0);
      this.dynamic.devil = new THREE.Group();
      for (let i = 0; i < 4; i++) { const c = mesh(new THREE.CylinderGeometry(1 + i * 0.9, 0.6 + i * 0.9, 3, 8, 1, true), new THREE.MeshStandardMaterial({ color: '#D9A86A', transparent: true, opacity: 0.55, side: THREE.DoubleSide })); c.position.y = i * 3 + 1.5; this.dynamic.devil.add(c); }
      this.dynamic.devil.visible = false; g.add(this.dynamic.devil);

    } else if (D.props === 'tidepool') {
      // The sea wall sits behind the stacks and the lighthouse. Any closer and it fills the frame,
      // hiding the sky gradient and flattening the whole stage to one grey slab.
      add(box(340, 34, 10, mat('#93A4A8'), false), 0, -2, -130);
      // sea stacks and a lighthouse-shaped spire out past the water, with a low moon
      add(tower(34, 3.5, 5, 3, '#6B7E82', '#6B7E82'), -70, 14, -80);
      add(tower(50, 4, 6, 3, '#5E7276', '#5E7276'), 85, 20, -100);
      add(tower(38, 2.6, 3.6, 5, '#DDE6E8', '#C24B4B'), 30, 24, -95);
      add(glowOrb('#DCEFF6', 16, 0.5), -30, 85, -160);
      for (let i = 0; i < 6; i++) add(mesh(new THREE.DodecahedronGeometry(2.5 + (i % 3), 0), mat('#5A6E68')), -40 + i * 16, m.bottom - 4, -12);
      const water = mesh(new THREE.BoxGeometry(400, 60, 120), new THREE.MeshStandardMaterial({ color: '#3FA0B0', transparent: true, opacity: 0.55, roughness: 0.2 }));
      water.position.set(0, -38, 0); g.add(water); this.dynamic.water = water;
      for (let i = 0; i < 5; i++) add(mesh(new THREE.SphereGeometry(1.2, 6, 5), mat('#D64C8C')), m.x1 + 4 + i * 12, m.top + 0.6, -5);
    }
  }

  setDebug(on) { this.blastLine.visible = on; }

  update(t) {
    const st = this.stage;
    for (const [p, holder] of this.platMeshes) holder.position.set(p.cx, p.top, 0);
    const b = st.blast;
    this.blastLine.geometry.setFromPoints([
      new THREE.Vector3(b.left, b.bottom, 0), new THREE.Vector3(b.right, b.bottom, 0),
      new THREE.Vector3(b.right, b.top, 0), new THREE.Vector3(b.left, b.top, 0),
      new THREE.Vector3(b.left, b.bottom, 0),
    ]);
    const V = st.visual, D = this.dynamic;
    if (V.vents && D.vents) {
      D.vents.forEach((v) => { v.material.emissiveIntensity = V.vents.phase === 'warn' ? 0.4 + Math.sin(t * 20) * 0.3 : V.vents.phase === 'erupt' ? 1 : 0; });
      if (V.vents.phase === 'erupt' && Math.random() < 0.6) for (const x of V.vents.positions) { const s = mesh(new THREE.SphereGeometry(1.2, 6, 5), new THREE.MeshStandardMaterial({ color: '#F4EBDD', transparent: true, opacity: 0.7 }), false); s.position.set(x + (Math.random() - 0.5) * 3, st.main.top + 1, (Math.random() - 0.5) * 3); s.userData.vy = 40 + Math.random() * 20; s.userData.life = 40; this.group.add(s); D.steam.push(s); }
      for (let i = D.steam.length - 1; i >= 0; i--) { const s = D.steam[i]; s.position.y += s.userData.vy / 60; s.scale.multiplyScalar(1.03); s.material.opacity -= 0.018; if (--s.userData.life <= 0) { this.group.remove(s); D.steam.splice(i, 1); } }
    }
    if (V.sprinkler && D.sprinkler) { D.sprinkler.visible = V.sprinkler.phase !== 'idle'; D.sprinkler.position.x = V.sprinkler.phase === 'sweep' ? V.sprinkler.x : st.main.x1 - 10; D.sprinklerSpray.visible = V.sprinkler.phase === 'sweep'; D.sprinkler.children[0].material.emissive.set('#9FD1E8'); D.sprinkler.children[0].material.emissiveIntensity = V.sprinkler.phase === 'tick' ? 0.5 + Math.sin(t * 30) * 0.5 : 0; }
    if (D.devil) { D.devil.visible = !!V.dustdevil; if (V.dustdevil) { D.devil.position.set(V.dustdevil.x, st.main.top, 0); D.devil.rotation.y = t * 12; } }
    if (D.water && V.tide) { D.water.position.y = V.tide.level - 30; }
  }

  dispose() {
    this.scene.remove(this.group);
    this.group.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material) { (Array.isArray(o.material) ? o.material : [o.material]).forEach((mm) => mm.dispose()); } });
    if (this.scene.background && this.scene.background.isTexture) this.scene.background.dispose();
    this.scene.fog = null;
  }
}
