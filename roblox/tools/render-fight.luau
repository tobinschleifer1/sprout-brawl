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
local Color3 = require("@lune/roblox").Color3
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

local W, H = 960, 540
local shapes = {}
local function hex(c: any): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	local m = c.m
	local function P(u: number, v: number) return { m.a * u + m.c * v + m.e, m.b * u + m.d * v + m.f } end
	table.insert(shapes, { "p", P(x, y), P(x + w, y), P(x + w, y + h), P(x, y + h), hex(colour), (alpha or 1) * c.alpha })
end
Canvas.ellipse = function(c: any, x: number, y: number, rx: number, ry: number, colour: any, alpha: number?)
	-- an ellipse under a rotation is still drawn axis-aligned on screen; good enough for a preview
	local m = c.m
	local cx, cy = m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f
	local sx = math.sqrt(m.a * m.a + m.b * m.b)
	local sy = math.sqrt(m.c * m.c + m.d * m.d)
	table.insert(shapes, { "e", cx, cy, math.abs(rx * sx), math.abs(ry * sy), hex(colour), (alpha or 1) * c.alpha })
end
Canvas.circle = function(c: any, x: number, y: number, r: number, colour: any, alpha: number?)
	Canvas.ellipse(c, x, y, r, r, colour, alpha)
end
Canvas.sprite = function(c: any, _key: string, rects: any, x0: number, y1: number, pw: number, ph: number, _cols, _rows, alpha: number?)
	Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, h, hx, a)
		Canvas.rect(c, x, y, w, h, Color3.fromHex(hx), a * (alpha or 1))
	end)
end

local out, weapon = process.args[1], process.args[2]
local wanted = {}
for n in string.gmatch(process.args[3] or "10,30,50", "[^,]+") do wanted[tonumber(n)] = true end
local avatarArg = process.args[4] or "Classic"
local stageId = process.args[5] or "FoundryFloor"
local enemyCount = tonumber(process.args[6] or "2") or 2
local gap = tonumber(process.args[7] or "7") or 7
-- "left": the caster starts on the right and faces left, so the mirrored drawing is seen too
local side = if process.args[8] == "left" then -1 else 1

local avatar = avatarArg
for _, p in KIT.presets do if p.id == avatarArg then avatar = p.code end end
local stageData = Stages.LIST[1]
for _, s in Stages.LIST do if s.id == stageId then stageData = s end end

local held: { [string]: boolean } = {}
local inputs = { poll = function() end, get = function(_, source)
	local f = Input.emptyFrame()
	if held[source] then f.ult = true end
	return f
end }
local fighters = { { char = Loadout.build(avatar, weapon), source = "p1", team = 0 } }
local foes = { "Sword", "Hammer", "Daggers" }
local foeLooks = { "Noir", "Classic", "Noir" }
for i = 1, enemyCount do
	table.insert(fighters, { char = Loadout.build(foeLooks[i], foes[i]), source = "e" .. i, team = i })
end
local match = Match.new({ mode = "Training", stage = stageData, seed = 1, items = false, input = inputs, fighters = fighters })
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
	held.p1 = frame == 0 or (frame % 20 == 0 and frame < 140)
	match:step()
	local states = {}
	for _, f in match.fighters do table.insert(states, Snapshot.decode(Snapshot.encode(f))) end
	local scene = SceneSnapshot.encode(match)
	for _, e in match.events do
		if e.type == "ultimate" and not ultFrame then ultFrame = frame end
		FightScene.spawn(fx, player, e, states, chars, function(i) local ch = chars[(i or 0) + 1]; return ch and ch.weaponPalette.glow end,
			rand, function() return 5.2 end, true)
	end
	table.clear(match.events)
	Effects.step(fx, 1 / 60)
	FxPlayer.step(player, 1 / 60)
	if wanted[frame] then
		table.clear(shapes)
		-- frame the caster and the first enemy, as the follow camera would
		local x0, x1 = math.huge, -math.huge
		for _, s in states do if s.alive then x0, x1 = math.min(x0, s.x), math.max(x1, s.x) end end
		local cx = (x0 + x1) / 2
		local ppu = math.min(30, W / ((x1 - x0) + 26))
		local cine = UltCinematic.at(if ultFrame then frame - ultFrame else -1)
		local casterState = if ultFrame then states[1] else nil
		local view = { x = cx, y = match.stage.main.top + 6, ppu = ppu }
		if cine.active and casterState then
			view = UltCinematic.punch(view.x, view.y, ppu, casterState.x, casterState.y + chars[1].height * 0.5, cine.zoom)
		end
		local c = setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
			gui = { AbsoluteSize = { X = W, Y = H } } }, { __index = Canvas })
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
