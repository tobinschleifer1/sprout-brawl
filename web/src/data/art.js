// Authored pixel silhouettes and weapon inlays, shared with Roblox through gen-data.mjs.
// Rectangles are [x, y, width, height, colour/palette key, opacity]. Background coordinates use
// a 480x270 tile. Small hard highlights sit against broad, quiet masses, away from the fighters.
const rect = (x, y, w, h, colour, alpha = 1) => [x, y, w, h, colour, alpha].map(v => typeof v === 'number' ? +v.toFixed(4) : v);

function motif(kind, x, base, height, dark, light) {
  const r = [];
  const add = (...args) => r.push(rect(...args));
  if (kind === 'forge') {
    add(x, base - height, 13, height, dark);
    add(x - 3, base - height, 19, 4, dark);
    add(x - 14, base - 28, 61, 28, dark);
    add(x - 11, base - 32, 54, 5, dark);
    add(x + 25, base - height * 0.7, 7, height * 0.7, dark);
    add(x - 7, base - 19, 10, 14, light, 0.7);
    add(x - 5, base - 17, 6, 10, '#FFD698', 0.6);
    add(x + 18, base - 14, 16, 2, light, 0.45);
    for (let k = 0; k < 3; k++) add(x + 3 + k * 7, base - height - 10 - k * 5, 18 + k * 9, 5, dark, 0.45 - k * 0.1);
  } else if (kind === 'bridge') {
    add(x, base - height, 9, height, dark);
    add(x + 48, base - height, 9, height, dark);
    add(x - 4, base - height + 7, 65, 7, dark);
    add(x - 28, base - 14, 112, 6, dark);
    for (let k = 0; k < 6; k++) {
      const y = base - height + 17 + k * 7;
      add(x + 8 + k * 7, y, 9, 3, dark);
      add(x + 12 + k * 7, y + 3, 2, Math.max(2, base - 14 - y), dark, 0.6);
    }
    add(x + 1, base - height - 3, 6, 3, light, 0.85);
  } else if (kind === 'city') {
    add(x, base - height, 40, height, dark);
    add(x + 7, base - height - 8, 25, 8, dark);
    add(x + 21, base - height - 21, 2, 15, dark);
    add(x + 20, base - height - 22, 4, 3, light, 0.9);
    add(x + 35, base - 33, 27, 33, dark);
    for (let k = 0; k < 8; k++) {
      if (k % 3 === 1) continue;
      add(x + 7 + (k % 2) * 17, base - height + 13 + Math.floor(k / 2) * 13, 5, 3, light, 0.35 + (k % 2) * 0.3);
    }
    add(x + 4, base - 9, 32, 2, light, 0.25);
  } else if (kind === 'mesa') {
    add(x - 8, base - height, 51, 9, dark);
    add(x - 15, base - height + 9, 66, 13, dark);
    add(x - 23, base - height + 22, 83, height - 22, dark);
    add(x - 8, base - height, 51, 2, light, 0.4);
    add(x - 10, base - height + 17, 54, 2, light, 0.16);
    add(x - 21, base - 16, 77, 3, light, 0.15);
    add(x + 3, base - height + 5, 3, height - 5, dark, 0.8);
  } else if (kind === 'dock') {
    add(x, base - height, 5, height, dark);
    add(x - 29, base - height, 83, 5, dark);
    add(x + 49, base - height + 5, 2, 32, dark);
    add(x + 44, base - height + 34, 12, 4, dark);
    add(x - 14, base - 25, 47, 22, dark);
    add(x - 19, base - 29, 56, 5, dark);
    add(x - 10, base - 16, 9, 5, light, 0.65);
    add(x + 9, base - 16, 9, 5, light, 0.4);
    add(x - 24, base, 78, 4, light, 0.13);
    add(x - 8, base + 8, 36, 2, light, 0.1);
  }
  return r;
}

function scene(kind, sky, far, near, light, sun) {
  const layers = [];
  for (let layer = 0; layer < 2; layer++) {
    const rectangles = [];
    for (let i = 0; i < 4; i++) {
      rectangles.push(...motif(kind, i * 120 + (layer ? 18 : 61), layer ? 239 : 215,
        49 + ((i * 23 + layer * 17) % 44), layer ? near : far, light));
    }
    rectangles.push(rect(0, layer ? 239 : 215, 480, layer ? 31 : 55, layer ? near : far));
    layers.push({ parallax: layer ? 0.18 : 0.06, rectangles });
  }
  return { sky, light, sun, layers };
}

