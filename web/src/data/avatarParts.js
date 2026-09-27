// The part catalogue behind avatarKit.js: every ready-made piece a character can be built from.
//
// HOW A PART IS DRAWN. The fighter is a puppet - head, torso, two arms, two legs and a pelvis, each
// posed every frame by channels.js - so a part is not one picture. It is a set of LAYERS, each laid
// onto one of the five puppet pieces below. A hoodie is a layer on the torso and a sleeve layer on
// the arm; a cowboy hat is one layer on the head. The composer stacks every chosen option's layers
// by `z` and the rig animates the result exactly as it animates everything else.
//
// PIECE CANVASES, in cells. One cell is a head-twelfth wide (hs / 12, about 0.105 studs at the base
// rig) on every piece, so the pixels are one size across the whole body; vertically each piece is
// stretched to its limb (`span` cells = the limb's length), which is what lets a thrust extend an
// arm without the art tearing. (ox, oy) is the joint the piece hangs from, in cell units measured
// from the canvas's top-left corner. Every canvas keeps a spare cell round the art where it can,
// because the outline is drawn one cell outside the silhouette.
//
//   head   18 x 20  skull at cols 3-14, rows 5-16; neck rows 17-19. Faces +X, seen three-quarter:
//                   near eye cols 9-10, far eye col 13, nose off the front edge at col 15.
//   torso  16 x 18  row 0 is the shoulder line, row 17 the hip.
//   arm     6 x 16  the limb is cols 1-4 from the shoulder (row 0) to the hand (rows 12-14).
//   leg     7 x 18  cols 1-4 from the hip (row 0) to the foot (rows 15-16); toes point to col 5.
//   pelvis 14 x 10  the hip block is rows 0-4, cols 1-12; rows 5-9 are for skirts and coat tails.
//
// TEXT GRIDS. A layer is written as rows of characters. '.' is transparent; every other character
// is a colour ROLE (below): 's' is "this character's skin", 'h' "their hair", 'a' "their top", and so
// on, so one drawing works in every colour a player picks. Capitals are the shadow of the same slot.

export const PARTS = {
  head: { w: 18, h: 20, ox: 9, oy: 15.2, span: 12 },
  torso: { w: 16, h: 18, ox: 8, oy: 18, span: 18 },
  arm: { w: 6, h: 16, ox: 3, oy: 0, span: 15 },
  leg: { w: 7, h: 18, ox: 3, oy: 0, span: 17 },
  pelvis: { w: 14, h: 10, ox: 7, oy: 2.5, span: 5 },
};

// Colour roles. `slot` reads a colour slot; `shade` darkens (x0.72) or lightens (35% toward white)
// it; `mix` averages two slots. `fixed` is a literal. `weight` is how hard a cell fights to survive
// when the piece is drawn at half resolution (see avatarCompose.js): eyes and mouths are one or
// two cells, and without it a face disappears whenever the camera zooms out.
export const FIXED = {
  ink: '#1B1526', white: '#F4F2EE', mouth: '#6A2230', pink: '#E8808E', red: '#D8323A',
  metal: '#C4CCD6', metalDark: '#6E7684', gold: '#EDBE3A', goldDark: '#A87A1E',
  lens: '#232838', shine: '#9FE0FF', sole: '#3A2A22', blush: '#F0907A', bone: '#EDE3CC', leaf: '#4E9A3A',
};

export const ROLES = {
  s: { slot: 'skin' }, S: { slot: 'skin', shade: 'dark' }, z: { slot: 'skin', shade: 'light' },
  h: { slot: 'hair' }, H: { slot: 'hair', shade: 'dark' }, i: { slot: 'hair', shade: 'light' },
  q: { slot: 'skin', mix: 'hair' },
  e: { slot: 'eyes', weight: 3 },
  a: { slot: 'top' }, A: { slot: 'top', shade: 'dark' }, u: { slot: 'top', shade: 'light' },
  b: { slot: 'trim' }, B: { slot: 'trim', shade: 'dark' },
  c: { slot: 'bottom' }, C: { slot: 'bottom', shade: 'dark' }, v: { slot: 'bottom', shade: 'light' },
  f: { slot: 'shoes' }, F: { slot: 'shoes', shade: 'dark' },
  x: { slot: 'accessory' }, X: { slot: 'accessory', shade: 'dark' }, y: { slot: 'accessory', shade: 'light' },
  k: { fixed: 'ink', weight: 3 }, w: { fixed: 'white', weight: 2 }, m: { fixed: 'mouth', weight: 3 },
  p: { fixed: 'pink' }, d: { fixed: 'red' }, r: { fixed: 'metal' }, R: { fixed: 'metalDark' },
  g: { fixed: 'gold' }, G: { fixed: 'goldDark' }, l: { fixed: 'lens', weight: 2 }, L: { fixed: 'shine' },
  o: { fixed: 'sole' }, n: { fixed: 'blush' }, j: { fixed: 'bone' }, t: { fixed: 'leaf' },
};

// ------------------------------------------------------------------------------ builders -----
// A layer from blocks of text. Each block is [row, col, lines]: its top-left character lands on
// (col, row) of the piece's canvas. The result is trimmed to the cells actually painted, so the
// generated data carries a tight grid and an offset rather than acres of dots.
function layer(part, z, blocks, opts = {}) {
  const cells = [];
  for (const [row, col, lines] of blocks) {
    lines.forEach((line, dy) => {
      for (let dx = 0; dx < line.length; dx++) if (line[dx] !== '.' && line[dx] !== ' ') cells.push([col + dx, row + dy, line[dx]]);
    });
  }
  if (!cells.length) throw new Error(`empty ${part} layer`);
  const x0 = Math.min(...cells.map((c) => c[0])), y0 = Math.min(...cells.map((c) => c[1]));
  const x1 = Math.max(...cells.map((c) => c[0])), y1 = Math.max(...cells.map((c) => c[1]));
  const grid = Array.from({ length: y1 - y0 + 1 }, () => Array(x1 - x0 + 1).fill('.'));
  for (const [x, y, ch] of cells) grid[y - y0][x - x0] = ch;       // later blocks overwrite earlier
  const out = { part, z, x: x0, y: y0, rows: grid.map((r) => r.join('')) };
  if (opts.base) out.base = true;
  if (opts.clip) out.clip = true;
  if (opts.hair) out.hair = true;
  return out;
}
const at = (row, col, lines) => [row, col, lines];
const whole = (lines) => [0, 0, lines];          // a block written across the full canvas width

// Z order. Within a piece, lower draws first. Across categories the numbers interleave: the hair's
// back layer is behind the skull, its front layer over the face, and headwear over everything.
const Z = {
  hairBack: 10, skull: 20, ears: 22, marks: 25, eyes: 30, brows: 32, nose: 34, mouth: 36,
  beard: 40, hair: 50, earsOver: 52, eyewear: 55, headwear: 60,
  body: 10, top: 20, topOver: 24, neck: 30,
  skin: 10, sleeve: 20, glove: 30,
  legSkin: 10, pants: 20, shoes: 30,
  hips: 10, waist: 20, skirt: 26,
};

const opt = (id, name, layers = [], extra = {}) => ({ id, name, layers, ...extra });

// ------------------------------------------------------------------------------ BODY -----
// The build is the torso's skin silhouette, and every top is CLIPPED to it - so each shirt is drawn
// once, full width, and fits all five builds.
const torsoBody = (rows) => layer('torso', Z.body, [whole(rows)], { base: true });
const ARM_BASE = layer('arm', Z.skin, [whole([
  '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.', '.Ssss.',
  '.Ssss.', '.Ssss.', '.Sssz.', '.Sssz.', '..SS..',
])], { base: true });
const LEG_BASE = layer('leg', Z.legSkin, [whole([
  '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..',
  '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Ssss..', '.Sssss.', '.SSSSS.',
])], { base: true });
const HIPS = layer('pelvis', Z.hips, [whole([
  '.SSssssssssss.', '.Ssssssssssss.', '.Ssssssssssss.', '.Ssssssssssss.', '..SSSSSSSSSS..',
])], { base: true });
const bodyWith = (rows) => [torsoBody(rows), ARM_BASE, LEG_BASE, HIPS];

const BUILD = [
  opt('average', 'Average', bodyWith([
    '...ssssssssss...', '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..',
    '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..',
    '..Ssssssssssss..', '...Ssssssssss...', '...Ssssssssss...', '...Ssssssssss...', '...Ssssssssss...',
    '...Ssssssssss...', '...Ssssssssss...', '...Ssssssssss...',
  ])),
  opt('slim', 'Slim', bodyWith([
    '....ssssssss....', '...Sssssssss....', '...Sssssssss....', '...Sssssssss....', '...Sssssssss....',
    '...Sssssssss....', '...Sssssssss....', '...Sssssssss....', '...Sssssssss....', '....Sssssssss...',
    '....Ssssssss....', '....Ssssssss....', '....Ssssssss....', '....Ssssssss....', '....Ssssssss....',
    '....Ssssssss....', '....Ssssssss....', '....Ssssssss....',
  ])),
  opt('athletic', 'Athletic', bodyWith([
    '..ssssssssssss..', '.Sssssssssssssz.', '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.',
    '..Sssssssssssss.', '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..', '...Sssssssssss..',
    '...Sssssssssss..', '...Ssssssssss...', '...Ssssssssss...', '...Ssssssssss...', '...Ssssssssss...',
    '...Ssssssssss...', '...Ssssssssss...', '...Ssssssssss...',
  ])),
  opt('broad', 'Broad', bodyWith([
    '.ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.',
    '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.',
    '.Ssssssssssssss.', '.Ssssssssssssss.', '.Ssssssssssssss.', '..Sssssssssssss.', '..Sssssssssssss.',
    '..Sssssssssssss.', '..Sssssssssssss.', '..Sssssssssssss.',
  ])),
  opt('stocky', 'Stocky', bodyWith([
    '..ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..', '..Sssssssssssss.',
    '..Sssssssssssss.', '..Ssssssssssssss', '..Ssssssssssssss', '..Ssssssssssssss', '..Ssssssssssssss',
    '..Ssssssssssssss', '..Ssssssssssssss', '..Sssssssssssss.', '..Sssssssssssss.', '..Ssssssssssss..',
    '..Ssssssssssss..', '..Ssssssssssss..', '..Ssssssssssss..',
  ])),
];

