--!strict
-- Runtime stage: platforms (including moving and sinking ones), ledges, blast zones and hazards.
-- Ported 1:1 from web/src/engine/stage.js. tests/trace-parity.luau replays recorded JavaScript
-- traces through this and fails on any divergence.
--
-- The stage owns the match's randomness. `Stage.new(data, seed)` seeds a generator that the slag
-- drip and the item spawner draw from, so everything stochastic about a match is a pure function of
-- the seed - which is what makes a server-authoritative match replayable and this port testable.

local Config = require(script.Parent.Config)
local Hazards = require(script.Parent.Hazards)
local Rng = require(script.Parent.Rng)

local FRAME = Config.FRAME
local LEDGE = Config.LEDGE

export type Platform = {
	id: string, solid: boolean, soft: boolean,
	cx: number, cy: number?, baseY: number?, w: number,
	x1: number, x2: number, top: number, bottom: number,
	dx: number, dy: number,
	thickness: number?, tris: any, moving: any,
	sinking: boolean?, sink: number?, occupiedFrames: number?,
	ledges: any,
}

export type Ledge = { x: number, y: number, side: number, platform: Platform }

local Stage = {}
Stage.__index = Stage

export type Stage = typeof(setmetatable({} :: {
	data: any, time: number, blast: { left: number, right: number, top: number, bottom: number },
	platforms: { Platform }, solids: { Platform }, main: Platform, ledges: { Ledge },
	hazards: { any }, waterLevel: number?, events: { any }, visual: any,
	seed: number, rng: () -> number,
}, Stage))

function Stage.new(data: any, seed: number?): Stage
	local self = setmetatable({}, Stage) :: any
	self.data = data
	self.time = 0
	self.seed = if seed == nil then 1 else bit32.band(seed, 0xFFFFFFFF)
	self.rng = Rng.make(self.seed)
	self.blast = { left = data.blast.left, right = data.blast.right, top = data.blast.top, bottom = data.blast.bottom }
	self.platforms = {}
	local m = data.main
	-- Deliberately the same PARTIAL shape the JavaScript builds: `main` carries no thickness, no
	-- baseY and no moving spec, because it is never sinking and never moves. Filling them in here
	-- would only change branches main cannot enter, and would make the two files differ for no
	-- reason a reader could check.
	self.main = {
		id = "main", solid = true, soft = false,
		x1 = m.x1, x2 = m.x2, top = m.y, bottom = m.y - m.thickness,
		cx = (m.x1 + m.x2) / 2, w = m.x2 - m.x1, dx = 0, dy = 0,
		thickness = nil, tris = nil, moving = nil,
		ledges = if m.ledges == nil then true else m.ledges,
	} :: Platform
	table.insert(self.platforms, self.main)
	self.solids = { self.main }

	for _, p in data.platforms do
		-- A `moving` spec can carry an `x` range, a `y` range, or both, each with its own period
		-- and phase. The old flat {from,to,period,phase} shape means "x only".
		local move = nil
		if p.moving then
			move = if p.moving.x or p.moving.y then p.moving else { x = p.moving }
		end
		local thickness = p.thickness or (if p.solid then 5 else 1)
		local built: Platform = {
			id = p.id, solid = not not p.solid, soft = not p.solid,
			cx = p.x, cy = p.y, baseY = p.y, w = p.w,
			x1 = p.x - p.w / 2, x2 = p.x + p.w / 2, top = p.y, bottom = p.y - thickness,
			dx = 0, dy = 0,
			thickness = thickness, tris = p.tris or nil,
			moving = move,
			sinking = not not p.sinking, sink = 0, occupiedFrames = 0,
			-- A solid can opt out of being grabbable, for blocks you fight on top of rather than
			-- hang off.
			ledges = if p.solid then (if p.ledges == nil then true else p.ledges) else false,
		}
		table.insert(self.platforms, built)
		if built.solid then
			table.insert(self.solids, built)
		end
	end

	-- Ledges, per edge. `ledges = false` gives none; `ledges = "outer"` gives only the edge facing
	-- away from stage centre, which is what makes a pit between two islands dangerous instead of
	-- the safest place to be knocked into.
	self.ledges = {}
	local lo, hi = math.huge, -math.huge
	for _, s in self.solids do
		lo = math.min(lo, s.x1)
		hi = math.max(hi, s.x2)
	end
	local centre = (lo + hi) / 2
	for _, sp in self.solids do
		local mode = if sp == self.main then (if sp.ledges == nil then true else sp.ledges) else sp.ledges
		if mode then
			local outerIsRight = sp.cx >= centre
			if mode ~= "outer" or not outerIsRight then
				table.insert(self.ledges, { x = sp.x1, y = sp.top, side = -1, platform = sp })
			end
			if mode ~= "outer" or outerIsRight then
				table.insert(self.ledges, { x = sp.x2, y = sp.top, side = 1, platform = sp })
			end
		end
	end

	self.hazards = {}
	for _, h in data.hazards do
		local copy = table.clone(h)
		copy.state = {}
		table.insert(self.hazards, copy)
	end
	self.waterLevel = nil
	self.events = {}
	self.visual = {}
	return self
