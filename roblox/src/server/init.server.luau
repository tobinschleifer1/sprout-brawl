--!strict
-- Server entry point.
--
-- Thin slice: the first player to load gets dropped into a stock match on Foundry Floor against
-- one bot. Matchmaking, lobbies, character select and the rest of section 5 of the design document
-- replace this; what it exists to prove is that the ported simulation runs on a Roblox server at a
-- fixed 60Hz and that what a client sees is what the server computed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchService = require(script.MatchService)
local StageBuild = require(script.StageBuild)

-- The fighters are ours, posed from the simulation. A Roblox-spawned character would be a second
-- body walking around under Roblox physics with opinions about where the player is.
Players.CharacterAutoLoads = false

local service = MatchService.new()
service:bindRemotes()

local stageModel: Model? = nil
local movingParts: { any } = {}

local function beginMatch(player: Player)
	if service.match then
		return
	end
	local roster: { any } = {
		{ player = player, avatar = "Classic", weapon = "Sword" },
		{ avatar = "Noir", weapon = "Sword", botLevel = "normal" },
	}
	local match = service:start(roster, { stage = "FoundryFloor", mode = "StockFFA", stocks = 3 })

	if stageModel then
		stageModel:Destroy()
	end
	stageModel, movingParts = StageBuild.build(match.stage, Workspace)
	print(`[Blockfall] match started: stage={match.stage.data.id} seed={match.seed}`)
end

local Net = require(ReplicatedStorage.Shared.Net)
Net.remote("Hello").OnServerEvent:Connect(beginMatch)

RunService.PostSimulation:Connect(function()
	if #movingParts > 0 then
		StageBuild.follow(movingParts)
	end
end)

Players.PlayerRemoving:Connect(function()
	if #Players:GetPlayers() <= 1 then
		service:stop()
		if stageModel then
			stageModel:Destroy()
			stageModel = nil
		end
		movingParts = {}
	end
end)