// ------------------------------------------------------------------------------ HEAD -----
const neck = ['.......SSSS.......', '.......SSSS.......', '.......SSSS.......'];
const skull = (rows) => layer('head', Z.skull, [at(20 - rows.length - 3, 0, [...rows, ...neck])], { base: true });

const HEAD = [
  opt('round', 'Round', [skull([
    '......ssssss......', '....ssssssssss....', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...',
    '...ssssssssssss...', '...ssssssssssss...', '...Sssssssssssz...', '...Ssssssssssss...', '....Sssssssssss...',
    '....SSsssssssss...', '......SSSsssss....',
  ])]),
  opt('square', 'Square', [skull([
    '....ssssssssss....', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...',
    '...ssssssssssss...', '...ssssssssssss...', '...Sssssssssssz...', '...Ssssssssssss...', '...Ssssssssssss...',
    '...SSsssssssssz...', '....SSSSssssss....',
  ])]),
  opt('oval', 'Oval', [skull([
    '.......ssss.......', '.....ssssssss.....', '....ssssssssss....', '...ssssssssssss...', '...ssssssssssss...',
    '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...', '...Sssssssssssz...', '...Ssssssssssss...',
    '....Sssssssssss...', '.....SSssssssss...', '.......SSsssss....',
  ])]),
  opt('long', 'Long', [skull([
    '......ssssss......', '.....ssssssss.....', '....sssssssssss...', '....sssssssssss...', '....sssssssssss...',
    '....sssssssssss...', '....sssssssssss...', '....sssssssssss...', '....Ssssssssssz...', '....Sssssssssss...',
    '....Sssssssssss...', '.....SSssssssss...', '......SSSsssss....',
  ])]),
  opt('heart', 'Heart', [skull([
    '.....ssssssss.....', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...',
    '...ssssssssssss...', '...ssssssssssss...', '...Ssssssssssss...', '....Sssssssssss...', '.....SSsssssss....',
    '.......SSsssss....', '.........SSss.....',
  ])]),
  opt('wide', 'Wide', [skull([
    '......ssssss......', '....ssssssssss....', '...ssssssssssss...', '..ssssssssssssss..', '..ssssssssssssss..',
    '..ssssssssssssss..', '..ssssssssssssss..', '..Ssssssssssssss..', '..Ssssssssssssss..', '..Sssssssssssssz..',
    '...SSssssssssss...', '.....SSSssssss....',
  ])]),
  opt('block', 'Block', [skull([
    '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...',
    '...ssssssssssss...', '...ssssssssssss...', '...ssssssssssss...', '...Ssssssssssss...', '...Ssssssssssss...',
    '...Ssssssssssss...', '...SSSSSSSSSSSS...',
  ])]),
];

const EARS = [
  opt('normal', 'Normal', [layer('head', Z.ears, [at(9, 5, ['SS.', 'SsS', 'SsS', '.SS'])])]),
  opt('small', 'Small', [layer('head', Z.ears, [at(10, 5, ['SS', 'SS'])])]),
  opt('big', 'Big', [layer('head', Z.ears, [at(8, 4, ['.SS.', 'SssS', 'SsSS', 'SssS', '.SS.'])])]),
  opt('pointed', 'Pointed', [layer('head', Z.earsOver, [at(5, 1, [
    'S......', '.SS....', '..SsS..', '...SsS.', '....SsS', '....SsS', '.....SS',
  ])])]),
  opt('none', 'Hidden'),
];

// Eyes, brows, nose and mouth: small stamps at fixed places on the face. Every skull keeps its
// front edge at col 14 from the brow to the jaw, which is what lets one stamp fit all seven.
const face = (z, row, col, lines) => layer('head', z, [at(row, col, lines)]);
const EYES = [
  opt('round', 'Round', [face(Z.eyes, 10, 8, ['.we..e.', '.we..e.'])]),
  opt('dot', 'Dot', [face(Z.eyes, 10, 8, ['..k..k.', '..k..k.'])]),
  opt('wide', 'Wide', [face(Z.eyes, 9, 8, ['.kkk.k.', '.wwe.e.', '.wwe.e.'])]),
  opt('sleepy', 'Sleepy', [face(Z.eyes, 10, 8, ['.SS..S.', '.we..e.'])]),
  opt('fierce', 'Fierce', [face(Z.eyes, 10, 8, ['.kkk.k.', '.we..e.'])]),
  opt('angry', 'Angry', [face(Z.eyes, 9, 8, ['...k...', '.kkk.kk', '.we..e.'])]),
  opt('happy', 'Happy', [face(Z.eyes, 10, 8, ['.k...k.', 'k.k.k.k'])]),
  opt('lashes', 'Lashes', [face(Z.eyes, 9, 8, ['..kkkk.', '.we..e.', '.we..e.'])]),
  opt('anime', 'Anime', [face(Z.eyes, 9, 8, ['.kkk.k.', '.wwe.e.', '.wke.k.', '..ee.e.'])]),
  opt('tired', 'Tired', [face(Z.eyes, 10, 8, ['.we..e.', '.we..e.', '.SS..S.'])]),
  opt('wink', 'Wink', [face(Z.eyes, 10, 8, ['...k.e.', '.kk..e.'])]),
  opt('closed', 'Closed', [face(Z.eyes, 11, 8, ['.kk..k.'])]),
  opt('glow', 'Glowing', [face(Z.eyes, 10, 8, ['.ee..e.', '.ee..e.'])]),
];

const BROWS = [
  opt('normal', 'Normal', [face(Z.brows, 8, 8, ['.HHH.HH'])]),
  opt('none', 'None'),
  opt('thin', 'Thin', [face(Z.brows, 8, 8, ['..HH.H.'])]),
  opt('thick', 'Thick', [face(Z.brows, 7, 8, ['.HHH.HH', '.HHH.HH'])]),
  opt('angry', 'Angry', [face(Z.brows, 8, 8, ['.H....H', '..HH.H.'])]),
  opt('worried', 'Worried', [face(Z.brows, 7, 8, ['..HH.H.', '.H....H'])]),
  opt('raised', 'Raised', [face(Z.brows, 7, 8, ['.HHH.HH'])]),
  opt('arched', 'Arched', [face(Z.brows, 7, 8, ['..HH.H.', '.H..H.H'])]),
  opt('unibrow', 'Unibrow', [face(Z.brows, 8, 8, ['.HHHHHH'])]),
  opt('scarred', 'Scarred', [face(Z.brows, 7, 8, ['..z....', '.HzH.HH', '..z....'])]),
];

const NOSE = [
  opt('small', 'Small', [face(Z.nose, 11, 14, ['.s', 'S.'])]),
  opt('button', 'Button', [face(Z.nose, 11, 14, ['.s', 'Ss'])]),
  opt('pointed', 'Pointed', [face(Z.nose, 10, 14, ['.s.', '.ss', 'S..'])]),
  opt('long', 'Long', [face(Z.nose, 10, 14, ['.s.', '.ss', '.sS', 'S..'])]),
  opt('hooked', 'Hooked', [face(Z.nose, 10, 14, ['.s.', '.ss', '.sS', '.S.'])]),
  opt('wide', 'Wide', [face(Z.nose, 11, 13, ['..s', 'SSs'])]),
  opt('snub', 'Snub', [face(Z.nose, 11, 14, ['.z', '.S'])]),
  opt('clown', 'Clown', [face(Z.nose, 11, 14, ['dd', 'dd'])]),
  opt('none', 'None'),
];

const MOUTH = [
  opt('smile', 'Smile', [face(Z.mouth, 13, 10, ['m..m', '.mm.'])]),
  opt('grin', 'Grin', [face(Z.mouth, 14, 10, ['mwwwm', '.mmm.'])]),
  opt('neutral', 'Neutral', [face(Z.mouth, 14, 11, ['mmm'])]),
  opt('smirk', 'Smirk', [face(Z.mouth, 13, 11, ['..m', 'mm.'])]),
  opt('frown', 'Frown', [face(Z.mouth, 14, 10, ['.mm.', 'm..m'])]),
  opt('open', 'Open', [face(Z.mouth, 14, 11, ['mmm', 'mpm'])]),
  opt('shout', 'Shout', [face(Z.mouth, 13, 11, ['www', 'mmm', 'mpm'])]),
  opt('tongue', 'Tongue', [face(Z.mouth, 13, 10, ['m..m', '.mm.', '..p.'])]),
  opt('fangs', 'Fangs', [face(Z.mouth, 14, 11, ['mmm', 'w.w'])]),
  opt('oh', 'Oh', [face(Z.mouth, 14, 12, ['mm', 'mm'])]),
  opt('tight', 'Tight', [face(Z.mouth, 14, 12, ['mm'])]),
  opt('zigzag', 'Nervous', [face(Z.mouth, 14, 10, ['m.m.m', '.m.m.'])]),
];

