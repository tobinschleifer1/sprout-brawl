--!strict
-- Exercise shipping input/transport modules with only the Roblox services replaced.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Loader = require("./loader")
local Codec = Loader.load("InputCodec")
local Input = Loader.load("Input")
local RemoteInput = Loader.loadFrom("src/server/", "RemoteInput")
local function check(ok: boolean, message: string)
	assert(ok, message)
end

local remote = RemoteInput.new()
remote:register("p1")
local right = Input.emptyFrame()
right.x = 1
local malicious: any = { a = Codec.packFrame(right) }
remote:push("p1", malicious)
check(remote:get("p1").x == 0, "dictionary entries cannot bypass input array limit")
local frames = {}
for _ = 1, 40 do table.insert(frames, Codec.packFrame(right)) end
remote:push("p1", frames)
check(remote:consumedBy("p1") == 10, "only the first sixteen frames are accepted, with ten dropped")
remote:get("p1")
check(remote:consumedBy("p1") == 14, "catch-up accounts for every coalesced frame")
remote:register("tap")
local burst = table.create(16, Codec.packFrame(Input.emptyFrame()))
local ultimate = Input.emptyFrame(); ultimate.ult = true; ultimate.anyPress = true
burst[1] = Codec.packFrame(ultimate)
remote:push("tap", burst)
check(remote:get("tap").ult, "queue overflow must preserve an ultimate press from the oldest frame")

local codes = setmetatable({}, { __index = function(_, k) return k end })
local focused = false
local pressedKey = "J"
local pressedPad = ""
local began = {}
local gamepad: any = {
	{ KeyCode = "DPadRight", Position = { X = 0, Y = 0, Z = 1 } },
	{ KeyCode = "Thumbstick1", Position = { X = 0, Y = 0, Z = 0 } },
}
local uis = {
	InputBegan = { Connect = function(_, fn) table.insert(began, fn) end },
	GetFocusedTextBox = function() return if focused then {} else nil end,
	GetConnectedGamepads = function() return { 1 } end,
	GetGamepadState = function() return gamepad end,
	IsKeyDown = function(_, k) return k == pressedKey end,
	IsGamepadButtonDown = function(_, _pad, k) return k == pressedPad end,
}
local InputClient = luau.load(fs.readFile("src/client/InputClient.luau"), {
	environment = {
		Enum = { KeyCode = codes, UserInputType = codes },
		game = { GetService = function(_, name) return if name == "UserInputService" then uis else { Shared = { Input = "Input" } } end },
		script = { Parent = { Bindings = "Bindings" } },
		require = function(name) return if name == "Bindings" then Loader.loadFrom("src/client/", "Bindings") else Input end,
	}, injectGlobals = true,
})()
local sampler = InputClient.new()
check(sampler:build(sampler:levels()).x == 1, "neutral stick must not overwrite D-pad")
gamepad = { gamepad[2], gamepad[1] }
check(sampler:build(sampler:levels()).x == 1, "D-pad is independent of Roblox input enumeration order")
focused = true
local quiet = sampler:build(sampler:levels())
check(quiet.x == 0 and not quiet.light and not quiet.lightHeld, "typing in chat cannot drive a fighter")
focused = false
gamepad = {}
for _, binding in { { "O", "ult", "ButtonL3" }, { "I", "guard", "ButtonR1" }, { "P", "pickup", "ButtonR3" } } do
	pressedKey, pressedPad = binding[1], ""
	sampler.prev = {}
	local first = sampler:build(sampler:levels())
	check(first[binding[2]], binding[1] .. " must trigger " .. binding[2])
	local held = sampler:build(sampler:levels())
	check(not held[binding[2]], "a held key must not repeat its press edge")
	if binding[2] == "guard" then check(held.guardHeld, "shield stays held while I is down") end
	pressedKey, pressedPad, sampler.prev = "", binding[3], {}
	check(sampler:build(sampler:levels())[binding[2]], "gamepad binding must trigger " .. binding[2])
