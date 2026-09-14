import { emptyFrame } from './input.js';

// `ult` is how well a bot spends its ultimate: at 0.2 it throws it out roughly whenever the bar
// fills, at 1.0 it waits for the range the move actually wants and for a target worth spending it
// on. `edge` is how willing it is to follow someone off the stage.
// `sight` is the one that matters, and it is the lever this table was missing.
//
// Difficulty here used to be delivered by cranking AGGRESSION: the hardest bot attacked more,
// chased further, dodged more. Measured over eighty games that produced a stock ratio of 1.09 -
// the best bot in the game was nine percent better than the worst, and two of the six levels were
// statistically identical. Turning every dial to 1.0 does not make a fighter good, it makes them
// reckless, and the hardest bot was losing stocks by walking into things.
//
// The fix is the one the fighting-game AI literature settled on years ago: handicap PERCEPTION,
// not behaviour. FightingICE gives its bots a 15-frame observation delay to stand in for human
// reaction; published work on real-time fighting AI uses ~230ms for the same reason, and notes
// that at zero delay play collapses into degenerate frame-perfect reaction. So `sight` is how many
// frames STALE this bot's view of its opponent is - 26 frames is a third of a second behind, which
// is roughly a distracted human, and 0 is a machine reading the current frame.
//
// A bot that sees late is worse at everything at once, which is what "worse" should mean: it
// whiffs punishes because the opponent has already moved, mistimes edgeguards, chases where
// somebody was, and answers an attack that has already finished. None of that required making it
// passive.
//
// `slip` is the second handicap: the chance of fumbling an input outright on a given decision.
// `chains` is how many of the committed multi-frame sequences (see CHAINS) the level knows.
// `ult` is how well a bot spends its ultimate: at 0.2 it throws it out roughly whenever the bar
// fills, at 1.0 it waits for the range the move actually wants. `edge` is how willing it is to
// follow someone off the stage.
export const LEVELS = {
  dummy: null,
  easy: { sight: 26, reaction: 22, commit: 20, aggression: 0.35, defence: 0.15, kill: 0.5, dodge: 0.1, ult: 0.2, edge: 0.0, slip: 0.30, chains: 0 },
  normal: { sight: 15, reaction: 12, commit: 16, aggression: 0.55, defence: 0.35, kill: 0.7, dodge: 0.25, ult: 0.5, edge: 0.15, slip: 0.15, chains: 1 },
  hard: { sight: 9, reaction: 6, commit: 13, aggression: 0.7, defence: 0.55, kill: 0.9, dodge: 0.4, ult: 0.75, edge: 0.4, slip: 0.07, chains: 2 },
  elite: { sight: 5, reaction: 3, commit: 11, aggression: 0.85, defence: 0.7, kill: 1.0, dodge: 0.6, ult: 0.9, edge: 0.65, slip: 0.03, chains: 3 },
  impossible: { sight: 2, reaction: 1, commit: 9, aggression: 0.95, defence: 0.85, kill: 1.0, dodge: 0.8, ult: 1.0, edge: 0.8, slip: 0.01, chains: 3 },
  just_dont: { sight: 0, reaction: 1, commit: 8, aggression: 1.0, defence: 1.0, kill: 1.0, dodge: 1.0, ult: 1.0, edge: 0.95, slip: 0.0, chains: 3 },
};
LEVELS.imposible = LEVELS.impossible;
const sign = (v) => (v < 0 ? -1 : 1);
const chance = (p) => Math.random() < p;

// ------------------------------------------------------------------------- perception -----
// One ring of snapshots per match, written once per frame by whichever bot runs first, read by all
// of them. A bot reads its OPPONENT through this ring at its own `sight` delay; its own state is
// always current, because you always know where you are standing.

const SIGHT_MAX = 30;

function history(match) {
  const H = match._aiHist || (match._aiHist = { frame: -1, ring: new Map() });
  if (H.frame === match.frame) return H;
  H.frame = match.frame;
  for (const v of match.fighters) {
    let buf = H.ring.get(v);
    if (!buf) { buf = []; H.ring.set(v, buf); }
    buf.push({ x: v.x, y: v.y, cy: v.cy, vx: v.vx, vy: v.vy, state: v.state, percent: v.percent,
      onGround: v.onGround, alive: v.alive, facing: v.facing, tumbling: v.tumbling });
    if (buf.length > SIGHT_MAX) buf.shift();
  }
  return H;
}

