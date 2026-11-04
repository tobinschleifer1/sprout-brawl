--!strict
-- The fight behind the loading screen (Roblox only; the owner's ask, 2026-11-04): two bots at the
-- top difficulty, a plain Sword and a plain Grimoire, fighting for real in a local Training match -
-- so neither runs out of stocks - and drawn by the game's own fight renderer (FightScene). Their
-- meters refill on a clock as well as from hits, so both keep casting their ultimates.
--
-- It is the client's own simulation, so it needs nothing from the server, and the loading screen
-- (src/first) starts it once the game's modules have arrived. Anything that fails in it is the
-- loading screen's problem only: the screen keeps its falling blocks and loads on.
local Shared = game:GetService("ReplicatedStorage").Shared
local Match = require(Shared.Match)
local Loadout = require(Shared.Loadout)
local Input = require(Shared.Input)
local Snapshot = require(Shared.Snapshot)
local SceneSnapshot = require(Shared.SceneSnapshot)
local Stages = require(Shared.Data.Stages)
local Config = require(Shared.Config)
local FightScene = require(script.Parent.FightScene)
local Effects = require(script.Parent.Effects)
local FxPlayer = require(script.Parent.FxPlayer)
local UltCinematic = require(script.Parent.UltCinematic)
local Camera2D = require(script.Parent.Camera2D)
local LoadingFight = {}
LoadingFight.__index = LoadingFight

LoadingFight.FIGHTERS = { { avatar = "Classic", weapon = "Sword" }, { avatar = "Noir", weapon = "Grimoire" } }
LoadingFight.LEVEL = "impossible"
LoadingFight.STAGE = "FoundryFloor"
-- a meter fills from empty in this many seconds without a hit (hits fill it faster, as in a match)
LoadingFight.ULT_EVERY = 7
-- the most simulation frames one drawn frame catches up: a hitch skips time, it does not spiral
LoadingFight.MAX_STEPS = 4
local FRAME = Config.FRAME
local FULL = Config.ULTIMATE.hitsRequired

-- `canvas` is drawn into each step; `viewport()` is its size in pixels.
function LoadingFight.new(canvas: any, viewport: () -> Vector2, seed: number?): any
	local stage = Stages.LIST[1]
	for _, s in Stages.LIST do if s.id == LoadingFight.STAGE then stage = s end end
	local fighters = {}
	for i, f in LoadingFight.FIGHTERS do
		table.insert(fighters, { char = Loadout.build(f.avatar, f.weapon), source = "bot" .. i, isBot = true, botLevel = LoadingFight.LEVEL })
	end
	local idle = { poll = function() end, get = function() return Input.emptyFrame() end }
	local match = Match.new({ mode = "Training", stage = stage, seed = seed or 1, items = false, input = idle, fighters = fighters })
	match.state = "fight"
	local chars = {}
	for i, f in match.fighters do chars[i] = f.char end
	local self = setmetatable({ canvas = canvas, viewport = viewport, match = match, chars = chars,
		cam = Camera2D.new(), fx = Effects.new(), player = FxPlayer.new(), states = {}, scene = nil,
		frame = 0, acc = 0, t = 0, ult = nil, ults = {} :: { [number]: number }, hits = {} :: { [number]: number }, failed = false }, LoadingFight)
	self:simulate()
	Camera2D.setFloor(self.cam, match.stage.main.top)
	Camera2D.snapTo(self.cam, self:bodies(), viewport())
	return self
end

function LoadingFight.bodies(self: any): { any }
	local out = {}
	for i, st in self.states do table.insert(out, { x = st.x, y = st.y, h = self.chars[i].height, alive = st.alive }) end
	return out
end

local function glowOf(self: any): (number?) -> string?
	return function(i: number?): string?
		local ch = self.chars[(i or 0) + 1]
		return ch and ch.weaponPalette.glow
	end
end

-- One simulation frame: the meters, the match, its events into sparks and drawn moments.
function LoadingFight.simulate(self: any)
	local match = self.match
	for _, f in match.fighters do
		if f.ultActive == 0 then f.ultCharge = math.min(FULL, f.ultCharge + FULL * FRAME / LoadingFight.ULT_EVERY) end
	end
	match:step()
	self.frame += 1
	local states = {}
	for _, f in match.fighters do table.insert(states, Snapshot.decode(Snapshot.encode(f))) end
	self.states, self.scene = states, SceneSnapshot.encode(match)
	for _, e in match.events do
		if e.type == "ultimate" then
			local i = (e.fighter or 0) + 1
			self.ults[i] = (self.ults[i] or 0) + 1
			local pal = self.chars[i] and self.chars[i].weaponPalette
			self.ult = { frame = self.frame, fighter = e.fighter, label = e.label or "ULTIMATE", weapon = e.weapon,
				name = "", colour = pal and pal.glow or "#FFFFFF" }
		end
		if e.type == "hit" and e.attacker then self.hits[e.attacker + 1] = (self.hits[e.attacker + 1] or 0) + 1 end
		FightScene.spawn(self.fx, self.player, e, states, self.chars, glowOf(self), math.random, function() return 5.2 end, true)
	end
	table.clear(match.events)
end

-- Advance by `dt` seconds of wall clock and draw.
function LoadingFight.step(self: any, dt: number)
	self.t += dt
	self.acc = math.min(self.acc + dt, LoadingFight.MAX_STEPS * FRAME)
	while self.acc >= FRAME do
		self.acc -= FRAME
		self:simulate()
	end
	Effects.step(self.fx, dt)
	FxPlayer.step(self.player, dt)
	local vp = self.viewport()
	local cam = self.cam
	cam.shake = self.fx.shake * vp.Y / 270
	Camera2D.setFloor(cam, self.match.stage.main.top)
	Camera2D.update(cam, self:bodies(), dt, vp)
	local ult = self.ult
	if ult and UltCinematic.over(self.frame - ult.frame) then self.ult, ult = nil, nil end
	local cine = UltCinematic.at(if ult then self.frame - ult.frame else -1)
	local caster = nil
	if ult then for _, st in self.states do if st.index == ult.fighter then caster = st end end end
	local casterChar = if caster then self.chars[caster.index + 1] else nil
	local view = { x = cam.x, y = cam.y, ppu = cam.ppu }
	if cine.active and caster and casterChar then
		view = UltCinematic.punch(cam.x, cam.y, cam.ppu, caster.x, caster.y + casterChar.height * 0.5, cine.zoom)
	end
	FightScene.draw(self.canvas, { view = view, shakeX = cam.shakeX, shakeY = cam.shakeY, stage = self.match.stage,
		platforms = nil, scene = self.scene, states = self.states, chars = self.chars, t = self.t, fx = self.fx,
		player = self.player, cine = cine, caster = caster, casterChar = casterChar, ult = ult,
		report = function(_key: number, err: string)
			if not self.failed then warn(`[Blockfall] the loading screen's fight: {err}`) end
			self.failed = true
		end })
	self.canvas:finish()
end

return LoadingFight