// Facial hair keeps a hole where the mouth is, because it is drawn after it.
const beard = (row, col, lines) => layer('head', Z.beard, [at(row, col, lines)]);
const FACIAL_HAIR = [
  opt('none', 'Clean'),
  opt('stubble', 'Stubble', [beard(12, 5, [
    'q.........', 'qq......qq', '.qq......q', '..qqq....q', '...qqqqqq.',
  ])]),
  opt('moustache', 'Moustache', [beard(13, 11, ['hhhh'])]),
  opt('handlebar', 'Handlebar', [beard(12, 10, ['h....h', '.hhhh.'])]),
  opt('goatee', 'Goatee', [beard(15, 11, ['hhh', 'Hhh'])]),
  opt('soulpatch', 'Soul patch', [beard(15, 12, ['h'])]),
  opt('chinstrap', 'Chin strap', [beard(12, 6, [
    'H.......', 'H.......', '.H......', '..HH...H', '...Hhhhh',
  ])]),
  opt('full', 'Full beard', [beard(12, 5, [
    'H.........', 'HH....hhhh', 'HHh......h', '.HHhh....h', '..HHhhhhhh', '....Hhhhh.',
  ])]),
  opt('long', 'Long beard', [beard(12, 5, [
    'H.........', 'HH....hhhh', 'HHh......h', '.HHhh....h', '..HHhhhhhh', '....Hhhhhh', '....HHhhhh', '......Hhh.',
  ])]),
  opt('chops', 'Mutton chops', [beard(10, 6, ['H...', 'Hh..', 'Hhh.', 'Hhh.', '.Hhh', '..Hh'])]),
];

// Hair: a back layer (behind the skull - long hair, the far side of an afro) and a front layer (over
// the face). Both are tagged `hair`, which is what a hat's `trim` cuts away.
const hairFront = (lines, row = 0) => layer('head', Z.hair, [at(row, 0, lines)], { hair: true });
const hairBack = (lines, row = 0) => layer('head', Z.hairBack, [at(row, 0, lines)], { hair: true });
const HAIR = [
  opt('crew', 'Crew cut', [hairFront([
    '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhiiiihhh...', '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..',
    '..HHhhhh..........', '..HHhhh...........', '..HHh.............', '...HH.............', '...H..............',
  ], 2)]),
  opt('bald', 'Bald'),
  opt('buzz', 'Buzz', [hairFront([
    '.......qqqq.......', '.....qqqqqqqq.....', '...qqqqqqqqqqqq...', '...qqqqqq.........', '...qqqq...........',
    '...qqq............', '...qq.............',
  ], 4)]),
  opt('sidepart', 'Side part', [hairFront([
    '.......hhhh.......', '.....hhhhhhhhh....', '....hhhHhhiiihhh..', '...hhhHhhhhhhhhhh.', '..HhhHhhhhhhhhhhhh',
    '..HHhhhhhhhhhhhhh.', '..HHhhhh.....hhhh.', '..HHhh............', '..HHh.............', '...HH.............',
    '...H..............',
  ], 1)]),
  opt('spiky', 'Spiky', [hairFront([
    '....h.....h.......', '....hh...hhh...h..', '...hhhh.hhhhh.hh..', '..hhhhhhhhhhhhhh..', '.Hhhhhhhiihhhhhhhh',
    '.HHhhhhhhhhhhhhhh.', '..HHhhhhhhhhhhhhh.', '..HHhhhh.h..h..h..', '.HHhhh............', '..HHh.............',
    '..HH..............', '...H..............',
  ], 0)]),
  opt('messy', 'Messy', [hairFront([
    '......h..h........', '....h.hhhhhh.h....', '...hhhhhhhhhhhh...', '..hhhhhiiihhhhhh..', '.Hhhhhhhhhhhhhhhh.',
    '.HHhhhhhhhhhhhhhhh', '..HHhhhhh.hhh.hh..', '.HHhhh.....h......', '..HHhh............', '..HH..............',
    '...H..............',
  ], 1)]),
  opt('mohawk', 'Mohawk', [hairFront([
    '........hhh.......', '......hhhhhh......', '.....hhhiiihh.....', '....Hhhhhhhhhh....', '....HHhhhhhhhh....',
    '......qqqqqq......', '....qqqqqqqqqq....', '...qqqqqqq........', '...qqqq...........', '...qqq............',
    '...qq.............',
  ], 0)]),
  opt('flattop', 'Flat top', [hairFront([
    '...hhhhhhhhhhh....', '...hhhhhiiihhhh...', '...hhhhhhhhhhhh...', '...Hhhhhhhhhhhh...', '...Hhhhhhhhhhhh...',
    '...HHhhhhhhhhhh...', '..HHHhhhhhhhhhh...', '..HHhh............', '..HHh.............', '...HH.............',
    '...H..............',
  ], 0)]),
  opt('pompadour', 'Pompadour', [hairFront([
    '.........hhhh.....', '.......hhhhhhhh...', '.....hhhhhiiiihhh.', '....hhhhhhhhhhhhhh', '...Hhhhhhhhhhhhhhh',
    '..HHhhhhhhhhhhhhh.', '..HHhhhhhhhhhh....', '..HHhhh...........', '..HHh.............', '...HH.............',
    '...H..............',
  ], 0)]),
  opt('undercut', 'Undercut', [hairFront([
    '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhhh..', '..Hhhhhhhhhhhhhhh.', '..HHhhhhhhhhhhhhh.',
    '...qqqqqq....hhh..', '...qqqq...........', '...qqq............', '...qq.............',
  ], 2)]),
  opt('curly', 'Curly', [hairFront([
    '....hh..hh..hh....', '...hhhhhhhhhhhhh..', '..hhhhihhhhihhhhh.', '.Hhhhhhhhhhhhhhhh.', '.HHhhhhhhhhhhhhhhh',
    '.HHhhhhhhhhhhhhhh.', '.HHhhhhhh.hh.hh.h.', '.HHhhhh...........', '..HHhhh...........', '..HHhh............',
    '...HHh............', '....H.............',
  ], 1)]),
  opt('afro', 'Afro', [
    hairBack([
      '....hhhhhhhhh.....', '..hhhhhhhhhhhhh...', '.hhhhhhhiiihhhh...', 'hhhhhhhhhhhhhhhhh.', 'hhhhhhhhhhhhhhhhhh',
      'Hhhhhhhhhhhhhhhhhh', 'Hhhhhhhhhhhhhhhhh.', 'HHhhhhhhhhhhhhh...', 'HHhhhhhhhhhhhh....', 'HHhhhhhhhhhh......',
      'HHHhhhhhhhh.......', '.HHHhhhhh.........', '..HHHhh...........', '...HHH............',
    ], 0),
    hairFront([
      '...hhhhhhhhhhhh...', '...hhhhhhhhhhhhh..', '...hhhhhh...hhh...', '...hhhh...........', '...hhh............',
      '...hh.............',
    ], 5),
  ]),
  opt('fringe', 'Fringe', [hairFront([
    '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhhh.', '..HHhhhhhhhhhhhhh.',
    '..HHhhhhhhhhhhhhh.', '..HHhhh...h...h...', '..HHh.............', '..HH..............', '...H..............',
  ], 2)]),
  opt('bob', 'Bob', [hairFront([
    '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhhh.', '.HHhhhhhhhhhhhhhh.',
    '.HHhhhhhhhhhhhhh..', '.HHhhhh...........', '.HHhhh............', '.HHhhh............', '.HHhhh............',
    '.HHhhh............', '.HHHhh............', '..HHH.............',
  ], 2)]),
  opt('shoulder', 'Shoulder length', [
    hairBack(['.Hhhh', 'HHhhh', 'HHhhh', 'HHhhh', 'HHhhh', 'HHhhh', 'HHhh.', '.HH..'], 10),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhhh.', '.HHhhhhhhhhhhhhhh.',
      '.HHhhhhhhh...hhh..', '.HHhhhh...........', '.HHhhh............', '.HHhhh............', '.HHhh.............',
    ], 2),
  ]),
  opt('long', 'Long', [
    hairBack(['.Hhhhh', 'HHhhhh', 'HHhhhh', 'HHhhhh', 'HHhhhh', 'HHhhhh', 'HHhhhh', 'HHhhh.', 'HHhhh.', 'HHhhh.', '.HHh..'], 9),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhhh.', '.HHhhhhhhhhhhhhhh.',
      '.HHhhhhhhhh..hhh..', '.HHhhhh...........', '.HHhhh............', '.HHhh.............',
    ], 2),
  ]),
  opt('wavy', 'Long wavy', [
    hairBack(['.Hhhhh', 'HHhhhhh', '.HHhhhh', 'HHhhhh.', 'HHhhhhh', '.HHhhhh', 'HHhhhh.', 'HHhhhhh', '.HHhhh.', 'HHhhh..', '.HH....'], 9),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhhh..', '..Hhhhhhhhhhhhhhhh', '.HHhhhhhhhhhhhhhh.',
      '.HHhhhhhhhh..hhhh.', '.HHhhhh......h....', '.HHhhh............', '..HHh.............',
    ], 2),
  ]),
  opt('ponytail', 'Ponytail', [
    hairBack(['hhh.', 'Hhhh', 'HHhh', 'HHhh', '.HHh', '.HHh', '..HH', '..HH', '...H'], 8),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..',
      '..HHhhhhh.........', '.xxHhh............', '..HHh.............', '...HH.............',
    ], 2),
  ]),
  opt('bun', 'Bun', [hairFront([
    '..hhhh............', '.hhhiih...........', '.Hhhhhh...........', '..Hxxhhhhhh.......', '...hhhhhhiiihh....',
    '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..', '..HHhhhh..........', '..HHhh............', '...HH.............',
    '...H..............',
  ], 0)]),
  opt('topknot', 'Top knot', [hairFront([
    '.......hhhh.......', '......hhiihh......', '.......Hxxh.......', '.....hhhhhhhh.....',
    '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhh...', '..HHhhhh..........', '..HHhh............',
    '...HH.............',
  ], 0)]),
  opt('braid', 'Braid', [
    hairBack(['hhh.', 'Hhhh', 'HHh.', '.hhH', 'Hhh.', '.hhH', 'Hhh.', '.hhH', '.Hh.', '.xx.', '.hh.', '..h.'], 8),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhhiiihhh...', '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..',
      '..HHhhhhh.........', '..HHhh............', '..HHh.............', '...HH.............',
    ], 2),
  ]),
  opt('dreads', 'Dreadlocks', [
    hairBack(['.H.H.H', 'HhHhHh', 'HhHhHh', 'HhHhH.', 'HhHhH.', 'HhHhH.', '.hHhH.', '.h.hH.', '.h..h.', '....h.'], 9),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhHhhhhHhhh...', '..HhHhhhHhhhhHhh..', '.HhHhHhhhhhhhhhh..',
      '.HhHhHhhh.h.h.h...', '.HhHhHh...........', '.HhHhH............', '.H.HhH............', '...H..............',
    ], 2),
  ]),
  opt('mullet', 'Mullet', [
    hairBack(['.HHhh', 'HHHhh', 'HHHhh', 'HHHhh', 'HHHh.', 'HHHh.', '.HHh.', '.HH..'], 10),
    hairFront([
      '......hhhhhh......', '....hhhhhhhhhh....', '...hhhhhiiiihhh...', '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..',
      '..HHhhhh..........', '..HHhh............', '..HHh.............', '..HHh.............',
    ], 2),
  ]),
  opt('slick', 'Slicked back', [hairFront([
    '.......hhhh.......', '.....hhhhhhhh.....', '...hhhiiiiiihh....', '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..',
    '..HHhhhhhhh.......', '..HHhhh...........', '...HHh............', '...HH.............', '...H..............',
  ], 2)]),
  opt('spacebuns', 'Space buns', [hairFront([
    '..hhhh......hhh...', '.hhiihh....hiihh..', '.Hhhhhh....Hhhhh..', '..Hhhhhhhhhhhhh...', '...hhhhhhiiihhh...',
    '..Hhhhhhhhhhhhhh..', '..HHhhhhhhhhhhhh..', '..HHhhhh..........', '..HHhh............', '...HH.............',
    '...H..............',
  ], 0)]),
  opt('anime', 'Anime spikes', [
    hairBack(['HH....', 'HHh...', '.HHh..', '..HHh.', '...HH.'], 10),
    hairFront([
      '...h..............', '...hh.....h.......', '..hhhh...hh.......', '..hhhhh.hhh....h..', '.Hhhhhhhhhhh..hh..',
      '.HHhhhhhhhiihhhhh.', 'HHHhhhhhhhhhhhhhhh', '.HHhhhhhhhhhhhhh..', '.HHhhhhhh.hhh.hh..', 'HHHhhh....h....h..',
      '.HHh..............', '..HH..............',
    ], 0),
  ]),
];

