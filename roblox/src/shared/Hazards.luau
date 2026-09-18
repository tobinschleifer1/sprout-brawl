--!nonstrict
-- Stage hazards, ported 1:1 from web/src/engine/hazards.js.
--
-- Every hazard is one entry in HAZARDS with the same shape:
--
--   step(h, ctx)   run once a frame. `h` is the stage's hazard data plus `h.state` (scratch that
--                  survives between frames). `ctx` is { stage, match, fighters, visual }.
--                  Write to `ctx.visual[key]` to tell the renderer what to draw.
--
-- The rule the file is built around: a hazard is PRESSURE, never an execution. Nothing here KOs on
-- its own. Hazards push, lift, carry, slow and chip; they can throw you into a blast zone, but the
-- kill is always the geometry finishing what the hazard started, and the player always had frames
-- in which to do something about it.
--
-- Two Luau-specific traps live in here, and neither is visible on a read:
--   * `Math.round` rounds halves toward +infinity; math.round rounds them AWAY FROM ZERO. The
--     sprinkler snaps its slick to a 3-stud grid with Math.round(x / 3), and x is negative over
--     half the stage. The two only disagree when x / 3 lands exactly on a half, which a
--     smoothstepped sweep essentially never does - swapping jsRound for math.round passes the
--     whole parity trace - so this is faithfulness rather than a live bug. It stays because the
--     day something feeds this integers, it stops being theoretical.
--   * `splice(i, 1)` walks backwards over a 0-indexed array; the Luau loops are 1-indexed.

local Config = require(script.Parent.Config)

local FRAME = Config.FRAME

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end

-- Smooth 0->1->0 over a normalised span, so no hazard switches on at full strength in one frame.
local function bell(k: number): number
	return math.sin(clamp(k, 0, 1) * math.pi)
end

local function smooth(k: number): number
	local c = clamp(k, 0, 1)
	return c * c * (3 - 2 * c)
end

-- JavaScript's Math.round, which is not Luau's. See the header.
local function jsRound(v: number): number
	return math.floor(v + 0.5)
end

-- A hazard's cycle, as a phase name plus how far through that phase we are. Every hazard has the
-- same shape - quiet, then a warning, then the event - and that consistency is most of what makes
-- a stage learnable.
local function cyclePhase(s: any, period: number, warnSeconds: number, activeSeconds: number): any
	s.timer = (s.timer or 0) + FRAME
	local t = s.timer % period
	local warnStart = period - warnSeconds - activeSeconds
	local activeStart = period - activeSeconds
	if t >= activeStart then
		return { phase = "active", k = (t - activeStart) / activeSeconds, t = t }
	end
	if t >= warnStart then
		return { phase = "warn", k = (t - warnStart) / warnSeconds, t = t }
	end
	return { phase = "idle", k = (t - 0) / math.max(0.001, warnStart), t = t }
end

-- Everyone alive and touchable. Hazards skip fighters who are dead, respawning or invincible.
local function targets(ctx: any): { any }
	local out = {}
	for _, f in ctx.fighters do
		if f.alive and not f.untouchable and f.state ~= "respawn" and f.state ~= "ko" then
			table.insert(out, f)
		end
	end
	return out
end

-- Everyone a hazard may PUSH. The extra rule is that a fighter already in hitstun or tumbling is
-- off limits: a hazard may create a kill, it must never cancel one somebody else earned.
local function pushable(ctx: any): { any }
	local out = {}
	for _, f in targets(ctx) do
		if f.state ~= "hitstun" and not f.tumbling then
			table.insert(out, f)
		end
	end
	return out
end

local HAZARDS: { [string]: any } = {}

