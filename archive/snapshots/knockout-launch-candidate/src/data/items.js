// ITEMS
//
// The old set - Seed Bomb, Trowel, Watering Can - were Sprout Brawl leftovers: gardening tools in
// a game that is now about swords, axes, pikes and blasters. They were also, measurably, inert. In
// eight four-player bot matches thirty-eight items spawned, ZERO were picked up and thirty-four
// despawned untouched, because nothing in ai.js ever reached for one. An item nobody picks up is a
// prop, and the Watering Can did no damage even when it was used.
//
// So this is a new set, and the rule behind it is that each item owns a different VERB. Another
// thing that throws for damage is not another item, it is the same item with a new sprite:
//
//   BlastKeg     THROW   - and anyone can set it off, including the person who threw it
//   RivetGun     SHOOT   - eight bolts of chip and hitstun, no kill power at all
//   Bulwark      HOLD    - a shield you carry, which is the only defensive item here
//   SpringPlate  PLACE   - changes the stage rather than hitting anybody
//   Lodestone    APPLY   - does no damage and is the most lethal thing on the list
//
// Damage and knockback numbers are MEASURED against the kill bands in test/items.test.mjs, not
// guessed: the keg kills around the percent a heavy signature does, and the rivet gun cannot kill
// at all no matter how long you hold someone in it.

export const ITEMS = {
  // The keg is a commitment. It arcs, it has a long fuse, and it is live the whole time it is on
  // screen - a stray sword swing detonates it, so throwing one into a scramble is as likely to
  // launch you as them. That is the whole item: a big threat you do not fully control.
  BlastKeg: {
    id: 'BlastKeg', name: 'Blast Keg', kind: 'throw', uses: 1, colour: '#8A5A2B', accent: '#E8862E',
    blurb: 'Arcs, fuses, and goes off if anyone hits it.',
    throw: { vx: 30, vy: 30, gravity: 115, fuse: 110, size: [1.6, 1.8] },
    explode: { damage: 16, base: 30, growth: 3.6, angle: 62, radius: 5.5 },
    volatile: true,                    // a hit from ANY fighter sets it off
  },

  // Pure pressure. Three percent a bolt with more hitstun than the damage deserves, so it is for
  // interrupting an approach and for racking up percent someone else converts - never for the kill.
  RivetGun: {
    id: 'RivetGun', name: 'Rivet Gun', kind: 'shoot', uses: 8, colour: '#7C8695', accent: '#FFD37A',
    blurb: 'Eight bolts. Chip and interrupt, no kill.',
    shot: { speed: 52, lifetime: 26, damage: 3, base: 6, growth: 0.35, angle: 20, size: [1.0, 0.4], cooldown: 7, extraHitstun: 6 },
    thrown: { speed: 42, lifetime: 30, damage: 7, base: 15, growth: 1.4, angle: 45, size: [1.2, 0.8] },
  },

  // The only item that answers an attack rather than making one. Carrying it costs you your run
  // speed and your weapon; what you get is a wall in front of you that eats most of a hit. It has
  // hit points, so it is a resource, not a state you can sit in.
  Bulwark: {
    id: 'Bulwark', name: 'Bulwark', kind: 'hold', uses: 1, colour: '#5A6472', accent: '#EDF1F6',
    blurb: 'Carry it and the front is covered. Slows you down.',
    guard: { hp: 46, damageMul: 0.35, launchMul: 0.4, speedMul: 0.72, arc: 0.55 },
    bash: { label: 'Shield Bash', startup: 9, active: 3, recovery: 16, damage: 6, base: 16, growth: 1.4, angle: 30, shieldDamageMul: 2.6,
      hitboxes: [{ frames: [10, 12], offset: [2.2, 2.6], size: [3.4, 3.6] }] },
    thrown: { speed: 34, lifetime: 30, damage: 11, base: 22, growth: 2.2, angle: 40, size: [1.8, 2.2] },
  },

  // Put it on the floor and it is part of the stage. It does not damage anybody, which is exactly
  // why it is interesting: it is a recovery you can give yourself, a ledge trap you can set, and
  // something an opponent can use against you the moment you stop paying attention to it.
  SpringPlate: {
    id: 'SpringPlate', name: 'Spring Plate', kind: 'place', uses: 1, colour: '#3E8A2E', accent: '#A8FF7A',
    blurb: 'Anyone who lands on it goes straight up.',
    plate: { vy: 88, life: 12 * 60, cooldown: 24, size: [3.4, 0.9] },
    thrown: { speed: 30, lifetime: 26, damage: 6, base: 13, growth: 1.2, angle: 55, size: [1.8, 0.7] },
  },

  // Zero damage, and the most lethal item in the set. It sticks to whoever it hits and makes them
  // fall like the axe does - the recovery they know stops reaching. A platform fighter takes most
  // of its stocks off the stage, so the item that decides who gets back is the strong one.
  Lodestone: {
    id: 'Lodestone', name: 'Lodestone', kind: 'throw', uses: 1, colour: '#2B3038', accent: '#9AA6FF',
    blurb: 'Sticks. They fall like a stone for five seconds.',
    throw: { vx: 40, vy: 12, gravity: 55, fuse: 70, size: [1.2, 1.2] },
    stick: { frames: 300, fallMul: 1.9, airMul: 0.45, jumpMul: 0.8, damage: 2 },
  },
};

export const ITEM_LIST = Object.values(ITEMS);
export const ITEM_BY_ID = ITEMS;