const MARKS = [
  opt('none', 'None'),
  opt('freckles', 'Freckles', [face(Z.marks, 12, 9, ['S.S.S', '.S.S.'])]),
  opt('blush', 'Blush', [face(Z.marks, 12, 8, ['.nn..n'])]),
  opt('scar', 'Scar', [face(Z.marks, 9, 11, ['...z', '..z.', '.z..', 'z...'])]),
  opt('warpaint', 'War paint', [face(Z.marks, 12, 8, ['.xx..x', '.xx..x'])]),
  opt('beautymark', 'Beauty mark', [face(Z.marks, 13, 14, ['k'])]),
  opt('bandage', 'Plaster', [face(Z.marks, 12, 6, ['jwwj'])]),
  opt('stripes', 'Stripes', [face(Z.marks, 8, 3, ['HH..', '....', 'HHH.', '....', 'HH..'])]),
];

// ------------------------------------------------------------------------------- TOPS -----
// Torso layers are written full width and clipped to the build; sleeves are clipped to the arm.
const topTorso = (rows, z = Z.top) => layer('torso', z, [whole(rows)], { clip: true });
const sleeve = (n, cuff = 'b', body = '.Aaaa.') => {
  const rows = Array.from({ length: n }, () => body);
  if (cuff && n > 0) rows[n - 1] = '.' + cuff.repeat(4) + '.';
  return layer('arm', Z.sleeve, [whole(rows)], { clip: true });
};
const FULL = '.AAaaaaaaaaaaaa.';   // a plain full-width row, shaded at the back
const rowsOf = (n, row) => Array.from({ length: n }, () => row);