end

-- Highest platform at or below `yMax` under `x`.
function Stage.surfaceUnder(self: Stage, x: number, yMax: number): Platform?
	local best: Platform? = nil
	for _, p in self.platforms do
		if not (x < p.x1 or x > p.x2 or p.top > yMax + 0.5) then
			if best == nil or p.top > best.top then
				best = p
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------- the viewer's copy ----
-- The platform state a client cannot work out for itself.
--
-- `moving` IS derivable - it is a pure function of stage time - but `sinking` is not: it depends
-- on which fighters are standing on the platform this frame. Sending both rather than deriving one
-- and receiving the other is deliberate: two code paths that can disagree about where the floor is
-- would be a fighter standing on air on one machine, and the disagreement would be invisible until
-- somebody fell through it.
--
-- Nil when the stage has nothing dynamic, which is four of the six, so the common case costs
-- nothing on the wire.
function Stage.dynamicState(self: Stage): { any }?
	local out = nil
	for i, p in self.platforms do
		if p.moving or p.sinking then
			out = out or {}
			table.insert(out, { i = i, cx = p.cx, top = p.top })
		end
	end
	return out
end

-- Applied to the client's view-only Stage, which is never stepped. dx/dy are set from the move so
-- anything reading them - the ledge logic, the renderer's scrape - sees the same deltas the server
-- computed rather than a platform that teleports with zero velocity.
function Stage.applyDynamicState(self: Stage, list: { any }?)
	if not list then
		return
	end
	for _, e in list do
		local p = self.platforms[e.i]
		if p then
			p.dx = e.cx - p.cx
			p.cx = e.cx
			p.x1 = e.cx - p.w / 2
			p.x2 = e.cx + p.w / 2
			p.dy = e.top - p.top
			p.top = e.top
			p.cy = e.top
			p.bottom = e.top - (p.thickness or 1)
		end
	end
end

function Stage.step(self: Stage, match: any)
	self.time += FRAME
	for _, p in self.platforms do
		p.dx = 0
		p.dy = 0
		if p.moving then
			if p.moving.x then
				local M = p.moving.x
				local t = ((self.time / M.period) + M.phase) * math.pi * 2
				local mid, amp = (M.from + M.to) / 2, (M.to - M.from) / 2
				local nx = mid + amp * math.sin(t)
				p.dx = nx - p.cx
				p.cx = nx
				p.x1 = nx - p.w / 2
				p.x2 = nx + p.w / 2
			end
			if p.moving.y then
				local M = p.moving.y
				local t = ((self.time / M.period) + M.phase) * math.pi * 2
				local mid, amp = (M.from + M.to) / 2, (M.to - M.from) / 2
				local ny = mid + amp * math.sin(t)
				p.dy = ny - p.top
				p.top = ny
				p.cy = ny
				p.bottom = ny - (p.thickness or 1)
			end
		end
		if p.sinking then
			local stood = false
			for _, f in match.fighters do
				if f.alive and f.onGround and f.platform == p then
					stood = true
					break
				end
			end
			if stood then
				p.occupiedFrames = (p.occupiedFrames :: number) + 1
				p.sink = math.min(4, (p.sink :: number) + 4 / 60)
			else
				p.occupiedFrames = 0
				p.sink = math.max(0, (p.sink :: number) - 4 / 60)
			end
			local ny = (p.baseY :: number) - (p.sink :: number)
			p.dy = ny - p.top
			p.top = ny
			p.cy = ny
			p.bottom = ny - 1
			if (p.occupiedFrames :: number) > 120 then
				for _, f in match.fighters do
					if f.onGround and f.platform == p then
						f:dropThrough()
					end
				end
				p.occupiedFrames = 0
			end
		end
	end
	-- Hazards write into each fighter's `env` bag, so it is cleared here, once, immediately before
	-- they run. Doing it anywhere else lets a force from last frame leak into this one.
	for _, f in match.fighters do
		f.env.updraft = 0
		f.env.windX = 0
		f.env.traction = 1
		f.env.grip = 1
		f.env.damp = 1
	end
	self.visual = {}
	local ctx = { stage = self, match = match, fighters = match.fighters, visual = self.visual }
	for _, h in self.hazards do
		Hazards.step(h, ctx)
	end
end

