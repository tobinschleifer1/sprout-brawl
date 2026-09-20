--!strict
-- Runs the match. This is the only place in the game where the simulation advances.
--
-- The shared modules under ReplicatedStorage are the same code the web build runs, verified
-- frame-for-frame against it. This file does not reimplement any of it: it feeds Match a stage, a
-- roster and an input source, steps it at a fixed 60Hz, and broadcasts what came out.
--
-- Fixed step, not delta time. Heartbeat fires at the render rate and varies; the simulation is
-- defined only at 1/60 and every parity guarantee in roblox/tests depends on that. So the
-- accumulator converts wall time into whole ticks and the leftover waits for the next frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Match = require(Shared.Match)
local Stages = require(Shared.Data.Stages)
local Loadout = require(Shared.Loadout)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Snapshot = require(Shared.Snapshot)
local RemoteInput = require(script.Parent.RemoteInput)

local FRAME = Config.FRAME

-- A long hitch must not turn into a burst of thirty simulated frames: the match would fast-forward
-- past whatever the player was doing. Past this many ticks of debt the server drops the rest and
-- the match simply loses that time, which is visible but survivable.
local MAX_CATCHUP = 8

local MatchService = {}
MatchService.__index = MatchService

function MatchService.new(): any
	local self = setmetatable({}, MatchService)
	self.match = nil :: any
	self.input = RemoteInput.new()
	self.accum = 0
	self.conn = nil :: RBXScriptConnection?
	self.finished = false
	self.onFinished = nil :: ((any, any) -> ())?
	self.sources = {} :: { [number]: string }   -- userId -> input source key
	self.userIds = {} :: { [string]: number }  -- and back, so the roster can name a rig's owner
	return self
end

function MatchService.sourceFor(_self: any, player: Player): string
	return `p{player.UserId}`
end

-- ---------------------------------------------------------------- start ----
-- `roster` is a list of { player = Player? , avatar = string, weapon = string, isBot = boolean?,
-- botLevel = string? }. A nil player means a bot, which is how a single player tests against a CPU.
function MatchService.start(self: any, roster: { any }, opts: any?)
	local o = opts or {}
	self:stop()

	local stageId = o.stage or "FoundryFloor"
	local stage = nil
	for _, s in Stages.LIST do
		if s.id == stageId then
			stage = s
		end
	end
	assert(stage, `no such stage: {stageId}`)

	local fighters = {}
	for i, entry in roster do
		local source = if entry.player then self:sourceFor(entry.player) else `bot{i}`
		if entry.player then
			self.sources[entry.player.UserId] = source
			self.userIds[source] = entry.player.UserId
		end
		self.input:register(source)
		table.insert(fighters, {
			char = Loadout.build(entry.avatar, entry.weapon),
			skin = entry.skin or 0,
			team = entry.team,
			source = source,
			isBot = entry.player == nil,
			botLevel = entry.botLevel or "normal",
			name = if entry.player then entry.player.DisplayName else nil,
		})
	end

	self.match = Match.new({
		mode = o.mode or "StockFFA",
		stage = stage,
		fighters = fighters,
		stocks = o.stocks or 3,
		timeLimit = o.timeLimit or 180,
		items = o.items or false,
		input = self.input,
		-- The seed is what makes this match reproducible from its inputs. It is generated once,
		-- here, and sent to every client so a replay can be rebuilt later.
		seed = o.seed or math.random(1, 2 ^ 31 - 1),
	})

	Net.remote("Match"):FireAllClients({
		stage = stageId,
		seed = self.match.seed,
		mode = self.match.mode,
		fighters = self:roster(),
	})

	self.accum = 0
	self.finished = false
	self.conn = RunService.PostSimulation:Connect(function(dt: number)
		self:tick(dt)
	end)
	return self.match
end

function MatchService.roster(self: any): { any }
	local out = {}
	for _, f in self.match.fighters do
		table.insert(out, {
			index = f.index, name = f.name, team = f.team,
			avatar = f.char.avatar.id, weapon = f.char.weapon.id,
			isBot = f.isBot, source = f.source,
			userId = self.userIds[f.source],
			height = f.h, radius = f.r,
		})
	end
	return out
