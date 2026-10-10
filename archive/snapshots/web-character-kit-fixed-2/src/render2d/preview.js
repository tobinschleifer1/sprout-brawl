// A fighter that is not in a match.
//
// The animation sheet and the character creator both need to draw a fighter at an exact pose with
// no engine running. They used to be free to invent their own stand-in, and anim.html did exactly
// that for a long time - its own grey rectangles, its own transform - which meant the page used to
// review the animation was showing a different animation from the game.
//
// So there is one fake fighter, here, and it sets the same fields fighter.js sets on itself.
// `channelsFor` and `weaponPose` cannot tell the difference, and `Renderer2D.drawFighterInto`
// paints it with the real paint path. A preview that agrees with the match is not a nicety: the
// creator is the screen where a player decides what their character looks like.

export function posedFighter(loadout, moveId, mf, opts = {}) {
  const m = (moveId && loadout.moves[moveId]) || null;
  return {
    char: loadout, index: opts.index || 0, facing: opts.facing || 1, sf: mf, mf, charge: 0, frameCount: opts.frameCount != null ? opts.frameCount : mf,
    state: opts.state || (m ? 'attack' : 'idle'), move: m, moveId, startupEff: m ? m.startup : 0,
    onGround: opts.onGround !== undefined ? opts.onGround : !String(moveId).startsWith('Air'),
    platform: opts.platform || null, vy: 0, vx: opts.vx || 0,
    alive: true, hitlag: 0, invincible: 0, shield: 50, percent: 0, tumbling: false,
    fastFalling: false, ultShots: 0, ultCooldown: 0, ultHeld: [], ultActive: 0,
    h: loadout.height, r: loadout.radius, y: 0, x: 0,
    effects: { chill: { stacks: 0 }, tangle: { stacks: 0 }, grit: {}, slow: 0 },
    techRoll: 0, la: null,
  };
}
