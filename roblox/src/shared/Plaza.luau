--!strict
-- Walking the lobby: a line-for-line port of web/src/engine/plaza.js, replayed against it by
-- tests/plaza-parity.luau. Beat-'em-up movement on a floor with depth - x along the street, z into
-- the depth, y a cosmetic hop. See the JavaScript for why this is not the fighter engine: a lobby
-- that shares nothing with combat can never let an attack button do anything.
--
-- Shared, because the server checks every position a client reports against the same floor.

local PLAZA: any = require(script.Parent.Data.Plaza)
local W = PLAZA.walk
local DT = 1 / W.hz

local Plaza = {}
Plaza.__index = Plaza
Plaza.DATA = PLAZA

local function inside(r: any, x: number, z: number): boolean
	return x >= r.x1 and x <= r.x2 and z >= r.z1 and z <= r.z2
end

function Plaza.walkable(scene: any, x: number, z: number): boolean
	local on = false
	for _, r in scene.floor do
		if inside(r, x, z) then
			on = true
			break
		end
	end
	if not on then
		return false
	end
	for _, r in scene.blocks do
		if x > r.x1 and x < r.x2 and z > r.z1 and z < r.z2 then
			return false
		end
	end
	return true
end

function Plaza.new(scene: any): any
	local self = setmetatable({}, Plaza) :: any
	self.p = { x = 0, z = 0, y = 0, vx = 0, vz = 0, vy = 0, facing = 1, state = "idle", sf = 0 }
	self:setScene(scene)
	return self
end

function Plaza.setScene(self: any, scene: any, at: any?)
	self.data = scene
	local s = at or scene.spawn
	local p = self.p
	p.x, p.z, p.y, p.vx, p.vz, p.vy, p.state, p.sf = s.x, s.z, 0, 0, 0, 0, "idle", 0
end

function Plaza.warp(self: any, id: string): boolean
	for _, w in self.data.warps do
		if w.id == id then
			self:setScene(self.data, w)
			return true
		end
	end
	return false
end

function Plaza.step(self: any, input: any)
	local p = self.p
	local ax = math.clamp(input.x or 0, -1, 1)
	local az = math.clamp(input.y or 0, -1, 1)
	p.vx += (ax * W.speedX - p.vx) * W.accel
	p.vz += (az * W.speedZ - p.vz) * W.accel
	if math.abs(p.vx) < W.stop then p.vx = 0 end
	if math.abs(p.vz) < W.stop then p.vz = 0 end
	local nx = p.x + p.vx * DT
	if Plaza.walkable(self.data, nx, p.z) then p.x = nx else p.vx = 0 end
	local nz = p.z + p.vz * DT
	if Plaza.walkable(self.data, p.x, nz) then p.z = nz else p.vz = 0 end
	if input.jump and p.y == 0 and p.vy == 0 then
		p.vy = W.jump
	end
	if p.y > 0 or p.vy > 0 then
		p.vy -= W.gravity * DT
		p.y += p.vy * DT
		if p.y <= 0 then
			p.y, p.vy = 0, 0
		end
	end
	if ax ~= 0 then
		p.facing = if ax > 0 then 1 else -1
	end
	local state = if p.y > 0 then "air" elseif math.abs(p.vx) > 0.5 or math.abs(p.vz) > 0.5 then "run" else "idle"
	p.sf = if state == p.state then p.sf + 1 else 0
	p.state = state
end

function Plaza.nearest(self: any): any
	local p = self.p
	if p.y > 0 then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, s in self.data.stations do
		if math.abs(p.x - s.x) <= s.rx and math.abs(p.z - s.z) <= s.rz then
			local d = (p.x - s.x) * (p.x - s.x) + (p.z - s.z) * (p.z - s.z)
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	return best
end

function Plaza.district(self: any): any
	local x = self.p.x
	for _, d in self.data.districts do
		if x >= d.x1 and x <= d.x2 then
			return d
		end
	end
	return nil
end

-- The scene a room plays in, or the market.
function Plaza.scene(format: string?): any
	return if format then PLAZA.rooms[format] else PLAZA.market
end

return Plaza
