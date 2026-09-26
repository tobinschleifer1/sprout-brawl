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
local ContextActionService = game:GetService("ContextActionService")

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
	-- Keys the game has heard go down through its own ContextActionService binding, by KeyCode.
	self.heldCodes = {} :: { [any]: boolean }

	-- I AND O NEVER REACH UserInputService. They are Roblox's camera zoom keys: the default
	-- camera script binds them through ContextActionService and sinks the press, so InputBegan
	-- does not fire for them at all - only InputEnded does - and a physical press of Shield or
	-- Ultimate was simply lost. (Recorded in Studio from a real keyboard: every other key arrived,
	-- I and O arrived only as releases. Keys injected by the Studio MCP take a different path and
	-- DO fire InputBegan, which is why every automated check passed while the game did not work.)
	--
	-- So the game binds its own keys through ContextActionService above the camera's priority: it
	-- hears the press first, keeps its own held state from Begin and End, and passes the input on so
	-- nothing else - the hub's walking, the camera - loses anything it had.
	local byCode: { [any]: boolean } = {}
	local codes = {}
	for _, keys in (KB :: { [string]: { string } }) do
		for _, key in keys do
			local code = (Enum.KeyCode :: any)[key]
			if not byCode[code] then byCode[code] = true; table.insert(codes, code) end
		end
	end
	for _, key in PAD do
		local code = (Enum.KeyCode :: any)[key]
		if not byCode[code] then byCode[code] = true; table.insert(codes, code) end
	end
	ContextActionService:BindActionAtPriority("BlockfallCombatKeys", function(_: string, state: any, input: InputObject)
		if state == Enum.UserInputState.Begin then
			-- Letters typed into chat are not holds or presses.
			if not UserInputService:GetFocusedTextBox() then
				self.heldCodes[input.KeyCode] = true
				self:press(input.KeyCode)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self.heldCodes[input.KeyCode] = nil
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 1, table.unpack(codes))
	-- A key released while the window is unfocused never delivers End; forget every hold then.
	UserInputService.WindowFocusReleased:Connect(function()
		self.heldCodes = {}
	end)

	-- Polling holds avoids stuck keys, but polling alone loses a whole tap between ticks.
	-- Text entry still owns its keys. Keep one bounded pending edge per action.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() then return end
		self:press(input.KeyCode)
	end)
	return self
end

-- Latch the press edge for every action bound to this key or button.
function InputClient.press(self: any, code: any)
	for action, keys in (KB :: { [string]: { string } }) do
		for _, key in keys do
			if code == (Enum.KeyCode :: any)[key] then self.pending[action] = true end
		end
	end
	for action, key in PAD do
		if code == (Enum.KeyCode :: any)[key] then self.pending[action] = true end
	end
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
	-- Held is either: UserInputService knows the key is down, or our own binding heard it go down
	-- and has not heard it come up. The second is the only way to know about I and O.
	local down = function(codes: { string }): boolean
		for _, c in codes do
			local code = (Enum.KeyCode :: any)[c]
			if UserInputService:IsKeyDown(code) or self.heldCodes[code] then
				return true
			end
		end
		return false
	end
	local pad = function(code: string): boolean
		local c = (Enum.KeyCode :: any)[code]
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, c) or self.heldCodes[c] == true
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
