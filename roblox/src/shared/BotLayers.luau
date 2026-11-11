--!strict
-- Roblox-only changes to how bots fight (the design pass's bot subject,
-- docs/reviews/bots-round1-review.md). The bot (Ai.luau) is held to the web by replay, so these
-- run after it, on the input frame it decided, in Ai.computeBotInput beside the Chakram's and the
-- Boots' gates, and only while RobloxRules is on (every replay switches it off). A fighter with
-- `noBotLayers` plays the shipping bot, so the two can be played against each other.
--
-- Each layer names its finding. What a bot knows of anyone else it reads through Ai's perception
-- (`view`, `sight` frames late), never live: no layer may cheat what the bot itself cannot see.
local Knockback = require(script.Parent.Knockback)
local BotLayers = {}
-- layers switched off by number, for measuring each one's share (tools/bot-ab's BOT_LAYERS_OFF)
BotLayers.off = {} :: { [number]: boolean }

-- (a function, not a comparison: strict mode refines a compared state to the wrong literal)
local function isState(f: any, s: string): boolean
	return f.state == s
end

local function sign(v: number): number
	return if v > 0 then 1 elseif v < 0 then -1 else 0
end

-- The furthest a move reaches in front (its boxes), or far for a thing it throws.
local function reach(m: any): number
	if m.kind == "projectile" or m.kind == "beam" then return 30 end
	local far = 0
	for _, hb in m.hitboxes or {} do far = math.max(far, hb.offset[1] + hb.size[1] / 2) end
	return far
end
local function launchAt(m: any, percent: number): number
	if not m.damage or not m.base then return 0 end
	return Knockback.launchSpeed(m.base, m.growth or 0, m.damage, percent + m.damage, 100)
end