const TOP = [
  opt('tee', 'T-shirt', [topTorso([
    '.AAaaaAAAaaaaaa.', ...rowsOf(16, FULL), '.AAAAAAAAAAAAAA.',
  ]), sleeve(5, 'A')]),
  opt('tank', 'Tank top', [topTorso([
    '....aa....aa....', '....aa....aa....', '...Aaa....aaa...', '..AAaaaaaaaaaa..', ...rowsOf(13, FULL), '.AAAAAAAAAAAAAA.',
  ])]),
  opt('longsleeve', 'Long sleeve', [topTorso([
    '.AAaaaAAAaaaaaa.', ...rowsOf(16, FULL), '.AAAAAAAAAAAAAA.',
  ]), sleeve(12, 'b')]),
  opt('hoodie', 'Hoodie', [topTorso([
    '.AAAAAaaaaaaaaa.', '.AAAAaaaaaaaaaa.', '.AAAaaaaaaaaaaa.', '.AAaaaaaabaaba..', '.AAaaaaaabaaba..',
    '.AAaaaaaabaaba..', ...rowsOf(5, FULL), '.AAaaaaAAAAAAaa.', '.AAaaaaAaaaaAaa.', '.AAaaaaAaaaaAaa.', '.AAaaaaAAAAAAaa.',
    '.AAaaaaaaaaaaaa.', '.AbbbbbbbbbbbbB.', '.BBBBBBBBBBBBBB.',
  ]), sleeve(12, 'b')]),
  opt('zipjacket', 'Zip jacket', [topTorso([
    '.bbbbbbbbbbbbb..', '.AAaaaaaaabaaaa.', ...rowsOf(14, '.AAaaaaaaabaaaa.'), '.AAaaaaaaabaaaa.', '.bbbbbbbbbbbbbb.',
  ]), sleeve(12, 'b')]),
  opt('leather', 'Leather jacket', [topTorso([
    '.AAAaaaAbbbAaaa.', '.AAaaaaAbbbbAaa.', '.AAaaaaAbbbbAaa.', '.AAaaaaaAbbbAaa.', '.AAaaaaaAbbbAaa.',
    '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.',
    '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.', '.AAaaaaaaAbbAaa.',
    '.AAaaaaaaAbbAaa.', '.AAAAAAAAAAAAAA.', '.AAAAAAAAAAAAAA.',
  ]), sleeve(12, 'A', '.AaaA.')]),
  opt('vest', 'Vest', [topTorso([
    '.AAbbbbbbbbbbba.', '.AAabbbbbbbbbaa.', '.AAaabbbbbbbaaa.', '.AAaaabbbbbbaaa.', '.AAaaaabbbbaaaa.',
    '.AAaaaaabbkaaaa.', '.AAaaaaabbbaaaa.', '.AAaaaaabbkaaaa.', '.AAaaaaabbbaaaa.', '.AAaaaaabbkaaaa.',
    '.AAaaaaabbbaaaa.', '.AAaaaaabbkaaaa.', '.AAaaaaabbbaaaa.', '.AAaaaaabbbaaaa.', '.AAaaaaabbbaaaa.',
    '.AAaaaaaabbaaaa.', '.AAAAAAAAbbAAAA.', '.AAAAAAAAAAAAAA.',
  ]), sleeve(5, 'B', '.Bbbb.')]),
  opt('collar', 'Collared shirt', [topTorso([
    '.AAuuuuAAAuuuu..', '.AAaauuaaauuaa..', '.AAaaaaaaaabaaa.', ...rowsOf(3, '.AAaaaaaaaaaaaa.'), '.AAaaaaaaaabaaa.',
    ...rowsOf(3, FULL), '.AAaaaaaaaabaaa.', ...rowsOf(5, FULL), '.AAAAAAAAAAAAAA.',
  ]), sleeve(5, 'u')]),
  opt('suit', 'Suit', [topTorso([
    '.AAAaaaAwwwAaaa.', '.AAaaaaAwwwwAaa.', '.AAaaaaaAwwwAaa.', '.AAaaaaaAwwwAaa.', '.AAaaaaaaAwwAaa.',
    '.AAaaaaaaAwwAaa.', '.AAaaaaaaaAwaaa.', '.AAaaaaaaaaAaaa.', '.AAaaaaaaaaakaa.', ...rowsOf(3, FULL),
    '.AAaaaaaaaaakaa.', ...rowsOf(3, FULL), '.AAAAAAAAAAAAAA.', '.AAAAAAAAAAAAAA.',
  ]), sleeve(12, 'w')]),
  opt('sweater', 'Striped sweater', [topTorso([
    '.AAAAAAbbbbbbbb.', FULL, FULL, '.BBbbbbbbbbbbbb.', FULL, FULL, '.BBbbbbbbbbbbbb.', FULL, FULL,
    '.BBbbbbbbbbbbbb.', FULL, FULL, '.BBbbbbbbbbbbbb.', FULL, FULL, FULL, '.bbbbbbbbbbbbbb.', '.BBBBBBBBBBBBBB.',
  ]), layer('arm', Z.sleeve, [whole(['.Aaaa.', '.Aaaa.', '.Bbbb.', '.Aaaa.', '.Aaaa.', '.Bbbb.', '.Aaaa.', '.Aaaa.', '.Bbbb.', '.Aaaa.', '.Aaaa.', '.bbbb.'])], { clip: true })]),
  opt('jersey', 'Jersey', [topTorso([
    '.BBbbbbbbbbbbbb.', '.AAaaaaaaaaaaaa.', '.AAaaaaaaaaaaaa.', '.AAaaaaabbbbbaa.', '.AAaaaaaaaaabaa.',
    '.AAaaaaaaaabaaa.', '.AAaaaaaaaabaaa.', '.AAaaaaaaabaaaa.', '.AAaaaaaaabaaaa.', '.AAaaaaaaabaaaa.',
    ...rowsOf(6, FULL), '.BBbbbbbbbbbbbb.', '.BBBBBBBBBBBBBB.',
  ]), sleeve(5, 'b')]),
  opt('gi', 'Martial arts gi', [topTorso([
    '.AAaaaaAsssaaaa.', '.AAaaaaaAssaaaa.', '.AAaaaaaaAsaaaa.', '.AAaaaaaaaAaaaa.', '.AAaaaaaaaaAaaa.',
    '.AAaaaaaaaaaAaa.', ...rowsOf(6, FULL), '.bbbbbbbbbbbbbb.', '.BBBBBBBBbbbbbb.', ...rowsOf(3, FULL), '.AAAAAAAAAAAAAA.',
  ]), sleeve(9, 'A')]),
  opt('armor', 'Plate armour', [topTorso([
    '.RRrrrrrrrrrrrr.', '.RRrrrrrrrrrrrr.', '.RRaaaaaaaauuaa.', '.RRaaaaaaauuuaa.', '.RRaaaaaaaauaaa.',
    '.RRaaaaaaaaaaaa.', '.RRAaaaaaaaaaaa.', '.RRAAaaaaaaaaaa.', '.RRRRRRRRRRRRRR.', '.RRaaaaaaaaaaaa.',
    '.RRRRRRRRRRRRRR.', '.RRaaaaaaaaaaaa.', '.RRRRRRRRRRRRRR.', '.RRaaaaaaaaaaaa.', '.gggggggggggggg.',
    '.GGGGGGgggGGGGG.', '.RRrrrrrrrrrrrr.', '.RRRRRRRRRRRRRR.',
  ]), layer('arm', Z.sleeve, [whole(['RrrrrR', 'Raaaar', 'RAaaaR', 'RRRRRR', '.RrrR.', '.Rrrr.', '.RrrR.', '.RRRR.', '.Rrrr.', '.RrrR.', '.Rrrr.', '.RRRR.'])])]),
  opt('robe', 'Robe', [topTorso([
    '.AAaaaaabbbaaaa.', '.AAaaaaaabbbaaa.', '.AAaaaaaaabbaaa.', '.AAaaaaaaabbaaa.', ...rowsOf(8, '.AAaaaaaaabbaaa.'),
    '.BBbbbbbbbbbbbb.', '.BBbbbbbbbbbbbb.', ...rowsOf(3, '.AAaaaaaaabbaaa.'), '.AAaaaaaaabbaaa.',
  ]), sleeve(12, 'b', '.Aaaaa'), layer('pelvis', Z.skirt, [whole([
    '.AAaaaaaaabba.', '.AAaaaaaaabba.', '.AAaaaaaaabba.', '.AAaaaaaaabba.', '.AAaaaaaaabba.',
    'AAaaaaaaaabbaa', 'AAaaaaaaaabbaa', 'AAaaaaaaaabbaa', 'AAaaaaaaaabbaa', 'BBbbbbbbbbbbbb',
  ])])]),
  opt('overalls', 'Overalls', [topTorso([
    '.BBbbbbbbbbbbbb.', '.BBbbbbAAbbbAAb.', '.BBbbbbAAbbbAAb.', '.BBbbbbAAbbbAAb.', '.BBbbbbAAbbbAAb.',
    '.BBbbbbAAbbbAAb.', '.BBbbbbAAbbbAAb.', '.BBbbbbAgaaagAb.', '.BBbbbAaaaaaaAb.', '.BBbbbAaaaaaaAb.',
    '.BBbbbAaAAAaaAb.', '.BBbbbAaAaAaaAb.', '.BBbbbAaAAAaaAb.', '.BBbbbAaaaaaaAb.', '.AAaaaaaaaaaaaa.',
    '.AAaaaaaaaaaaaa.', '.AAaaaaaaaaaaaa.', '.AAAAAAAAAAAAAA.',
  ]), sleeve(5, 'B', '.Bbbb.')]),
  opt('trench', 'Trench coat', [topTorso([
    '.AAAuuaaaAAAaaa.', '.AAuuuaaaAwwaaa.', '.AAaaaaaaaAwaaa.', '.AAaaaaaaaaAkaa.', ...rowsOf(3, '.AAaaaaaaaaAaaa.'),
    '.AAaaaaaaaaAkaa.', ...rowsOf(3, '.AAaaaaaaaaAaaa.'), '.BBBBBBBBBBgBBB.', '.BBBBBBBBBBBBBB.', ...rowsOf(3, '.AAaaaaaaaaAaaa.'),
  ]), sleeve(12, 'A'), layer('pelvis', Z.skirt, [whole([
    '.AAaaaaaaaaAa.', '.AAaaaaaaaaAa.', '.AAaaaaaaaaAa.', '.AAaaaaaaaaAa.', '.AAaaaaaaaaAa.',
    'AAaaaaaaaaaAaa', 'AAaaaaaaaaaAaa', 'AAaaaaaaaaaAaa', 'AAaaaaaaaaaAaa', 'AAAAAAAAAAAAAA',
  ])])]),
  opt('flannel', 'Flannel', [topTorso([
    '.AAaaaBaaaaBaaa.', '.AAaaaBaaaaBaaa.', '.AAaaaBaaaaBaaa.', '.BBBBBBBBBBBBBB.', '.AAaaaBaaaaBaaa.',
    '.AAaaaBaaaaBaaa.', '.AAaaaBaaaaBaaa.', '.BBBBBBBBBBBBBB.', '.AAaaaBaaaaBaaa.', '.AAaaaBaaaaBaaa.',
    '.AAaaaBaaaaBaaa.', '.BBBBBBBBBBBBBB.', '.AAaaaBaaaaBaaa.', '.AAaaaBaaaaBaaa.', '.AAaaaBaaaaBaaa.',
    '.BBBBBBBBBBBBBB.', '.AAaaaBaaaaBaaa.', '.AAAAAAAAAAAAAA.',
  ]), layer('arm', Z.sleeve, [whole(['.AaBa.', '.AaBa.', '.BBBB.', '.AaBa.', '.AaBa.', '.BBBB.', '.AaBa.', '.AaBa.', '.BBBB.', '.AaBa.', '.AaBa.', '.bbbb.'])], { clip: true })]),
  opt('tunic', 'Tunic', [topTorso([
    '.AAaaaabkbaaaa..', '.AAaaaaabkbaaaa.', '.AAaaaaaabkaaaa.', '.AAaaaaaabkaaaa.', ...rowsOf(8, FULL),
    '.AAaaaaaaaaaaaa.', '.oooooooooooooo.', '.ooooooogoooooo.', ...rowsOf(2, FULL), '.AAAAAAAAAAAAAA.',
  ]), sleeve(8, 'A'), layer('pelvis', Z.skirt, [whole([
    '.AAaaaaaaaaaa.', '.AAaaaaaaaaaa.', '.AAaaaaaaaaaa.', '.AAaaaaaaaaaa.', '.AAaaaaaaaaaa.', '.AAaaaaaaaaaa.', '.AAAAAAAAAAAA.',
  ])])]),
  opt('bomber', 'Bomber jacket', [topTorso([
    '.BBbbbbbbbbbbbb.', '.BBbbbbbbbbbbbb.', '.AAauuuaaaaaaaa.', '.AAauuuaaaakaaa.', '.AAaaaaaaaaaaaa.',
    '.AAaaaaaaaakaaa.', '.AAaaaaaaaaaaaa.', '.AAaaaaaaaakaaa.', '.AAaAAAaaaaaaaa.', '.AAaAaAaaaakaaa.',
    '.AAaAAAaaaaaaaa.', '.AAaaaaaaaaaaaa.', '.AAaaaaaaaaaaaa.', '.AAaaaaaaaaaaaa.', '.AAaaaaaaaaaaaa.',
    '.BBbbbbbbbbbbbb.', '.BBbbbbbbbbbbbb.', '.BBBBBBBBBBBBBB.',
  ]), sleeve(12, 'b', '.Aaau.')]),
  opt('ninja', 'Shinobi wrap', [topTorso([
    '.AAaaaaabaaaaaa.', '.AAaaaaaabaaaaa.', '.AAaaaaaaabaaaa.', '.AAaaaaaaaabaaa.', '.AAaaaaaaaaabaa.',
    '.AAaaaaaaaaaaba.', '.AAabaaaaaaaaaa.', '.AAaabaaaaaaaaa.', '.AAaaabaaaaaaaa.', '.AAaaaabaaaaaaa.',
    '.AAaaaaabaaaaaa.', '.AAaaaaaabaaaaa.', '.bbbbbbbbbbbbbb.', '.BBbbbbbbbbbbbb.', ...rowsOf(3, FULL), '.AAAAAAAAAAAAAA.',
  ]), sleeve(12, 'b')]),
];