// What this bot currently believes about a fighter. Returns a SNAPSHOT, never the fighter itself,
// so nothing downstream can accidentally read a live value and quietly cheat.
function seen(H, v, sight) {
  const buf = H.ring.get(v);
  if (!buf || !buf.length) return v;
  return buf[Math.max(0, buf.length - 1 - sight)];
}

// ------------------------------------------------------------------------- execution -----
// Seeing late is only half of being worse. A weak player also just fumbles: drops the button,
// holds the wrong way, lets go of shield early. Applied to the ground game only - a bot that
// fumbles its recovery dies to nothing at all, and a difficulty level that mostly kills itself is
// not an easier opponent, it is an absent one.
function fumble(frame, L, st) {
  if (!L.slip || st.noFumble || !chance(L.slip)) return frame;
  const r = Math.random();
  if (r < 0.45) { frame.light = false; frame.heavy = false; frame.grab = false; frame.anyPress = false; }
  else if (r < 0.8) frame.x = -frame.x;
  else { frame.jump = false; frame.dodge = false; frame.guardHeld = false; frame.guard = false; }
  return frame;
}

// ---------------------------------------------------------------------------- chains -----
// Borrowed from SmashBot's Strategy / Tactic / Chain split: a chain is a short sequence of inputs
// the bot commits to and does NOT re-decide part way through, the way a human executes a known
// option rather than reconsidering every frame. Our `plan` is the tactic; this is the layer under
// it that was missing, and it is why the better bots used to thrash - they re-picked a plan every
// `commit` frames and never finished one.
//
// Each step is { n: frames, f: (frame, c) => void } where `c` carries dir, the target view and the
// bot itself. Chains are gated by level: a weak bot simply does not know them.
export const CHAINS = {
  // Close the gap at a run, then hit. The most basic thing a human does and the bot never did:
  // it walked into range and then decided, from a standstill, what to do.
  dashIn: { need: 1, steps: [
    { n: 10, f: (fr, c) => { fr.x = c.dir; } },
    { n: 2, f: (fr, c) => { fr.x = c.dir; fr.light = true; } },
  ] },
  // Shield the thing coming at you, then take the free grab. A real option and a real read.
  shieldGrab: { need: 2, steps: [
    { n: 11, f: (fr) => { fr.guardHeld = true; } },
    { n: 2, f: (fr, c) => { fr.x = c.dir; fr.grab = true; } },
  ] },
  // Walk backwards out of range, wait for them to over-commit, then punish with the heavy. This
  // is the bait SmashBot's docs describe as its default strategy, and it is the one thing on this
  // list that only the top levels get.
  bait: { need: 3, steps: [
    { n: 12, f: (fr, c) => { fr.x = -c.dir; } },
    { n: 6, f: (fr, c) => { fr.x = c.dir; } },
    { n: 3, f: (fr, c) => { fr.x = c.dir; fr.heavy = true; } },
  ] },
};

function startChain(st, name) { st.chain = { name, i: 0, t: CHAINS[name].steps[0].n }; }

// Run the current chain for one frame. Returns false when it is finished or was interrupted.
function runChain(frame, st, c) {
  const ch = st.chain;
  if (!ch) return false;
  const def = CHAINS[ch.name];
  const step = def.steps[ch.i];
  if (!step) { st.chain = null; return false; }
  step.f(frame, c);
  if (--ch.t <= 0) { ch.i++; ch.t = def.steps[ch.i] ? def.steps[ch.i].n : 0; if (!def.steps[ch.i]) st.chain = null; }
  return true;
}

