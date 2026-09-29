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
-- How close to a reward's middle counts as touching it, in studs, across and up and down.
Parkour.REWARD_REACH = 1.6

-- `opts.climbed`: the furthest checkpoint climbed to before (skips excluded); `opts.collected`: the
-- reward ids already owned. Together they decide which rewards can be picked up.
function Parkour.new(course: any, char: any, from: number?, opts: any?): any
	local o = opts or {}
	local self = setmetatable({}, Parkour) :: any
	self.course, self.char = course, char
	self.stage = Stage.new(course, 1)
	self.stage:placeMovers()
	self.reached = math.max(0, math.min(from or 0, #course.checkpoints - 1))
	self.deaths, self.frames = 0, 0
	self.done = self.reached == #course.checkpoints - 1
	self.skipped = false   -- a checkpoint was skipped this climb (skipTo): not a clean, timed climb
	self.climbedTo = math.max(0, o.climbed or 0)
	self.collected = {}
	for _, id in o.collected or {} do self.collected[id] = true end
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
	self.padTop = p.top
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
	-- Below the street, or too far below your checkpoint's pad (course.fallDepth): a fall.
	local floor = if self.course.fallDepth ~= nil then math.max(self.course.killY, self.padTop - self.course.fallDepth) else self.course.killY
	if f.y < floor then
		self:fall()
		return
	end
	if f.onGround and f.platform then
		local n = #self.course.checkpoints
		for i = self.reached + 1, n - 1 do
			if self.course.checkpoints[i + 1].pad == f.platform.id then
				self.reached = i
				self.padTop = f.platform.top
				self.climbedTo = math.max(self.climbedTo, i)
				table.insert(self.events, { type = "checkpoint", checkpoint = i })
				if i == n - 1 then
					self.done = true
					table.insert(self.events, { type = "summit", frames = self.frames, deaths = self.deaths })
				end
			end
		end
	end
	self:collect()
end

-- A reward can be picked up by whoever climbed to its checkpoint (now or before) and has not got it.
function Parkour.available(self: any, reward: any): boolean
	return not self.collected[reward.id] and self.climbedTo >= reward.checkpoint
end

-- Touching an available reward collects it.
function Parkour.collect(self: any)
	local f = self.fighter
	local R = Parkour.REWARD_REACH
	for _, r in self.course.rewards or {} do
		if self:available(r) and math.abs(f.x - r.x) < R and f.y < r.y + R and f.y + f.h > r.y - R then
			self.collected[r.id] = true
			table.insert(self.events, { type = "reward", id = r.id, checkpoint = r.checkpoint })
		end
	end
end

-- A skipped checkpoint (bought): on its pad as if reached, with a 'skip' event and none of the
-- checkpoint or summit events, which mean it was climbed. Forward only. See parkour.js skipTo.
function Parkour.skipTo(self: any, index: number): boolean
	local i = math.max(0, math.min(index, #self.course.checkpoints - 1))
	if i <= self.reached then return false end
	self.reached = i
	self.skipped = true
	if i == #self.course.checkpoints - 1 then self.done = true end
	table.insert(self.events, { type = "skip", checkpoint = i })
	self:spawn()
	return true
end

function Parkour.drain(self: any): { any }
	local out = self.events
	self.events = {}
	return out
end

return Parkour