const NECK = [
  opt('none', 'None'),
  opt('scarf', 'Scarf', [layer('torso', Z.neck, [whole([
    '...XXxxxxxxxx...', '..XXxxxxxxxxxx..', '..XXxxyxxxxxxx..', '..XXX...........', '..XXX...........',
    '..XX............', '..Xx............', '..XX............',
  ])])]),
  opt('bandana', 'Bandana', [layer('torso', Z.neck, [whole([
    '.....xxxxxxxxx..', '......Xxxxxxx...', '.......Xxxxx....', '........Xxx.....', '.........X......',
  ])])]),
  opt('tie', 'Tie', [layer('torso', Z.neck, [whole([
    '.........XxX....', '.........xxx....', '..........x.....', '.........xxx....', '.........xXx....',
    '.........xxx....', '.........xXx....', '.........xxx....', '..........x.....',
  ])])]),
  opt('bowtie', 'Bow tie', [layer('torso', Z.neck, [whole([
    '........x..x....', '........xXXx....', '........x..x....',
  ])])]),
  opt('chain', 'Chain', [layer('torso', Z.neck, [whole([
    '.......g....g...', '........g..g....', '.........gg.....', '.........GgG....', '..........g.....',
  ])])]),
  opt('spiked', 'Spiked collar', [layer('torso', Z.neck, [whole([
    '......r.r.r.r...', '.....kkkkkkkk...', '.....kRkkRkkR...',
  ])])]),
  opt('medal', 'Medal', [layer('torso', Z.neck, [whole([
    '.......x....x...', '........x..x....', '.........xx.....', '........gggg....', '........gGGg....', '........gggg....',
  ])])]),
];

// ---------------------------------------------------------------------------- BOTTOMS -----
// A bottom is the hips plus both leg layers (the rig draws the same leg twice, the far one darker).
const legRows = (n, row, hem) => { const r = rowsOf(n, row); if (hem) r[n - 1] = hem; return r; };
const bottom = (hips, legs, skirt) => {
  const out = [layer('pelvis', Z.waist, [whole(hips)])];
  if (legs) out.push(layer('leg', Z.pants, [whole(legs)]));
  if (skirt) out.push(layer('pelvis', Z.skirt, [whole(skirt)]));
  return out;
};
const HIP_WAIST = ['.CCCCCCCCCCCC.', '.Cccccccccccc.', '.Cccccccccccc.', '.CccccccCcccc.', '.CccccccCcccc.'];
const BOTTOM = [
  opt('jeans', 'Jeans', bottom(['.CCCCCCCCCCCC.', '.Ccccccgccccc.', '.Cccccccccccc.', '.CccccccCcccc.', '.CccccccCcccc.'],
    [...legRows(13, '.Cccc..'), '.CccC..', '.CCCC..'])),
  opt('shorts', 'Shorts', bottom(HIP_WAIST, [...legRows(5, '.Cccc..'), '.CCCC..'])),
  opt('cargo', 'Cargo pants', bottom(HIP_WAIST, [
    ...legRows(4, '.Cccc..'), '.CCCCC.', '.CcccC.', '.CcccC.', '.CCCCC.', ...legRows(5, '.Cccc..'), '.CCCC..', '.CCCC..',
  ])),
  opt('track', 'Track pants', bottom(['.CCCCCCCCCCCC.', '.Cccccccccccw.', '.Cccccccccccw.', '.Cccccccccccw.', '.Cccccccccccw.'],
    [...legRows(13, '.Cccw..'), '.CCCw..', '.CCCC..'])),
  opt('slacks', 'Slacks', bottom(['.XXXXXXXXXXXX.', '.CccccccCcccc.', '.CccccccCcccc.', '.CccccccCcccc.', '.CccccccCcccc.'],
    [...legRows(14, '.CcCc..'), '.CCCC..'])),
  opt('ripped', 'Ripped jeans', bottom(['.CCCCCCCCCCCC.', '.Cccccccccccc.', '.Cccccccccccc.', '.CccccccCcccc.', '.CccccccCcccc.'],
    ['.Cccc..', '.Cccc..', '.Cccc..', '.Cccc..', '.Cccc..', '.Cccc..', '.Cccc..', '.Cc.c..', '.C..c..', '.Cc.c..',
      '.Cccc..', '.Cccc..', '.Cccc..', '.Cccc..', '.CCCC..'])),
  opt('skirt', 'Skirt', bottom(HIP_WAIST, null, [
    '.CCCCCCCCCCCC.', '.Cccccccccccc.', '.Cccccccccccc.', '.Cccccccccccc.', 'CCcccccccccccc', 'CCcccccccccccc',
    'CCcccccccccccc', 'CCCCCCCCCCCCCC',
  ])),
  opt('kilt', 'Pleated kilt', bottom(HIP_WAIST, null, [
    '.XXXXXXXXXXXX.', '.CcCcCcCcCcCc.', '.CcCcCcCcCcCc.', 'CcCcCcCcCcCcCc', 'CcCcCcCcCcCcCc', 'CcCcCcCcCcCcCc', 'CCCCCCCCCCCCCC',
  ])),
  opt('greaves', 'Greaves', bottom(['.RRRRRRRRRRRR.', '.Rrrrrrrrrrrr.', '.Cccccccccccc.', '.Cccccccccccc.', '.Cccccccccccc.'],
    [...legRows(5, '.Cccc..'), '.RRRR..', '.Rrrr..', '.RrrR..', '.Rrrr..', '.RrrR..', '.Rrrr..', '.RrrR..', '.RRRR..', '.Rrrr..', '.RRRR..'])),
  opt('baggy', 'Baggy pants', bottom(HIP_WAIST, [
    '.Cccc..', '.Cccc..', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.', 'CCcccc.',
    'CCcccc.', 'CCCCCC.',
  ])),
  opt('leggings', 'Leggings', bottom(['.CCCCCCCCCCCC.', '.Cccccccccccc.', '.Cccccccccccc.', '.Cccccccccccc.', '.Cccccccccccc.'],
    [...legRows(15, '.Cccc..')])),
  opt('joggers', 'Joggers', bottom(['.CCCCCCCCCCCC.', '.CcccccwwCccc.', '.Cccccccccccc.', '.Cccccccccccc.', '.Cccccccccccc.'],
    [...legRows(12, '.Cccc..'), '.CCCC..', '.CCCC..'])),
];

// ------------------------------------------------------------------------------ SHOES -----
const shoe = (row, lines) => [layer('leg', Z.shoes, [at(row, 0, lines)])];
const SHOES = [
  opt('sneakers', 'Sneakers', shoe(13, ['.ffff..', '.fwfff.', '.Ffffff', '.wwwwww'])),
  opt('hightops', 'High-tops', shoe(11, ['.ffff..', '.fwwf..', '.ffff..', '.fwwf..', '.Ffffff', '.wwwwww'])),
  opt('boots', 'Boots', shoe(10, ['.ffff..', '.FFFF..', '.ffff..', '.ffff..', '.ffff..', '.Ffffff', '.oooooo'])),
  opt('combat', 'Combat boots', shoe(9, ['.ffff..', '.fwfF..', '.ffff..', '.fwfF..', '.ffff..', '.fwfF..', '.Ffffff', '.oooooo'])),
  opt('sandals', 'Sandals', shoe(14, ['.f.f...', '.ffff..', '.Ssssss', '.oooooo'])),
  opt('barefoot', 'Barefoot'),
  opt('dress', 'Dress shoes', shoe(14, ['.ffff..', '.Ffffff', '.FFFFFF'])),
  opt('slippers', 'Slippers', shoe(13, ['.ffff..', 'ffffff.', 'fFFFFFf', '.ffffff'])),
  opt('sabatons', 'Sabatons', shoe(12, ['.RRRR..', '.rrrr..', '.RrrR..', '.rrrrr.', '.RRrrrr', '.RRRRRR'])),
  opt('rainboots', 'Rain boots', shoe(8, ['ffffff.', '.ffff..', '.ffff..', '.ffff..', '.ffff..', '.ffff..', '.ffff..', '.Ffffff', '.FFFFFF'])),
];

// ----------------------------------------------------------------------------- GLOVES -----
const glove = (row, lines) => [layer('arm', Z.glove, [at(row, 0, lines)])];
const GLOVES = [
  opt('none', 'None'),
  opt('gloves', 'Gloves', glove(10, ['.XXXX.', '.xxxx.', '.Xxxy.', '.Xxxy.', '..XX..'])),
  opt('fingerless', 'Fingerless', glove(10, ['.XXXX.', '.xxxx.', '.Xxxx.'])),
  opt('bracers', 'Bracers', glove(7, ['.yxxx.', '.Xxxx.', '.Xxxx.', '.Xxxx.', '.XXXX.'])),
  opt('wraps', 'Hand wraps', glove(9, ['.wwww.', '.jwjw.', '.wjwj.', '.wwww.', '.wwwj.'])),
  opt('gauntlets', 'Gauntlets', glove(8, ['RrrrrR', 'Rrrrrr', '.RrrR.', '.Rrrr.', '.Rrrr.', '.RRRR.', '..RR..'])),
];