// Should this bot spend its ultimate right now?
//
// Bots charged the meter and never pressed the key — every ultimate in the game was player-only,
// so a bot match never showed the moves the last few rounds of work went into. Each ultimate wants
// a different situation, and the numbers below come from the moves' own data rather than taste:
//   slam      a grounded overhead with a ~5-stud blade and a crater that walks 4.2 x 4 studs out
//   vortex    reaches `vortex.range` and drags them in; useless beyond it
//   sniper    a stance that paints the nearest target and needs THREE presses to spend
//   starfall  hits everyone alive wherever they are, so it only wants a living target
function wantsUltimate(f, tv, L, adx, dy, enemies) {
  if (!f.ultReady) return false;
  const U = f.char.moves.Ultimate;
  if (!U) return false;
  if (U.grounded && !f.onGround) return false;
  // A sloppy bot just throws it out; a good one waits for the shape the move wants.
  if (!chance(L.ult)) return chance(0.02);
  switch (U.kind) {
    case 'slam': {
      const reach = (U.crater ? U.crater.step * (U.crater.count - 1) : 8);
      return adx < reach * 0.7 && Math.abs(dy) < 6 && tv.onGround;
    }
    case 'vortex':
      return adx < (U.vortex ? U.vortex.range : 17) * 0.8 && Math.abs(dy) < 8;
    case 'sniper':
      // No range condition — the round steers. What it wants is not being hit mid-stance.
      return f.onGround && !(tv.state === 'attack' && adx < 8);
    case 'starfall':
      return enemies.length > 0 && (enemies.length > 1 || tv.percent > 40);
    default:
      return adx < 10;
  }
}


// ------------------------------------------------------------------------------ items -----
// Wanting an item, going to get it, and knowing what it is for. Each item has one verb, so this
// is a small table rather than a policy: the AI does not need to be clever about a Blast Keg, it
// needs to throw it at somebody and not be standing next to it when it goes off.
function itemAction(f, match, L, st, tv, dir, adx, frame) {
  if (!match.itemsOn || !f.onGround) return false;
  const C = match.combat;
  const held = f.item;

  if (!held) {
    // Go and get one. `greed` scales with level, so a weak bot notices items late and often walks
    // past them - the same handicap as its sight, applied to the thing on the floor.
    //
    // The FETCH TIMEOUT is not decoration. The first version walked toward any item within 26
    // studs, re-rolling every frame, with no way to give up: two bots that each wanted an item on
    // a ledge they could not reach would walk at it until the clock ran out. It turned a
    // one-stock four-bot match into a five-minute stalemate about one in ten runs, and that is
    // exactly the kind of failure that gets written off as a flake.
    if (st.fetchCd > 0) { st.fetchCd--; return false; }
    if (adx < 5) return false;                       // somebody is on top of you; fight first
    const greed = 0.25 + L.aggression * 0.75;
    let best = null, bd = 1e9;
    for (const it of C.items) {
      if (it.held) continue;
      const d = Math.abs(it.x - f.x), dy2 = Math.abs(it.y - f.y);
      if (d > 20 || dy2 > 4) continue;               // same floor, and close enough to be worth it
      if (d < bd) { bd = d; best = it; }
    }
    if (!best || !chance(greed)) { st.fetch = 0; return false; }
    if (bd < 2.6) { frame.pickup = true; frame.anyPress = true; st.chain = null; st.fetch = 0; return true; }
    // Give up on an item you are not getting closer to.
    st.fetch = (st.fetch || 0) + 1;
    if (st.fetch > 100) { st.fetch = 0; st.fetchCd = 180; return false; }
    frame.x = sign(best.x - f.x);
    st.chain = null;
    return true;
  }
  st.fetch = 0;

  const def = held.def;
  const faces = sign(tv.x - f.x) === f.facing || adx < 3;

  // Heavy throws whatever is left when the fight has moved on and the item is no longer the plan.
  if (def.kind === 'hold') {
    if (held.hp <= 0) { frame.heavy = true; frame.anyPress = true; return true; }
    if (adx < 4 && chance(L.aggression * 0.5)) { frame.light = true; frame.anyPress = true; return true; }
    return false;                                   // otherwise just carry it: the guard is passive
  }
  if (def.kind === 'place') {
    // Put it down where it is worth something: near the edge you keep getting knocked off.
    const main = match.stage.main;
    const nearEdge = Math.min(Math.abs(f.x - main.x1), Math.abs(f.x - main.x2)) < 12;
    if (nearEdge || chance(0.02)) { frame.light = true; frame.anyPress = true; return true; }
    frame.x = sign((f.x < main.cx ? main.x1 : main.x2) - f.x);
    return true;
  }
  if (def.kind === 'shoot') {
    if (adx < 30 && Math.abs(tv.y - f.y) < 4 && faces) { frame.light = true; frame.anyPress = true; return true; }
    frame.x = dir;
    return true;
  }
  if (def.kind === 'throw') {
    // A keg wants an arc, so it is thrown from further out than the Lodestone, which flies flat.
    const want = def.explode ? [6, 22] : [3, 26];
    if (adx > want[0] && adx < want[1] && Math.abs(tv.y - f.y) < 6 && faces) { frame.light = true; frame.anyPress = true; return true; }
    frame.x = dir;
    return true;
  }
  return false;
}

