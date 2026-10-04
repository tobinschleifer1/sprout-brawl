--!nocheck
-- Development tool, not a test: plays one fighter's ultimate in a real Match and draws chosen
-- frames through the SHIPPING fight renderer (FightScene, the same call the client makes every
-- frame), with a recording canvas, as JSON for tools/fight-png.mjs. The game renders into a
-- ScreenGui, so Studio's screenshot of a fight is empty; this is how to look at one without it.
--
--   lune run tools/render-fight <out.json> <weapon> <frames,comma,separated> [avatar] [stage] [enemies]
--
-- The caster starts at x = -5 facing right with a full meter and presses the ultimate on the
-- first fighting frame (and again every 20 frames, which is how Deadeye fires its rounds). The
-- enemies stand still to the right. Frames count from that first press. `avatar` is a preset id,
-- a kit code (k1...), or an avatar name from Data/Avatars; `enemies` is how many (default 2).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local SceneSnapshot = Loader.load("SceneSnapshot")
local Stages = Loader.load("Data/Stages")
local KIT = Loader.load("Data/AvatarKit")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local FightScene = Loader.loadFrom("src/client/", "FightScene")
local Effects = Loader.loadFrom("src/client/", "Effects")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local UltCinematic = Loader.loadFrom("src/client/", "UltCinematic")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local World2D = Loader.loadFrom("src/client/", "World2D")
local Stage = Loader.load("Stage")
local Camera2D = Loader.loadFrom("src/client/", "Camera2D")

local W, H = 960, 540
local Recorder = require("./recorder")
local shapes = Recorder.install(Canvas)

