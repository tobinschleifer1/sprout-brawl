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
local SceneSnapshot = require(Shared.SceneSnapshot)
local Stage = require(Shared.Stage)
local RemoteInput = require(script.Parent.RemoteInput)

local FRAME = Config.FRAME

-- A long hitch must not turn into a burst of thirty simulated frames: the match would fast-forward
-- past whatever the player was doing. Past this many ticks of debt the server drops the rest and
-- the match simply loses that time, which is visible but survivable.
local MAX_CATCHUP = 8

local MatchService = {}
MatchService.__index = MatchService

function MatchService.new(audience: any?, generation: number?): any
	local self = setmetatable({}, MatchService)
	self.match = nil :: any
	self.input = RemoteInput.new()
	self.accum = 0
	self.conn = nil :: RBXScriptConnection?
	self.finished = false
	self.generation = generation or 0
	self.audience = audience
	self.inputEpochs = {} :: { [number]: number }
	self.onFinished = nil :: ((any, any) -> ())?
	self.sources = {} :: { [number]: string }   -- userId -> input source key
	self.userIds = {} :: { [string]: number }  -- and back, so the roster can name a rig's owner
	return self
end

function MatchService.send(self: any, name: string, payload: any, ...: any)
	if self.audience then
		for _, player in self.audience do Net.remote(name):FireClient(player, payload, ...) end
	else
		-- Legacy harness only; production always provides room membership.
		Net.remote(name):FireAllClients(payload, ...)
	end
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
	self.generation += 1

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
			self.inputEpochs[entry.player.UserId] = 0
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
		disasters = o.disasters or "off",   -- natural disasters; see shared/Disasters.luau
		input = self.input,
		-- The seed is what makes this match reproducible from its inputs. It is generated once,
		-- here, and sent to every client so a replay can be rebuilt later.
		seed = o.seed or math.random(1, 2 ^ 31 - 1),
	})

	self:send("Match", self:description())

	self.accum = 0
	self.finished = false
	self.sceneFrame = -2
	self.snapshotFrame = -2
	self.conn = RunService.PostSimulation:Connect(function(dt: number)
		self:tick(dt)
	end)
	return self.match
end

-- Reused for startup and recovery when a client reloads or retries during its own match.
function MatchService.description(self: any): any
	return {
		id = self.generation,
		stage = self.match.stage.data.id,
		seed = self.match.seed,
		mode = self.match.mode,
		-- The HUD needs to know whether there is a clock at all, and what it counts down from.
		timed = self.match.timed,
		timeLimit = self.match.timeLimit,
		fighters = self:roster(),
	}
end

function MatchService.rejoin(self: any, player: Player): boolean
	if not self.match or not self.sources[player.UserId] then return false end
	-- The client creates a fresh predictor on rejoin. Reset its input sequence too, and reject
	-- in-flight input from before that reset rather than counting it in the new history.
	self.inputEpochs[player.UserId] = (self.inputEpochs[player.UserId] or 0) + 1
	self.input:register(self.sources[player.UserId])
	local cfg = self:description()
	cfg.inputEpoch = self.inputEpochs[player.UserId]
	Net.remote("Match"):FireClient(player, cfg)
	if self.finished then Net.remote("Results"):FireClient(player, self:results()) end
	return true
end

-- Spectators: someone watching joins the audience and is sent the match as it stands; their client
-- finds no fighter of its own in the roster and simply draws. Leaving takes them out again.
function MatchService.addViewer(self: any, player: Player): boolean
	if not self.match or not self.audience or self.finished then return false end
	if table.find(self.audience, player) then return true end
	table.insert(self.audience, player)
	Net.remote("Match"):FireClient(player, self:description())
	return true
end

function MatchService.removeViewer(self: any, player: Player)
	if not self.audience or self.sources[player.UserId] then return end
	local at = table.find(self.audience, player)
	if at then table.remove(self.audience, at) end
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
	self.inputEpochs = {}
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
	self:send("Results", self:results())
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
			damage = row.damage, taken = row.taken, percent = row.percent,
			stocks = row.stocks, score = row.score,
		})
	end
	return {
		rows = rows, winnerTeam = r.winnerTeam, teams = r.teams, mode = r.mode, timed = r.timed,
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
-- Complete snapshots are reliable and capped at 30Hz (simulation/input stay at 60Hz). Four
-- fighters exceeded the unreliable packet limit. Never throttle the discrete event stream.
function MatchService.broadcast(self: any)
	local m = self.match
	-- Separate world state keeps the fighter/prediction format independent of effect complexity.
	if m.frame - self.sceneFrame >= 2 or m.state == "results" then
		local scene = SceneSnapshot.encode(m)
		scene.id = self.generation
		self:send("Scene", scene)
		self.sceneFrame = m.frame
	end
	if m.frame - self.snapshotFrame >= 2 or m.state == "results" then
		self.snapshotFrame = m.frame
		local fighters = table.create(#m.fighters)
		for i, f in m.fighters do
			fighters[i] = Snapshot.encode(f)
		end
		self:send("Snapshot", {
			id = self.generation,
			frame = m.frame, state = m.state, time = m.time,
			countdown = m.countdown, fighters = fighters,
			platforms = Stage.dynamicState(m.stage),
			-- Count consumed frames per human. A sparse table keyed by index would not survive
			-- transport intact, so acknowledgements remain a list.
			acks = self:acks(),
		})
	end
	if #m.events > 0 then
		-- With the frame they happened on: snapshots go out at 30Hz, so a client stamping an event
		-- with its newest snapshot's frame would be up to a frame late, and the ultimate's cutscene
		-- (UltCinematic) is timed in frames from its event.
		self:send("Events", m.events, m.frame)
		m.events = {}
	end
end

function MatchService.acks(self: any): { any }?
	local out = nil
	for _, f in self.match.fighters do
		if not f.isBot then
			out = out or {}
			table.insert(out, { i = f.index, n = self.input:consumedBy(f.source), e = self.inputEpochs[self.userIds[f.source]] or 0 })
		end
	end
	return out
end

-- ---------------------------------------------------------------- input ----
function MatchService.receiveInput(self: any, player: Player, packed: any, matchId: any, epoch: any)
		local source = self.sources[player.UserId]
		if not source or matchId ~= self.generation or type(packed) ~= "table" then
			return
		end
		if (epoch or 0) ~= (self.inputEpochs[player.UserId] or 0) then return end
		-- Length is bounded here as well as in RemoteInput: an unbounded table from a client is a
		-- way to make the server walk a million entries before the queue cap ever runs.
		if #packed > 16 then
			return
		end
		self.input:push(source, packed)
end
function MatchService.bindRemotes(self: any)
	Net.remote("Input").OnServerEvent:Connect(function(player: Player, packed: any, matchId: any, epoch: any)
		self:receiveInput(player, packed, matchId, epoch)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local source = self.sources[player.UserId]
		if source then
			self.input.sources[source] = nil
		end
		self.sources[player.UserId] = nil
	end)
end

return MatchService
