export const ITEMS = {
  SeedBomb: {
    id: 'SeedBomb', name: 'Seed Bomb', kind: 'throw', uses: 1, color: '#6B8E23',
    throw: { vx: 34, vy: 26, gravity: 110, fuse: 120, size: [1.4, 1.4] },
    explode: { damage: 12, base: 24, growth: 3.0, angle: 60, radius: 4 },
  },
  Trowel: {
    id: 'Trowel', name: 'Trowel', kind: 'melee', uses: 4, color: '#B0B8C0',
    swing: { label: 'Trowel Swing', startup: 8, active: 4, recovery: 14, damage: 9, base: 18, growth: 2.2, angle: 40, hitboxes: [{ frames: [9, 12], offset: [2.6, 2.6], size: [4.0, 2.6] }] },
    thrown: { speed: 40, lifetime: 30, damage: 10, base: 18, growth: 2.0, angle: 45, size: [1.6, 0.8] },
  },
  WateringCan: {
    id: 'WateringCan', name: 'Watering Can', kind: 'spray', uses: 180, color: '#3F8A2E',
    spray: { push: 10, range: 9, height: 4 },
    thrown: { speed: 30, lifetime: 30, damage: 4, base: 10, growth: 1.0, angle: 50, size: [1.6, 1.4] },
  },
};
export const ITEM_LIST = Object.values(ITEMS);
