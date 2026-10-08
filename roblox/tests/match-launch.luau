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
local SnapshotCodec = Loader.load("SnapshotCodec")
local SceneCodec = Loader.load("SceneCodec")
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
		assert(#messages.Snapshot == 300, "snapshot cadence must be exactly 60Hz, independent of roster size")
		-- Decoded in order, as a client does (keyframes and deltas, SnapshotCodec): every one decodes
		-- to a complete state of the current match, the first needing no base.
		local base = nil
		for n, packed in messages.Snapshot do
			local snap = SnapshotCodec.decode(packed, base)
			assert(snap, `snapshot {n} could not be decoded from the one before it`)
			assert(#snap.fighters == count and snap.id == service.generation, "every packet must be a complete current-match state")
			base = snap
		end
		assert(SnapshotCodec.isKeyframe(messages.Snapshot[1]), "a match starts with a keyframe")
		assert(#messages.Scene == 150, "world state stays at 30Hz")
		-- and the scenes decode in order as a client decodes them: a keyframe first, deltas after
		local sceneBase = nil
		for n, packet in messages.Scene do
			local scene = SceneCodec.decode(packet, sceneBase)
			assert(scene and scene.id == service.generation and scene.hazards, `scene {n} could not be decoded from the one before it`)
			sceneBase = scene
		end
		assert(messages.Scene[1].k, "a match's first scene is a keyframe")
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
-- A room's match (Rooms.roster): weapon drops on, every fighter with its pair. What the client is
-- told, and what the wire then carries: the drops on the scene and the bots armed on the fighters.
local Snapshot = Loader.load("Snapshot")
local Rooms = Loader.loadFrom("src/server/", "Rooms")
local drops = 0
do
	local model = Rooms.new()
	local room = model:join(player, "Doubles")
	for slot = 2, 4 do assert(model:edit(player, { id = room.id, revision = room.revision, action = "bot", value = "normal", slot = slot })) end
	assert(model:edit(player, { id = room.id, revision = room.revision, action = "weapon2", value = "Pike" }))
	local roster, opts = model:roster(room, function() return 1 end)
	messages = {}
	service:start(roster, opts)
	local m = messages.Match[1]
	assert(m.weaponDrops == true and service.match.dropsOn, "a room's match has weapon drops on, and the client is told")
	for i, entry in m.fighters do
		local slot = room.slots[i]
		assert(entry.kit and entry.kit[1] == slot.weapon and entry.kit[2] == slot.weapon2, "the client is told every fighter's pair")
		local f = service.match.fighters[i]
		assert(f.kit[1].weapon.id == slot.weapon and f.kit[2].weapon.id == slot.weapon2 and f.armed == -1, "every fighter brings its pair and starts on fists")
		-- a bot is named by its slot - not for its weapon (three Sword bots read "KO! Sword by
		-- Sword"), and never for the fists it spawns holding
		if slot.bot then assert(entry.name == `CPU {i}`, `a bot is named "{entry.name}"`) end
	end
	for _ = 1, 60 * 14 do service:tick(1 / 60) end
	local base, armed = nil, 0
	for _, packed in messages.Snapshot do
		base = SnapshotCodec.decode(packed, base)
		for _, w in base.fighters do if Snapshot.decode(w).armed >= 0 then armed += 1 end end
	end
	local sceneBase = nil
	for _, packet in messages.Scene do
		sceneBase = SceneCodec.decode(packet, sceneBase)
		drops = math.max(drops, #(sceneBase.drops or {}))
	end
	assert(drops > 0, "no drop ever reached the client's scene")
	assert(armed > 0, "no fighter was ever armed on the wire: the bots never took a drop")
	cases += 1
end
service:stop()
assert(not service:rejoin(player), "no stale rejoin after match teardown")
print(`PASS launch: {cases} real matches (2/3/4 fighters x six arenas, and a room's with drops on), complete snapshots at 60Hz, scenes as keyframe and deltas, events, safe retry; the room's match tells the client every pair, and its drops and armed bots reach the wire`)
