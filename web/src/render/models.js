import * as THREE from '../../vendor/three.module.js';
import { GLTFLoader } from '../../vendor/GLTFLoader.js';
import { clone as cloneSkinned } from '../../vendor/SkeletonUtils.js';
import { toonMaterial, outlineMaterial } from './toon.js';

// Loads the Blender-built .glb characters, swaps palettes by material name, and adapts the
// real skeleton to the same channel names the procedural animation already drives.

const loader = new GLTFLoader();
const CACHE = new Map();     // rigId -> { scene, bonesByName }
const FAILED = new Set();

const ROLE_KEYS = ['primary', 'secondary', 'tertiary', 'accent', 'glow', 'dark', 'eyeWhite', 'eyeDark'];

function darken(hex, k) {
  const c = new THREE.Color(hex);
  c.multiplyScalar(k);
  return '#' + c.getHexString();
}
function lighten(hex, k) {
  const c = new THREE.Color(hex);
  c.lerp(new THREE.Color('#ffffff'), k);
  return '#' + c.getHexString();
}

// Fill in the roles a character file does not spell out.
export function resolvePalette(char, skin = 0) {
  const base = skin > 0 && char.skins[skin - 1] ? char.skins[skin - 1] : char.palette;
  return {
    primary: base.primary,
    secondary: base.secondary,
    tertiary: base.tertiary,
    accent: base.accent,
    glow: base.glow || char.palette.glow || lighten(base.primary, 0.25),
    dark: base.dark || darken(base.secondary, 0.58),
    eyeWhite: '#FFFFFF',
    eyeDark: '#1B2418',
  };
}

export function preload(chars, base = 'assets/characters/') {
  return Promise.all(chars.map((c) => new Promise((resolve) => {
    const id = c.rig;
    if (CACHE.has(id) || FAILED.has(id)) return resolve(false);
    loader.load(
      `${base}${id}.glb`,
      (gltf) => {
        const scene = gltf.scene;
        scene.updateMatrixWorld(true);
        CACHE.set(id, { scene, animations: gltf.animations || [] });
        resolve(true);
      },
      undefined,
      () => { FAILED.add(id); resolve(false); },   // no model yet: primitives will cover it
    );
  })));
}

export function hasModel(char) { return CACHE.has(char.rig); }

// Channel names the existing poseRig drives, mapped onto R15-style bone names.
const CHANNEL_BONES = {
  body: 'LowerTorso',
  torso: 'UpperTorso',
  head: 'Head',
  crown: 'Head_Crown',
  armL: 'LeftUpperArm',
  armR: 'RightUpperArm',
  foreL: 'LeftLowerArm',
  foreR: 'RightLowerArm',
  handL: 'LeftHand',
  handR: 'RightHand',
  legL: 'LeftUpperLeg',
  legR: 'RightUpperLeg',
  shinL: 'LeftLowerLeg',
  shinR: 'RightLowerLeg',
};

export function instantiate(char, skin = 0, opts = {}) {
  const entry = CACHE.get(char.rig);
  if (!entry) return null;
  const root = cloneSkinned(entry.scene);
  const pal = resolvePalette(char, skin);

  const rig = new THREE.Group();
  rig.add(root);

  const mats = [];
  const outlines = [];
  const skinned = [];
  root.traverse((o) => {
    if (!o.isMesh) return;
    o.castShadow = true;
    o.receiveShadow = false;
    const src = Array.isArray(o.material) ? o.material : [o.material];
    const next = src.map((sm) => {
      const role = ROLE_KEYS.includes(sm.name) ? sm.name : 'primary';
      const col = pal[role] || pal.primary;
      const isGlow = role === 'glow';
      const m = toonMaterial({
        color: col,
        rim: lighten(col, 0.55),
        rimStrength: isGlow ? 0.9 : 0.45,
        steps: 3,
        emissive: isGlow ? col : null,
        emissiveIntensity: isGlow ? 0.55 : 0,
      });
      m.name = role;
      m.userData.role = role;
      mats.push(m);
      return m;
    });
    o.material = Array.isArray(o.material) ? next : next[0];
    if (o.isSkinnedMesh) skinned.push(o);
  });

  // Inverted-hull outline, sharing the skeleton so it follows the pose.
  if (opts.outline !== false) {
    for (const sm of skinned) {
      const shell = new THREE.SkinnedMesh(sm.geometry, outlineMaterial(opts.outlineColor || '#22301E', opts.outlineWidth ?? 0.05));
      shell.bind(sm.skeleton, sm.bindMatrix);
      shell.castShadow = false;
      shell.receiveShadow = false;
      shell.frustumCulled = false;
      // Sibling, not child: nesting a SkinnedMesh inside another applies the parent transform twice.
      shell.position.copy(sm.position);
      shell.quaternion.copy(sm.quaternion);
      shell.scale.copy(sm.scale);
      shell.renderOrder = -1;
      (sm.parent || root).add(shell);
      outlines.push(shell);
    }
  }

  // Bone lookup + rest transforms so the animation layer can pose additively.
  const bones = {};
  root.traverse((o) => { if (o.isBone) bones[o.name] = o; });
  const channels = {};
  for (const [ch, bn] of Object.entries(CHANNEL_BONES)) {
    const b = bones[bn];
    if (b) channels[ch] = b;
  }
  // Every trailing chain in the rig, however it was named: hand vines, head blades, hyphal
  // threads. Anything matching "<prefix>_<Vine|Thread><nn>" becomes one animated chain.
  const chains = new Map();
  for (const [name, b] of Object.entries(bones)) {
    const m = /^(.*)_(Vine|Thread)(\d{2})$/.exec(name);
    if (!m) continue;
    const key = `${m[1]}_${m[2]}`;
    if (!chains.has(key)) chains.set(key, []);
    chains.get(key).push({ i: parseInt(m[3], 10), b });
  }
  const vines = { L: [], R: [] };
  const allChains = [];
  for (const [key, list] of chains) {
    list.sort((a, b2) => a.i - b2.i);
    const bonesInChain = list.map((x) => x.b);
    const side = key.startsWith('Left') ? 1 : key.startsWith('Right') ? -1 : 0;
    allChains.push({ key, side, bones: bonesInChain });
    if (key === 'LeftHand_Vine') vines.L = bonesInChain;
    if (key === 'RightHand_Vine') vines.R = bonesInChain;
  }
  // Rest pose, plus each bone's rest orientation relative to the rig root. The second one lets
  // the animation layer rotate a bone about a rig-space axis without caring how Blender happened
  // to orient that bone.
  const rest = new Map();
  const restWorld = new Map();
  const walk = (obj, parentQ) => {
    let q = parentQ;
    if (obj.isBone) {
      q = parentQ.clone().multiply(obj.quaternion);
      rest.set(obj, { p: obj.position.clone(), q: obj.quaternion.clone(), s: obj.scale.clone() });
      restWorld.set(obj, q);
    }
    for (const c of obj.children) walk(c, q);
  };
  walk(root, new THREE.Quaternion());

  rig.userData = {
    modelled: true, char, pal, bones, channels, vines, allChains, rest, restWorld, mats, outlines,
    glowMats: mats.filter((m) => m.userData.role === 'glow'),
    accentMats: mats.filter((m) => m.userData.role === 'accent'),
  };
  return rig;
}
