// Animation channels: the pose of a fighter for one frame, as plain numbers.
//
// Extracted from render/rigs.js so the 2D renderer can drive the same animation without pulling in
// Three.js. Nothing in here touches a renderer - it reads fighter state and returns a channel bag
// that a painter interprets however it likes.
//
//   lean      body tilt, radians, positive = leaning into the attack
//   bob/yOff  vertical offsets in studs
//   sx/sy     squash and stretch
//   armL/armR shoulder rotation, z = swing in the side-on plane, x = swing across it
//   legL/legR hip rotation
//   spinY     full-body spin (used by neutral air and recoveries)
//   tint      an emissive flash colour, or null

const PI = Math.PI;

function attackChannels(ch, f) {
  const m = f.move; if (!m) return;
  const st = f.startupEff, act = m.active, rec = m.recovery, mf = f.mf;
  const inStartup = mf <= st, inActive = mf > st && mf <= st + act;
  const k = inStartup ? mf / Math.max(1, st) : inActive ? 1 : Math.max(0, 1 - (mf - st - act) / Math.max(1, rec));
  const id = m.id || '';
  const cat = id.startsWith('LightNeutral') ? 'jab' : id.startsWith('LightSide') || id === 'ItemSwing' ? 'side' : id === 'LightDown' ? 'down' : id === 'LightUp' ? 'sigdown' : id === 'AirNeutral' ? 'nair' : id === 'AirForward' ? 'fair' : id === 'AirDown' ? 'dair' : id === 'AirUp' ? 'nair' : id === 'SigSide' ? 'sigside' : id === 'SigDown' ? 'sigdown' : id === 'SigNeutral' ? 'sigside' : id === 'CounterBurst' ? 'burst' : id === 'ItemSpray' ? 'spray' : 'jab';
  const F = PI / 2; // arm forward
  if (m.kind === 'counter') { ch.armL.z = 0.9; ch.armR.z = -0.9; ch.sy = 0.92; ch.sx = 1.08; ch.tint = '#3E4F2E'; return; }
  switch (cat) {
    case 'jab': ch.armR.z = inStartup ? -0.4 * k : inActive ? F : F * k; ch.lean = inActive ? 0.15 : 0.05 * k; break;
    case 'side': ch.armR.z = inStartup ? -0.9 * k : inActive ? F + 0.2 : F * k; ch.armL.z = inActive ? -0.6 : 0.2; ch.lean = inStartup ? -0.25 * k : 0.35 * k; ch.sx = inActive ? 1.12 : 1; break;
    case 'down': ch.sy = 0.7; ch.sx = 1.2; ch.lean = 0.3; ch.legR = inActive ? 1.3 : 0.4 * k; ch.armR.z = inActive ? 0.5 : 0; ch.armL.z = 0.6; break;
    case 'nair': ch.spinY = (mf / (st + act + rec)) * PI * 4; ch.armL.z = 1.4; ch.armR.z = -1.4; ch.legL = 0.5; ch.legR = -0.5; break;
    case 'fair': ch.armR.z = inStartup ? -1.0 * k : inActive ? F : F * k; ch.lean = 0.4 * k; ch.legL = -0.5; ch.legR = -0.7; break;
    case 'dair': if (inStartup) { ch.armL.z = 2.8 * k; ch.armR.z = -2.8 * k; ch.sy = 0.9; } else { ch.armL.z = 0.2; ch.armR.z = -0.2; ch.sy = 1.15; ch.sx = 0.9; ch.head = 0.4; } break;
    case 'sigside':
      if (inStartup) { ch.lean = -0.45 * k; ch.armR.z = -1.4 * k; ch.sx = 1 - 0.1 * k; ch.sy = 1 + 0.1 * k; ch.tint = k > 0.7 ? '#FFFFFF' : null; }
      else if (inActive) { ch.lean = 0.5; ch.armR.z = F + 0.3; ch.armL.z = -0.8; ch.sx = 1.2; ch.sy = 0.95; }
      else { ch.lean = 0.5 * k; ch.armR.z = (F + 0.3) * k; ch.sx = 1 + 0.2 * k; }
      break;
    case 'sigdown':
      if (inStartup) { ch.sy = 1 - 0.3 * k; ch.sx = 1 + 0.2 * k; ch.armL.z = 0.6; ch.armR.z = -0.6; ch.tint = k > 0.7 ? '#FFFFFF' : null; }
      else if (inActive) { ch.sy = 1.25; ch.sx = 1.15; ch.armL.z = 3.0; ch.armR.z = -3.0; ch.bob = 0.3; }
      else { ch.sy = 1 + 0.25 * k; ch.sx = 1 + 0.15 * k; ch.armL.z = 3.0 * k; ch.armR.z = -3.0 * k; }
      break;
    case 'burst': ch.sx = 1.3; ch.sy = 1.3; ch.armL.z = 1.6; ch.armR.z = -1.6; ch.tint = '#FFFFFF'; break;
    case 'spray': ch.armR.z = F; ch.lean = 0.1; ch.bob = Math.sin(mf * 0.8) * 0.05; break;
  }
  if (m.charge && mf === st && f.charge > 0) { const p = Math.sin(f.charge * 0.5) * 0.04; ch.sx += p; ch.sy -= p; ch.tint = '#FFF6DC'; }
}