end
pressedPad, pressedKey, sampler.prev = "", "LeftControl", {}
check(sampler:build(sampler:levels()).guardHeld, "Left Ctrl also holds shield")

-- A complete press/release can occur between two simulation samples (especially on a hitch).
-- It must survive even though IsKeyDown is already false when the next frame is sampled.
pressedKey, pressedPad = "", ""
for _, binding in { {"O", "ult"}, {"I", "guard"} } do
	sampler.prev = {}
	for _, fn in began do fn({KeyCode=binding[1], UserInputType="Keyboard"}, true) end
	local tapped = sampler:build(sampler:levels())
	check(tapped[binding[2]], "between-frame " .. binding[1] .. " tap must not disappear")
	if binding[2] == "guard" then check(tapped.guardHeld, "a shield tap must hold for its activation frame") end
	check(not sampler:build(sampler:levels())[binding[2]], "a latched press is consumed exactly once")
end

-- Instantiate the real Net module to check its transport, not a copy of the intended setting.
local made: any = {}
local storage = { FindFirstChild = function() return nil end }
local Net = luau.load(fs.readFile("src/shared/Net.luau"), {
	environment = {
		game = { GetService = function(_, name) return if name == "ReplicatedStorage" then storage else { IsServer = function() return true end } end },
		script = { Parent = { InputCodec = "InputCodec" } },
		require = function() return Codec end,
		Instance = { new = function(class) local instance = { ClassName = class }; table.insert(made, instance); return instance end },
	}, injectGlobals = true,
})()
local foundInput = false
for _, instance in made do
	if instance.Name == "Input" then
		foundInput = true
		check(instance.ClassName == "RemoteEvent", "count-based prediction requires ordered, reliable input")
	end
	if instance.Name == "Snapshot" then
		check(instance.ClassName == "RemoteEvent", "four-fighter snapshots exceed unreliable payload limits")
	end
end
check(foundInput, "input remote must exist")

local callbacks: any = {}
local signal = function(name)
	return { Connect = function(_, fn) callbacks[name] = fn end }
end
local modules: any = { RemoteInput = RemoteInput, Net = {
	remote = function() return { OnServerEvent = signal("input") } end,
} }
local shared = setmetatable({ Data = codes }, { __index = function(_, k) return k end })
local Service = luau.load(fs.readFile("src/server/MatchService.luau"), {
	environment = {
		game = { GetService = function(_, name)
			if name == "ReplicatedStorage" then return { Shared = shared } end
			if name == "Players" then return { PlayerRemoving = signal("leave") } end
			return {}
		end },
		script = { Parent = { RemoteInput = "RemoteInput" } },
		require = function(name) return modules[name] or {} end,
	}, injectGlobals = true,
})()
local service = Service.new()
service.generation = 42
service.sources[7] = "p7"
service.input:register("p7")
service:bindRemotes()
callbacks.input({ UserId = 7 }, { Codec.packFrame(right) }, 41)
check(#service.input.sources.p7.queue == 0, "old-match input is rejected")
callbacks.input({ UserId = 7 }, { Codec.packFrame(right) }, 42)
check(service.input:get("p7").x == 1, "current-match input is accepted")
service.inputEpochs[7] = 1
service.input:register("p7")
callbacks.input({ UserId = 7 }, { Codec.packFrame(right) }, 42, 0)
check(service.input:get("p7").x == 0, "old input cannot enter a rejoined predictor history")
callbacks.input({ UserId = 7 }, { Codec.packFrame(right) }, 42, 1)
check(service.input:get("p7").x == 1, "current rejoin epoch accepts input")
callbacks.leave({ UserId = 7 })
check(service.input:get("p7").x == 0, "disconnected fighters stop repeating their last movement")
-- Real rematch button callbacks and layout are now exercised by lobby-ui.luau.
print("PASS runtime input: packet bounds, D-pad order, chat focus, combat bindings, reliable transport and disconnects")
