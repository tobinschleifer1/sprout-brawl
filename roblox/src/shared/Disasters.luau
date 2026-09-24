--!strict
-- Natural disasters, ported from web/src/engine/disasters.js. The JavaScript is the source of truth
-- and tests/disaster-parity.luau replays it frame for frame; read that file for the design and the
-- contract every disaster keeps. Port notes, each a trap this repo has already fallen into once:
--   * `sign` returns 1 for 0 in both builds (unlike math.sign), so no `|| 1` guard is needed; a
--     mutation test showed the guard could not change anything, and it was deleted from both.
--   * the chaos pool is built in ORDER, never by iterating DISASTERS - Luau has no key order.
--   * distances use math.sqrt, as the JavaScript does, never a hypot.
--   * `d.hit` / `d.cool` are tables keyed by fighter index, the JavaScript's Set / Map.
local Config = require(script.Parent.Config)
local Knockback = require(script.Parent.Knockback)

local FRAME = Config.FRAME
local SHIELD = Config.SHIELD

local Disasters = {}

Disasters.MODES = { "off", "stage", "chaos" }
Disasters.FIRST_AT = 45
Disasters.GAP = { 40, 55 }
Disasters.MIN_WARN = 90
Disasters.ORDER = { "lavasurge", "lightning", "tornado", "tsunami", "earthquake", "meteor" }

local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end
local function sign(v: number): number
	return if v < 0 then -1 else 1
end

local function targets(ctx: any): { any }
	local out = {}
	for _, f in ctx.fighters do
		if f.alive and not f.untouchable and f.state ~= "respawn" and f.state ~= "ko" then
			table.insert(out, f)
		end
	end
	return out
end

function Disasters.hit(ctx: any, f: any, p: any): boolean
	if f.untouchable then
		return false
	end
	local facing = if p.facing ~= nil then p.facing else sign(f.x - p.x)
	if f.state == "shield" and p.blockable ~= false then
		local perfect = f.sf <= SHIELD.perfectFrames
		f:applyBlock({ damage = p.damage, facing = facing, perfect = perfect })
		ctx.match.combat:emit({ type = "block", x = f.x, y = f.cy, perfect = perfect, victim = f.index, disaster = p.kind })
		return true
	end
	local after = f.percent + p.damage
	local launch = Knockback.launchSpeed(p.base, p.growth, p.damage, after, f.weight)
	local stun = Knockback.stunSpeed(p.base, p.growth, p.damage, after, f.weight)
	f:applyHit({ damage = p.damage, launch = launch, stun = stun, angle = p.angle, facing = facing,
		attacker = nil, hitlag = if p.hitlag ~= nil then p.hitlag else 6 })
	ctx.match.combat:emit({ type = "hit", x = f.x, y = f.cy, damage = p.damage, launch = launch, heavy = false,
		weight = f.weight, attacker = -1, victim = f.index, angle = p.angle, facing = facing, disaster = p.kind })
	return true
end

local function chip(ctx: any, f: any, damage: number, kind: string)
	if f.untouchable then
		return
	end
	f.percent = math.min(999, f.percent + damage)
	f.stats.damageTaken += damage
	ctx.match.combat:emit({ type = "chip", x = f.x, y = f.cy, damage = damage, victim = f.index, disaster = kind })
end

local function groundSpan(stage: any): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, s in stage.solids do
		lo, hi = math.min(lo, s.x1), math.max(hi, s.x2)
	end
	return lo, hi
end
local function surfaceY(stage: any, x: number): number
	local s = stage:surfaceUnder(x, 999)
	return if s then s.top else stage.main.top
end
local function merge(a: any, b: any?): any
	local out = table.clone(a)
	for k, v in b or {} do
		out[k] = v
	end
	return out
end

local D: { [string]: any } = {}
Disasters.DISASTERS = D

D.lavasurge = {
	warn = 120, strike = 360, after = 120, chaos = false,
	params = { line = 3, low = -14, damage = 14, base = 55, growth = 0.25, angle = 90, cooldown = 60 },
	begin = function(d: any)
		d.level = d.p.low
		d.cool = {}
	end,
	step = function(d: any, ctx: any, phase: string, k: number)
		local p = d.p
		if phase == "strike" then
			d.level = p.low + (p.line - p.low) * clamp(k * 6, 0, 1)
		elseif phase == "after" then
			d.level = p.line + (p.low - p.line) * clamp(k, 0, 1)
		else
			d.level = p.low
		end
		for i, t in d.cool do
			if t > 0 then d.cool[i] = t - 1 end
		end
		if phase == "warn" then return end
		for _, f in targets(ctx) do
			if f.y >= d.level or (d.cool[f.index] or 0) > 0 then continue end
			d.cool[f.index] = p.cooldown
			Disasters.hit(ctx, f, { kind = "lavasurge", damage = p.damage, base = p.base, growth = p.growth,
				angle = p.angle, x = f.x, blockable = false })
		end
	end,
	visual = function(d: any): any
		return { level = d.level, line = d.p.line }
	end,
}

