import * as THREE from '../../vendor/three.module.js';
import { GLTFLoader } from '../../vendor/GLTFLoader.js';

// CC0 scenery props (Kenney Nature Kit) used to dress the stages: grass tufts, bushes, flowers,
// mushrooms, rocks and trees. They are loaded once, then cloned per placement.
//
// Everything here is CC0 / public domain, so it ships with the game without attribution
// obligations. See web/assets/props/KENNEY-LICENSE.txt.

const loader = new GLTFLoader();
const CACHE = new Map();     // name -> { scene, size }
const PENDING = new Map();
const MISSING = new Set();

export const PROP_SETS = {
  // grass and low ground cover, scattered along platform tops
  turf: ['grass', 'grass_large', 'grass_leafs', 'grass_leafsLarge'],
  bushes: ['plant_bush', 'plant_bushDetailed', 'plant_bushLarge', 'plant_bushSmall'],
  flowers: ['flower_purpleA', 'flower_purpleB', 'flower_redA', 'flower_redB', 'flower_yellowA', 'flower_yellowB'],
  fungi: ['mushroom_red', 'mushroom_redGroup', 'mushroom_tan', 'mushroom_tanGroup'],
  pebbles: ['rock_smallA', 'rock_smallB', 'rock_smallC', 'rock_smallFlatA', 'rock_smallFlatB', 'stone_smallA', 'stone_smallB'],
  boulders: ['rock_largeA', 'rock_largeB', 'rock_largeC', 'stone_largeA', 'stone_largeB', 'rock_smallTopA', 'rock_smallTopB'],
  trees: ['tree_default', 'tree_cone', 'tree_fat', 'tree_detailed', 'tree_blocks'],
  water: ['lily_large', 'lily_small'],
  misc: ['log', 'plant_flatShort', 'plant_flatTall'],
};

const ALL = [...new Set(Object.values(PROP_SETS).flat())];

export function preloadProps(base = 'assets/props/') {
  return Promise.all(ALL.map((name) => new Promise((resolve) => {
    if (CACHE.has(name) || MISSING.has(name)) return resolve(true);
    loader.load(
      `${base}${name}.glb`,
      (gltf) => {
        const scene = gltf.scene;
        scene.updateMatrixWorld(true);
        const bb = new THREE.Box3().setFromObject(scene);
        const size = new THREE.Vector3(); bb.getSize(size);
        // Kenney models sit on the origin already; record the height so callers can scale by
        // a target size in studs rather than guessing a multiplier per model.
        CACHE.set(name, { scene, size, minY: bb.min.y });
        resolve(true);
      },
      undefined,
      () => { MISSING.add(name); resolve(false); },
    );
  }))).then((r) => r.filter(Boolean).length);
}

export function hasProp(name) { return CACHE.has(name); }
export function loadedCount() { return CACHE.size; }

// Clone a prop. `height` scales it to that many studs tall; `tint` multiplies its materials so a
// prop can be pulled toward a stage's palette instead of always reading as generic Kenney green.
export function spawnProp(name, { height = null, scale = 1, tint = null, flip = false, rotY = null } = {}) {
  const entry = CACHE.get(name);
  if (!entry) return null;
  const g = entry.scene.clone(true);
  const s = height ? (height / Math.max(0.0001, entry.size.y)) : scale;
  g.scale.setScalar(s * (flip ? -1 : 1));
  if (flip) g.scale.x *= -1;
  g.rotation.y = rotY == null ? Math.random() * Math.PI * 2 : rotY;

  g.traverse((o) => {
    if (!o.isMesh) return;
    o.castShadow = true;
    o.receiveShadow = false;
    const src = Array.isArray(o.material) ? o.material : [o.material];
    o.material = src.map((m) => {
      const c = m.clone();
      c.flatShading = true;
      if (tint) c.color.lerp(new THREE.Color(tint), 0.45);
      c.needsUpdate = true;
      return c;
    });
    if (!Array.isArray(o.material)) o.material = o.material[0];
    if (Array.isArray(o.material) && o.material.length === 1) o.material = o.material[0];
  });
  return g;
}

// Deterministic scatter along a platform top: picks props from a set, spaces them out, and keeps
// them clear of the centre lane where fighters actually stand.
export function scatter({ set, count, w, depth = 6, height, tint, rnd, y = 0, zBias = 0, avoidCentre = 0 }) {
  const out = [];
  const names = PROP_SETS[set] || [];
  if (!names.length || !count) return out;
  for (let i = 0; i < count; i++) {
    const name = names[Math.floor(rnd() * names.length)];
    let x = (rnd() - 0.5) * w;
    if (avoidCentre && Math.abs(x) < avoidCentre) x += Math.sign(x || 1) * avoidCentre;
    if (Math.abs(x) > w / 2) continue;
    const h = height[0] + rnd() * (height[1] - height[0]);
    const p = spawnProp(name, { height: h, tint, flip: rnd() > 0.5 });
    if (!p) continue;
    p.position.set(x, y, zBias + (rnd() - 0.5) * depth);
    out.push(p);
  }
  return out;
}
