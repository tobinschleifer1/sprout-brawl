--!strict
-- Server entry point.
--
-- The stage has no geometry on the server: collision is resolved by Stage.collide against the
-- numbers, and the picture is drawn on the client's canvas. Nothing physical exists in Workspace.
--
-- A player who loads gets the select screen; what they pick comes back over `Setup` and becomes
-- the match. The hard-coded Foundry-Floor-versus-one-bot slice that proved the simulation runs at
-- a fixed 60Hz is gone, and with it the assumption that there is only ever one shape of match.
--
-- Nothing the client sends is trusted. `Setup` is the first remote in this game that decides
-- anything, and MatchConfig is the boundary: it turns whatever arrives into a match the server is
-- willing to run, or refuses it with a reason. Matchmaking, lobbies and the rest of section 5 of
-- the design document still replace this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchService = require(script.MatchService)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Net = require(ReplicatedStorage.Shared.Net)

-- The fighters are ours, posed from the simulation. A Roblox-spawned character would be a second
-- body walking around under Roblox physics with opinions about where the player is.
Players.CharacterAutoLoads = false

local service = MatchService.new()
service:bindRemotes()

-- How long the scoreboard stays up before the players are returned to the select screen.
local RESULTS_HOLD = 6

-- The last config each player asked for, so a rematch after the scoreboard does not need them to
-- pick everything again. Cleared when they leave.
local lastConfig: { [number]: any } = {}

local function beginMatch(player: Player, cfg: any)
	if service.match then
		return
	end
	-- NOTHING here trusts `cfg`. It came off a remote; MatchConfig turns whatever it is into a
	-- match this server is willing to run, or says why it cannot.
	local roster, opts, why = MatchConfig.sanitise(cfg, player)
	if not roster then
		warn(`[Blockfall] refused a match from {player.Name}: {tostring(why)}`)
		Net.remote("Select"):FireClient(player, { error = why })
		return
	end
	lastConfig[player.UserId] = cfg
	local match = service:start(roster :: { any }, opts)
	print(`[Blockfall] match started: stage={match.stage.data.id} mode={match.mode} `
		.. `fighters={#(roster :: { any })} seed={match.seed}`)
end

-- The match is over, the loop is down, and the scoreboard has gone out. Hold it, then go again with
-- whoever is still here.
service.onFinished = function(self: any, m: any)
	print(`[Blockfall] match over after {m.frame} frames ({string.format("%.1f", m.time)}s)`)
	task.wait(RESULTS_HOLD)
	-- stop() clears service.match, which is what beginMatch guards on; without it the select
	-- screen below would be answered by a server that thinks a match is still running.
	service:stop()
	-- Back to select rather than straight into a rematch: the point of a select screen is that the
	-- next match does not have to be the last one. Their previous picks come back with it.
	for _, player in Players:GetPlayers() do
		Net.remote("Select"):FireClient(player, { ready = true, last = lastConfig[player.UserId] })
	end
end

-- `Hello` now means "I have loaded", not "start a match". The client answers it by showing the
-- select screen, and asks for a match with `Setup` when the player is ready.
Net.remote("Hello").OnServerEvent:Connect(function(player: Player)
	Net.remote("Select"):FireClient(player, { ready = true, last = lastConfig[player.UserId] })
end)

Net.remote("Setup").OnServerEvent:Connect(beginMatch)

Players.PlayerRemoving:Connect(function(player: Player)
	lastConfig[player.UserId] = nil
	if #Players:GetPlayers() <= 1 then
		service:stop()
	end
end)