D.lightning = {
	warn = 90, strike = 4 * 40 + 3 * 12 + 6, after = 30, chaos = true,
	params = { waves = 4, perWave = 3, waveGap = 40, stagger = 12, markWarn = 90, bolt = 6, width = 2.5,
		damage = 11, base = 40, growth = 0.3, angle = 80, pull = 8, rods = {} },
	begin = function(d: any, ctx: any)
		local p = d.p
		local lo, hi = groundSpan(ctx.stage)
		d.strikes = {}
		for w = 0, p.waves - 1 do
			for s = 0, p.perWave - 1 do
				local x = lo + 3 + ctx.stage.rng() * (hi - lo - 6)
				for _, r in p.rods do
					if math.abs(x - r) < p.pull then x = r end
				end
				table.insert(d.strikes, { x = x, at = w * p.waveGap + s * p.stagger, hit = {} })
			end
		end
	end,
	step = function(d: any, ctx: any, _phase: string, _k: number, frame: number)
		local p = d.p
		for _, s in d.strikes do
			local t = frame - s.at
			s.live = t >= p.markWarn and t < p.markWarn + p.bolt
			s.marked = t >= 0 and t < p.markWarn
			if not s.live then continue end
			for _, f in targets(ctx) do
				if s.hit[f.index] or math.abs(f.x - s.x) > p.width + f.r then continue end
				s.hit[f.index] = true
				Disasters.hit(ctx, f, { kind = "lightning", damage = p.damage, base = p.base, growth = p.growth,
					angle = p.angle, x = s.x, hitlag = 12 })
			end
		end
	end,
	visual = function(d: any, ctx: any): any
		local strikes = {}
		for _, s in d.strikes do
			if s.marked or s.live then
				table.insert(strikes, { x = s.x, y = surfaceY(ctx.stage, s.x), live = not not s.live })
			end
		end
		return { strikes = strikes }
	end,
}

D.tornado = {
	warn = 120, strike = 720, after = 60, chaos = true,
	params = { speed = 9, radiusTop = 5, radiusFloor = 1.5, height = 16, damage = 8, base = 45, growth = 0.6, angle = 75, pull = 14 },
	begin = function(d: any, ctx: any)
		local lo, hi = groundSpan(ctx.stage)
		d.dir = if ctx.stage.rng() < 0.5 then 1 else -1
		d.x = if d.dir > 0 then lo - 4 else hi + 4
		d.floor = ctx.stage.main.top
		d.hit = {}
	end,
	step = function(d: any, ctx: any, phase: string)
		local p = d.p
		if phase ~= "strike" then return end
		d.x += d.dir * p.speed * FRAME
		for _, f in targets(ctx) do
			local up = f.y - d.floor
			if up < -1 or up > p.height then continue end
			local r = p.radiusFloor + (p.radiusTop - p.radiusFloor) * clamp(up / p.height, 0, 1)
			local dx = f.x - d.x
			if math.abs(dx) <= r + f.r then
				if d.hit[f.index] then continue end
				d.hit[f.index] = true
				Disasters.hit(ctx, f, { kind = "tornado", damage = p.damage, base = p.base, growth = p.growth,
					angle = p.angle, facing = d.dir, x = d.x })
			elseif math.abs(dx) < r * 3 and not f.onGround and f.state ~= "hitstun" and not f.tumbling then
				f.env.windX += -sign(dx) * p.pull
			end
		end
	end,
	visual = function(d: any): any
		return { x = d.x, floor = d.floor, height = d.p.height, radiusTop = d.p.radiusTop,
			radiusFloor = d.p.radiusFloor, dir = d.dir }
	end,
}