-- The kill press: side + heavy, unless the side signature cannot finish and another that reaches
-- throws half again as hard at the target's percent (1. on the Blasters the press was Full Auto,
-- launch 21, beside Scattergun's 145). Swapping to the hardest-throwing signature outright put the
-- heavies on their slowest moves, and they lost to the shipping bot (Axe 5 of 24 where 17 is even).
local SIGS = { { id = "SigSide", x = 1, y = 0 }, { id = "SigDown", x = 0, y = -1 }, { id = "SigNeutral", x = 0, y = 0 } }
function BotLayers.killSignature(char: any, adx: number, percent: number): any?
	local side = char.moves.SigSide
	local sideLaunch = if side then launchAt(side, percent) else 0
	local best, bestLaunch = SIGS[1], sideLaunch * 1.5
	for _, sg in SIGS do
		local m = char.moves[sg.id]
		-- (a counter has no hitbox of its own; the Chakram's Halo needs both rings)
		if sg.id ~= "SigSide" and m and m.kind ~= "counter" and not (m.rings and m.rings > 1) and reach(m) + 1 >= adx then
			local l = launchAt(m, percent)
			if l > bestLaunch then best, bestLaunch = sg, l end
		end
	end
	return best
end

local function press(frame: any, x: number, y: number)
	frame.heavy, frame.heavyHeld, frame.light = true, true, false
	frame.x, frame.y, frame.anyPress = x, y, true
	frame.guard, frame.guardHeld = false, false
end

-- the solid under a fighter, if any (a floor it is above, within the next few studs down)
local function floorUnder(stage: any, f: any): any?
	for _, sp in stage.solids do
		if f.x > sp.x1 + 1.5 and f.x < sp.x2 - 1.5 and sp.top <= f.y + 0.5 and sp.top > f.y - 12 then return sp end
	end
	return nil
end

-- `view(v)`: what this bot sees of v (Ai's perception). `L`: its level. `rng`: the match's.
function BotLayers.apply(f: any, match: any, frame: any, L: any, view: (any) -> any, rng: () -> number): any
	local st = f.ai
	if not st or not frame then return frame end
	st.layerCd = math.max(0, (st.layerCd or 0) - 1)
	st.antiAirCd = math.max(0, (st.antiAirCd or 0) - 1)
	local stage, main = match.stage, match.stage.main
	local state: any = f.state
	if state == "respawn" or state == "ko" or state == "hitstun" or state == "ledge" or state == "grabbed" then return frame end

	-- 2. With nobody left to fight, a bot off the stage stopped pressing anything and fell. It
	--    comes home as it would with a foe alive.
	local foe: any, fv: any = nil, nil
	for _, v in match.fighters do
		if v ~= f and v.alive and v.team ~= f.team then
			local seen = view(v)
			if not fv or math.abs(seen.x - f.x) < math.abs(fv.x - f.x) then foe, fv = v, seen end
		end
	end
	local offStage = f.x < main.x1 - 0.5 or f.x > main.x2 + 0.5
	if not foe then
		if not BotLayers.off[2] and not f.onGround and (offStage or f.y < -2) and not isState(f, "helpless") then
			frame.x, frame.y = sign(main.cx - f.x), 0
			if f.jumpsLeft > 0 and f.vy < 0 and st.layerCd <= 0 then
				frame.jump, frame.anyPress = true, true; st.layerCd = 14
			elseif f.jumpsLeft == 0 and not f.recoveryUsed and f.vy < 2 then
				press(frame, 0, 1)
			end
		end
		return frame
	end

	-- 3. In water a bot spent its jumps and its recovery where the water damps them to nothing, then
	--    drowned. It swims to the nearest ledge and only jumps or recovers when one is in reach.
	if not BotLayers.off[3] and f.inWater and not isState(f, "helpless") then
		local near = stage:nearestLedge(f.x, f.cy)
		local L2 = near.ledge
		if L2 then
			local dx = L2.x - f.x
			frame.x, frame.y = sign(dx), 0
			frame.light, frame.heavy, frame.heavyHeld, frame.jump = false, false, false, false
			if math.abs(dx) < 4 and f.jumpsLeft > 0 and st.layerCd <= 0 then
				frame.jump, frame.anyPress = true, true; st.layerCd = 14
			elseif f.jumpsLeft == 0 and not f.recoveryUsed and math.abs(dx) < 6 and f.vy < 2 then
				press(frame, 0, 1)
			end
		end
		return frame
	end

	local dx, dy = fv.x - f.x, fv.y - f.y
	local adx, dir = math.abs(dx), sign(dx)

	if not f.onGround then
		-- 4. A recovery spent over a floor: the bot knew only the main platform, so over the other
		--    islands it "recovered" onto solid ground. Over a floor it goes for its foe instead.
		if not BotLayers.off[4] and frame.heavy and frame.y > 0.5 and st.noFumble and not isState(f, "attack") and floorUnder(stage, f) then
			frame.heavy, frame.heavyHeld, frame.y = false, false, 0
			frame.x = dir
		end
		-- 5. An airborne heavy outside the recovery branch is the recovery move, spent as an attack
		--    (the zoners' and the Scythe's lasso plans): it becomes a light.
		if not BotLayers.off[5] and frame.heavy and not st.noFumble and not isState(f, "attack") then
			frame.heavy, frame.heavyHeld, frame.light = false, false, true
		end
		-- 6. An air finisher could not be reached: the drift overwrote a neutral combo press as a
		--    side one.
		if not BotLayers.off[6] and isState(f, "attack") and st.combo and st.combo.dir == "neutral" and (frame.light or frame.heavy) then
			frame.x = 0
		end
		-- 8. Climbing to a foe above: the second jump at the top of the first.
		if not BotLayers.off[8] and dy > 6 and adx < 8 and f.vy < 2 and f.jumpsLeft > 0 and st.layerCd <= 0 and isState(f, "air") then
			frame.jump, frame.anyPress = true, true; st.layerCd = 14
		end
		return frame
	end

	if isState(f, "attack") or isState(f, "shield") and not frame.guardHeld then return frame end
	local neutral = f.char.moves.SigNeutral
	local upward = neutral and (neutral.angle or 0) >= 70 and neutral.kind ~= "counter"
	-- (an anti-air has to come out in time: the heavies' upward signatures start in 15-23 frames, and
	-- pressed at a foe overhead they were punished)
	local quickUp = upward and (neutral.startup or 99) <= 14

	-- 7. Neutral heavies, which no tactic pressed: an upward one against a foe overhead, and a
	--    counter (the Shield's Counterguard) in place of the shield against a swing in reach.
	if not BotLayers.off[7] and quickUp and adx < 4 and dy > 3 and dy < 12 and st.antiAirCd <= 0 and rng() < L.aggression * 0.6 then
		st.antiAirCd = 30
		press(frame, 0, 0)
		return frame
	end
	if not BotLayers.off[7] and neutral and neutral.kind == "counter" and frame.guardHeld and fv.state == "attack" and adx < 6 and math.abs(dy) < 4
		and rng() < L.defence * 0.6 then
		press(frame, 0, 0)
		return frame
	end

	-- 1. The kill press: the signature that throws hardest from here, and against a wall (the
	--    launch is soaked up sideways) an upward one.
	if not BotLayers.off[1] and frame.heavy and math.abs(frame.x) > 0.5 and math.abs(frame.y) < 0.5 then
		local walled = false
		for _, sp in stage.solids do
			if sp ~= main and fv.y < sp.top and fv.y + 2 > sp.bottom then
				local face = if dir > 0 then sp.x1 else sp.x2
				local past = (face - fv.x) * dir
				if past >= 0 and past < 12 then walled = true end
			end
		end
		if walled and upward and adx < reach(neutral) + 1 then
			press(frame, 0, 0)
		else
			local sg = BotLayers.killSignature(f.char, adx, fv.percent or 0)
			if sg then press(frame, sg.x * dir, sg.y) end
		end
		return frame
	end

	-- 8. Reaching a foe above (a player stood on a top platform was never touched in 17 of 28 runs),
	--    and dropping through a soft platform to one below: only while the bot is heading for its
	--    foe, never while it is fetching an item or a weapon drop (overriding that left bots unarmed
	--    for whole matches).
	local fetching = (st.fetch or 0) > 0 or (st.dropFetch or 0) > 0 or st.wantArm == true
	local approaching = not fetching and (frame.x == 0 or sign(frame.x) == dir)
	if not approaching then return frame end
	if not BotLayers.off[8] and dy > 6 and adx < 8 and f.jumpsLeft > 0 and st.layerCd <= 0 then
		frame.jump, frame.anyPress = true, true; frame.x = dir; st.layerCd = 14
		return frame
	end
	if not BotLayers.off[8] and f.platform and f.platform.soft and dy < -4 and adx < 12 then
		frame.y, frame.downTap, frame.x = -1, true, 0
	end
	return frame
end

return BotLayers
