import { emptyFrame } from './input.js';

// `ult` is how well a bot spends its ultimate: at 0.2 it throws it out roughly whenever the bar
// fills, at 1.0 it waits for the range the move actually wants and for a target worth spending it
// on. `edge` is how willing it is to follow someone off the stage.
const LEVELS = {
  dummy: null,
  easy: { reaction: 22, commit: 20, aggression: 0.35, defence: 0.15, kill: 0.5, dodge: 0.1, ult: 0.2, edge: 0.0 },
  normal: { reaction: 12, commit: 16, aggression: 0.55, defence: 0.35, kill: 0.7, dodge: 0.25, ult: 0.5, edge: 0.15 },
  hard: { reaction: 6, commit: 13, aggression: 0.7, defence: 0.55, kill: 0.9, dodge: 0.4, ult: 0.75, edge: 0.4 },
  elite: { reaction: 3, commit: 11, aggression: 0.85, defence: 0.7, kill: 1.0, dodge: 0.6, ult: 0.9, edge: 0.65 },
  impossible: { reaction: 1, commit: 9, aggression: 0.95, defence: 0.85, kill: 1.0, dodge: 0.8, ult: 1.0, edge: 0.8 },
  just_dont: { reaction: 1, commit: 8, aggression: 1.0, defence: 1.0, kill: 1.0, dodge: 1.0, ult: 1.0, edge: 0.95 },
};
// The menu has offered "Bot · Impossible" the whole time while this table spelled it `imposible`,
// so that option silently played at Normal. Kept as an alias so any saved match config still works.
LEVELS.imposible = LEVELS.impossible;
const sign = (v) => (v < 0 ? -1 : 1);
const chance = (p) => Math.random() < p;

// Should this bot spend its ultimate right now?
//
// Bots charged the meter and never pressed the key — every ultimate in the game was player-only,
// so a bot match never showed the moves the last few rounds of work went into. Each ultimate wants
// a different situation, and the numbers below come from the moves' own data rather than taste:
//   slam      a grounded overhead with a ~5-stud blade and a crater that walks 4.2 x 4 studs out
//   vortex    reaches `vortex.range` and drags them in; useless beyond it
//   sniper    a stance that paints the nearest target and needs THREE presses to spend
//   starfall  hits everyone alive wherever they are, so it only wants a living target
function wantsUltimate(f, target, L, adx, dy, enemies) {
  if (!f.ultReady) return false;
  const U = f.char.moves.Ultimate;
  if (!U) return false;
  if (U.grounded && !f.onGround) return false;
  // A sloppy bot just throws it out; a good one waits for the shape the move wants.
  if (!chance(L.ult)) return chance(0.02);
  switch (U.kind) {
    case 'slam': {
      const reach = (U.crater ? U.crater.step * (U.crater.count - 1) : 8);
      return adx < reach * 0.7 && Math.abs(dy) < 6 && target.onGround;
    }
    case 'vortex':
      return adx < (U.vortex ? U.vortex.range : 17) * 0.8 && Math.abs(dy) < 8;
    case 'sniper':
      // No range condition — the round steers. What it wants is not being hit mid-stance.
      return f.onGround && !(target.state === 'attack' && adx < 8);
    case 'starfall':
      return enemies.length > 0 && (enemies.length > 1 || target.percent > 40);
    default:
      return adx < 10;
  }
}

