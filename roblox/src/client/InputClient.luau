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
local Bindings = require(script.Parent.Bindings)
local KB, PAD = Bindings.keyboard, Bindings.gamepad
local DEAD = 0.25

local LEVEL_KEYS = { "left", "right", "up", "down", "jump", "light", "heavy", "dodge",
	"guard", "grab", "taunt", "pickup", "ult" }

local InputClient = {}
InputClient.__index = InputClient

function InputClient.new(): any
	local self: any = setmetatable({}, InputClient)
	self.prev = {} :: { [string]: boolean }
	self.pending = {} :: { [string]: boolean }
	self.accum = 0
	-- Polling holds avoids stuck keys, but polling alone loses a whole tap between ticks.
	-- Roblox marks I/O as processed camera keys, so processed is NOT a combat filter.
	-- Text entry still owns its keys. Keep one bounded pending edge per action.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() then return end
		for action, keys in (KB :: { [string]: { string } }) do
			for _, key in keys do
				if input.KeyCode == (Enum.KeyCode :: any)[key] then self.pending[action] = true end
			end
		end
		for action, key in PAD do
			if input.KeyCode == (Enum.KeyCode :: any)[key] then self.pending[action] = true end
		end
	end)
	return self
end

function InputClient.reset(self: any)
	self.prev, self.pending, self.accum = {}, {}, 0
end

local function padAxis(): (number, number)
	local x, y = 0, 0
	local dx, dy = 0, 0
	for _, gp in UserInputService:GetConnectedGamepads() do
		for _, st in UserInputService:GetGamepadState(gp) do
			if st.KeyCode == Enum.KeyCode.Thumbstick1 then
				x, y = st.Position.X, st.Position.Y
			elseif st.KeyCode == Enum.KeyCode.DPadLeft and st.Position.Z > 0.5 then
				dx -= 1
			elseif st.KeyCode == Enum.KeyCode.DPadRight and st.Position.Z > 0.5 then
				dx += 1
			elseif st.KeyCode == Enum.KeyCode.DPadUp and st.Position.Z > 0.5 then
				dy += 1
			elseif st.KeyCode == Enum.KeyCode.DPadDown and st.Position.Z > 0.5 then
				dy -= 1
			end
		end
		break
	end
	return (if math.abs(x) > DEAD then x else dx), (if math.abs(y) > DEAD then y else dy)
end

function InputClient.levels(self: any): { [string]: any }
	-- Chat and text fields own their keystrokes; typing must not jump or attack underneath them.
	if UserInputService:GetFocusedTextBox() then
		self.pending = {}
		return { ax = 0, ay = 0 }
	end
	-- UserInputService is asked directly rather than tracked through InputBegan/InputEnded. A key
	-- released while the window was unfocused never fires InputEnded, and a fighter that holds a
	-- direction forever because the player alt-tabbed mid-dash is the bug that costs an hour.
	local down = function(codes: { string }): boolean
		for _, c in codes do
			if UserInputService:IsKeyDown((Enum.KeyCode :: any)[c]) then
				return true
			end
		end
		return false
	end
	local pad = function(code: string): boolean
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, (Enum.KeyCode :: any)[code])
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
	local pending = self.pending
	self.pending = {}
	local edge = function(k: string): boolean
		return pending[k] == true or (not not l[k] and not prev[k])
	end
	local f = Input.emptyFrame()
	-- Analogue wins over digital when the stick is out of the deadzone, exactly as in the JS: the
	-- engine reads fractional x for walk-vs-run and for DI angle.
	f.x = if l.ax ~= 0 then l.ax else (if l.right then 1 else 0) - (if l.left then 1 else 0)
	f.y = if l.ay ~= 0 then l.ay else (if l.up then 1 else 0) - (if l.down then 1 else 0)
	f.jump, f.light, f.heavy, f.dodge = edge("jump"), edge("light"), edge("heavy"), edge("dodge")
	f.guard, f.grab, f.taunt = edge("guard"), edge("grab"), edge("taunt")
	f.ult, f.pickup, f.downTap = edge("ult"), edge("pickup"), edge("down")
	f.jumpHeld, f.guardHeld = not not l.jump or pending.jump == true, not not l.guard or pending.guard == true
	f.heavyHeld, f.lightHeld = not not l.heavy or pending.heavy == true, not not l.light or pending.light == true
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