D.tsunami = {
	warn = 150, strike = 480, after = 180, chaos = false,
	params = { speed = 30, crest = 10, width = 6, base0 = -9, damage = 16, base = 50, growth = 0.35, angle = 30, current = 20 },
	begin = function(d: any, ctx: any)
		d.dir = if ctx.stage.rng() < 0.5 then 1 else -1
		d.x = if d.dir > 0 then ctx.stage.blast.left else ctx.stage.blast.right
		d.hit = {}
	end,
	step = function(d: any, ctx: any, phase: string, k: number)
		local p = d.p
		if phase == "warn" then return end
		local strength = if phase == "after" then 1 - k else 1
		if phase == "strike" then d.x += d.dir * p.speed * FRAME end
		for _, f in targets(ctx) do
			local behind = (d.x - f.x) * d.dir > 0
			local inCrest = phase == "strike" and math.abs(f.x - d.x) <= p.width / 2 + f.r and f.y < p.crest and f.y > p.base0 - 2
			if inCrest and not d.hit[f.index] then
				d.hit[f.index] = true
				Disasters.hit(ctx, f, { kind = "tsunami", damage = p.damage, base = p.base, growth = p.growth,
					angle = p.angle, facing = d.dir, x = d.x })
			elseif behind and f.y < p.crest and f.state ~= "hitstun" and not f.tumbling then
				f.env.windX += d.dir * p.current * strength
			end
		end
	end,
	visual = function(d: any): any
		return { x = d.x, dir = d.dir, crest = d.p.crest, width = d.p.width, base = d.p.base0 }
	end,
}

