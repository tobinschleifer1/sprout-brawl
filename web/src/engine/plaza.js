// Walking the lobby (data/plaza.js): beat-'em-up movement on a floor with depth.
//
// Deliberately NOT the fighter engine. The old side-scrolling hub drove a real Fighter so the lobby
// moved like a fight, but a floor you walk into and out of has no platforms, ledges or gravity
// wells to borrow from the match - and a lobby that shares nothing with combat can never let a
// press of the attack button do anything. What is left is small, deterministic arithmetic, ported
// line for line to roblox/src/shared/Plaza.luau and replayed against it (tests/plaza-parity.luau).
//
// A walker is a point. Floors are inset from the edges they draw, so a point inside the floor is a
// character standing on it.

import { WALK } from '../data/plaza.js';

const inside = (r, x, z) => x >= r.x1 && x <= r.x2 && z >= r.z1 && z <= r.z2;

// Where a walker may stand: on some floor, in no footprint. Footprints are open on their edges, so
// a walker pressed against a cabinet is standing beside it, not in it.
export function walkable(scene, x, z) {
  if (!scene.floor.some((r) => inside(r, x, z))) return false;
  return !scene.blocks.some((r) => x > r.x1 && x < r.x2 && z > r.z1 && z < r.z2);
}

export class Plaza {
  constructor(scene) {
    this.p = { x: 0, z: 0, y: 0, vx: 0, vz: 0, vy: 0, facing: 1, state: 'idle', sf: 0 };
    this.setScene(scene);
  }

  // A new scene puts you at its spawn (or `at`), standing still, facing the way you were.
  setScene(scene, at) {
    this.data = scene;
    const s = at || scene.spawn;
    const p = this.p;
    p.x = s.x; p.z = s.z; p.y = 0; p.vx = 0; p.vz = 0; p.vy = 0; p.state = 'idle'; p.sf = 0;
  }

  warp(id) {
    const w = this.data.warps.find((v) => v.id === id);
    if (w) this.setScene(this.data, w);
    return !!w;
  }

  // One 60Hz frame. `input.x` is along the street, `input.y` into the depth (up is further away),
  // `input.jump` a hop. Nothing else in the frame is read.
  step(input) {
    const p = this.p, W = WALK, dt = 1 / W.hz;
    const ax = Math.max(-1, Math.min(1, input.x || 0));
    const az = Math.max(-1, Math.min(1, input.y || 0));
    p.vx += (ax * W.speedX - p.vx) * W.accel;
    p.vz += (az * W.speedZ - p.vz) * W.accel;
    if (Math.abs(p.vx) < W.stop) p.vx = 0;
    if (Math.abs(p.vz) < W.stop) p.vz = 0;
    // Per axis, so a walker running diagonally into a wall slides along it.
    const nx = p.x + p.vx * dt;
    if (walkable(this.data, nx, p.z)) p.x = nx; else p.vx = 0;
    const nz = p.z + p.vz * dt;
    if (walkable(this.data, p.x, nz)) p.z = nz; else p.vz = 0;
    if (input.jump && p.y === 0 && p.vy === 0) p.vy = W.jump;
    if (p.y > 0 || p.vy > 0) {
      p.vy -= W.gravity * dt;
      p.y += p.vy * dt;
      if (p.y <= 0) { p.y = 0; p.vy = 0; }
    }
    if (ax !== 0) p.facing = ax > 0 ? 1 : -1;
    const state = p.y > 0 ? 'air' : (Math.abs(p.vx) > 0.5 || Math.abs(p.vz) > 0.5 ? 'run' : 'idle');
    p.sf = state === p.state ? p.sf + 1 : 0;
    p.state = state;
  }

  // The station you would use now: the nearest whose reach box you stand in, not while hopping.
  nearest() {
    const p = this.p;
    if (p.y > 0) return null;
    let best = null, bestD = Infinity;
    for (const s of this.data.stations) {
      if (Math.abs(p.x - s.x) > s.rx || Math.abs(p.z - s.z) > s.rz) continue;
      const d = (p.x - s.x) * (p.x - s.x) + (p.z - s.z) * (p.z - s.z);
      if (d < bestD) { best = s; bestD = d; }
    }
    return best;
  }

  // Which named district you are in, for the location line and the member list.
  district() {
    const x = this.p.x;
    return this.data.districts.find((d) => x >= d.x1 && x <= d.x2) || null;
  }
}
