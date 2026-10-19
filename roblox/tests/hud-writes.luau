--!nocheck
-- A cached HUD must still follow every meaningful state transition, including a missing fighter
-- and a rebuilt roster. A repeated frame writes nothing, including while a callout/prompt shows.
local Scene = require("../tools/perf-scene")
local Rbx = require("@lune/roblox")
local scene = Scene.new()
local P, h, S = scene.probe, scene.hud, scene.state
local Ui, Colours = P:load("src/client/Ui"), P:load("src/client/HudColors")
scene:prepare(1)
scene.canvas:world(0, 4, 18, 0, 0)
local function draw()
	h:update(S.states, scene.snap, scene.canvas, S.chars, scene.cfg)
end
local function quiet()
	draw(); P:reset(); draw()
	assert(P.total.writes == 0 and P.total.creates == 0 and P.total.destroys == 0,
		`unchanged HUD wrote {P.total.writes} properties or changed Instance lifetime`)
end
quiet()
local s, tile, float = S.states[1], h.tiles[1], h.floats[1]
s.percent, s.stocks, s.ultCharge, s.state = 116.6, 2, 20, "shield"
draw()
assert(tile.pct.Text == "117%" and string.find(float.Text, "117%%"), "percent labels stayed cached")
local HudModule = P:load("src/client/Hud")
assert(tile.pct.TextColor3 == HudModule.cardPercent(116.6) and float.TextColor3 == Colours.percent(116.6), "damage colour stayed cached")
for i, pip in tile.pips do assert(pip.Visible == (i <= 2), "stock pip stayed cached") end
for _, block in tile.ult do assert(block.BackgroundColor3 == Ui.GOLD, "ready meter failed to turn gold") end
assert(tile.shield.Text == "SHIELD UP", "shield text stayed cached")
quiet()
s.ultCharge = 4
draw()
for i, block in tile.ult do
	assert(block.BackgroundColor3 == (if i <= 2 then tile.colour else P:load("src/client/Hud").SLATE), "meter failed to discharge")
end
s.state, s.hitlag, s.comboHits, s.breakCooldown = "hitstun", 4, 4, 0
quiet()
assert(h.breakPrompt.Visible, "break prompt did not appear")
s.hitlag = 0
draw()
assert(not h.breakPrompt.Visible, "break prompt stayed visible after hitlag")
local p = float.Position
s.x += 3
draw()
assert(float.Position ~= p, "head label stopped tracking the camera/fighter")
s.alive, s.stocks, s.state = false, 0, "ko"
draw()
assert(not float.Visible and tile.root.BackgroundTransparency > 0.5, "KO failed to hide/dim HUD")
s.alive, s.stocks, s.state = true, 3, "idle"
draw()
assert(float.Visible and tile.root.BackgroundTransparency < 0.1, "respawn failed to restore HUD")
table.remove(S.states, 1)
draw()
assert(not float.Visible and h.byIndex[0] == nil, "removed fighter survived the reused index table")
table.insert(S.states, 1, s)

scene.snap.state, scene.snap.countdown = "countdown", 120
quiet()
assert(h.callout.Text == "2" and h.guideCard.Visible, "countdown/guide failed to appear")
scene.snap.state = "fight"
h:announce("ko", "A LONG KNOCKOUT")
quiet()
assert(h.callout.TextSize == Ui.px(48) and h.callout.TextTransparency == 0, "long callout changed size")
P.now += h.flash.dur * 0.9
draw()
assert(h.callout.TextTransparency > 0 and h.callout.TextTransparency < 1, "callout failed to fade")
assert(h.calloutOutline.Transparency == h.callout.TextTransparency, "outline failed to follow fade")
P.now += 10
draw()
assert(h.callout.TextTransparency == 1, "expired callout stayed visible")
scene.snap.state = "suddendeath"
draw()
assert(h.timer.Text == "SUDDEN DEATH" and h.timerPill.Size.X.Offset >= Ui.textWidth("SUDDEN DEATH", 30) + 40 and h.timerPill.Size.X.Offset > 124, "timer failed to widen")
scene.snap.state, scene.cfg.timed = "fight", false
draw()
assert(not h.timerPill.Visible, "stock-only match kept its timer")

local B = { rot = 0.2, h = 60, alpha = 0.7, text = { x = 300, y = 90, size = 24 } }
local ult = { label = "Starfall", name = "CPU 1" }
h:ultBanner(B, ult); P:reset(); h:ultBanner(B, ult)
assert(P.total.writes == 0, "identical ultimate banner rewrote properties")
assert(h.ultName.Visible and h.ultName.Text == "STARFALL", "ultimate text missing")
h:ultBanner(nil, nil)
assert(not h.ultName.Visible and not h.ultCaster.Visible, "ultimate banner failed to hide")

-- New Instances must receive all properties even if their fighter's values did not change.
h:bind(scene.cfg.fighters, S.chars, 0, false)
quiet()
assert(h.tiles[1].pct.Text == "117%" and h.floats[1].Visible, "rebind reused stale widget cache")
print("PASS HUD writes: repeated frames are quiet; damage, stocks, meter, prompts, fades, banners and rebind update")
