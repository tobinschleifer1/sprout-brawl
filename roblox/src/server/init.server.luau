--!strict
-- Server entry point.
--
-- The stage has no geometry on the server: collision is resolved by Stage.collide against the
-- numbers, and the picture is drawn on the client's canvas. Nothing physical exists in Workspace.
--
-- Thin slice: the first player to load gets dropped into a stock match on Foundry Floor against
-- one bot. Matchmaking, lobbies, character select and the rest of section 5 of the design document
-- replace this; what it exists to prove is that the ported simulation runs on a Roblox server at a
-- fixed 60Hz and that what a client sees is what the server computed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchService = require(script.MatchService)

-- The fighters are ours, posed from the simulation. A Roblox-spawned character would be a second
-- body walking around under Roblox physics with opinions about where the player is.
Players.CharacterAutoLoads = false

local service = MatchService.new()
service:bindRemotes()

-- How long the scoreboard stays up before the next match. A results screen with a button on it is
-- section 5's job; until then the slice loops on a timer so a playtest does not end with one match.
local RESULTS_HOLD = 6

local function beginMatch(player: Player)
	if service.match then
		return
	end
	local roster: { any } = {
		{ player = player, avatar = "Classic", weapon = "Sword" },
		{ avatar = "Noir", weapon = "Sword", botLevel = "normal" },
	}
	local match = service:start(roster, { stage = "FoundryFloor", mode = "StockFFA", stocks = 3 })
	print(`[Blockfall] match started: stage={match.stage.data.id} seed={match.seed}`)
end

-- The match is over, the loop is down, and the scoreboard has gone out. Hold it, then go again with
-- whoever is still here.
service.onFinished = function(self: any, m: any)
	print(`[Blockfall] match over after {m.frame} frames ({string.format("%.1f", m.time)}s)`)
	task.wait(RESULTS_HOLD)
	-- stop() clears service.match, which is what beginMatch guards on; without it the restart below
	-- would return immediately and the server would sit on the scoreboard forever.
	service:stop()
	local players = Players:GetPlayers()
	if #players > 0 then
		beginMatch(players[1])
	end
end

local Net = require(ReplicatedStorage.Shared.Net)
Net.remote("Hello").OnServerEvent:Connect(beginMatch)

Players.PlayerRemoving:Connect(function()
	if #Players:GetPlayers() <= 1 then
		service:stop()
	end
end)
