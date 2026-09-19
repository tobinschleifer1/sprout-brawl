--!nonstrict
-- One match: countdown, fight, KOs, respawns, items, the timer, sudden death, results.
-- Ported 1:1 from web/src/engine/match.js.
--
-- `cfg.input` is any object with `poll()` and `get(source)`. On the web that is the keyboard and
-- gamepad reader; on Roblox it will be whatever the server assembles from client remotes. The
-- simulation never learns the difference.

local Config = require(script.Parent.Config)
local Stage = require(script.Parent.Stage)
local Fighter = require(script.Parent.Fighter)
local Combat = require(script.Parent.Combat)
local Input = require(script.Parent.Input)
local Ai = require(script.Parent.Ai)

local FRAME = Config.FRAME
local RESPAWN = Config.RESPAWN
local SUDDEN_DEATH = Config.SUDDEN_DEATH

-- JavaScript's Math.round: halves go toward +infinity.
local function jsRound(v: number): number
	return math.floor(v + 0.5)
end

-- Distinct values in first-seen order. `[...new Set(...)]` in JavaScript keeps insertion order, and
-- the results table is built from it, so a `pairs` walk here would reorder the scoreboard.
local function distinct(values: { any }): { any }
	local seen, out = {}, {}
	for _, v in values do
		if not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	return out
end

local Match = {}
local matchMeta = {}
matchMeta.__index = function(self, key)
	if key == "alivePlayers" then
		local out = {}
		for _, f in self.fighters do
			if f.alive or f:stocksLeft() > 0 then
				table.insert(out, f)
			end
		end
		return out
	end
	return Match[key]
end