local out, weapon = process.args[1], process.args[2]
local wanted = {}
for n in string.gmatch(process.args[3] or "10,30,50", "[^,]+") do wanted[tonumber(n)] = true end
local avatarArg = process.args[4] or "Classic"
local stageId = process.args[5] or "FoundryFloor"
local enemyCount = tonumber(process.args[6] or "2") or 2
local gap = tonumber(process.args[7] or "7") or 7
-- "left": the caster starts on the right and faces left, so the mirrored drawing is seen too
local side = if process.args[8] == "left" then -1 else 1
-- "calm": nobody presses anything - for looking at a stage
local noUlt = process.args[9] == "calm" or process.args[9] == "wide" or process.args[9] == "brawl" or process.args[9] == "combo"
-- "brawl": every fighter is a hard bot, to see ordinary hits, shields and launches
local brawl = process.args[9] == "brawl"
-- "combo": the caster plays a timed string into its finisher (Light pressed as each hit lands) on
-- the first enemy, who starts at 120% - for looking at the combo effects and the counter's events
local comboMode = process.args[9] == "combo"
-- "wide": a fixed camera on the whole stage instead of the fight camera
local wide = process.args[9] == "wide"
-- a disaster to force, from 0.1 s into the fight (frames then count from the fight's start)
local disaster = process.args[10]

local avatar = avatarArg
for _, p in KIT.presets do if p.id == avatarArg then avatar = p.code end end
local stageData = Stages.LIST[1]
for _, s in Stages.LIST do if s.id == stageId then stageData = s end end

local held: { [string]: boolean } = {}
local inputs = { poll = function() end, get = function(_, source)
	local f = Input.emptyFrame()
	if held[source] then f.ult = true end
	if comboMode and source == "p1" and held.light then f.light = true; f.anyPress = true end
	return f
end }
local fighters = { { char = Loadout.build(avatar, weapon), source = "p1", team = 0 } }
local foes = { "Sword", "Hammer", "Daggers" }
local foeLooks = { "Noir", "Classic", "Noir" }
for i = 1, enemyCount do
	table.insert(fighters, { char = Loadout.build(foeLooks[i], foes[i]), source = "e" .. i, team = i })
end
local match = Match.new({ mode = "Training", stage = stageData, seed = 1, items = false, input = inputs, fighters = fighters,
	disasters = if disaster then "chaos" else nil, forceDisaster = disaster, disasterFirstAt = if disaster then 0.1 else nil })
match.state = "fight"
local caster = match.fighters[1]
caster:reset(-5 * side, match.stage.main.top, { state = "idle", invincible = 0 })
caster.onGround, caster.platform, caster.facing = true, match.stage.main, side
for i = 2, #match.fighters do
	local f = match.fighters[i]
	f:reset((-5 + (if i == 2 then gap else gap + 6)) * side, match.stage.main.top, { state = "idle", invincible = 0 })
	f.onGround, f.platform, f.facing = true, match.stage.main, -side
end
local chars = {}
for i, f in match.fighters do chars[i] = f.char end
if brawl then
	for _, f in match.fighters do f.isBot = true; f.botLevel = "hard" end
end
Fighter2D.effects = nil

local fx, player = Effects.new(), FxPlayer.new()
World2D.effects = fx
local frames = {}
local last = 0
for n in pairs(wanted) do last = math.max(last, n) end
local ultFrame = nil
local rand = (function() local s = 7; return function() s = (s * 48271) % 2147483647; return s / 2147483647 end end)()
for frame = 0, last do
	caster.ultCharge = if frame == 0 then 100 else caster.ultCharge
	held.p1 = not noUlt and (frame == 0 or (frame % 20 == 0 and frame < 140))
	if comboMode then
		if frame == 0 then match.fighters[2].percent = 120 end
		held.light = frame == 1 or (caster.state == "attack" and caster.moveLanded and caster.moveId ~= "Finisher")
	end
	match:step()
	local states = {}
	for _, f in match.fighters do table.insert(states, Snapshot.decode(Snapshot.encode(f))) end
	local scene = SceneSnapshot.encode(match)
	for _, e in match.events do
		if comboMode and (e.type == "perfectlink" or (e.type == "hit" and e.attacker == 0)) then
			print(`frame {frame}: {e.type}{if e.finisher then " (finisher)" else ""}{if e.streak then " streak " .. e.streak else ""}`)
		end
		if e.type == "ultimate" and not ultFrame then ultFrame = frame end
		FightScene.spawn(fx, player, e, states, chars, function(i) local ch = chars[(i or 0) + 1]; return ch and ch.weaponPalette.glow end,
			rand, function() return 5.2 end, true)
	end
	table.clear(match.events)
	Effects.step(fx, 1 / 60)
	FxPlayer.step(player, 1 / 60)
	if wanted[frame] then
		table.clear(shapes)
		-- framed by the game's own fight camera
		local bodies = {}
		for i, st in states do table.insert(bodies, { x = st.x, y = st.y, h = chars[i].height, alive = st.alive }) end
		local cam = Camera2D.new()
		Camera2D.snapTo(cam, bodies, { X = W, Y = H })
		local ppu = cam.ppu
		if wide then cam.x, cam.y, ppu = 0, 8, H / 52 end
		local cine = UltCinematic.at(if ultFrame then frame - ultFrame else -1)
		local casterState = if ultFrame then states[1] else nil
		local view = { x = cam.x, y = cam.y, ppu = ppu }
		if cine.active and casterState then
			view = UltCinematic.punch(view.x, view.y, ppu, casterState.x, casterState.y + chars[1].height * 0.5, cine.zoom)
		end
		local c = Recorder.canvas(Canvas, W, H)
		local stageView = Stage.new(stageData, 1)
		FightScene.draw(c, { view = view, shakeX = 0, shakeY = 0, stage = stageView, platforms = nil, scene = scene,
			states = states, chars = chars, t = frame / 60, fx = fx, player = player,
			cine = cine, caster = casterState, casterChar = chars[1],
			ult = { colour = chars[1].weaponPalette.glow, weapon = weapon } })
		table.insert(frames, { frame = frame, shapes = table.clone(shapes) })
		print(`frame {frame}: {#shapes} shapes, caster {states[1].state}/{states[1].moveId} mf={states[1].moveFrame}`)
	end
end
fs.writeFile(out, serde.encode("json", { w = W, h = H, frames = frames }))
