--!strict
-- The bullwhip on a Roblox screen: a foe its tip marks wears the gold mark over their head,
-- through the client's own draw (FightScene.draw) from what the snapshot carries - and nobody else
-- does, and it is gone once the mark is spent.
--
--     lune run tests/whip-view
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local FightScene = Loader.loadFrom("src/client/", "FightScene")
local Effects = Loader.loadFrom("src/client/", "Effects")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local Danger = Loader.loadFrom("src/client/", "Danger")

local function fail(msg: string): never
	error(msg, 0)
end

local gold: { any } = {}
-- a recording canvas: rectangles are noted, not built (the transform arithmetic is Canvas2D's own)
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	local want = Canvas.hex("#FFD25A", nil :: any)
	if colour and math.abs(colour.R - want.R) + math.abs(colour.G - want.G) + math.abs(colour.B - want.B) < 1e-6 then
		local m = c.m
		-- back from screen pixels to world units: ppu 1, the camera on the origin of a 1280x720 view
		table.insert(gold, { x = m.a * x + m.c * y + m.e - 640, y = 360 - (m.b * x + m.d * y + m.f) })
	end
end
Canvas.sprite = function() end
Canvas.circle = function() end
Canvas.ellipse = function() end
Canvas.tri = function() end
local function canvas(): any
	return setmetatable({ m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {},
		gui = { AbsoluteSize = { X = 1280, Y = 720 } }, used = 0 }, { __index = Canvas })
end

local data
for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
local idle = { kb2Active = false, poll = function() end, get = function() return Input.emptyFrame() end }
local chars = { Loadout.build("Classic", "Whip"), Loadout.build("Noir", "Sword"), Loadout.build("Ember", "Sword") }
local fighters = {}
for i, ch in chars do table.insert(fighters, { char = ch, skin = 0, team = i - 1, source = `p{i - 1}`, isBot = false, name = `P{i}` }) end
local m = Match.new({ mode = "StockFFA", stage = data, input = idle, seed = 1, stocks = 3, fighters = fighters })
while m.state == "countdown" do m:step() end
local a, v, u = m.fighters[1], m.fighters[2], m.fighters[3]
for i, f in m.fighters do
	f.x, f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = (i - 1) * 6.2, 0, 0, 0, true, m.stage.main, 0
	f:setState("idle")
end
u.x = -20
a.facing, v.facing = 1, -1
local stage = Stage.new(data, 1)

-- Draw the frame as the client would and say where the gold went, in world units (ppu 1, y up).
local function drawn(): { any }
	table.clear(gold)
	local states = {}
	for _, f in m.fighters do table.insert(states, Snapshot.decode(Snapshot.encode(f))) end
	FightScene.draw(canvas(), { view = { x = 0, y = 0, ppu = 1 }, shakeX = 0, shakeY = 0, stage = stage,
		platforms = nil, scene = nil, states = states, chars = chars, t = 0, fx = Effects.new(), player = FxPlayer.new(), cine = nil })
	return gold
end
local function over(list: { any }, f: any): number
	local n = 0
	for _, g in list do
		if math.abs(g.x - f.x) < 1 then n += 1 end
	end
	return n
end

if over(drawn(), v) ~= 0 then fail("gold drawn over the foe before anyone was marked") end
-- a real tip hit through the real combat: the jab, at its tip's distance
a:startMove("LightNeutral1")
for _ = 1, 20 do v.x, v.vx = 6.2, 0; m:step(); table.clear(m.events) end
if a.mech.mark ~= v.index then fail(`the jab at the tip did not mark (mark {a.mech.mark})`) end
local list = drawn()
local onV, onU = over(list, v), over(list, u)
local overHead = 0
for _, g in list do if math.abs(g.x - v.x) < 1 and g.y > v.y + chars[2].height then overHead += 1 end end
if onV == 0 or onU > 0 or overHead < 2 then fail(`the mark drew {onV} gold by the marked foe ({overHead} over their head), {onU} by the other`) end
print(`PASS the whip's mark is drawn over the marked foe only ({onV} gold rectangles), from the snapshot`)
a.mech.mark, a.mech.expires = -1, 0
if over(drawn(), v) ~= 0 then fail("the mark was still drawn once spent") end
print(`PASS and it is gone once spent ({#Danger.markShapes(0, 0, 5, 0, 0)} shapes for a faded mark)`)