// ---------------------------------------------------------------------------- EYEWEAR -----
const eyewear = (row, col, lines) => [layer('head', Z.eyewear, [at(row, col, lines)])];
const EYEWEAR = [
  opt('none', 'None'),
  opt('glasses', 'Glasses', eyewear(9, 3, ['.....kkkk.kk', 'kkkkk..k.k.k', '.....kkkk.kk'])),
  opt('round', 'Round glasses', eyewear(9, 3, ['......kk..k.', 'kkkkkk..kkkk', '......kk..k.'])),
  opt('shades', 'Shades', eyewear(9, 3, ['.....kkkkkkk', 'kkkkkklLkllk', '......lll.l.'])),
  opt('goggles', 'Goggles', eyewear(9, 2, ['......XXXXXXX', 'xxxxxXLlXXLlX', 'xxxxxXllXXllX', '......XXXXXXX'])),
  opt('monocle', 'Monocle', eyewear(9, 8, ['.gg..', 'g..g.', 'g..g.', '.gg..', '..g..', '..g..', '.g...'])),
  opt('visor', 'Visor', eyewear(9, 3, ['XXXXXXXXXXXXX', 'xxxxxyyyyyyyy', 'xxxxxyyyyyyyy', 'XXXXXXXXXXXXX'])),
  opt('eyepatch', 'Eye patch', eyewear(7, 3, ['.........k..', '........k...', '.......kkk..', 'kkkkkkkkkk..', '.......kkk..'])),
  opt('3d', '3D glasses', eyewear(9, 3, ['.....wwwwwww', 'wwwwwwddwLLw', '.....wwwwwww'])),
];

// --------------------------------------------------------------------------- HEADWEAR -----
// `trim` removes hair rows above that line, so a cap sits ON the head instead of a crew cut
// poking up through its crown.
const hat = (row, lines, trim, col = 0) => ({ layers: [layer('head', Z.headwear, [at(row, col, lines)])], ...(trim ? { trim } : {}) });
const withHat = (id, name, h) => opt(id, name, h.layers, h.trim ? { trim: h.trim } : {});
const HEADWEAR = [
  opt('none', 'None'),
  withHat('cap', 'Cap', hat(3, [
    '.....xxxxxx.......', '...xxxxxxxxxx.....', '..Xxxxxxxxxxxx....', '..XXxxxxxxxxxxxxxx', '..XXXXXXXXXXXXyyyy',
  ], 6)),
  withHat('backcap', 'Backwards cap', hat(3, [
    '.......xxxxxx.....', '.....xxxxxxxxxx...', '....xxxxxxxxxxxx..', 'xxxxxxxxxxxxxxxx..', 'yyyyXXXXXXXXXXXX..',
  ], 6)),
  withHat('beanie', 'Beanie', hat(1, [
    '.......yy.........', '......xxxx........', '....xxxxxxxx......', '..XxxxxxxxxxxX....', '..XxxxxxxxxxxxX...',
    '..XxxxxxxxxxxxxX..', '..yyyyyyyyyyyyyy..', '..XXXXXXXXXXXXXX..',
  ], 7)),
  withHat('headband', 'Headband', hat(6, ['..XXXXXXXXXXXXX...', '..xxxxxxxxxxxxxx..', '.XX...............', 'XX................'])),
  withHat('bandana', 'Bandana', hat(3, [
    '.....xxxxxxx......', '...xxxxyxxxxxx....', '..Xxxxxxxxxxxxx...', '.XXxxxxxxxxxxxxx..', 'XXX...............',
    'XX................', 'X.................',
  ], 6)),
  withHat('tophat', 'Top hat', hat(0, [
    '....XxxxxxxxX.....', '....XxxxxxxyX.....', '....XxxxxxxyX.....', '....bbbbbbbbb.....', '....XxxxxxxyX.....',
    '..XXXXXXXXXXXXX...',
  ], 6)),
  withHat('cowboy', 'Cowboy hat', hat(1, [
    '......xxxxxx......', '.....xxxxxxxx.....', '.....xxxxxxxxx....', '.....bbbbbbbbb....', 'X...XxxxxxxxxxX..X',
    '.XXXXXXXXXXXXXXXX.',
  ], 6)),
  withHat('crown', 'Crown', hat(1, ['....g..g..g..g....', '....gg.gg.gg.gg...', '....ggggggggggg...', '....gdgggggdggg...', '....GGGGGGGGGGG...'])),
  withHat('horns', 'Horns', hat(0, ['..j..........j....', '..jj........jj....', '...jj......jj.....', '....jj....jj......', '....jjj..jjj......'])),
  withHat('hood', 'Hood', hat(3, [
    '.....xxxxxxx......', '...xxxxxxxxxxx....', '..Xxxxxxxxxxxxx...', '.XXxxxxx.......x..', '.XXxxx............',
    '.XXxx.............', '.XXxx.............', '.XXxx.............', '.XXxx.............', '.XXxx.............',
    '.XXXx.............', '..XXXx............', '...XXxx...........', '....XXXX..........',
  ], 9)),
  withHat('knight', 'Knight helm', hat(3, [
    '.....rrrrrrr......', '...rrrrrrrrrrr....', '..Rrrrrrrrrrrrr...', '..RRrrrrrrrrrrrr..', '..RRrrrrrrrrrrrr..',
    '..RRrrrrrrrrrrrr..', '..RRrrrrrkkkkkkk..', '..RRrrrrrrrrrrrr..', '..RRrrrrrRkRkRkr..', '..RRrrrrrrrrrrrr..',
    '..RRRrrrrrrrrrrr..', '...RRRrrrrrrrrr...', '....RRRRRRRRRR....',
  ], 16)),
  withHat('antenna', 'Antenna', hat(0, ['..........yy......', '..........yy......', '...........R......', '...........R......', '..........RRR.....'])),
  withHat('wizard', 'Wizard hat', hat(0, [
    '.........X........', '........xX........', '.......xxxX.......', '......xxgxxX......', '.....xxxxxxxX.....',
    '..XXXXXXXXXXXXXX..',
  ], 6)),
  withHat('halo', 'Halo', hat(0, ['.....gggggg.......', '....g......g......', '.....gggggg.......'])),
  withHat('catears', 'Cat ears', hat(1, ['....h.....h.......', '...hph...hph......', '...hpph..hpph.....', '...hhhh..hhhh.....'])),
  withHat('viking', 'Viking helm', hat(0, [
    'j................j', 'jj..............jj', '.jj.....r......jj.', '..jjrrrrrrrrrrjj..', '...Rrrrrrrrrrrr...',
    '..RRrrrrrrrrrrrr..', '..RRrRrRrRrRrRrR..', '..RRRRRRRRRRRRRR..',
  ], 7)),
  withHat('flower', 'Flower', hat(4, ['..........p.p.....', '...........g......', '..........p.p.....', '...........t.t....'])),
  withHat('headphones', 'Headphones', hat(3, [
    '.....XXXXXXX......', '...XX.......XX....', '..X...........X...', '..X...............', '.XXX..............',
    'XxxxX.............', 'XxyxX.............', 'XxxxX.............', '.XXX..............',
  ])),
  withHat('beret', 'Beret', hat(3, ['.......x..........', '...xxxxxxxxx......', '.xxxxxxxxxxxxx....', '..XXXXXXXXXXXXX...'], 6)),
];

// ---------------------------------------------------------------------------- catalogue -----
// ORDER IS PERMANENT (see avatarKit.js): categories and their options are addressed by index in
// every saved character. `fallback` is the index the default character uses and the one a bad
// digit decodes to. The rest is for the creator: `group` is the tab a category sits under,
// `paint` the colour slots its swatches change (what the part is actually drawn in), and `view`
// whether its thumbnails show the head close up or the whole figure.
const C = (id, name, group, options, paint, view) => ({ id, name, group, options, paint, view });
export const CATEGORIES = [
  C('build', 'Build', 'body', BUILD, ['skin'], 'body'),
  C('head', 'Head', 'body', HEAD, ['skin'], 'head'),
  C('ears', 'Ears', 'face', EARS, ['skin'], 'head'),
  C('eyes', 'Eyes', 'face', EYES, ['eyes'], 'head'),
  C('brows', 'Brows', 'face', BROWS, ['hair'], 'head'),
  C('nose', 'Nose', 'face', NOSE, ['skin'], 'head'),
  C('mouth', 'Mouth', 'face', MOUTH, ['skin'], 'head'),
  C('facialHair', 'Facial hair', 'hair', FACIAL_HAIR, ['hair'], 'head'),
  C('hair', 'Hair', 'hair', HAIR, ['hair'], 'head'),
  C('marks', 'Face marks', 'face', MARKS, ['accessory', 'skin'], 'head'),
  C('top', 'Top', 'outfit', TOP, ['top', 'trim'], 'body'),
  C('neck', 'Neckwear', 'extras', NECK, ['accessory'], 'body'),
  C('bottom', 'Bottoms', 'outfit', BOTTOM, ['bottom'], 'body'),
  C('shoes', 'Shoes', 'outfit', SHOES, ['shoes'], 'body'),
  C('gloves', 'Gloves', 'extras', GLOVES, ['accessory'], 'body'),
  C('eyewear', 'Eyewear', 'extras', EYEWEAR, ['accessory'], 'head'),
  C('headwear', 'Headwear', 'extras', HEADWEAR, ['accessory'], 'head'),
];