export function computeBotInput(f, match) {
  const frame = emptyFrame();
  if (f.botLevel === 'dummy') return frame; // dummy stands still
  const L = LEVELS[f.botLevel] || LEVELS.normal;
  if (!f.ai) f.ai = { timer: 0, plan: 'approach', hold: 0, jumpCd: 0, lastState: '', ultCd: 0, defCd: 0, punish: 0 };
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
  // Deadeye is a stance: it holds three rounds and spends one per press. A bot that pressed once
  // fired one bullet and threw the other two away, so the stance keeps being fed here.
  if (f.ultActive && f.move && f.move.kind === 'sniper' && f.ultShots > 0) {
    frame.ult = st.ultCd-- <= 0;
    if (frame.ult) { st.ultCd = (f.move.sniper.reload || 16) + 2; frame.anyPress = true; }
    return frame;
  }
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
  // Defence has to convert into offence, or it is just time spent not playing.
  //
  // Measured: at defence 1.0 / dodge 1.0 the top difficulty spent 11% of the match in spot-dodge
  // (easy spends 1%) and attacked LESS than Normal — a spot-dodge is twenty frames of doing
  // nothing, and taking every single one available is how the hardest bot lost to the easiest on
  // stocks, 25 to 34, over thirty games. So `dodge` now means how well-TIMED the evasion is, not
  // how often it is taken; there is a cooldown between defensive reactions; and a bot that
  // successfully defends goes straight back at the opponent instead of resetting to neutral.
  st.defCd--;
  if ((threat || incomingProjectile) && st.timer <= 0 && st.defCd <= 0 && chance(L.defence)) {
    st.plan = chance(L.dodge * 0.45) ? 'dodge' : 'shield';
    st.timer = L.reaction + 10; st.hold = 16; st.defCd = 30;
    st.punish = L.aggression;                  // what to do the moment the defence is over
  }

  if (wantsUltimate(f, target, L, adx, dy, enemies)) {
    frame.ult = true; frame.anyPress = true;
    st.ultCd = 0; st.plan = 'approach';
    return frame;
  }

  if (st.timer <= 0) {
    // COMMIT, not reaction. `reaction` is how fast a bot answers a threat; re-rolling the plan on
    // that same clock meant the best bots re-decided what to do every single frame and thrashed
    // between approach, attack and retreat without ever finishing any of them. Measured, the
    // maximum difficulty lost to `easy` on stocks — the scale was inverted. A better bot now
    // reacts faster AND commits harder, which is what "better" means in a fighting game.
    st.timer = L.commit;
    const arche = f.char.archetype;
    const inRange = adx < 6 && Math.abs(dy) < 5;
    const r = Math.random();
    // The archetype strings come from the WEAPON, and there are exactly four: All-rounder,
    // Reach / combo, Zoner, Heavy zoner. This used to branch on 'Charge', 'Trap', 'Summoner' and
    // 'Grappler' — none of which exist — so the `setup` and `lasso` plans were unreachable, and
    // Grimoire, the heaviest zoner in the game, fell through to the melee branch and walked at you.
    if (inRange) st.plan = r < L.aggression + 0.25 ? 'attack' : r < 0.85 ? 'shield' : 'retreat';
    else if (arche === 'Zoner') st.plan = adx > 10 && adx < 34 && Math.abs(dy) < 5 && r < 0.6 ? 'zone' : 'approach';
    else if (arche === 'Heavy zoner') st.plan = adx > 12 && Math.abs(dy) < 8 && r < 0.55 ? 'zone' : 'approach';
    else if (arche === 'Reach / combo') st.plan = adx > 6 && adx < 14 && r < 0.4 ? 'lasso' : 'approach';
    else st.plan = r < 0.15 ? 'retreat' : 'approach';
    if (st.plan === 'attack') st.hold = 6; else st.hold = 14;
  }

  const plan = st.plan;
  if (plan === 'shield') {
    frame.guardHeld = true;
    // drop the shield the instant the threat is over and take the punish
    if (--st.hold <= 0 || target.state !== 'attack') { st.timer = 0; st.plan = chance(st.punish || 0) ? 'attack' : 'approach'; }
    if (adx < 3 && chance(0.1)) frame.light = true;
    return frame;
  }
  if (plan === 'dodge') { frame.dodge = true; st.plan = chance(st.punish || 0) ? 'attack' : 'approach'; st.timer = 0; return frame; }
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
    // Archetype-flavoured aggression. The archetype strings come from the WEAPON, so these are
    // the four that exist: All-rounder, Reach / combo, Zoner, Heavy zoner.
    if (f.char.archetype === 'Heavy zoner' && target.state === 'attack' && chance(0.4)) { frame.y = -1; frame.heavy = true; st.plan = 'approach'; return frame; }
    if (f.char.archetype === 'Reach / combo' && chance(0.35)) { frame.grab = true; st.plan = 'approach'; return frame; }
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
  // ---- edgeguard ----
  // Nothing here ever went after a fighter who was already off the stage, which is where most of
  // a platform fighter's stocks are actually taken. A bot would knock someone out over the pit and
  // then stand on the ledge waiting for them to come back.
  const targetOff = target.x < main.x1 - 1 || target.x > main.x2 + 1;
  // Only chase what can be chased AND returned from. Without the jump check a confident bot walks
  // off the edge after someone it cannot reach and takes itself out.
  const canComeBack = f.jumpsLeft > 0 && Math.abs(target.x - main.cx) < Math.abs(main.x2 - main.cx) + 16;
  if (targetOff && canComeBack && f.onGround && !offStage && chance(L.edge)) {
    const outward = sign(target.x - main.cx);
    // Ranged weapons cover the ledge from safety; melee has to commit to the chase.
    if (f.char.archetype === 'Zoner' || f.char.archetype === 'Heavy zoner') {
      frame.x = outward; frame.heavy = true; st.plan = 'approach'; return frame;
    }
    if (Math.abs(f.x - main.cx) > Math.abs(main.x2 - main.cx) - 6 && target.y < f.y - 1) {
      // standing on the lip and they are below it: a down-air is the kill, but only commit when
      // there is a real chance of getting back
      if (f.jumpsLeft > 1 && chance(0.5)) { frame.jump = true; st.plan = 'chase'; st.hold = 10; return frame; }
      frame.y = -1; frame.light = true; return frame;
    }
    frame.x = outward;
    return frame;
  }
  if (plan === 'chase') {
    frame.x = sign(target.x - f.x);
    if (Math.abs(dy) < 4 && adx < 5) { frame.y = -1; frame.light = true; st.plan = 'approach'; return frame; }
    if (--st.hold <= 0 || f.y < target.y - 4) st.plan = 'approach';
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