export function computeBotInput(f, match) {
  if (f.botLevel === 'dummy') return emptyFrame();            // dummy stands still
  const L = LEVELS[f.botLevel] || LEVELS.normal;
  if (!f.ai) f.ai = { timer: 0, plan: 'approach', hold: 0, jumpCd: 0, lastState: '', ultCd: 0, defCd: 0, punish: 0, chain: null, noFumble: false, fetch: 0, fetchCd: 0 };
  f.ai.noFumble = false;
  return fumble(decide(f, match, L, f.ai), L, f.ai);
}

function decide(f, match, L, st) {
  const frame = emptyFrame();
  st.timer--; st.jumpCd--;
  const stage = match.stage, main = stage.main;
  const enemies = match.fighters.filter((v) => v !== f && v.alive && v.team !== f.team);
  if (!enemies.length) return frame;
  // Everything this bot knows about anyone else is read through here, `sight` frames late.
  const H = history(match);
  let target = enemies[0], tv = seen(H, target, L.sight);
  for (const e of enemies) {
    const ev = seen(H, e, L.sight);
    if (Math.abs(ev.x - f.x) < Math.abs(tv.x - f.x)) { target = e; tv = ev; }
  }
  const dx = tv.x - f.x, dy = tv.y - f.y, adx = Math.abs(dx), dir = sign(dx);
  const offStage = f.x < main.x1 - 0.5 || f.x > main.x2 + 0.5;
  const toStage = f.x < main.cx ? 1 : -1;

  if (f.state === 'respawn') { st.noFumble = true; if (st.timer <= 0) { frame.jump = true; st.timer = 20; } return frame; }
  if (f.state === 'ko' || f.state === 'grabbed' || f.state === 'frozen' || f.state === 'stunned') { if (f.state === 'frozen' || f.state === 'grabbed') frame.light = chance(0.5); return frame; }

  // ---- recovery ----
  if (!f.onGround && (offStage || f.y < -6) && f.state !== 'ledge' && f.state !== 'tether') {
    // Never fumbled, and no chain survives being knocked off: getting home is not a difficulty
    // lever. A level that mostly kills itself is not an easier opponent, it is an absent one.
    st.noFumble = true; st.chain = null;
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
  if (f.state === 'hitstun') { st.noFumble = true; st.chain = null; frame.x = -sign(f.vx || 1) * 0.6; frame.y = f.vy > 0 ? -0.5 : 0.5; return frame; }
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
  const threat = tv.state === 'attack' && adx < 8 && Math.abs(dy) < 6;
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
    // Shield-grab is chosen HERE, not in the tactic block below, because a defensive plan is set
    // from this branch and returns before that block ever runs - which made the chain unreachable
    // the first time it was written. A chain nothing can start is the same bug as a channel
    // nothing draws, and this project has now shipped that bug four times.
    if (st.plan === 'shield' && CHAINS.shieldGrab.need <= L.chains && f.onGround && adx < 7 && chance(0.45)) startChain(st, 'shieldGrab');
  }

  if (wantsUltimate(f, tv, L, adx, dy, enemies)) {
    frame.ult = true; frame.anyPress = true;
    st.ultCd = 0; st.plan = 'approach';
    return frame;
  }

  // ---- items ----
  // Bots never touched an item. Measured over eight four-player matches: thirty-eight spawned,
  // ZERO picked up, thirty-four despawned untouched - the whole item system was scenery in any
  // match with a bot in it, which is most matches. Nothing in here ever pressed for one.
  const itemPlan = itemAction(f, match, L, st, tv, dir, adx, frame);
  if (itemPlan) return frame;

  // A chain in progress owns the next few frames outright - that is the whole point of it.
  if (st.chain && runChain(frame, st, { dir, tv, f })) return frame;

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

    // Tactic chosen; now pick the chain that executes it, if this level knows one. A weak bot
    // falls through to the single-frame behaviour below and plays the way it always did.
    if (L.chains > 0 && f.onGround && !f.ultActive) {
      if (st.plan === 'approach' && adx > 7 && adx < 22 && Math.abs(dy) < 4 && chance(L.aggression * 0.5)) startChain(st, 'dashIn');
      else if (st.plan === 'shield' && CHAINS.shieldGrab.need <= L.chains && adx < 7 && chance(0.5)) startChain(st, 'shieldGrab');
      else if (st.plan === 'attack' && CHAINS.bait.need <= L.chains && adx < 9 && tv.state !== 'attack' && chance(0.22)) startChain(st, 'bait');
      if (st.chain) { st.timer = 24; return runChain(frame, st, { dir, tv, f }) ? frame : frame; }
    }
  }

  const plan = st.plan;
  if (plan === 'shield') {
    frame.guardHeld = true;
    // drop the shield the instant the threat is over and take the punish
    if (--st.hold <= 0 || tv.state !== 'attack') { st.timer = 0; st.plan = chance(st.punish || 0) ? 'attack' : 'approach'; }
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
    const wantsKill = tv.percent > 90 && chance(L.kill);
    // Archetype-flavoured aggression. The archetype strings come from the WEAPON, so these are
    // the four that exist: All-rounder, Reach / combo, Zoner, Heavy zoner.
    if (f.char.archetype === 'Heavy zoner' && tv.state === 'attack' && chance(0.4)) { frame.y = -1; frame.heavy = true; st.plan = 'approach'; return frame; }
    if (f.char.archetype === 'Reach / combo' && chance(0.35)) { frame.grab = true; st.plan = 'approach'; return frame; }
    if (wantsKill) { frame.x = dir; frame.heavy = true; }
    else if (tv.state === 'shield' && chance(0.6)) { frame.grab = true; }
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
  const targetOff = tv.x < main.x1 - 1 || tv.x > main.x2 + 1;
  // Only chase what can be chased AND returned from. Without the jump check a confident bot walks
  // off the edge after someone it cannot reach and takes itself out.
  const canComeBack = f.jumpsLeft > 0 && Math.abs(tv.x - main.cx) < Math.abs(main.x2 - main.cx) + 16;
  if (targetOff && canComeBack && f.onGround && !offStage && chance(L.edge)) {
    const outward = sign(tv.x - main.cx);
    // Ranged weapons cover the ledge from safety; melee has to commit to the chase.
    if (f.char.archetype === 'Zoner' || f.char.archetype === 'Heavy zoner') {
      frame.x = outward; frame.heavy = true; st.plan = 'approach'; return frame;
    }
    if (Math.abs(f.x - main.cx) > Math.abs(main.x2 - main.cx) - 6 && tv.y < f.y - 1) {
      // standing on the lip and they are below it: a down-air is the kill, but only commit when
      // there is a real chance of getting back
      if (f.jumpsLeft > 1 && chance(0.5)) { frame.jump = true; st.plan = 'chase'; st.hold = 10; return frame; }
      frame.y = -1; frame.light = true; return frame;
    }
    frame.x = outward;
    return frame;
  }
  if (plan === 'chase') {
    frame.x = sign(tv.x - f.x);
    if (Math.abs(dy) < 4 && adx < 5) { frame.y = -1; frame.light = true; st.plan = 'approach'; return frame; }
    if (--st.hold <= 0 || f.y < tv.y - 4) st.plan = 'approach';
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
