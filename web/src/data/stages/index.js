// Stages. Coordinates in studs. Origin is the centre of the main platform's top surface,
// +X right, +Y up. A fighter is 5.2 studs tall and runs at ~23 studs/second, so 23 studs is one
// second of ground travel — that is the unit to think in when sizing a gap or a platform.
//
// LAYOUT VOCABULARY
//   main            the primary solid island. Walls on both sides, ledges on both corners.
//   platforms[]     everything else. `solid: true` makes another walled island with its own
//                   ledges; otherwise it is a drop-through shelf.
//   ledges: false   a solid you fight on top of but cannot hang from (blocks, pillars).
//   moving          { x: {from,to,period,phase}, y: {...} } — either axis, or both.
//   sinking         a shelf that sags while stood on and dumps you after two seconds.
//
// Each stage below is a different ARCHETYPE, because six variations of one shape is one map.
//   Foundry Floor  neutral tournament layout, symmetric        (ranked)
//   The Span       near-flat, one high shelf, long runway      (ranked)
//   Smeltworks     split floor with a real gap in the middle
//   Rooftops       vertical: stacked solids, tall blast ceiling
//   Saltflat       asymmetric, with a solid block to fight around
//   Undertow       everything moves, plus a tide that closes the floor

export const STAGES = [
  {
    // The neutral one. Every fighting game needs a stage with no opinion: symmetric, no hazard,
    // three shelves in the standard triangle. If a matchup is decided here it was decided by play.
    id: 'FoundryFloor', name: 'Foundry Floor', theme: 'Iron works', ranked: true,
    archetype: 'Neutral',
    blurb: 'Symmetric, hazardless, the standard triangle. The stage that argues with nobody.',
    main: { x1: -36, x2: 36, y: 0, thickness: 6 },
    platforms: [
      { id: 'left', x: -21, y: 14, w: 16, soft: true },
      { id: 'right', x: 21, y: 14, w: 16, soft: true },
      { id: 'top', x: 0, y: 27, w: 14, soft: true },
    ],
    blast: { left: -96, right: 96, top: 85, bottom: -50 },
    spawns: [-24, 24, -10, 10, -30, 30, -4, 4],
    // Ranked, so the one environmental element is a piece of LAYOUT rather than an event: two
    // fixed columns of rising heat off the pour below, sitting just OUTSIDE each ledge. Neutral is
    // untouched; what changes is the edgeguard. Always there, always in the same place, never
    // damages, and it only slows a fall — it can never push you upward past where you already were.
    hazards: [
      { type: 'emberdrift', positions: [-41, 41], width: 9, from: -34, to: 10, lift: 96 },
    ],
    // Ash, not embers: the hazard on this stage is rising orange sparks, so the ambient has to
    // fall and has to be grey. See the note on `ash` in render2d/ambient2d.js.
    ambient: { kind: 'ash', rate: 0.55, tint: 'rgba(196,200,208,0.9)', drift: 2.4 },
    palette: { ground: '#3E4450', groundTop: '#8A94A6', platform: '#6E7788', backdrop: '#8E9BB0', accent: '#E8862E', sky: '#C9D3E0',
      skyStops: [[0, '#38414F'], [0.45, '#6C788C'], [0.8, '#A9B5C6'], [1, '#C6D0DC']],
      glows: [{ y: 120, r: 150, color: 'rgba(255,180,90,0.30)' }] },
    music: { bpm: 150, key: 'C', name: 'Cold Iron' },
  },

  {
    // The long one. Almost no platform to run to, so neutral is decided on the ground and
    // recoveries have to travel. The single high shelf keeps it from being a bare line.
    id: 'TheSpan', name: 'The Span', theme: 'Suspension bridge', ranked: true,
    archetype: 'Flat / horizontal',
    blurb: 'No platforms at all, a high roof and close walls. Every kill here goes out sideways.',
    // Deliberately bare. With a shelf it was Foundry Floor with a longer floor - same recovery
    // envelope, same side room, same problem. Stripping the platforms makes it a genuinely
    // different question: there is no vertical escape, no platform to reset on, and the ceiling at
    // 94 is far enough that up-angled signatures stop being kill moves. Side room drops to 52 so
    // the horizontal blast zone does all the work.
    main: { x1: -46, x2: 46, y: 0, thickness: 8 },
    platforms: [],
    blast: { left: -98, right: 98, top: 94, bottom: -48 },
    spawns: [-30, 30, -12, 12, -40, 40, -4, 4],
    // Ranked, so this never touches grounded play. A bridge in the open gets wind; the wind
    // changes every recovery and every edgeguard and nothing else. Strictly alternating direction
    // on a 16-second cycle with a 2-second warning, so it is learnable rather than random.
    hazards: [
      // push 18, measured: a full gust displaces an airborne fighter 9.5 studs over its 2 seconds,
      // and it displaces them 9.5 studs whether or not they are holding the stick against it —
      // which only became true once wind was carried in its own velocity instead of being folded
      // into vx, where air drift out-accelerated it three to one and erased it. At 46 the same
      // gust moved a recovery 17.5 studs, which is a coin flip rather than a read.
      { type: 'crosswind', period: 16, warn: 2, gustSeconds: 3.4, push: 18 },
    ],
    ambient: { kind: 'gulls', rate: 0.12, tint: 'rgba(255,255,255,0.5)', streaks: true },
    palette: { ground: '#4A4E58', groundTop: '#9AA6B4', platform: '#7C8695', backdrop: '#9FB4C4', accent: '#D9534F', sky: '#D6E4EE',
      skyStops: [[0, '#5C7A96'], [0.42, '#93AFC4'], [0.78, '#C8DCE8'], [1, '#E2EDF3']],
      glows: [{ y: 140, r: 170, color: 'rgba(255,240,220,0.45)' }] },
    music: { bpm: 145, key: 'F', name: 'Long Drop' },
  },

  {
    // Split floor. The 20-stud gap in the middle is the whole stage: you cannot walk across it,
    // so every crossing is a commitment, and a light fighter knocked into it is in real trouble.
    // Vents punish camping on either island.
    id: 'Smeltworks', name: 'Smeltworks', theme: 'Smelting floor', ranked: false,
    archetype: 'Split floor',
    blurb: 'Two islands and a hole between them. Crossing is a decision, not a walk.',
    // `ledges: 'outer'` on both islands: only the OUTWARD edges are grabbable. With ledges on the
    // inner edges too, the pit was the safest place on the stage - two ledges a jump apart with a
    // shelf overhead. Now falling in means crossing back, not hanging on.
    main: { x1: -34, x2: -11, y: 0, thickness: 7, ledges: 'outer' },
    platforms: [
      // x 20, not 22.5: the pit is sized as a PROPORTION of the worst jump in the roster, not as
      // an absolute. Adding the battle axe — heaviest body, lowest jump — took the worst-case
      // horizontal jump from 24.7 studs to 21.0, and a 20-stud pit that was 81% of a jump became
      // 95% of one, i.e. uncrossable for the weapon most likely to be knocked into it.
      { id: 'east', x: 20, y: 0, w: 27, solid: true, thickness: 7, ledges: 'outer' },
      // the shelf over the gap is the only free crossing, and it sinks if you loiter
      { id: 'gantry', x: -1, y: 15, w: 9, soft: true, sinking: true },
      { id: 'westShelf', x: -27, y: 13, w: 12, soft: true },
      { id: 'eastShelf', x: 26, y: 17, w: 12, soft: true },
    ],
    blast: { left: -90, right: 90, top: 88, bottom: -46 },
    // Every spawn clears both the pit (-11..9) and the vent footprints at +/-20, which reach
    // 15.4 to 24.6 out once a fighter's 1.1 radius is added to the 7-stud vent mouth.
    spawns: [-30, 28, -14, 14, -26, 27, -32, 32],
    // launch 62 was a 12.8-stud pop with no damage and no stun: a free extra jump, not a punish.
    hazards: [
      // A sustained column, not a pop. `lift` is an acceleration held for the whole eruption, so
      // standing on a grate peels you off it and falling through one catches you: the hazard and
      // the recovery route are the same object. `reach` gives the column a top.
      { type: 'vents', period: 9, warn: 46, erupt: 34, lift: 232, reach: 26, width: 7, positions: [-20, 20] },
      // And the gantry leaks. Small, constant, and only over the crossing — where the vents make
      // the islands unsafe, the slag makes the free route cost something.
      { type: 'slagfall', x: -1, spread: 9, from: 14, every: 1.1, damage: 4, launch: 22 },
    ],
    // shimmer 1.4: at 0.55 the wobble came out at 1.1 units of luminance, which is nothing.
    ambient: { kind: 'heat', rate: 0.9, tint: 'rgba(255,140,60,0.8)', shimmer: 1.4, glow: true },
    palette: { ground: '#3A2E2A', groundTop: '#8C5A3C', platform: '#6E4A38', backdrop: '#7A5A52', accent: '#FF7A3C', sky: '#E0A878',
      skyStops: [[0, '#2E2320'], [0.38, '#6B443A'], [0.74, '#B87452'], [1, '#E8A870']],
      glows: [{ y: 40, r: 190, color: 'rgba(255,140,60,0.40)' }] },
    music: { bpm: 158, key: 'D', name: 'Pour' },
  },

  {
    // Vertical. Two solid towers of different heights turn this into a stage about elevation:
    // the high ground is real ground you can be knocked off, and the blast ceiling is low enough
    // that an up-angled signature actually kills.
    id: 'Rooftops', name: 'Rooftops', theme: 'City rooftops', ranked: false,
    archetype: 'Vertical / tiered',
    blurb: 'Two towers at different heights and a low ceiling. Fights climb, and the top of the map kills.',
    main: { x1: -27.5, x2: 29, y: 0, thickness: 6 },
    // The towers are DROP-THROUGH tiers, not solid blocks. As solids they were walls standing
    // between the stage and the side blast zone, and a kill-percent launch only apexes about five
    // studs, so nothing could ever clear a 21-stud tower: every sideways launch stopped dead at
    // x=27.9 and the first horizontal KO came at 170%. Verticality in a platform fighter has to
    // come from tiers you can be knocked THROUGH, not from walls that absorb knockback.
    platforms: [
      { id: 'westTier', x: -17, y: 11, w: 15, soft: true, thickness: 2.5 },
      { id: 'eastTier', x: 15, y: 19, w: 14, soft: true, thickness: 2.5 },
      { id: 'aerial', x: -5, y: 27, w: 12, soft: true },
      // sits just off the east tower's shoulder, so the tower is the step up to it
      { id: 'crane', x: -22, y: 33, w: 11, soft: true },
    ],
    // Ceiling was 66: up-signatures killed at 65% here against 100% everywhere else, and bots died
    // off the top four times as often. 78 keeps it the tightest roof in the roster without making
    // the showcase move of two weapons a 65% finisher.
    blast: { left: -92, right: 92, top: 78, bottom: -46 },
    // All four primary spawns sit on the main floor at the same height. Slot 4 was x=35 - inside
    // the east tower's body with no platform at or below the respawn height of 14, so a fourth
    // player fell straight past the stage and lost a stock in three seconds. Slot 3 at x=-34 landed
    // on the west tier instead of the floor, starting that player 13 studs above everyone else.
    spawns: [-16, 16, -24, 24, -6, 6, -20, 20],
    hazards: [
      // The jet sweeps for 3.4 seconds and leaves the roof wet for ten. Long after the water has
      // gone the fight is still being shaped by where it went, which is what turns a shove into a
      // stage feature. It alternates direction so neither side is the safe side.
      // push 18, not 54: wind now composes with air control instead of being fought by it, so
      // every horizontal force in the game needed roughly a third of its old number.
      { type: 'sprinkler', period: 15, tick: 75, sweepSeconds: 3.4, push: 40, radius: 4.2,
        height: 30, wetSeconds: 10, slip: 0.62 },
      // Electricity between the masts, high up. It exists so the top of a vertical stage is not
      // simply the safest place to stand.
      // y=44, not 40. The crane tier tops out at 33, and a fighter standing on it reaches 38.2 —
      // inside a 2.2-thick band centred on 40. At 44 the band starts at 41.8 and the crane is
      // clear by three and a half studs, so standing on the highest platform is never a hit.
      { type: 'antennaarc', period: 13, warn: 54, arc: 22, x1: -21, x2: 16, y: 44, thickness: 2.2,
        damage: 6, launch: 30 },
    ],
    ambient: { kind: 'rain', rate: 1.4, tint: 'rgba(180,215,240,0.55)', wind: -7 },
    palette: { ground: '#2E3440', groundTop: '#5A6478', platform: '#4A5464', backdrop: '#5E6E86', accent: '#7DE8FF', sky: '#B8C8DC',
      skyStops: [[0, '#1E2430'], [0.4, '#3E4C62'], [0.76, '#7E90A8'], [1, '#B6C6D8']],
      glows: [{ y: 110, r: 150, color: 'rgba(125,232,255,0.28)' }] },
    music: { bpm: 152, key: 'A', name: 'Nine Floors Up' },
  },

  {
    // Asymmetric on purpose. The floor is longer on the left, and the right side has a solid block
    // you cannot hang from — so the two ledges play completely differently and picking a side is a
    // real decision. The block also gives the only wall in the game to tech off.
    id: 'Saltflat', name: 'Saltflat', theme: 'Dry lake', ranked: false,
    archetype: 'Asymmetric',
    blurb: 'Long on the left, blocked on the right. The two sides of this stage are not the same game.',
    main: { x1: -48, x2: 26, y: 0, thickness: 6 },
    platforms: [
      // Raised from 11 to 17 so the right side gains real high ground in exchange for having no
      // grabbable ledge. Previously the right was strictly worse with no compensating upside.
      { id: 'mesa', x: 38.5, y: 17, w: 19, solid: true, thickness: 5, ledges: false },
      // Waist-high cover: the only geometry in the roster that stops a shot at fighting height.
      // Low enough (top 4) that a kill-percent launch clears it, high enough to break a sightline.
      { id: 'bunker', x: -16, y: 4, w: 8, solid: true, thickness: 4, ledges: false },
      { id: 'shade', x: -34, y: 14, w: 13, soft: true },
      { id: 'perch', x: -8, y: 20, w: 11, soft: true },
    ],
    blast: { left: -110, right: 100, top: 80, bottom: -52 },
    spawns: [-34, 18, -6, 6, -42, 24, -24, 2],
    // crossSeconds 4.2 over ~100 studs was 23.3 studs/s - exactly run speed, so running was never
    // an escape. 6.5 seconds brings it to 15 studs/s: you can outrun it, or jump it, or eat it.
    hazards: [
      // It CARRIES. Step inside and you are drawn to the core, lifted, and spun up the funnel
      // until it throws you out of the top. Almost no damage; you keep air control the whole way,
      // so a good player rides it across the stage and a panicking one gets thrown over the pit.
      // It reverses direction every pass, and warns for two seconds before it arrives.
      // eastStop 8 puts the funnel's measured east reach at x=25 and the sandfall's west reach at
      // x=25 — adjacent, not overlapping. The funnel gives up the last seven studs of the island
      // to the sandfall, which is the price of the two being readable as separate threats.
      //
      // eastStop/westStop keep the funnel's turnaround ON the island at both ends. eastStop was 9,
      // which put the east turnaround at x=22 — four studs INSIDE the right ledge — and a passive
      // rider was being set down in the 3-stud gap between the floor (ends 26) and the mesa
      // (starts 29). A hazard that deposits a 0% fighter who never touched the stick into a pit is
      // the one thing "pressure, never an execution" is supposed to rule out.
      { type: 'dustdevil', period: 19, warn: 2, crossSeconds: 6.5, radius: 5.5, height: 20, eastStop: 8, westStop: 5,
        pull: 44, lift: 225, drag: 26, throwAfter: 46, damage: 4, launch: 24, angle: 80 },
      // Sand pours off the lip of the mesa. It does not hurt; it makes the space under the mesa
      // a bad place to be, and that is exactly the space an edgeguarder wants.
      { type: 'sandfall', x: 29.5, width: 7, from: 17, to: -30, period: 11, warn: 48,
        pourSeconds: 3.2, push: 62 },
    ],
    // The sand ambient measured 2.7 units of luminance against this stage's own sky — on the one
    // stage that most needs visible blowing sand. Darker and denser.
    ambient: { kind: 'sand', rate: 1.1, tint: 'rgba(150,124,86,0.75)', wind: 11 },
    palette: { ground: '#7A6448', groundTop: '#C9A87A', platform: '#A88A62', backdrop: '#D8C0A0', accent: '#E8B04A', sky: '#F0DCB8',
      skyStops: [[0, '#8FA8C0'], [0.4, '#CFC0A8'], [0.76, '#EEDCBC'], [1, '#F6E8CE']],
      glows: [{ y: 130, r: 180, color: 'rgba(255,240,200,0.50)' }] },
    music: { bpm: 138, key: 'E', name: 'Nothing For Miles' },
  },

  {
    // Everything moves. Two drifting shelves and a solid raft that slides across the gap, plus a
    // tide that periodically swallows the outer floor — so the safe ground is different every
    // twenty seconds and positioning has to be re-solved constantly.
    id: 'Undertow', name: 'Undertow', theme: 'Flooded dock', ranked: false,
    archetype: 'Moving / dynamic',
    blurb: 'Drifting platforms over a rising tide. The safe ground moves, and sometimes there is none.',
    main: { x1: -20, x2: 20, y: 0, thickness: 6 },
    platforms: [
      // A drop-through shelf, not a solid. As a solid its body occupied y 8..12 - exactly where a
      // 40-degree launch passes - and it roamed the full width of the stage, so a side signature
      // from centre KO'd 5 times in 91 samples. Knockback now passes straight through it.
      { id: 'raft', x: 0, y: 12, w: 14, soft: true, thickness: 2,
        moving: { x: { from: -30, to: 30, period: 11, phase: 0 } } },
      { id: 'buoyW', x: -30, y: 8, w: 11, soft: true,
        moving: { y: { from: 5, to: 13, period: 5.5, phase: 0.15 } } },
      { id: 'buoyE', x: 30, y: 10, w: 11, soft: true,
        moving: { y: { from: 7, to: 15, period: 6.5, phase: 0.62 } } },
      { id: 'gull', x: 0, y: 27, w: 10, soft: true },
    ],
    blast: { left: -92, right: 92, top: 84, bottom: -44 },
    // Slots 7 and 8 were both x=0 - two fighters at the identical point - and 3/4 started on the
    // moving raft while 1/2 started on the floor.
    spawns: [-14, 14, -7, 7, -18, 18, -11, 11],
    hazards: [
      // Water is a second set of physics rather than a hazard: slow, buoyant, and it DAMPS
      // knockback. At 140% the water is the safest place on the stage and also the place you
      // cannot fight from. Choosing when to be in it is the whole layout.
      { type: 'tide', period: 34, rise: 3, hold: 10, fall: 3, low: -9, high: 8, edge: 21,
        swell: 0.9, buoyancy: 205, drift: 5, damp: 0.55, depth: 12 },
      // And once per high tide, a crest rolls the length of the stage. It is the reason high
      // tide is tense rather than just wet.
      // 2.4s of warning, not 1.6: it fires while the tide is also mid-phase, so a player is
      // already reading one thing when it arrives and needs longer to process a second.
      // `at: 23.5` pins the crossing INSIDE the tide's hold (t=21..31). Hanging it off the end of
      // the period put it at 30.4, so the crest entered as the tide was already falling and spent
      // 83% of its travel below the island's bottom edge, hidden behind the stage — measured at
      // 108 of 648 active frames during high tide. It is the high-tide payoff hazard; it has to
      // happen at high tide.
      { type: 'roguewave', period: 34, at: 23.5, warn: 2.4, crossSeconds: 3.6, width: 13, crest: 7,
        // push 60: measured, the crest carries a fighter 9.7 studs across the 48 frames it is
        // actually on top of them. At 34 it was 4.6 — a passing wave you could ignore.
        push: 60, lift: 40 },
    ],
    // Spray sits over dark water, so it has to brighten rather than darken to be seen.
    ambient: { kind: 'spray', rate: 0.8, tint: 'rgba(240,252,255,0.9)', wind: 4 },
    palette: { ground: '#33454E', groundTop: '#4FA0A8', platform: '#4A6470', backdrop: '#8FC0CE', accent: '#59D9F2', sky: '#D2ECF2',
      skyStops: [[0, '#33566E'], [0.4, '#6E9CB4'], [0.76, '#B4DAE6'], [1, '#D8EEF4']],
      glows: [{ y: 150, r: 160, color: 'rgba(200,244,255,0.45)' }] },
    music: { bpm: 132, key: 'Bb', name: 'Ebb and Flow' },
  },
];

export const STAGE_BY_ID = Object.fromEntries(STAGES.map((s) => [s.id, s]));