-- ---------------------------------------------------------------- STEAM VENTS (Smeltworks)
HAZARDS.vents = {
	step = function(h, ctx)
		local s = h.state
		local c = cyclePhase(s, h.period, h.warn / 60, h.erupt / 60)
		s.phase = c.phase
		-- ONE grate per cycle, alternating. Arming every vent every time meant nobody on
		-- Smeltworks was ever on the ground; it also makes the stage readable, because the grate
		-- about to blow is the one glowing and the other one is safe.
		local cycleId = math.floor(s.timer / h.period)
		if s.cycleId ~= cycleId then
			s.cycleId = cycleId
			s.armed = { h.positions[(cycleId % #h.positions) + 1] }
		end
		local armed = s.armed or h.positions
		local strength = if c.phase == "active" then bell(c.k) else 0
		ctx.visual.vents = { phase = c.phase, k = c.k, positions = h.positions, armed = armed,
			width = h.width, strength = strength }
		if c.phase ~= "active" then
			return
		end
		local half = h.width / 2
		for _, f in pushable(ctx) do
			local over = false
			for _, px in armed do
				if math.abs(f.x - px) < half + f.r then
					over = true
					break
				end
			end
			if over and f.y <= h.reach then    -- the column has a top; above it, nothing
				-- Sustained lift, ramped by the bell. Neither is hitstun, so you keep control the
				-- whole way up.
				f.env.updraft += h.lift * strength
				if f.onGround then
					f.onGround = false
					f.platform = nil
					f.vy = math.max(f.vy, h.lift * 0.16 * strength)
				end
			end
		end
	end,
}

-- ---------------------------------------------------------------- SLAG DRIP (Smeltworks)
HAZARDS.slagfall = {
	step = function(h, ctx)
		local s = h.state
		s.timer = (s.timer or 0) + FRAME
		s.drops = s.drops or {}
		s.next = (s.next or 0) - FRAME
		if s.next <= 0 then
			-- From the stage's seeded generator, not an unseeded one: this is the only stochastic
			-- hazard in the game, and one unseeded call makes a whole match unreplayable.
			s.next = h.every * (0.6 + ctx.stage.rng() * 0.8)
			table.insert(s.drops, { x = h.x + (ctx.stage.rng() - 0.5) * h.spread, y = h.from,
				vy = 0, hit = false, life = 0 })
		end
		for i = #s.drops, 1, -1 do
			local d = s.drops[i]
			d.vy -= 90 * FRAME
			d.y += d.vy * FRAME
			d.life += FRAME
			-- A drop lands on whatever is under it, splashes, and is gone. It never pools, because
			-- a permanent damaging patch on the only crossing would just close the crossing.
			local surf = ctx.stage:surfaceUnder(d.x, d.y)
			if not d.hit then
				for _, f in targets(ctx) do
					if math.abs(f.x - d.x) < f.r + 0.5 and d.y > f.y and d.y < f.y + f.h then
						d.hit = true
						ctx.match.combat:hazardHit(f, { damage = h.damage, launch = h.launch,
							angle = 78, x = d.x, y = d.y })
						break
					end
				end
			end
			if d.hit or (surf and d.y <= surf.top + 0.4) or d.y < ctx.stage.blast.bottom then
				if not d.splash then
					d.splash = 1
					d.y = if surf then surf.top + 0.3 else d.y
					d.vy = 0
				end
				d.splash -= FRAME * 4
				if d.splash <= 0 then
					table.remove(s.drops, i)
				end
			end
		end
		local shown = {}
		for _, d in s.drops do
			table.insert(shown, { x = d.x, y = d.y, splash = d.splash or 0 })
		end
		ctx.visual.slagfall = { drops = shown, from = h.from, x = h.x, spread = h.spread }
	end,
}

-- ---------------------------------------------------------------- SPRINKLER (Rooftops)
-- The jet is four seconds; the slick it leaves behind is ten. Long after the water has gone the
-- fight is still being shaped by where it went.
HAZARDS.sprinkler = {
	step = function(h, ctx)
		local s = h.state
		local c = cyclePhase(s, h.period, h.tick / 60, h.sweepSeconds)
		s.wet = s.wet or {}
		local m = ctx.stage.main
		if c.phase == "active" then
			local dir = if math.floor(s.timer / h.period) % 2 ~= 0 then -1 else 1  -- alternates
			local from = if dir > 0 then m.x1 - 8 else m.x2 + 8
			local to = if dir > 0 then m.x2 + 8 else m.x1 - 8
			s.x = from + (to - from) * smooth(c.k)
			s.dir = dir
			for _, f in pushable(ctx) do
				if not (f.y < m.top - 8 or f.y > h.height) then   -- the jet has a top and a bottom
					local d = math.abs(f.x - s.x)
					if d <= h.radius + f.r then
						local falloff = 1 - d / (h.radius + f.r)
						-- Pushed the way the jet is going, not away from it: the sweep herds you
						-- toward a ledge rather than shoving you off wherever you stand.
						f.env.windX += dir * h.push * falloff
						if not f.onGround then
							f.env.updraft -= h.push * 0.25 * falloff
						end
					end
				end
			end
			-- lay down the slick behind the jet
			local surf = ctx.stage:surfaceUnder(s.x, m.top + 2)
			if surf then
				-- jsRound, NOT math.round: s.x is negative over half the stage.
				local cell = jsRound(s.x / 3) * 3
				local found = nil
				for _, w in s.wet do
					if w.x == cell then
						found = w
						break
					end
				end
				if found then
					found.life = h.wetSeconds
				else
					table.insert(s.wet, { x = cell, y = surf.top, life = h.wetSeconds })
				end
			end
		else
			s.phase = c.phase
		end
		-- Hoisted out of the loop: with ~20-25 live slicks this called pushable() once per cell per
		-- frame, in a file whose header claims it does not allocate.
		local wetTargets = pushable(ctx)
		for i = #s.wet, 1, -1 do
			local w = s.wet[i]
			w.life -= FRAME
			if w.life <= 0 then
				table.remove(s.wet, i)
			else
				for _, f in wetTargets do
					if f.onGround and math.abs(f.x - w.x) <= 2.2 and math.abs(f.y - w.y) <= 1.5 then
						local soak = clamp(w.life / h.wetSeconds, 0, 1)
						f.env.traction *= 1 - h.slip * soak
						f.env.grip *= 1 - h.slip * 0.6 * soak
					end
				end
			end
		end
		local shown = {}
		for _, w in s.wet do
			table.insert(shown, { x = w.x, y = w.y, k = clamp(w.life / h.wetSeconds, 0, 1) })
		end
		ctx.visual.sprinkler = { phase = c.phase, k = c.k, x = s.x or 0, dir = s.dir or 1,
			radius = h.radius, height = h.height, wet = shown }
	end,
}

-- ---------------------------------------------------------------- ANTENNA ARC (Rooftops)
HAZARDS.antennaarc = {
	step = function(h, ctx)
		local s = h.state
		local c = cyclePhase(s, h.period, h.warn / 60, h.arc / 60)
		s.phase = c.phase
		if c.phase == "active" then
			-- Per fighter, not global. A single shared `lastHit` was consumed by whoever was
			-- checked first, leaving players 2 through 4 permanently immune - invisible to a
			-- two-player suite.
			s.lastHit = s.lastHit or {}
			for _, f in targets(ctx) do
				if not (f.x < h.x1 or f.x > h.x2)
					and not (f.y + f.h < h.y - h.thickness or f.y > h.y + h.thickness) then
					local last = if s.lastHit[f.index] ~= nil then s.lastHit[f.index] else -999
					if ctx.match.frame - last >= 30 then
						s.lastHit[f.index] = ctx.match.frame
						ctx.match.combat:hazardHit(f, { damage = h.damage, launch = h.launch,
							angle = 88, x = f.x, y = h.y })
					end
				end
			end
		end
		ctx.visual.antennaarc = { phase = c.phase, k = c.k, x1 = h.x1, x2 = h.x2, y = h.y }
	end,
}

-- ---------------------------------------------------------------- DUST DEVIL (Saltflat)
-- It CARRIES: step inside and you are drawn to the core, lifted, and spun up the funnel until it
-- spits you out of the top. Almost no damage, and you keep air control the whole time.
HAZARDS.dustdevil = {
	step = function(h, ctx)
		local s = h.state
		s.timer = (s.timer or 0) + FRAME
		local t = s.timer % h.period
		local start = h.period - h.crossSeconds - h.warn
		local crossStart = h.period - h.crossSeconds
		local m = ctx.stage.main
		if t >= crossStart then
			if not s.active then
				s.active = true
				s.dir = s.nextDir or 1
				s.caught = {}
			end
			local k = (t - crossStart) / h.crossSeconds
			-- It crosses the ISLAND, not the sky beyond it. The east turnaround is pulled in
			-- further so the funnel never enters the sandfall's column: two hazards sharing a strip
			-- of ground is not depth, it is noise.
			local east = m.x2 - (h.eastStop or 0) + 5
			local west = m.x1 + (h.westStop or 0) - 5
			local from = if s.dir > 0 then west else east
			local to = if s.dir > 0 then east else west
			s.x = from + (to - from) * k
			s.spin = (s.spin or 0) + FRAME * 9
			for _, f in pushable(ctx) do
				local dx = f.x - s.x
				local up = clamp((f.y - m.top) / h.height, 0, 1)
				-- The funnel is a cone: narrow at the ground, wide at the top.
				local rAt = h.radius * (0.45 + 0.55 * up)
				if math.abs(dx) > rAt + f.r or f.y + f.h < m.top - 2 or f.y > m.top + h.height then
					s.caught[f.index] = nil
				else
					local held = (s.caught[f.index] or 0) + 1
					s.caught[f.index] = held
					local grip = 1 - math.abs(dx) / (rAt + f.r)
					-- pulled toward the core, lifted up it, and dragged along with its travel
					f.env.windX += (-sign(dx) * h.pull * grip) + (s.dir * h.drag * grip)
					f.env.updraft += h.lift * grip
					if f.onGround and grip > 0.35 then
						f.onGround = false
						f.platform = nil
						f.vy = math.max(f.vy, 10)
					end
					-- Held long enough and it throws you out of the top. One small hit, upward, so
					-- the exit reads as an event and not a ring-out.
					if held >= h.throwAfter then
						s.caught[f.index] = 0
						ctx.match.combat:hazardHit(f, { damage = h.damage, launch = h.launch,
							angle = h.angle, x = s.x, y = f.y + 2 })
					end
				end
			end
		elseif s.active then
			s.active = false
			s.nextDir = -s.dir                              -- it comes back the other way
		end
		local warning = t >= start and t < crossStart
		ctx.visual.dustdevil = {
			active = s.active, warn = warning,
			warnK = if warning then (t - start) / h.warn else 0,
			x = s.x or 0, dir = s.dir or 1, spin = s.spin or 0, radius = h.radius, height = h.height,
			from = if (s.nextDir or 1) > 0 then m.x1 else m.x2,
		}
	end,
}

-- ---------------------------------------------------------------- SANDFALL (Saltflat)
HAZARDS.sandfall = {
	step = function(h, ctx)
		local s = h.state
		local c = cyclePhase(s, h.period, h.warn / 60, h.pourSeconds)
		s.phase = c.phase
		if c.phase == "active" then
			local strength = bell(c.k)
			for _, f in pushable(ctx) do
				if math.abs(f.x - h.x) <= h.width / 2 + f.r
					and not (f.y > h.from or f.y + f.h < h.to) then
					f.env.updraft -= h.push * strength     -- pushed DOWN, which is the whole point
					f.env.windX += sign(h.x - f.x) * h.push * 0.2 * strength
				end
			end
		end
		ctx.visual.sandfall = { phase = c.phase, k = c.k, x = h.x, width = h.width,
			from = h.from, to = h.to }
	end,
}

-- ---------------------------------------------------------------- TIDE (Undertow)
-- Water is a second set of physics: slow, buoyant, and knockback is DAMPED. At 140% the water is
-- the safest place on the stage and also the place you cannot fight from.
HAZARDS.tide = {
	step = function(h, ctx)
		local s = h.state
		s.timer = (s.timer or 0) + FRAME
		local t = s.timer % h.period
		local riseStart = h.period - (h.rise + h.hold + h.fall)
		local level, phase = h.low, "low"
		if t >= riseStart and t < riseStart + h.rise then
			level = h.low + (h.high - h.low) * smooth((t - riseStart) / h.rise)
			phase = "rising"
		elseif t >= riseStart + h.rise and t < riseStart + h.rise + h.hold then
			level = h.high
			phase = "high"
		elseif t >= riseStart + h.rise + h.hold then
			level = h.high - (h.high - h.low) * smooth((t - riseStart - h.rise - h.hold) / h.fall)
			phase = "falling"
		end
		-- a slow swell on top of the tide, so the surface is never a straight line
		s.swell = (s.swell or 0) + FRAME
		ctx.stage.waterLevel = level
		local m = ctx.stage.main
		for _, f in ctx.fighters do
			if not f.alive then
				f.inWater = false
			else
				local surfaceHere = level + math.sin(s.swell * 1.1 + f.x * 0.12) * h.swell
				local outside = math.abs(f.x) > h.edge or f.y < m.bottom
				local inWater = f.y < surfaceHere and outside
				f.inWater = inWater
				if inWater and f.state ~= "hitstun" and not f.tumbling then
					local under = surfaceHere - f.y
					-- Buoyancy reaches `h.depth` studs down and no further. Without a floor the
					-- surface was a permanent refuge; below the depth you are simply falling, in
					-- water. Tapered at the surface and damped, because an undamped spring is not
					-- buoyancy.
					local depth = clamp(1 - under / h.depth, 0, 1) * clamp(under / 1.5, 0, 1)
					f.env.updraft += h.buoyancy * depth
					f.vy *= 0.90                            -- water is viscous; it does not ring
					f.env.windX += sign(if f.x ~= 0 then f.x else 1) * h.drift
					f.env.damp = math.min(f.env.damp, h.damp)
				end
			end
		end
		ctx.visual.tide = { level = level, phase = phase, edge = h.edge, swell = s.swell, amp = h.swell }
	end,
}

-- ---------------------------------------------------------------- ROGUE WAVE (Undertow)
HAZARDS.roguewave = {
	step = function(h, ctx)
		local s = h.state
		s.timer = (s.timer or 0) + FRAME
		local t = s.timer % h.period
		-- `at` pins the crossing to a moment in the cycle instead of hanging it off the end of the
		-- period, which used to put the crest below the island's own bottom edge for 83% of its
		-- travel.
		local crossStart = if h.at ~= nil then h.at else h.period - h.crossSeconds
		local start = crossStart - h.warn
		local m = ctx.stage.main
		if t >= crossStart and t < crossStart + h.crossSeconds then
			if not s.active then
				s.active = true
				s.dir = s.nextDir or 1
			end
			local k = (t - crossStart) / h.crossSeconds
			local from = if s.dir > 0 then m.x1 - 30 else m.x2 + 30
			s.x = from + (if s.dir > 0 then 1 else -1) * (m.w + 60) * k
			local lvl = if ctx.stage.waterLevel ~= nil then ctx.stage.waterLevel else 0
			for _, f in pushable(ctx) do
				local d = math.abs(f.x - s.x)
				if d <= h.width / 2 + f.r
					and not (f.y > lvl + h.crest or f.y + f.h < lvl - 4) then
					local g = 1 - d / (h.width / 2 + f.r)
					f.env.windX += s.dir * h.push * g
					f.env.updraft += h.lift * g
				end
			end
		elseif s.active then
			s.active = false
			s.nextDir = -s.dir
		end
		local warning = t >= start and t < crossStart
		ctx.visual.roguewave = {
			active = s.active, warn = warning,
			warnK = if warning then (t - start) / h.warn else 0,
			x = s.x or 0, dir = s.dir or 1, width = h.width, crest = h.crest,
		}
	end,
}

-- ---------------------------------------------------------------- CROSSWIND (The Span, ranked)
-- No damage, no stun, strictly alternating on a long cycle - but it changes every recovery and
-- every edgeguard, which is as much as a ranked layout should ever do.
HAZARDS.crosswind = {
	step = function(h, ctx)
		local s = h.state
		s.timer = (s.timer or 0) + FRAME
		local t = s.timer % h.period
		local gustStart = h.period - h.gustSeconds
		local warnStart = gustStart - h.warn
		local strength, phase = 0, "calm"
		if t >= gustStart then
			phase = "gust"
			strength = bell((t - gustStart) / h.gustSeconds)
		elseif t >= warnStart then
			phase = "warn"
		end
		if s.cycleId ~= math.floor(s.timer / h.period) then
			s.cycleId = math.floor(s.timer / h.period)
			s.dir = -(s.dir or -1)                          -- strictly alternating: learnable
		end
		local dir = s.dir or 1
		if phase == "gust" then
			for _, f in pushable(ctx) do
				if not f.onGround then                      -- grounded play is untouched
					f.env.windX += dir * h.push * strength
				end
			end
		end
		ctx.visual.crosswind = { phase = phase, dir = dir, strength = strength, k = t / h.period }
	end,
}

-- ---------------------------------------------------------------- EMBER DRIFT (Foundry Floor)
-- The columns sit OFF the stage, just outside each ledge. Centre-stage neutral is untouched; what
-- changes is edgeguarding. It only ever slows a FALL, so it is not a free extra jump.
HAZARDS.emberdrift = {
	step = function(h, ctx)
		local s = h.state
		s.timer = (s.timer or 0) + FRAME
		local pulse = 0.75 + 0.25 * math.sin(s.timer * 0.9)  -- a slow breathe, never a surprise
		for _, f in pushable(ctx) do
			if not f.onGround and not (f.y < h.from or f.y > h.to) then
				local inColumn = false
				for _, px in h.positions do
					if math.abs(f.x - px) < h.width / 2 + f.r then
						inColumn = true
						break
					end
				end
				if inColumn and f.vy < 0 then
					f.env.updraft += h.lift * pulse
				end
			end
		end
		ctx.visual.emberdrift = { positions = h.positions, width = h.width, from = h.from,
			to = h.to, pulse = pulse, t = s.timer }
	end,
}

local Hazards = { HAZARDS = HAZARDS, clamp = clamp, bell = bell, smooth = smooth }

function Hazards.step(h: any, ctx: any)
	local def = HAZARDS[h.type]
	if not def then
		return
	end
	if not h.state then
		h.state = {}
	end
	def.step(h, ctx)
end

return Hazards
