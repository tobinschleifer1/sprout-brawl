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

local codes = setmetatable({}, { __index = function(_, k) return k end })
local focused = false
local gamepad: any = {
	{ KeyCode = "DPadRight", Position = { X = 0, Y = 0, Z = 1 } },
	{ KeyCode = "Thumbstick1", Position = { X = 0, Y = 0, Z = 0 } },
}
local uis = {
	GetFocusedTextBox = function() return if focused then {} else nil end,
	GetConnectedGamepads = function() return { 1 } end,
	GetGamepadState = function() return gamepad end,
	IsKeyDown = function(_, k) return k == "J" end,
	IsGamepadButtonDown = function() return false end,
}
local InputClient = luau.load(fs.readFile("src/client/InputClient.luau"), {
	environment = {
		Enum = { KeyCode = codes, UserInputType = codes },
		game = { GetService = function(_, name) return if name == "UserInputService" then uis else { Shared = { Input = "Input" } } end },
		require = function() return Input end,
	}, injectGlobals = true,
})()
local sampler = InputClient.new()
check(sampler:build(sampler:levels()).x == 1, "neutral stick must not overwrite D-pad")
gamepad = { gamepad[2], gamepad[1] }
check(sampler:build(sampler:levels()).x == 1, "D-pad is independent of Roblox input enumeration order")
focused = true
local quiet = sampler:build(sampler:levels())
check(quiet.x == 0 and not quiet.light and not quiet.lightHeld, "typing in chat cannot drive a fighter")

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
callbacks.leave({ UserId = 7 })
check(service.input:get("p7").x == 0, "disconnected fighters stop repeating their last movement")
local Rbx = require("@lune/roblox")
local MatchConfig = Loader.load("MatchConfig")
local Select = luau.load(fs.readFile("src/client/Select.luau"), {
	environment = {
		game = { GetService = function() return { Shared = shared } end },
		require = function(name)
			if name == "MatchConfig" then return MatchConfig end
			return Loader.load("Data/" .. name)
		end,
		Enum = { Font = codes, TextXAlignment = codes },
		Color3 = Rbx.Color3, UDim2 = Rbx.UDim2, UDim = Rbx.UDim,
		Instance = { new = function() return { Activated = { Connect = function() end } } end },
	}, injectGlobals = true,
})()
local choices: any = {}
local select = setmetatable({ cfg = MatchConfig.default(), rows = {}, panel = {} }, { __index = Select })
select.row = function(_, _y, _title, _items, get, set)
	table.insert(choices, { get = get, set = set })
end
select:build()
check(select.oppNote.Position.Y.Offset >= 458 and select.oppNote.Position.Y.Offset + select.oppNote.Size.Y.Offset <= 480,
	"opponent summary must fit between the scroll row and Fight button")
local previous = select.cfg
select.cfg = MatchConfig.default()
choices[1].set("Hammer")
choices[2].set("Noir")
check(select.cfg.slots[1].weaponId == "Hammer" and select.cfg.slots[1].avatarId == "Noir", "rematch edits the current configuration")
check(previous.slots[1].weaponId == "Sword", "rematch must not edit the detached old configuration")
print("PASS runtime input: packet bounds, D-pad order, chat focus, reliable transport, rematch controls and disconnects")
