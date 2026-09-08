import * as THREE from '../../vendor/three.module.js';

// Painted, not physical: a banded toon ramp, a fresnel rim for separation from the stage,
// and an inverted-hull outline. Section 01 rules 05 and 06 of the art bible.

let GRADIENTS = new Map();

function gradientMap(steps) {
  if (GRADIENTS.has(steps)) return GRADIENTS.get(steps);
  // A hard-stepped ramp. Two or three bands read as painted; a smooth ramp reads as plastic.
  const data = new Uint8Array(steps * 4);
  for (let i = 0; i < steps; i++) {
    // Floor at 0.58: below that the shaded band eats the palette and everything reads muddy.
    const v = Math.round(255 * (0.58 + 0.42 * (i / (steps - 1))));
    data[i * 4] = data[i * 4 + 1] = data[i * 4 + 2] = v;
    data[i * 4 + 3] = 255;
  }
  const tex = new THREE.DataTexture(data, steps, 1, THREE.RGBAFormat);
  tex.minFilter = tex.magFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.needsUpdate = true;
  GRADIENTS.set(steps, tex);
  return tex;
}

const RIM_PARS = `
  uniform vec3 rimColor;
  uniform float rimPower;
  uniform float rimStrength;
  varying vec3 vRimNormal;
  varying vec3 vRimView;
`;

export function toonMaterial({ color, rim = '#ffffff', rimStrength = 0.5, steps = 3, emissive = null, emissiveIntensity = 0 }) {
  const m = new THREE.MeshToonMaterial({
    color: new THREE.Color(color),
    gradientMap: gradientMap(steps),
    emissive: new THREE.Color(emissive || '#000000'),
    emissiveIntensity,
  });
  m.userData.rim = { color: new THREE.Color(rim), strength: rimStrength };
  m.onBeforeCompile = (shader) => {
    shader.uniforms.rimColor = { value: m.userData.rim.color };
    shader.uniforms.rimStrength = { value: m.userData.rim.strength };
    shader.uniforms.rimPower = { value: 2.6 };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vRimNormal;\nvarying vec3 vRimView;')
      .replace('#include <fog_vertex>', `#include <fog_vertex>
        vRimNormal = normalize(normalMatrix * objectNormal);
        vRimView = normalize(-mvPosition.xyz);`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\n' + RIM_PARS)
      .replace('#include <dithering_fragment>', `#include <dithering_fragment>
        float rim = pow(1.0 - clamp(dot(normalize(vRimNormal), normalize(vRimView)), 0.0, 1.0), rimPower);
        gl_FragColor.rgb += rimColor * rim * rimStrength;`);
    m.userData.shader = shader;
  };
  return m;
}

export function setRim(mat, color, strength) {
  if (!mat.userData.rim) return;
  if (color) mat.userData.rim.color.set(color);
  if (strength != null) mat.userData.rim.strength = strength;
  const sh = mat.userData.shader;
  if (sh) {
    sh.uniforms.rimColor.value = mat.userData.rim.color;
    sh.uniforms.rimStrength.value = mat.userData.rim.strength;
  }
}

// Inverted hull. Extrusion happens in object space before skinning so the shell follows the pose.
export function outlineMaterial(color = '#1E2A1B', width = 0.055) {
  const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(color), side: THREE.BackSide });
  m.userData.width = width;
  m.onBeforeCompile = (shader) => {
    shader.uniforms.outlineWidth = { value: m.userData.width };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nuniform float outlineWidth;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n\ttransformed += normalize( normal ) * outlineWidth;');
    m.userData.shader = shader;
  };
  return m;
}

export function setOutlineWidth(mat, w) {
  mat.userData.width = w;
  if (mat.userData.shader) mat.userData.shader.uniforms.outlineWidth.value = w;
}

// Stage materials: same painted family, softer ramp, no rim, so the playfield stays quieter
// than the cast (art bible section 04).
export function stageMaterial(color, { steps = 3, flat = false, rimStrength = 0.12 } = {}) {
  const m = toonMaterial({ color, rim: '#ffffff', rimStrength, steps });
  m.flatShading = flat;
  return m;
}