end

function MatchService.stop(self: any)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	self.match = nil
	self.finished = false
	self.sources = {}
	self.userIds = {}
	self.input = RemoteInput.new()
end

-- ---------------------------------------------------------------- finish ----
-- Results go out reliably and exactly once. They are not in the snapshot because a snapshot is a
-- stream whose next message supersedes the last, and the one message a player must not miss is the
-- one saying who won.
function MatchService.finish(self: any)
	local m = self.match
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	Net.remote("Results"):FireAllClients(self:results())
	if self.onFinished then
		-- Spawned, because whatever restarts the match must not run inside the tick that ended it.
		task.spawn(self.onFinished, self, m)
	end
end

-- The rows Match builds carry the whole composed character, which is kilobytes of frame data the
-- client already has. Send the identifiers and let it look them up.
function MatchService.results(self: any): any
	local m = self.match
	local r = m.results
	local rows = {}
	for _, row in r.rows do
		table.insert(rows, {
			index = row.index, name = row.name, team = row.team,
			avatar = row.char.avatar.id, weapon = row.char.weapon.id,
			kos = row.kos, falls = row.falls, sds = row.sds,
			damage = row.damage, percent = row.percent,
			stocks = row.stocks, score = row.score,
		})
	end
	return {
		rows = rows, winnerTeam = r.winnerTeam, mode = r.mode, timed = r.timed,
		frames = m.frame, time = m.time,
	}
end

-- ---------------------------------------------------------------- loop ----
function MatchService.tick(self: any, dt: number)
	local m = self.match
	if not m then
		return
	end
	self.accum += dt
	local steps = 0
	while self.accum >= FRAME and steps < MAX_CATCHUP do
		self.accum -= FRAME
		steps += 1
		Match.step(m)
	end
	if self.accum >= FRAME then
		-- Debt we are choosing not to pay. Drop it rather than spiral.
		self.accum = 0
	end
	if steps > 0 then
		self:broadcast()
	end
	-- Match.step is a no-op once the match reaches "results", so the accumulator goes on "stepping" a
	-- finished match forever: steps stays > 0, the frame number never moves, and broadcast ships the
	-- same frozen snapshot 60 times a second for as long as the server is up. The broadcast above is
	-- the last one, and it carries both the final positions and Match's own `game` event; after it
	-- the loop comes down and the scoreboard goes out on its own reliable remote.
	if m.state == "results" and not self.finished then
		self.finished = true
		self:finish()
	end
end

-- ---------------------------------------------------------------- broadcast ----
-- Snapshots are unreliable on purpose: a snapshot that arrives late is worse than one that never
-- arrives, because the next one supersedes it entirely. Events are reliable, because a missed KO
-- or a missed hitspark is a missed KO or hitspark.
function MatchService.broadcast(self: any)
	local m = self.match
	local fighters = table.create(#m.fighters)
	for i, f in m.fighters do
		fighters[i] = Snapshot.encode(f)
	end
	Net.remote("Snapshot"):FireAllClients({
		frame = m.frame, state = m.state, time = m.time,
		countdown = m.countdown, fighters = fighters,
	})
	if #m.events > 0 then
		Net.remote("Events"):FireAllClients(m.events)
		m.events = {}
	end
end

-- ---------------------------------------------------------------- input ----
function MatchService.bindRemotes(self: any)
	Net.remote("Input").OnServerEvent:Connect(function(player: Player, packed: any)
		local source = self.sources[player.UserId]
		if not source or type(packed) ~= "table" then
			return
		end
		-- Length is bounded here as well as in RemoteInput: an unbounded table from a client is a
		-- way to make the server walk a million entries before the queue cap ever runs.
		if #packed > 16 then
			return
		end
		self.input:push(source, packed)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self.sources[player.UserId] = nil
	end)
end

return MatchService
