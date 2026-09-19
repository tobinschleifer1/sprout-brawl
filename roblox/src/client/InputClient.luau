--!strict
-- Samples the keyboard/gamepad into engine input frames at a fixed 60Hz.
--
-- Ported from web/src/engine/input.js, which is the one engine-adjacent file that did NOT port to
-- shared: polling is a client concern on Roblox and the transport is a remote. What ports exactly
-- is the shape of `_build` - level state in, edges out - because the whole state machine is written
-- against edges and a press that is sampled twice is a double jump the player did not ask for.
--
-- Sampling is on its own 60Hz accumulator rather than on RenderStepped, because the server consumes
-- one frame per tick. A 144Hz client sampling per render would send 144 frames a second into a
-- queue that drains at 60 and spend the match six frames behind its own inputs.

local UserInputService = game:GetService("UserInputService")

local Input = require(game:GetService("ReplicatedStorage").Shared.Input)

local KB = {
	left = { Enum.KeyCode.A, Enum.KeyCode.Left },
	right = { Enum.KeyCode.D, Enum.KeyCode.Right },
	up = { Enum.KeyCode.W, Enum.KeyCode.Up },
	down = { Enum.KeyCode.S, Enum.KeyCode.Down },
	jump = { Enum.KeyCode.Space, Enum.KeyCode.W, Enum.KeyCode.Up },
	light = { Enum.KeyCode.J },
	heavy = { Enum.KeyCode.K },
	dodge = { Enum.KeyCode.L, Enum.KeyCode.LeftShift },
	guard = { Enum.KeyCode.I, Enum.KeyCode.LeftControl },
	grab = { Enum.KeyCode.U },
	taunt = { Enum.KeyCode.T },
	pickup = { Enum.KeyCode.P },
	ult = { Enum.KeyCode.O },
}

local PAD = {
	jump = Enum.KeyCode.ButtonA, light = Enum.KeyCode.ButtonX, heavy = Enum.KeyCode.ButtonY,
	dodge = Enum.KeyCode.ButtonB, guard = Enum.KeyCode.ButtonR1, grab = Enum.KeyCode.ButtonL1,
	taunt = Enum.KeyCode.ButtonSelect, pickup = Enum.KeyCode.ButtonR3, ult = Enum.KeyCode.ButtonL3,
}
local DEAD = 0.25

local LEVEL_KEYS = { "left", "right", "up", "down", "jump", "light", "heavy", "dodge",
	"guard", "grab", "taunt", "pickup", "ult" }

local InputClient = {}
InputClient.__index = InputClient

function InputClient.new(): any
	local self = setmetatable({}, InputClient)
	self.prev = {} :: { [string]: boolean }
	self.accum = 0
	return self
end

local function padAxis(): (number, number)
	local x, y = 0, 0
	for _, gp in UserInputService:GetConnectedGamepads() do
		for _, st in UserInputService:GetGamepadState(gp) do
			if st.KeyCode == Enum.KeyCode.Thumbstick1 then
				x, y = st.Position.X, st.Position.Y
			elseif st.KeyCode == Enum.KeyCode.DPadLeft and st.Position.Z > 0.5 then
				x = -1
			elseif st.KeyCode == Enum.KeyCode.DPadRight and st.Position.Z > 0.5 then
				x = 1
			elseif st.KeyCode == Enum.KeyCode.DPadUp and st.Position.Z > 0.5 then
				y = 1
			elseif st.KeyCode == Enum.KeyCode.DPadDown and st.Position.Z > 0.5 then
				y = -1
			end
		end
		break
	end
	return (if math.abs(x) > DEAD then x else 0), (if math.abs(y) > DEAD then y else 0)
end

function InputClient.levels(_self: any): { [string]: any }
	-- UserInputService is asked directly rather than tracked through InputBegan/InputEnded. A key
	-- released while the window was unfocused never fires InputEnded, and a fighter that holds a
	-- direction forever because the player alt-tabbed mid-dash is the bug that costs an hour.
	local down = function(codes: { Enum.KeyCode }): boolean
		for _, c in codes do
			if UserInputService:IsKeyDown(c) then
				return true
			end
		end
		return false
	end
	local pad = function(code: Enum.KeyCode): boolean
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, code)
	end
	local ax, ay = padAxis()
	local l: { [string]: any } = {}
	for _, k in LEVEL_KEYS do
		l[k] = down(KB[k]) or (PAD[k] ~= nil and pad(PAD[k]))
	end
	l.left = l.left or ax < -DEAD
	l.right = l.right or ax > DEAD
	l.up = l.up or ay > DEAD
	l.down = l.down or ay < -DEAD
	l.ax, l.ay = ax, ay
	return l
end

function InputClient.build(self: any, l: { [string]: any }): Input.Frame
	local prev = self.prev
	local edge = function(k: string): boolean
		return not not l[k] and not prev[k]
	end
	local f = Input.emptyFrame()
	-- Analogue wins over digital when the stick is out of the deadzone, exactly as in the JS: the
	-- engine reads fractional x for walk-vs-run and for DI angle.
	f.x = if l.ax ~= 0 then l.ax else (if l.right then 1 else 0) - (if l.left then 1 else 0)
	f.y = if l.ay ~= 0 then l.ay else (if l.up then 1 else 0) - (if l.down then 1 else 0)
	f.jump, f.light, f.heavy, f.dodge = edge("jump"), edge("light"), edge("heavy"), edge("dodge")
	f.guard, f.grab, f.taunt = edge("guard"), edge("grab"), edge("taunt")
	f.ult, f.pickup, f.downTap = edge("ult"), edge("pickup"), edge("down")
	f.jumpHeld, f.guardHeld = not not l.jump, not not l.guard
	f.heavyHeld, f.lightHeld = not not l.heavy, not not l.light
	f.anyPress = f.jump or f.light or f.heavy or f.dodge or f.guard or f.grab or f.ult or f.pickup
	local snapshot: { [string]: boolean } = {}
	for _, k in LEVEL_KEYS do
		snapshot[k] = not not l[k]
	end
	self.prev = snapshot
	return f
end

-- Advances the sampler by `dt` and returns every whole frame that fell inside it, oldest first.
-- Usually zero or one; two when a render frame ran long.
function InputClient.sample(self: any, dt: number, frameTime: number): { Input.Frame }
	self.accum += dt
	local out = {}
	local guard = 0
	while self.accum >= frameTime and guard < 8 do
		self.accum -= frameTime
		guard += 1
		table.insert(out, self:build(self:levels()))
	end
	if self.accum >= frameTime then
		self.accum = 0
	end
	return out
end

return InputClient
