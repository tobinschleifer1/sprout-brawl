--!nocheck
local Probe = require("../tools/perf-probe")
local P = Probe.new(960, 540)
local Rbx = require("@lune/roblox")
local Fx = P:load("src/client/FxPlayer")
local p = Fx.new()
local items = p.items
local first = Fx.add(p, "ring", 1, 2, 3, 0.1, "gold")
local second = Fx.add(p, "pop", 2, 2, 3, 0.4, "gold")
local delayed = Fx.add(p, "star", 3, 2, 3, 0.2, "gold", { delay = 0.2 })
local fourth = Fx.add(p, "burst", 4, 2, 3, 0.15, "gold")
p.flash, p.glows[0] = 0.8, { colour = "#ffffff", left = 0.15 }
Fx.step(p, 0.1)
assert(p.items == items, "effect step allocated a replacement array")
assert(#items == 3 and items[1] == second and items[2] == delayed and items[3] == fourth, "compaction changed alpha overlap order")
assert(first.age == 0.1 and delayed.age == 0 and delayed.delay == 0.1, "delay/expiry boundary changed")
assert(math.abs(p.flash - 0.3) < 1e-9 and p.glows[0], "flash/glow timing changed")
Fx.step(p, 0.1)
assert(#items == 2 and items[1] == second and items[2] == delayed and delayed.age == 0, "delay crossing advanced age early")
assert(p.glows[0] == nil and p.flash == 0, "expired glow/flash survived")
Fx.step(p, 0.1)
assert(#items == 2 and delayed.age == 0.1, "live effect disappeared")
Fx.step(p, 0.1)
assert(#items == 0 and p.items == items, "expired tail survived compaction")

-- Static gradients are compiled once per palette, while their geometry still follows viewport
-- size. Use a black-to-white and a white-to-black sky with analytically known band colours.
local Canvas = P:load("src/client/Canvas2D")
local Realm = P:load("src/client/RealmArt")
local realm = table.clone(P:load("src/shared/Realms").LIST[1])
realm.sky = { "#000000", "#555555", "#AAAAAA", "#FFFFFF" }
local rects, hexCalls = {}, 0
local hex = Canvas.hex
Canvas.hex = function(...) hexCalls += 1; return hex(...) end
Canvas.rect = function(_, x, y, w, h, colour) table.insert(rects, { x, y, w, h, colour }) end
Canvas.ellipse, Canvas.sprite = function() end, function() end
local c = setmetatable({ gui = { AbsoluteSize = Rbx.Vector2.new(960, 540) } }, Canvas)
Realm.sky(c, realm, 1, 2)
table.clear(rects); hexCalls = 0
Realm.sky(c, realm, 4, 3)
assert(#rects == 30 and hexCalls == 3, `warm sky rebuilt gradient ({hexCalls} hex calls)`)
for i, r in rects do
	local v = math.floor(255 * (i - 0.5) / 30 + 0.5)
	assert(r[5] == Rbx.Color3.fromRGB(v, v, v), "cached sky band changed colour")
	assert(r[2] == (i - 1) * 540 / 30 and r[3] == 960 and r[4] == 19, "sky band geometry changed")
end
realm.sky = { "#FFFFFF", "#AAAAAA", "#555555", "#000000" }
c.gui.AbsoluteSize = Rbx.Vector2.new(640, 360)
table.clear(rects)
Realm.sky(c, realm, 0, 0)
for i, r in rects do
	local v = math.floor(255 * (1 - (i - 0.5) / 30) + 0.5)
	assert(r[5] == Rbx.Color3.fromRGB(v, v, v), "a new palette inherited the old gradient")
	assert(r[3] == 640 and r[4] == 13, "resize retained the old gradient geometry")
end
print("PASS render reuse: effect order/delay/expiry preserved; sky palette cached independently of camera/viewport")
