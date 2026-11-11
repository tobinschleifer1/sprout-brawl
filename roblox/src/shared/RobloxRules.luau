--!strict
-- Roblox-only changes to the fight's rules (the design pass's combat subject,
-- docs/reviews/combat-round1-review.md). The shared simulation is held to the web by replay, so the
-- replays switch these off (RobloxRules.on = false, before they build a match); the game plays
-- them. Each one names the review that asked for it. Nothing here draws a random number.
local RobloxRules = {}
RobloxRules.on = true

-- A launched fighter stopped by a wall (slower than Config.BOUNCE.speed, so it does not rebound)
-- keeps at most this much hitstun. Zeroing the launch and keeping all the stun held the victim in
-- reach: 20-45-hit true combos at 300% against Saltflat's bunker, 9-12 at 600% with no KO.
RobloxRules.WALL_STUN = 8

-- Falling into water (Undertow's tide) gives back what a fall into it spent: a helpless fighter
-- can act again, with its recovery and a jump. A swimmer who had used them could never leave the
-- water at low tide and drowned on the rise (the stages review; the owner, 2026-11-11).
RobloxRules.WATER_RESTORES = true

-- The bots' Roblox-only layers (BotLayers.luau), after the replayed bot's choice.
RobloxRules.BOT_LAYERS = true

-- Acting from the ledge ends the grab's invincibility, so each option's own window governs. The
-- first grab's 30 frames covered the whole getup (0 of its 25 frames vulnerable).
RobloxRules.LEDGE_ACTION_CLEARS = true

return RobloxRules