D.earthquake = {
	warn = 120, strike = 280, after = 30, chaos = true,
	params = { drop = 4, dropFrames = 10, lockFrames = 90, damage = 6, base = 40, growth = 0.2, angle = 90, tremorDamage = 3, tremorBase = 30 },
	begin = function(d: any, ctx: any)
		local solids = ctx.stage.solids
		d.plates = {}
		if #solids >= 3 then
			-- JavaScript's reduce keeps the FIRST extreme on a tie; so do these strict comparisons.
			local left, right = solids[1], solids[1]
			for _, s in solids do
				if s.x1 < left.x1 then left = s end
			end
			for _, s in solids do
				if s.x2 > right.x2 then right = s end
			end
			local inner = {}
			for _, s in solids do
				if s ~= left and s ~= right then table.insert(inner, s) end
			end
			local pool = inner
			if #pool == 0 then
				pool = {}
				for i = 2, #solids do table.insert(pool, solids[i]) end
			end
			local n = if #pool > 1 and ctx.stage.rng() < 0.5 then 2 else 1
			for _ = 1, n do
				local pick = pool[math.floor(ctx.stage.rng() * #pool) + 1]
				if not table.find(d.plates, pick) then table.insert(d.plates, pick) end
			end
		end
		d.base = {}
		for i, s in d.plates do d.base[i] = s.top end
		d.done = false
	end,
	step = function(d: any, ctx: any, phase: string, k: number, frame: number)
		local p = d.p
		local t = frame - d.warn
		ctx.stage.ledgesLocked = phase == "strike" and t < p.lockFrames
		if phase == "warn" then return end
		if phase == "strike" and t == 0 and not d.done then
			d.done = true
			local tremor = #d.plates == 0
			for _, f in targets(ctx) do
				if not f.onGround then continue end
				if not tremor and not table.find(d.plates, f.platform) then continue end
				Disasters.hit(ctx, f, { kind = "earthquake", damage = if tremor then p.tremorDamage else p.damage,
					base = if tremor then p.tremorBase else p.base, growth = p.growth, angle = p.angle, x = f.x })
			end
		end
		for i, s in d.plates do
			local off = 0
			if phase == "strike" then
				off = -p.drop * clamp(t / p.dropFrames, 0, 1)
			elseif phase == "after" then
				off = -p.drop * (1 - k)
			end
			local ny = d.base[i] + off
			s.dy = ny - s.top
			s.top = ny
			s.bottom = ny - (s.thickness or 5)
			-- Stage.dynamicState ships displaced platforms to clients, so prediction and the view
			-- see the plate where the server has it.
			s.displaced = off ~= 0
		end
	end,
	finish = function(d: any, ctx: any)
		ctx.stage.ledgesLocked = false
		for i, s in d.plates do
			s.dy = d.base[i] - s.top
			s.top = d.base[i]
			s.bottom = d.base[i] - (s.thickness or 5)
			s.displaced = false
		end
	end,
	visual = function(d: any): any
		local plates = {}
		for _, s in d.plates do table.insert(plates, { x1 = s.x1, x2 = s.x2, top = s.top }) end
		return { plates = plates }
	end,
}

D.meteor = {
	warn = 100, strike = 3 * 70 + 104, after = 180, chaos = true,
	params = { waves = 3, perWave = 6, waveGap = 70, shadow = 100, impact = 4, radius = 5, spacing = 10,
		damage = 13, base = 50, growth = 0.3, angle = 65, crater = 180, craterRadius = 3, chip = 2, chipEvery = 30 },
	begin = function(d: any, ctx: any)
		local p = d.p
		local lo, hi = groundSpan(ctx.stage)
		d.rocks = {}
		for w = 0, p.waves - 1 do
			local wave: { any } = {}
			local tries = 0
			while #wave < p.perWave and tries < 60 do
				local x = lo + 2 + ctx.stage.rng() * (hi - lo - 4)
				local clear = true
				for _, r in wave do
					if math.abs(r.x - x) < p.spacing then clear = false; break end
				end
				if clear then table.insert(wave, { x = x, at = w * p.waveGap, hit = {} }) end
				tries += 1
			end
			for _, r in wave do table.insert(d.rocks, r) end
		end
	end,
	step = function(d: any, ctx: any, _phase: string, _k: number, frame: number)
		local p = d.p
		for _, r in d.rocks do
			local t = frame - r.at
			r.y = surfaceY(ctx.stage, r.x)
			r.shadow = if t >= 0 and t < p.shadow then t / p.shadow else 0
			r.live = t >= p.shadow and t < p.shadow + p.impact
			r.burning = t >= p.shadow + p.impact and t < p.shadow + p.impact + p.crater
			for _, f in targets(ctx) do
				local dx, dy = f.x - r.x, f.cy - r.y
				if r.live and not r.hit[f.index] and math.sqrt(dx * dx + dy * dy) <= p.radius + f.r then
					r.hit[f.index] = true
					Disasters.hit(ctx, f, { kind = "meteor", damage = p.damage, base = p.base, growth = p.growth,
						angle = p.angle, facing = sign(dx), x = r.x })
				elseif r.burning and f.onGround and math.abs(dx) <= p.craterRadius and (t - p.shadow - p.impact) % p.chipEvery == 0 then
					chip(ctx, f, p.chip, "meteor")
				end
			end
		end
	end,
	visual = function(d: any): any
		local rocks = {}
		for _, r in d.rocks do
			if r.shadow > 0 or r.live or r.burning then
				table.insert(rocks, { x = r.x, y = r.y, shadow = r.shadow, live = not not r.live, burning = not not r.burning })
			end
		end
		return { rocks = rocks }
	end,
}

-- ------------------------------------------------------------------------------ the director ----
local Director = {}
Director.__index = Director
Disasters.Director = Director

function Director.new(mode: string?, own: { string }?, params: any?): any
	local m = if mode and table.find(Disasters.MODES, mode) then mode else "off"
	return setmetatable({ mode = m, own = own or {}, params = params or {}, clock = 0, next = nil :: number?, active = nil :: any }, Director)
end

function Director.pool(self: any): { string }
	if self.params.force then return { self.params.force } end
	if self.mode == "stage" then return table.clone(self.own) end
	if self.mode == "chaos" then
		local out = table.clone(self.own)
		for _, k in Disasters.ORDER do
			if D[k].chaos and not table.find(out, k) then table.insert(out, k) end
		end
		return out
	end
	return {}
end

function Director.step(self: any, ctx: any): any
	local match = ctx.match
	if self.mode == "off" or not match or match.state ~= "fight" then
		self:finish(ctx)
		return nil
	end
	local pool = self:pool()
	if #pool == 0 then return nil end
	self.clock += FRAME
	if self.next == nil then
		self.next = if self.params.firstAt ~= nil then self.params.firstAt else Disasters.FIRST_AT
	end
	if not self.active and self.clock >= self.next then self:start(ctx, pool) end
	local a = self.active
	if not a then return nil end
	local def = D[a.type]
	local total = a.warn + def.strike + def.after
	local phase = if a.frame < a.warn then "warn" elseif a.frame < a.warn + def.strike then "strike" else "after"
	local k = if phase == "warn" then a.frame / a.warn
		elseif phase == "strike" then (a.frame - a.warn) / def.strike
		else (a.frame - a.warn - def.strike) / def.after
	def.step(a, ctx, phase, k, a.frame)
	local view = merge({ type = a.type, phase = phase, k = k, frame = a.frame, warn = a.warn, total = total }, def.visual(a, ctx))
	a.frame += 1
	if a.frame >= total then self:finish(ctx) end
	return view
end

function Director.start(self: any, ctx: any, pool: { string })
	local kind = pool[math.floor(ctx.stage.rng() * #pool) + 1]
	local def = D[kind]
	self.active = { type = kind, frame = 0, warn = math.max(Disasters.MIN_WARN, def.warn),
		p = merge(def.params, self.params[kind]) }
	def.begin(self.active, ctx)
	ctx.match.combat:emit({ type = "disaster", disaster = kind, phase = "warn" })
end

function Director.finish(self: any, ctx: any)
	if not self.active then return end
	local def = D[self.active.type]
	if def.finish then def.finish(self.active, ctx) end
	self.active = nil
	self.next = self.clock + Disasters.GAP[1] + ctx.stage.rng() * (Disasters.GAP[2] - Disasters.GAP[1])
end

return Disasters
