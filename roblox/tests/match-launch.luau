--!strict
-- The shipping MatchService with real simulation and intercepted network calls. Exercise the
-- full roster sizes the old two-fighter Studio smoke test failed to cover.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Loader = require("./loader")
local MatchConfig = Loader.load("MatchConfig")
local messages: any = {}
local sent: any = {}
local codes = setmetatable({}, { __index = function(_, k) return k end })
local shared = setmetatable({ Data = codes }, { __index = function(_, k) return k end })
local Service = luau.load(fs.readFile("src/server/MatchService.luau"), { environment = {
	game = { GetService = function(_, name)
		if name == "ReplicatedStorage" then return { Shared = shared } end
		return { PostSimulation = { Connect = function() return { Disconnect = function() end } end } }
	end },
	script = { Parent = { RemoteInput = "RemoteInput" } },
	require = function(name)
		if name == "Net" then return { remote = function(remote)
			return {
				FireAllClients = function(_, data)
					messages[remote] = messages[remote] or {}
					table.insert(messages[remote], data)
				end,
				FireClient = function(_, player, data) table.insert(sent, { remote = remote, player = player, data = data }) end,
			}
		end } end
		if name == "RemoteInput" then return Loader.loadFrom("src/server/", name) end
		if name == "Stages" then return Loader.load("Data/Stages") end
		return Loader.load(name)
	end,
}, injectGlobals = true })()
local player = { UserId = 17, Name = "LaunchTest", DisplayName = "LaunchTest" }
local outsider = { UserId = 99 }
local service = Service.new()
local cases = 0
for _, stage in Loader.load("Data/Stages").LIST do
	for count = 2, 4 do
		local cfg = MatchConfig.default()
		cfg.stageId, cfg.stocks, cfg.items = stage.id, 5, true
		for i = 2, count do cfg.slots[i].type = "bot-normal" end
		local roster, opts = MatchConfig.sanitise(cfg, player)
		assert(roster and #roster == count)
		messages = {}
		service:start(roster, opts)
		assert(#messages.Match == 1 and #messages.Match[1].fighters == count, "startup must describe every fighter")
		assert(messages.Match[1].stage == stage.id)
		for _ = 1, 300 do service:tick(1/60) end
		assert(#messages.Snapshot == 150, "snapshot cadence must be exactly 30Hz, independent of roster size")
		for _, snap in messages.Snapshot do
			assert(#snap.fighters == count and snap.id == service.generation, "every packet must be a complete current-match state")
		end
		assert(#messages.Scene == 150, "world state stays at 30Hz")
		assert(#messages.Events > 0, "countdown events are never suppressed by snapshot throttling")
		local match = service.match
		service.input:push("p17", { 0, 0, 0 })
		service.input:get("p17")
		assert(service.input:consumedBy("p17") > 0, "rejoin regression must start with a nonempty input history")
		sent = {}
		assert(service:rejoin(player) and service.match == match, "retry must rejoin, not restart an active match")
		assert(#sent == 1 and sent[1].remote == "Match" and sent[1].data.id == service.generation)
		assert(sent[1].data.inputEpoch == 1 and service.input:consumedBy("p17") == 0, "rejoining must reset the predictor input sequence")
		assert(not service:rejoin(outsider), "a stranger cannot claim the current fighter")
		cases += 1
	end
end
service:stop()
assert(not service:rejoin(player), "no stale rejoin after match teardown")
print(`PASS launch: {cases} real matches (2/3/4 fighters x six arenas), complete snapshots at 30Hz, events, safe retry`)