export function channelsFor(f, t) {
  const ch = { lean: 0, bob: 0, sx: 1, sy: 1, spinY: 0, spinZ: 0, armL: { z: 0.25, x: 0 }, armR: { z: -0.25, x: 0 }, legL: 0, legR: 0, head: 0, opacity: 1, tint: null, rigRotZ: 0, yOff: 0, bubble: 0, visible: true, shakeX: 0 };
  const s = f.state, sf = f.sf;
  const runPhase = f.frameCount * 0.38;
  switch (s) {
    case 'idle': ch.bob = Math.sin(t * 3 + f.index) * 0.06; ch.armL.z = 0.3 + Math.sin(t * 3) * 0.05; ch.armR.z = -0.3 - Math.sin(t * 3) * 0.05; break;
    case 'run': { const sp = Math.min(1, Math.abs(f.vx) / f.char.runSpeed); ch.legL = Math.sin(runPhase) * 0.9 * sp; ch.legR = -Math.sin(runPhase) * 0.9 * sp; ch.armL.x = -Math.sin(runPhase) * 0.7 * sp; ch.armR.x = Math.sin(runPhase) * 0.7 * sp; ch.lean = 0.18 * sp; ch.bob = Math.abs(Math.sin(runPhase)) * 0.12 * sp; break; }
    case 'dash': ch.lean = 0.4; ch.legL = 0.9; ch.legR = -0.9; ch.armL.z = 0.8; ch.armR.z = -0.8; ch.sx = 1.1; ch.sy = 0.92; break;
    case 'jumpsquat': ch.sy = 0.8; ch.sx = 1.15; break;
    case 'air': case 'helpless': case 'recovery':
      if (f.vy > 6) { ch.sy = 1.08; ch.sx = 0.95; ch.armL.z = 2.5; ch.armR.z = -2.5; ch.legL = -0.6; ch.legR = -0.6; }
      else if (f.vy < -6) { ch.armL.z = 1.2; ch.armR.z = -1.2; ch.legL = 0.3; ch.legR = -0.2; ch.sy = f.fastFalling ? 1.1 : 1; }
      else { ch.armL.z = 1.6; ch.armR.z = -1.6; }
      if (s === 'helpless') { ch.spinY = t * 6; ch.armL.z = 2.2; ch.armR.z = -2.2; }
      if (s === 'recovery') { ch.spinY = sf * 0.6; ch.armL.z = 3; ch.armR.z = -3; ch.sy = 1.1; }
      break;
    case 'landing': if (sf <= 6) { ch.sy = 0.85; ch.sx = 1.1; } break;
    case 'attack': attackChannels(ch, f); if (!f.onGround) { ch.legL = 0.3; ch.legR = -0.3; } break;
    case 'hitstun': ch.lean = -0.5; ch.armL.z = 2.2; ch.armR.z = -2.0; ch.armL.x = Math.sin(sf) * 0.6; ch.head = -0.3; ch.shakeX = sf < 4 ? (sf % 2 ? 0.15 : -0.15) : 0; ch.legL = 0.5; ch.legR = -0.4; break;
    case 'knockdown': ch.rigRotZ = -PI / 2 + 0.1; ch.yOff = 0.7; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
    case 'tech': ch.opacity = 0.6; if (f.techRoll) ch.rigRotZ = -sf * 0.35; else { ch.sy = 0.85; ch.sx = 1.1; } break;
    case 'shield': case 'shielddrop': ch.sy = 0.88; ch.sx = 1.05; ch.armL.z = 0.9; ch.armR.z = -0.9; if (s === 'shield') ch.bubble = Math.max(0.25, f.shield / 50); break;
    case 'stunned': ch.lean = Math.sin(sf * 0.3) * 0.25; ch.head = Math.sin(sf * 0.5) * 0.3; ch.armL.z = 1.0; ch.armR.z = -1.0; ch.tint = sf % 12 < 6 ? '#F4C531' : null; break;
    case 'spotdodge': ch.opacity = 0.35; ch.sy = 0.9; ch.lean = -0.3; break;
    case 'airdodge': ch.opacity = 0.35; ch.spinZ = sf * 0.45; break;
    case 'ledge': ch.armL.z = 2.9; ch.armR.z = -2.9; ch.legL = 0.3; ch.legR = -0.2; ch.head = -0.3; ch.bob = Math.sin(t * 4) * 0.05; break;
    case 'ledgeaction': { const k = f.la?.kind; if (k === 'attack') { ch.armR.z = sf > 8 ? PI / 2 : -0.8; ch.lean = 0.3; } else if (k === 'roll') { ch.rigRotZ = -sf * 0.3 * f.facing; ch.opacity = 0.7; } else { ch.lean = -0.2; ch.armL.z = 1.4; ch.armR.z = -1.4; } break; }
    case 'grab': ch.armL.z = 1.4; ch.armR.z = -1.4; ch.lean = sf > 7 ? 0.3 : 0.1; if (sf > 7) { ch.armL.z = PI / 2; ch.armR.z = PI / 2; } break;
    case 'holding': ch.armL.z = PI / 2; ch.armR.z = PI / 2; ch.lean = 0.15; ch.sx = 1.05; break;
    case 'grabbed': ch.armL.z = 1.6; ch.armR.z = -1.6; ch.legL = Math.sin(sf * 0.6) * 0.8; ch.legR = -Math.sin(sf * 0.6) * 0.8; ch.head = -0.2; break;
    case 'groundpound': if (sf <= 8) { ch.sy = 0.8; ch.sx = 1.15; ch.armL.z = 2.9; ch.armR.z = -2.9; } else { ch.sy = 1.25; ch.sx = 0.85; ch.armL.z = 3.1; ch.armR.z = -3.1; ch.legL = 0; ch.legR = 0; } break;
    case 'tether': ch.armL.z = 2.9; ch.armR.z = -2.9; ch.sy = 1.15; ch.sx = 0.9; break;
    case 'frozen': ch.tint = '#A9D8F0'; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
    case 'taunt': ch.bob = Math.abs(Math.sin(sf * 0.25)) * 0.5; ch.spinY = sf * 0.15; ch.armL.z = 2.6 + Math.sin(sf * 0.5) * 0.4; ch.armR.z = -0.4; break;
    case 'ko': ch.visible = false; break;
    case 'respawn': ch.yOff = Math.sin(t * 4) * 0.3; ch.opacity = 0.85; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
  }
  if (f.tumbling && (s === 'air' || s === 'hitstun')) ch.rigRotZ = -f.frameCount * 0.3 * f.facing;
  if (f.invincible > 0 && s !== 'ledge' && s !== 'respawn' && f.frameCount % 6 < 3) ch.opacity *= 0.55;
  if (f.effects.chill.stacks > 0 && !ch.tint) ch.tint = ['#C9E6F5', '#A9D8F0', '#7FC0E6'][f.effects.chill.stacks - 1];
  if (f.hitlag > 0) ch.shakeX = (f.frameCount % 2 ? 0.12 : -0.12);
  return ch;
}

