--!strict
-- The wire between the server simulation and the client that draws it.
--
-- Two things cross it. Input frames go up: the client samples the keyboard at a fixed 60Hz and
-- ships every sampled frame, because the simulation consumes exactly one frame per tick and a
-- client that sampled at its own render rate would feed the server 144 frames one second and 30
-- the next. Snapshots come down: the server's authoritative fighter state, which the client
-- interpolates between rather than simulating.
--
-- Nothing here is allowed to be the source of truth for anything. If a field is in a snapshot it is
-- because the client draws it; the client decides nothing.
--
-- The frame codec lives in InputCodec and is re-exported here, so that the half of this file with
-- the bit arithmetic in it can be loaded and tested outside Roblox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InputCodec = require(script.Parent.InputCodec)

local Net = {}

Net.packFrame = InputCodec.packFrame
Net.unpackFrame = InputCodec.unpackFrame
Net.holdOnly = InputCodec.holdOnly
Net.coalesce = InputCodec.coalesce
Net.MAX_PACKED = InputCodec.MAX_PACKED

-- ---------------------------------------------------------------- remotes ----
-- Snapshots and input are Unreliable: both are a stream where the next message supersedes the
-- last, and a retransmitted stale one would be worse than the gap it filled. Events and the
-- handshake are reliable, because a dropped KO or a dropped match config never comes back.
local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Net")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Net"
		local function make(class: string, name: string)
			local r = if class == "UnreliableRemoteEvent"
				then Instance.new("UnreliableRemoteEvent") :: Instance
				else Instance.new("RemoteEvent") :: Instance
			r.Name = name
			r.Parent = folder
		end
		make("UnreliableRemoteEvent", "Input")      -- client -> server, one packed frame per sim tick
		make("UnreliableRemoteEvent", "Snapshot")   -- server -> client, authoritative state
		make("RemoteEvent", "Events")               -- server -> client, hits/KOs/countdown
		make("RemoteEvent", "Hello")                -- client -> server, "I have loaded, put me in"
		make("RemoteEvent", "Match")                -- server -> client, the config to build a view from
		make("RemoteEvent", "Results")              -- server -> client, the final scoreboard, once
		make("RemoteEvent", "Setup")                -- client -> server, "run this match please"
		make("RemoteEvent", "Select")               -- server -> client, "pick a match" / why one was refused
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Net") :: Folder
end

function Net.remote(name: string): any
	return folder:WaitForChild(name)
end

return Net