// The creator's tabs, in order, and the parts under each in the order they are offered. This is
// display order, free to change - unlike CATEGORIES, whose order is baked into every saved code.
export const GROUPS = [
  { id: 'presets', name: 'Presets', parts: [] },
  { id: 'body', name: 'Body', parts: ['build', 'head'] },
  { id: 'face', name: 'Face', parts: ['eyes', 'brows', 'mouth', 'nose', 'ears', 'marks'] },
  { id: 'hair', name: 'Hair', parts: ['hair', 'facialHair'] },
  { id: 'outfit', name: 'Outfit', parts: ['top', 'bottom', 'shoes'] },
  { id: 'extras', name: 'Extras', parts: ['headwear', 'eyewear', 'neck', 'gloves'] },
];

// Colour slots, each a curated list rather than a free picker: a palette of swatches is what makes a
// character look designed, and it is what keeps the code one digit per slot.
const CLOTH = [
  '#F2F0EA', '#B8BCC4', '#6E7480', '#3A3E48', '#1E2028', '#C8323A', '#8A1E2A', '#E8762A', '#D8A82A', '#F2D23A',
  '#8AC83A', '#3A9A4A', '#2A5A34', '#2A9A9A', '#5AB4E8', '#3A64C8', '#22305A', '#6A42B0', '#B08AE0', '#E86AA8',
  '#6A2438', '#7A4E2E', '#C8A478', '#4A6A9A',
];
export const COLOURS = [
  { id: 'skin', name: 'Skin', fallback: 3, list: [
    '#FFE3CC', '#F8D2AE', '#F0C08E', '#E3A878', '#D0935F', '#B97A4A', '#9C6238', '#7E4C2A', '#633A20', '#4A2A18',
    '#F5C9B6', '#E8B890', '#F5CD30', '#9ED2A0', '#8FB8E8', '#C8A0E0', '#D8D8E0', '#E07060',
  ] },
  { id: 'hair', name: 'Hair', fallback: 2, list: [
    '#1E1A1D', '#3B2518', '#5E3A22', '#7A4526', '#8E3B1F', '#C8642A', '#D9955A', '#E6C170', '#F0E6C8', '#9A9AA2',
    '#F2F2F2', '#3E6FD8', '#2AA59A', '#4CA83A', '#7A4CC8', '#E86AAE', '#C8283A',
  ] },
  { id: 'eyes', name: 'Eyes', fallback: 0, list: [
    '#3A2418', '#1E1A1D', '#6A5A22', '#2E7A3E', '#2E5AB8', '#6A7A8A', '#C8862A', '#7A3AB8', '#C8323A', '#4FE0FF',
  ] },
  { id: 'top', name: 'Top', fallback: 15, list: CLOTH },
  { id: 'trim', name: 'Trim', fallback: 0, list: CLOTH },
  { id: 'bottom', name: 'Bottoms', fallback: 23, list: CLOTH },
  { id: 'shoes', name: 'Shoes', fallback: 5, list: CLOTH },
  { id: 'accessory', name: 'Accessory', fallback: 5, list: [...CLOTH, '#EDBE3A', '#C4CCD6', '#B0703A'] },
];

// Ready-made characters: a whole look in one click, and a starting point to change one thing on.
const P = (id, name, parts, colours) => ({ id, name, parts, colours });
export const PRESETS = [
  P('rookie', 'Rookie', {}, {}),
  P('knight', 'Knight', { build: 'broad', head: 'square', eyes: 'fierce', brows: 'thick', hair: 'crew', top: 'armor', bottom: 'greaves', shoes: 'sabatons', gloves: 'gauntlets', headwear: 'knight' },
    { skin: 2, hair: 3, top: 15, trim: 8, bottom: 3, shoes: 2, accessory: 24 }),
  P('ninja', 'Shinobi', { build: 'slim', eyes: 'fierce', brows: 'angry', hair: 'topknot', mouth: 'tight', top: 'ninja', bottom: 'joggers', shoes: 'sandals', gloves: 'wraps', headwear: 'headband' },
    { skin: 4, hair: 0, top: 4, trim: 5, bottom: 4, shoes: 3, accessory: 5 }),
  P('wizard', 'Wizard', { build: 'slim', head: 'long', eyes: 'sleepy', brows: 'thick', nose: 'long', facialHair: 'long', hair: 'long', top: 'robe', bottom: 'leggings', shoes: 'slippers', headwear: 'wizard' },
    { skin: 1, hair: 10, eyes: 4, top: 17, trim: 8, bottom: 16, shoes: 17, accessory: 17 }),
  P('punk', 'Punk', { build: 'athletic', eyes: 'angry', brows: 'angry', mouth: 'smirk', hair: 'mohawk', marks: 'scar', top: 'leather', neck: 'spiked', bottom: 'ripped', shoes: 'combat', gloves: 'fingerless' },
    { skin: 0, hair: 15, top: 4, trim: 5, bottom: 23, shoes: 4, accessory: 4 }),
  P('cowboy', 'Drifter', { build: 'athletic', head: 'square', eyes: 'sleepy', facialHair: 'stubble', hair: 'crew', mouth: 'smirk', top: 'vest', neck: 'bandana', bottom: 'jeans', shoes: 'boots', headwear: 'cowboy' },
    { skin: 5, hair: 3, top: 21, trim: 22, bottom: 23, shoes: 21, accessory: 21 }),
  P('pirate', 'Corsair', { build: 'stocky', eyes: 'fierce', brows: 'thick', facialHair: 'full', hair: 'long', eyewear: 'eyepatch', top: 'tunic', bottom: 'baggy', shoes: 'boots', headwear: 'bandana' },
    { skin: 6, hair: 0, top: 0, trim: 21, bottom: 3, shoes: 4, accessory: 5 }),
  P('samurai', 'Ronin', { build: 'athletic', eyes: 'fierce', brows: 'normal', mouth: 'neutral', hair: 'topknot', facialHair: 'goatee', top: 'gi', bottom: 'baggy', shoes: 'sandals', gloves: 'bracers' },
    { skin: 3, hair: 0, top: 16, trim: 4, bottom: 16, shoes: 21, accessory: 6 }),
  P('viking', 'Raider', { build: 'broad', head: 'wide', eyes: 'fierce', brows: 'thick', facialHair: 'long', hair: 'braid', top: 'tunic', bottom: 'kilt', shoes: 'boots', gloves: 'bracers', headwear: 'viking' },
    { skin: 1, hair: 5, eyes: 4, top: 21, trim: 22, bottom: 12, shoes: 21, accessory: 21 }),
  P('athlete', 'Athlete', { build: 'athletic', eyes: 'round', mouth: 'grin', hair: 'buzz', top: 'jersey', bottom: 'shorts', shoes: 'hightops', gloves: 'none', headwear: 'headband' },
    { skin: 7, hair: 0, top: 5, trim: 0, bottom: 5, shoes: 0, accessory: 0 }),
  P('detective', 'Detective', { build: 'average', head: 'oval', eyes: 'sleepy', brows: 'raised', facialHair: 'moustache', hair: 'slick', top: 'trench', neck: 'tie', bottom: 'slacks', shoes: 'dress', headwear: 'none' },
    { skin: 2, hair: 1, top: 22, trim: 0, bottom: 3, shoes: 4, accessory: 6 }),
  P('royal', 'Royal', { build: 'average', head: 'heart', eyes: 'lashes', brows: 'arched', mouth: 'smile', hair: 'wavy', marks: 'beautymark', top: 'suit', neck: 'medal', bottom: 'slacks', shoes: 'dress', headwear: 'crown' },
    { skin: 0, hair: 7, eyes: 4, top: 17, trim: 0, bottom: 16, shoes: 4, accessory: 5 }),
  P('skater', 'Skater', { build: 'slim', eyes: 'round', mouth: 'tongue', hair: 'messy', marks: 'freckles', top: 'hoodie', bottom: 'cargo', shoes: 'sneakers', headwear: 'backcap' },
    { skin: 3, hair: 5, top: 10, trim: 0, bottom: 21, shoes: 3, accessory: 5 }),
  P('elf', 'Ranger', { build: 'slim', head: 'heart', ears: 'pointed', eyes: 'anime', brows: 'thin', hair: 'long', top: 'tunic', bottom: 'leggings', shoes: 'boots', gloves: 'bracers' },
    { skin: 1, hair: 8, eyes: 3, top: 11, trim: 21, bottom: 12, shoes: 21, accessory: 21 }),
  P('demon', 'Hellion', { build: 'athletic', ears: 'pointed', eyes: 'glow', brows: 'angry', mouth: 'fangs', hair: 'spiky', marks: 'stripes', top: 'leather', bottom: 'jeans', shoes: 'combat', headwear: 'horns' },
    { skin: 17, hair: 0, eyes: 9, top: 4, trim: 5, bottom: 4, shoes: 4, accessory: 6 }),
  P('robot', 'Automaton', { build: 'broad', head: 'block', ears: 'none', eyes: 'glow', brows: 'none', nose: 'none', mouth: 'tight', hair: 'bald', top: 'armor', bottom: 'greaves', shoes: 'sabatons', gloves: 'gauntlets', eyewear: 'visor', headwear: 'antenna' },
    { skin: 16, eyes: 9, top: 2, trim: 1, bottom: 2, shoes: 2, accessory: 13 }),
  P('classic', 'Blocky', { head: 'block', eyes: 'dot', brows: 'none', mouth: 'smile', hair: 'bald', top: 'tee', bottom: 'jeans', shoes: 'barefoot' },
    { skin: 12, top: 15, bottom: 10, shoes: 10 }),
  P('student', 'Scholar', { build: 'slim', eyes: 'round', brows: 'worried', hair: 'bob', eyewear: 'round', top: 'sweater', bottom: 'skirt', shoes: 'dress', neck: 'none' },
    { skin: 2, hair: 3, top: 20, trim: 0, bottom: 16, shoes: 21, accessory: 4 }),
];