function Match.new(cfg: any): any
	local self = setmetatable({}, matchMeta)
	self.cfg = cfg
	self.mode = cfg.mode           -- StockFFA | TimedFFA | StockTeams | TimedTeams | Training
	self.teams = string.find(self.mode, "Teams") ~= nil
	self.timed = string.sub(self.mode, 1, 5) == "Timed"
	self.training = self.mode == "Training"
	-- A match is deterministic given its seed, and the seed is kept so it can be replayed from its
	-- inputs. There is no unseeded default here, unlike the JavaScript: a Roblox match without an
	-- explicit seed is a match nobody can reproduce, and the server always has one to give.
	self.seed = bit32.band(cfg.seed or 1, 0xFFFFFFFF)
	self.stage = Stage.new(cfg.stage, self.seed)
	self.input = cfg.input
	self.frame = 0
	self.time = 0
	self.timeLimit = cfg.timeLimit or 180
	self.itemsOn = not not cfg.items
	self.fighters = {}
	for i, fc in cfg.fighters do
		local spawns = self.stage.data.spawns
		local spawnX = spawns[((i - 1) % #spawns) + 1]
		local f = Fighter.new({ index = i - 1, char = fc.char, skin = fc.skin,
			team = if self.teams then fc.team else i - 1, source = fc.source, isBot = fc.isBot,
			botLevel = fc.botLevel, name = fc.name, stocks = cfg.stocks or 3,
			x = spawnX, y = RESPAWN.height })
		f:setState("respawn")
		f.invincible = 0
		f.eliminatedAt = nil
		f.koTimer = 0
		f._match = self
		self.fighters[i] = f
	end
	self.teamPool = {}
	if self.teams then
		for _, f in self.fighters do
			self.teamPool[f.team] = (self.teamPool[f.team] or 0) + (cfg.stocks or 3)
		end
	end
	self.combat = Combat.new(self)
	self.state = "countdown"
	self.countdown = 3 * 60 + 30
	self.events = {}
	self.results = nil
	self.sdTimer = 0
	self.paused = false
	self.ctx = { stage = self.stage, combat = self.combat, match = self }
	-- The input layer wants to know whether anybody is on the second keyboard mapping. Meaningless
	-- on Roblox, ported because it is one line and match.js does it.
	if self.input then
		local any = false
		for _, f in self.fighters do
			if f.source == "kb2" then
				any = true
			end
		end
		self.input.kb2Active = any
	end
	table.insert(self.events, { type = "matchstart" })
	return self
end

function Match.step(self)
	if self.paused or self.state == "results" then
		return
	end
	self.frame += 1
	-- The clock starts on GO. Ticking it through the 3.5s countdown used to shave that time off
	-- every timed match.
	if self.state ~= "countdown" then
		self.time += FRAME
	end
	if self.input and self.input.poll then
		self.input:poll()
	end
	local inputsOn = self.state ~= "countdown"
	for _, f in self.fighters do
		local frame = Input.emptyFrame()
		if inputsOn then
			frame = if f.isBot then Ai.computeBotInput(f, self) else self.input:get(f.source)
		end
		f:applyInput(frame)
	end
	Stage.step(self.stage, self)
	for _, f in self.fighters do
		f:step(self.ctx)
	end
	Combat.step(self.combat)
	-- collect events
	for _, f in self.fighters do
		for _, e in f.events do
			local ev = table.clone(e)
			ev.fighter = f.index
			ev.x = if e.x ~= nil then e.x else f.x
			ev.y = if e.y ~= nil then e.y else f.cy
			table.insert(self.events, ev)
		end
		table.clear(f.events)
	end
	for _, e in self.combat.events do
		table.insert(self.events, e)
	end
	table.clear(self.combat.events)

	if self.state == "countdown" then
		self.countdown -= 1
		if self.countdown == 180 then table.insert(self.events, { type = "count", n = 3 }) end
		if self.countdown == 120 then table.insert(self.events, { type = "count", n = 2 }) end
		if self.countdown == 60 then table.insert(self.events, { type = "count", n = 1 }) end
		if self.countdown <= 0 then
			self.state = "fight"
			table.insert(self.events, { type = "go" })
		end
		return
	end
	-- KOs
	for _, f in self.fighters do
		if f.alive and Stage.outsideBlast(self.stage, f) then
			Match.knockOut(self, f)
		end
		if not f.alive and f.koTimer > 0 then
			f.koTimer -= 1
			if f.koTimer == 0 and (self.training or self.timed or f:stocksLeft() > 0) then
				Match.respawn(self, f)
			end
		end
	end
	if self.itemsOn and self.state == "fight" then
		Combat.maybeSpawnItem(self.combat, #self.fighters)
	end
	if self.state == "suddendeath" then
		self.sdTimer += FRAME
		if self.sdTimer >= SUDDEN_DEATH.shrinkEvery then
			self.sdTimer = 0
			Stage.shrink(self.stage, SUDDEN_DEATH.shrinkFactor)
			table.insert(self.events, { type = "shrink" })
		end
	end
	if self.training then
		return
	end
	if self.timed and self.state == "fight" and self.time >= self.timeLimit then
		local tied = Match.tiedTeams(self)
		if #tied > 1 then
			Match.startSuddenDeath(self, tied)
		else
			Match.finish(self)
		end
		return
	end
	if Match.winnerDecided(self) then
		Match.finish(self)
	end
end

function Match.stocksLeftFor(self, f: any): number
	return if self.teams then self.teamPool[f.team] else f.stocks
end

function Match.knockOut(self, f: any)
	local b = self.stage.blast
	local side = if f.x < b.left then "left"
		elseif f.x > b.right then "right"
		elseif f.y > b.top then "top"
		else "bottom"
	local credit = if f.lastHitBy and f.frameCount - f.lastHitFrame < 480 then f.lastHitBy else nil
	if credit and credit ~= f then
		credit.stats.kos += 1
	else
		f.stats.selfDestructs += 1
	end
	-- Timed modes score on KOs, not stocks, so a KO there costs nothing but the respawn wait.
	if self.timed then
		-- unlimited lives
	elseif self.teams then
		self.teamPool[f.team] = math.max(0, self.teamPool[f.team] - 1)
	else
		f.stocks = math.max(0, f.stocks - 1)
	end
	if self.training then
		f.stocks = 3
	end
	f:knockOut()
	f.koTimer = jsRound(RESPAWN.delay * 60)
	if not self.training and f:stocksLeft() == 0 and not self.timed then
		f.eliminatedAt = self.frame
	end
	table.insert(self.events, { type = "ko", fighter = f.index,
		by = if credit then credit.index else -1,
		x = math.max(b.left, math.min(b.right, f.x)),
		y = math.max(b.bottom, math.min(b.top, f.cy)),
		side = side, last = not self.timed and f:stocksLeft() == 0 })
end

function Match.respawn(self, f: any)
	local spawns = self.stage.data.spawns
	local spawnX = spawns[(f.index % #spawns) + 1]
	f:respawn(spawnX, { percent = if self.state == "suddendeath" then SUDDEN_DEATH.percent else 0 })
	table.insert(self.events, { type = "respawn", fighter = f.index })
end

function Match.teamsAlive(self): { any }
	local live = {}
	for _, f in self.fighters do
		if f.alive or f:stocksLeft() > 0 then
			table.insert(live, f.team)
		end
	end
	return distinct(live)
end

function Match.winnerDecided(self): boolean
	if self.timed then
		return false
	end
	return #Match.teamsAlive(self) <= 1
end

function Match.teamScore(self, team: any): number
	local s = 0
	for _, f in self.fighters do
		if f.team == team then
			s += f.stats.kos - f.stats.selfDestructs
		end
	end
	return s
end

function Match.tiedTeams(self): { any }
	local teams = {}
	for _, f in self.fighters do
		table.insert(teams, f.team)
	end
	teams = distinct(teams)
	local best = -math.huge
	local scores = {}
	for _, t in teams do
		local sc = Match.teamScore(self, t)
		table.insert(scores, { t = t, s = sc })
		if sc > best then
			best = sc
		end
	end
	local out = {}
	for _, x in scores do
		if x.s == best then
			table.insert(out, x.t)
		end
	end
	return out
end

function Match.startSuddenDeath(self, tied: { any })
	self.state = "suddendeath"
	self.timed = false
	self.sdTimer = 0
	local inTie = {}
	for _, t in tied do
		inTie[t] = true
	end
	for _, f in self.fighters do
		if inTie[f.team] then
			f.stocks = 1
			if self.teams then
				self.teamPool[f.team] = 1
			end
			if f.alive then
				f.percent = SUDDEN_DEATH.percent
			else
				f.koTimer = 1
			end
		else
			f.stocks = 0
			if self.teams then
				self.teamPool[f.team] = 0
			end
			if f.alive then
				f:knockOut()
			end
			f.eliminatedAt = self.frame
		end
	end
	table.insert(self.events, { type = "suddendeath" })
end

function Match.finish(self)
	self.state = "results"
	local rows = {}
	for _, f in self.fighters do
		table.insert(rows, {
			index = f.index, name = f.name, char = f.char, team = f.team,
			kos = f.stats.kos, falls = f.stats.falls, sds = f.stats.selfDestructs,
			damage = jsRound(f.stats.damageDealt), percent = f.percent,
			stocks = f:stocksLeft(), score = Match.teamScore(self, f.team),
			eliminatedAt = if f.eliminatedAt == nil then math.huge else f.eliminatedAt,
		})
	end
	-- The final index comparison makes the order TOTAL. JavaScript's sort is stable and Luau's
	-- table.sort is not, so two fighters tied on every other key would have come out in a different
	-- order here; match.js carries the same tiebreak for the same reason.
	local timed = self.timed
	table.sort(rows, function(a, b)
		if timed then
			if a.score ~= b.score then return a.score > b.score end
			if a.percent ~= b.percent then return a.percent < b.percent end
			return a.index < b.index
		end
		if a.eliminatedAt ~= b.eliminatedAt then return a.eliminatedAt > b.eliminatedAt end
		if a.stocks ~= b.stocks then return a.stocks > b.stocks end
		if a.percent ~= b.percent then return a.percent < b.percent end
		return a.index < b.index
	end)
	local teams = {}
	for _, f in self.fighters do
		table.insert(teams, f.team)
	end
	self.results = { rows = rows, winnerTeam = rows[1].team, teams = self.teams,
		timed = string.sub(self.mode, 1, 5) == "Timed", mode = self.mode }
	table.insert(self.events, { type = "game", winner = rows[1].index })
end

function Match.resetTraining(self)
	local spawns = self.stage.data.spawns
	for _, f in self.fighters do
		local spawnX = spawns[(f.index % #spawns) + 1]
		f.alive = true
		f:reset(spawnX, RESPAWN.height, { state = "respawn", percent = 0, invincible = 0 })
	end
	table.clear(self.combat.projectiles)
	table.clear(self.combat.summons)
	table.clear(self.combat.bursts)
	table.clear(self.combat.items)
end

return Match