-- Sudden death closes the blast box in. It must never close past the stage itself, or there is
-- solid ground sitting outside the kill boundary and a fighter standing on it dies for nothing.
function Stage.shrink(self: Stage, factor: number)
	local l, r, t = math.huge, -math.huge, -math.huge
	for _, sp in self.solids do
		l = math.min(l, sp.x1)
		r = math.max(r, sp.x2)
		t = math.max(t, sp.top)
	end
	for _, p in self.platforms do
		t = math.max(t, p.top)
	end
	local SIDE = 14
	-- The ceiling margin has to clear a double jump (25.4 studs) or late sudden death makes
	-- jumping suicide.
	local ROOF = 30
	self.blast.left = math.min(self.blast.left * factor, l - SIDE)
	self.blast.right = math.max(self.blast.right * factor, r + SIDE)
	self.blast.top = math.max(self.blast.top * factor, t + ROOF)
	self.blast.bottom *= factor
end

function Stage.outsideBlast(self: Stage, f: any): boolean
	local b = self.blast
	return f.x < b.left or f.x > b.right or f.y > b.top or f.y + f.h < b.bottom
end

export type Collision = { x: number, y: number, landed: Platform?, wall: boolean, bumped: boolean }

-- Resolve movement from (px,py) to (nx,ny) for a fighter with half-width r and height h.
function Stage.collide(self: Stage, f: any, px: number, py: number, nx: number, ny: number): Collision
	local r, h = f.r, f.h
	local x, y = nx, ny
	local landed: Platform? = nil
	local wall, bumped = false, false
	-- Horizontal against every solid's sides
	local bodyBottom, bodyTop = math.min(py, ny), math.max(py, ny) + h
	for _, sp in self.solids do
		if bodyBottom < sp.top - 0.05 and bodyTop > sp.bottom then
			if px <= sp.x1 - r + 0.001 and x > sp.x1 - r then
				x = sp.x1 - r
				wall = true
			elseif px >= sp.x2 + r - 0.001 and x < sp.x2 + r then
				x = sp.x2 + r
				wall = true
			elseif sp.dx ~= 0 and x > sp.x1 - r and x < sp.x2 + r then
				-- Only for a solid that MOVED this frame: it drove into a fighter who never moved
				-- into it, so nothing above catches it. Eject out the nearer face.
				x = if x - sp.cx < 0 then sp.x1 - r else sp.x2 + r
				wall = true
			end
		end
	end
	-- Vertical
	if f.vy <= 0 or ny < py then
		for _, p in self.platforms do
			if not (p.soft and f.dropTimer > 0) then
				local inside = x + r * 0.6 > p.x1 and x - r * 0.6 < p.x2
				if inside then
					local prevTop = p.top - p.dy -- where the platform surface was last frame
					if py >= prevTop - 0.05 and y < p.top then
						y = p.top
						landed = p
					end
				end
			end
		end
	elseif f.vy > 0 then
		for _, sp in self.solids do
			local inside = x + r * 0.6 > sp.x1 and x - r * 0.6 < sp.x2
			if inside and py + h <= sp.bottom and y + h > sp.bottom then
				y = sp.bottom - h
				bumped = true
				break
			end
		end
	end
	return { x = x, y = y, landed = landed, wall = wall, bumped = bumped }
end

function Stage.supported(self: Stage, f: any): boolean
	local p = f.platform
	if not p then
		return false
	end
	return f.x + f.r * 0.6 > p.x1 and f.x - f.r * 0.6 < p.x2 and math.abs(f.y - p.top) < 0.5
end

-- Returns a ledge the fighter can grab right now, or nil.
function Stage.ledgeFor(self: Stage, f: any, guardPressed: boolean): Ledge?
	if f.ledgeCooldown > 0 or f.ledgeGrabs >= LEDGE.maxGrabs then
		return nil
	end
	if f.vy > 6 then
		return nil
	end
	for _, L in self.ledges do
		local dx = (f.x - L.x) * L.side -- positive = outside the stage
		if not (dx < 0.2 or dx > LEDGE.grabReach + f.r) then
			if not (f.y > L.y + 1 or f.y < L.y - LEDGE.grabDepth) then
				if f.facing == -L.side or guardPressed then
					return L
				end
			end
		end
	end
	return nil
end

-- Spawn spot for an item: a point on top of a platform, from the stage's seeded generator.
function Stage.itemSpawn(self: Stage): { x: number, y: number }
	local p = self.platforms[math.floor(self.rng() * #self.platforms) + 1]
	return { x = p.x1 + 2 + self.rng() * (p.w - 4), y = p.top + 8 }
end

function Stage.nearestLedge(self: Stage, x: number, y: number): { ledge: Ledge?, dist: number }
	local best: Ledge? = nil
	local bd = math.huge
	for _, L in self.ledges do
		local dx, dy = L.x - x, L.y - y
		local d = math.sqrt(dx * dx + dy * dy)
		if d < bd then
			bd = d
			best = L
		end
	end
	return { ledge = best, dist = bd }
end

return Stage
