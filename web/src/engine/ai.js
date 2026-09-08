import { emptyFrame } from './input.js';

const LEVELS = {
  dummy: null,
  easy: { reaction: 22, aggression: 0.35, defence: 0.15, kill: 0.5, dodge: 0.1 },
  normal: { reaction: 12, aggression: 0.55, defence: 0.35, kill: 0.7, dodge: 0.25 },
  hard: { reaction: 6, aggression: 0.7, defence: 0.55, kill: 0.9, dodge: 0.4 },
};
const sign = (v) => (v < 0 ? -1 : 1);
const chance = (p) => Math.random() < p;

export function computeBotInput(f, match) {
  const frame = emptyFrame();
  if (f.botLevel === 'dummy') return frame; // dummy stands still
  const L = LEVELS[f.botLevel] || LEVELS.normal;
  if (!f.ai) f.ai = { timer: 0, plan: 'approach', hold: 0, jumpCd: 0, lastState: '' };
  const st = f.ai;
  st.timer--; st.jumpCd--;
  const stage = match.stage, main = stage.main;
  const enemies = match.fighters.filter((v) => v !== f && v.alive && v.team !== f.team);
  if (!enemies.length) return frame;
  let target = enemies[0];
  for (const e of enemies) if (Math.abs(e.x - f.x) < Math.abs(target.x - f.x)) target = e;
  const dx = target.x - f.x, dy = target.y - f.y, adx = Math.abs(dx), dir = sign(dx);
  const offStage = f.x < main.x1 - 0.5 || f.x > main.x2 + 0.5;
  const toStage = f.x < main.cx ? 1 : -1;

  if (f.state === 'respawn') { if (st.timer <= 0) { frame.jump = true; st.timer = 20; } return frame; }
  if (f.state === 'ko' || f.state === 'grabbed' || f.state === 'frozen' || f.state === 'stunned') { if (f.state === 'frozen' || f.state === 'grabbed') frame.light = chance(0.5); return frame; }

  // ---- recovery ----
  if (!f.onGround && (offStage || f.y < -6) && f.state !== 'ledge' && f.state !== 'tether') {
    frame.x = toStage;
    const nearLedge = stage.nearestLedge(f.x, f.cy);
    if (f.state === 'hitstun') { frame.x = toStage; frame.y = 1; return frame; }
    if (f.state === 'helpless') { if (nearLedge.dist < 8) frame.guard = chance(0.5); return frame; }
    const belowLedge = f.y < -2;
    if (f.jumpsLeft > 0 && f.vy < 0 && (belowLedge || nearLedge.dist > 14) && st.jumpCd <= 0) { frame.jump = true; st.jumpCd = 14; return frame; }
    if (f.jumpsLeft === 0 && !f.recoveryUsed && f.vy < 2 && (belowLedge || nearLedge.dist > 6)) { frame.heavy = true; frame.y = 1; return frame; }
    if (nearLedge.dist < 6 && f.vy < 0) frame.guard = true;
    if (f.tumbling && chance(0.3)) frame.dodge = true;
    return frame;
  }
  // ---- ledge ----
  if (f.state === 'ledge') {
    if (st.timer <= 0) {
      const r = Math.random();
      const enemyNear = adx < 10;
      if (r < 0.3 && !enemyNear) frame.x = -f.ledge.side;
      else if (r < 0.55) frame.dodge = true;
      else if (r < 0.8 && enemyNear) frame.light = true;
      else frame.jump = true;
      st.timer = 30;
    }
    return frame;
  }
  // ---- hitstun / tumble / knockdown ----
  if (f.state === 'hitstun') { frame.x = -sign(f.vx || 1) * 0.6; frame.y = f.vy > 0 ? -0.5 : 0.5; return frame; }
  if (f.tumbling && !f.onGround) { if (f.y < 4 && f.vy < 0) frame.guard = true; else if (chance(0.2)) frame.jump = true; return frame; }
  if (f.state === 'knockdown') return frame;
  if (f.state === 'attack' || f.state === 'holding' || f.state === 'grab') {
    if (f.state === 'holding') { const r = Math.random(); frame.x = r < 0.4 ? f.facing : r < 0.6 ? -f.facing : 0; frame.y = r > 0.8 ? 1 : 0; }
    if (f.move && f.move.charge && f.state === 'attack') frame.heavyHeld = f.charge < (f.move.charge.maxHold * 0.6);
    if (f.move && f.move.chainsTo && f.moveLanded) frame.light = chance(0.7);
    if (f.state === 'attack' && f.move && !f.onGround) frame.x = dir * 0.6;
    return frame;
  }

  // ---- threat reaction ----
  const threat = target.state === 'attack' && adx < 8 && Math.abs(dy) < 6;
  const incomingProjectile = match.combat.projectiles.some((p) => p.owner !== f && Math.abs(p.x - f.x) < 12 && sign(p.vx) === -sign(f.x - p.x || 1) && Math.abs(p.y - f.cy) < 4);
  if ((threat || incomingProjectile) && st.timer <= 0 && chance(L.defence)) {
    st.plan = chance(L.dodge) ? 'dodge' : 'shield'; st.timer = L.reaction + 10; st.hold = 16;
  }

  if (st.timer <= 0) {
    st.timer = L.reaction;
    const arche = f.char.archetype;
    const inRange = adx < 6 && Math.abs(dy) < 5;
    const r = Math.random();
    if (inRange) st.plan = r < L.aggression + 0.25 ? 'attack' : r < 0.85 ? 'shield' : 'retreat';
    else if (arche === 'Zoner' || arche === 'Charge') st.plan = adx > 10 && adx < 34 && Math.abs(dy) < 5 && r < 0.6 ? 'zone' : 'approach';
    else if (arche === 'Trap' || arche === 'Summoner') st.plan = adx > 12 && r < 0.5 ? 'setup' : 'approach';
    else if (arche === 'Grappler') st.plan = adx < 12 && r < 0.4 ? 'lasso' : 'approach';
    else st.plan = r < 0.15 ? 'retreat' : 'approach';
    if (st.plan === 'attack') st.hold = 6; else st.hold = 14;
  }

  const plan = st.plan;
  if (plan === 'shield') { frame.guardHeld = true; if (--st.hold <= 0) st.timer = 0; if (adx < 3 && chance(0.1)) { frame.light = true; } return frame; }
  if (plan === 'dodge') { frame.dodge = true; st.plan = 'approach'; return frame; }
  if (plan === 'retreat') { frame.x = -dir; if (f.onGround && chance(0.03)) frame.jump = true; if (--st.hold <= 0) st.timer = 0; return frame; }
  if (plan === 'zone') { frame.x = dir; frame.heavy = true; frame.heavyHeld = true; st.plan = 'approach'; return frame; }
  if (plan === 'setup') { frame.y = -1; frame.heavy = true; st.plan = 'approach'; return frame; }
  if (plan === 'lasso') { frame.x = dir; frame.heavy = true; st.plan = 'approach'; return frame; }
  if (plan === 'attack') {
    if (!f.onGround) {
      if (dy < -3) frame.y = -1; else frame.x = dir;
      frame.light = true; st.plan = 'approach'; return frame;
    }
    const wantsKill = target.percent > 90 && chance(L.kill);
    if (f.char.archetype === 'Heavy' && target.state === 'attack' && chance(0.4)) { frame.y = -1; frame.heavy = true; st.plan = 'approach'; return frame; }
    if (f.char.archetype === 'Grappler' && chance(0.35)) { frame.grab = true; st.plan = 'approach'; return frame; }
    if (f.char.id === 'Frostbud' && target.effects.chill.stacks >= 3 && adx < 5) { frame.y = -1; frame.heavy = true; st.plan = 'approach'; return frame; }
    if (wantsKill) { frame.x = dir; frame.heavy = true; }
    else if (target.state === 'shield' && chance(0.6)) { frame.grab = true; }
    else if (dy > 4 && chance(0.6)) { frame.jump = true; st.hold = 8; }
    else {
      const r = Math.random();
      frame.x = dir;
      if (r < 0.45) frame.light = true;
      else if (r < 0.75) { frame.x = 0; frame.light = true; }
      else { frame.y = -1; frame.x = 0; frame.light = true; }
    }
    st.plan = 'approach';
    return frame;
  }
  // approach
  frame.x = dir;
  if (adx > 20 && f.onGround && chance(0.06)) frame.dodge = true;
  if (dy > 6 && f.onGround && st.jumpCd <= 0 && chance(0.15)) { frame.jump = true; st.jumpCd = 20; }
  if (!f.onGround && dy > 3 && f.jumpsLeft > 0 && st.jumpCd <= 0 && chance(0.1)) { frame.jump = true; st.jumpCd = 20; }
  if (!f.onGround && adx < 5 && dy < -2 && chance(0.3)) { frame.y = -1; frame.light = true; }
  if (!f.onGround && adx < 5 && Math.abs(dy) < 3 && chance(0.4)) frame.light = true;
  if (f.onGround && adx < 3 && chance(0.02)) frame.taunt = target.stocksLeft && target.stocksLeft() === 0;
  return frame;
}
