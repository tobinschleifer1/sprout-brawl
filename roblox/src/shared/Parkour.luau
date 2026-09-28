--!strict
-- Climbing the Skyline Climb: a line-for-line port of web/src/engine/parkour.js, replayed against it
-- by tests/parkour-parity.luau. The real fighter and stage engines on a course (Data/Parkour),
-- plus checkpoints, falls and a clock. Harmless: only direction, jump and drop-through are read.

local Fighter = require(script.Parent.Fighter)
local Stage = require(script.Parent.Stage)
local Input = require(script.Parent.Input)

local Parkour = {}
Parkour.__index = Parkour
Parkour.DATA = require(script.Parent.Data.Parkour) :: any

function Parkour.new(course: any, char: any, from: number?): any
	local self = setmetatable({}, Parkour) :: any
	self.course, self.char = course, char
	self.stage = Stage.new(course, 1)
	self.reached = math.max(0, math.min(from or 0, #course.checkpoints - 1))
	self.deaths, self.frames = 0, 0
	self.done = self.reached == #course.checkpoints - 1
	self.events = {}
	self:spawn()
	return self
end

-- Checkpoints are counted from 0, as in the JavaScript; the list is 1-indexed.
function Parkour.pad(self: any, index: number): any
	local id = self.course.checkpoints[index + 1].pad
	for _, p in self.stage.platforms do
		if p.id == id then return p end
	end
	return nil
end

function Parkour.spawn(self: any)
	local p = self:pad(self.reached)
	local f = Fighter.new({ index = 0, char = self.char, x = p.cx, y = p.top, stocks = 3 })
	f.invincible = 0
	f.facing = 1
	f.onGround = true
	f.platform = p
	f:setState("idle")
	self.fighter = f
	self.ctx = { stage = self.stage, fighters = { f }, combat = { fighters = { f } } }
end

function Parkour.fall(self: any)
	self.deaths += 1
	table.insert(self.events, { type = "fall", checkpoint = self.reached })
	self:spawn()
end

function Parkour.step(self: any, input: any)
	local clean = Input.emptyFrame()
	clean.x, clean.y = input.x or 0, input.y or 0
	clean.jump, clean.jumpHeld, clean.downTap = input.jump == true, input.jumpHeld == true, input.downTap == true
	local f = self.fighter
	self.stage:step(self.ctx)
	f:applyInput(clean)
	f:step(self.ctx)
	if not self.done then self.frames += 1 end
	if f.y < self.course.killY then
		self:fall()
		return
	end
	if f.onGround and f.platform then
		local n = #self.course.checkpoints
		for i = self.reached + 1, n - 1 do
			if self.course.checkpoints[i + 1].pad == f.platform.id then
				self.reached = i
				table.insert(self.events, { type = "checkpoint", checkpoint = i })
				if i == n - 1 then
					self.done = true
					table.insert(self.events, { type = "summit", frames = self.frames, deaths = self.deaths })
				end
			end
		end
	end
end

function Parkour.drain(self: any): { any }
	local out = self.events
	self.events = {}
	return out
end

return Parkour
