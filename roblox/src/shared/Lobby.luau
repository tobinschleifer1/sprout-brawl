--!strict
-- Port of web/src/engine/lobby.js. Real fighter movement, harmless local hub context.
local HUB = require(script.Parent.Data.Hub)
local Fighter = require(script.Parent.Fighter)
local Stage = require(script.Parent.Stage)
local Input = require(script.Parent.Input)
local Lobby = {}
Lobby.__index = Lobby
function Lobby.new(char: any, data: any?): any
	local scene = data or HUB
	local self = setmetatable({ data = scene, stage = Stage.new(scene, 1) }, Lobby)
	self:setLoadout(char)
	return self
end
function Lobby.setLoadout(self: any, char: any)
	self.char = char
	local old = self.fighter
	local f = Fighter.new({ index = 0, char = char, x = if old then old.x else self.data.spawn.x,
		y = if old then old.y else self.data.spawn.y, stocks = 3 })
	self.fighter = f
	f.facing = if old then old.facing else 1
	f.onGround = f.y == 0
	f.platform = if f.onGround then self.stage.main else nil
	f:setState(if f.onGround then "idle" else "air")
	self.ctx = { stage = self.stage, fighters = { f }, combat = { fighters = { f } } }
end
function Lobby.setScene(self: any, data: any)
	self.data, self.stage, self.fighter = data, Stage.new(data, 1), nil
	self:setLoadout(self.char)
end
function Lobby.step(self: any, input: any)
	local clean = Input.emptyFrame()
	clean.x, clean.y = input.x, input.y
	clean.jump, clean.jumpHeld, clean.downTap = input.jump, input.jumpHeld, input.downTap
	local f = self.fighter
	f:applyInput(clean)
	f:step(self.ctx)
	local x = math.clamp(f.x, self.data.main.x1 + 3, self.data.main.x2 - 3)
	if x ~= f.x then f.vx = 0 end
	f.x = x
	if f.y < -12 then f.x, f.y, f.vx, f.vy = self.data.spawn.x, self.data.spawn.y, 0, 0 end
end
function Lobby.nearest(self: any): any
	local f = self.fighter
	for _, station in self.data.stations do
		if math.abs(f.x - station.x) <= 7 and math.abs(f.y - station.y) <= 3 then return station end
	end
	return nil
end
return Lobby