export const SCENES = {
  FoundryFloor: scene('forge', ['#101721', '#29313C', '#78604B'], '#38414B', '#202932', '#EFA65D', [346, 65, 12]),
  TheSpan: scene('bridge', ['#111B2A', '#34465D', '#8390A0'], '#414F60', '#253443', '#D5B58D', [326, 58, 9]),
  Smeltworks: scene('forge', ['#1B1115', '#48292B', '#9E573C'], '#563C3A', '#2D252B', '#FF864A', [92, 150, 17]),
  Rooftops: scene('city', ['#0D1526', '#28364E', '#5C7084'], '#34435A', '#192637', '#A6DCEE', [367, 52, 8]),
  Saltflat: scene('mesa', ['#1C2432', '#64545A', '#B98B64'], '#765E55', '#493E3A', '#E3B782', [143, 103, 16]),
  Undertow: scene('dock', ['#101F2B', '#294A59', '#678F96'], '#365763', '#1C3541', '#9ACDD0', [297, 73, 10]),
};

// Sparse coloured fittings with distinct motifs: runes, cooling vents, rivets and bindings.
// These are painted only on the finished weapon, never on the dark contour or its afterimages.
export const WEAPON_DETAILS = {
  Sword: [rect(-0.46, -0.15, 0.08, 0.3, 'accent'), rect(-0.27, -0.15, 0.08, 0.3, 'accent'), rect(0.35, -0.08, 0.12, 0.16, 'glow'), rect(0.66, -0.045, 0.28, 0.09, 'glow')],
  Scythe: [rect(0.2, -0.15, 0.14, 0.3, 'secondary'), rect(0.54, -0.15, 0.14, 0.3, 'accent'), rect(2.62, -0.23, 0.22, 0.46, 'secondary'), rect(2.68, -0.09, 0.1, 0.18, 'glow')],
  Blasters: [rect(-0.19, -0.24, 0.11, 0.15, 'tertiary'), rect(0.01, -0.24, 0.11, 0.15, 'tertiary'), rect(0.64, -0.2, 0.1, 0.22, 'tertiary'), rect(-0.19, 0.19, 0.18, 0.09, 'accent')],
  Grimoire: [rect(-0.43, -0.54, 0.12, 1.08, 'accent'), rect(-0.4, -0.54, 0.8, 0.09, 'accent'), rect(-0.4, 0.45, 0.8, 0.09, 'accent'), rect(-0.08, -0.31, 0.08, 0.14, 'glow'), rect(-0.08, 0.19, 0.08, 0.14, 'glow')],
  Axe: [rect(-0.56, -0.15, 0.11, 0.3, 'tertiary'), rect(-0.28, -0.15, 0.11, 0.3, 'tertiary'), rect(2.46, -0.55, 0.22, 0.18, 'secondary'), rect(2.46, 0.35, 0.22, 0.18, 'secondary'), rect(2.79, -0.21, 0.13, 0.42, 'glow')],
  Pike: [rect(0.68, -0.16, 0.12, 0.32, 'accent'), rect(1.05, -0.16, 0.12, 0.32, 'accent'), rect(4.7, -0.15, 0.2, 0.3, 'tertiary'), rect(5.08, -0.06, 0.44, 0.12, 'glow')],
  Gauntlets: [rect(-0.36, -0.18, 0.13, 0.36, 'tertiary'), rect(0.22, -0.25, 0.34, 0.1, 'accent'), rect(0.22, 0.15, 0.34, 0.1, 'tertiary'), rect(0.3, -0.07, 0.15, 0.14, 'glow')],
  Hammer: [rect(2.65, -0.79, 0.52, 0.17, 'secondary'), rect(2.65, 0.62, 0.52, 0.17, 'tertiary'), rect(2.9, -0.45, 0.13, 0.9, 'glow'), rect(-0.7, -0.16, 0.13, 0.32, 'tertiary'), rect(-0.35, -0.16, 0.13, 0.32, 'tertiary')],
  Longbow: [rect(0.68, -0.43, 0.4, 0.13, 'accent'), rect(0.68, 0.3, 0.4, 0.13, 'accent'), rect(0.75, -1.21, 0.1, 0.43, 'glow'), rect(0.75, 0.78, 0.1, 0.43, 'glow')],
  Flail: [rect(-0.65, -0.15, 0.13, 0.3, 'tertiary'), rect(-0.31, -0.15, 0.13, 0.3, 'accent'), rect(3.57, -0.38, 0.17, 0.76, 'tertiary'), rect(3.5, -0.1, 0.34, 0.2, 'glow')],
  Shield: [rect(-0.2, -0.93, 0.18, 0.55, 'accent'), rect(-0.2, 0.4, 0.18, 0.55, 'accent'), rect(0.43, -0.9, 0.12, 0.31, 'secondary'), rect(0.43, 0.59, 0.12, 0.31, 'secondary'), rect(-0.1, -0.08, 0.58, 0.16, 'glow')],
  Daggers: [rect(-0.4, -0.14, 0.1, 0.28, 'accent'), rect(-0.2, -0.14, 0.1, 0.28, 'accent'), rect(0.28, -0.08, 0.1, 0.16, 'glow'), rect(0.51, -0.045, 0.3, 0.09, 'glow')],
};
