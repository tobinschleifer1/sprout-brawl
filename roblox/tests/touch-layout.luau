--!nocheck
-- Touch controls' layout (shared/TouchLayout; the owner's ask, 2026-11-02): one layout, measured
-- in a main button's diameter, right on every phone and tablet. At each real device's landscape
-- size (Roblox logical pixels): every control wholly on screen, under the HUD's top band, none
-- overlapping, none smaller than a thumb can hit, the stick and the buttons far enough apart for
-- two thumbs, and the lobby's two clear of its button row. Then the customisation: kept as
-- sanitize rebuilds it, a drag stored and placed back where it was dropped, never off screen.
--     lune run tests/touch-layout
local Loader = require("./loader")
local TouchLayout = Loader.load("TouchLayout")
local function fail(msg: string): never error(msg, 0) end

-- (the HUD's top band on a touch screen: the clock, and the ability pill under it to y 88 - Hud)
local TOP = 96
local SCREENS = {
	{ "iPhone SE", 568, 320 }, { "iPhone 8", 667, 375 }, { "iPhone 8 Plus", 736, 414 }, { "iPhone X/11 Pro", 812, 375 },
	{ "iPhone 12-15", 844, 390 }, { "iPhone 11/XR", 896, 414 }, { "iPhone Pro Max", 932, 430 }, { "small Android", 640, 360 },
	{ "Android", 800, 360 }, { "Pixel", 915, 412 }, { "iPad mini", 1133, 744 }, { "iPad", 1080, 810 }, { "iPad 10th", 1180, 820 },
	{ "iPad Pro 11", 1194, 834 }, { "iPad Pro 12.9", 1366, 1024 }, { "Android tablet", 1280, 800 }, { "Galaxy Tab", 1138, 712 },
	{ "large Android tablet", 1600, 1000 },
}
local LOBBY_ROW = 96                                       -- the lobby's icon buttons: 76 + 10 + a gap

for _, s in SCREENS do
	local name, w, h = s[1], s[2], s[3]
	local class = TouchLayout.class(w, h)
	if (h >= 600) ~= (class == "tablet") then fail(`{name} is a {class}`) end
	local placed = TouchLayout.layout(w, h)
	local margin = TouchLayout.margin(w, h)
	for _, c in TouchLayout.CONTROLS do
		local p = placed[c.id]
		if p.x - p.r < margin - 0.01 or p.x + p.r > w - margin + 0.01 or p.y + p.r > h - margin + 0.01 then fail(`{name} {w}x{h}: {c.id} runs off the screen`) end
		if p.y - p.r < TOP then fail(`{name} {w}x{h}: {c.id} reaches into the HUD's top band (top {math.floor(p.y - p.r)})`) end
		if p.r * 2 < TouchLayout.MIN_TOUCH then fail(`{name} {w}x{h}: {c.id} is {math.floor(p.r * 2)} px, too small to hit`) end
		-- (the defaults are never pushed by the screen's edge: a clamp would mean a squeezed layout)
		local m = TouchLayout.unit(w, h)
		local wantX = if c.side == "left" then margin + c.x * m else w - margin - c.x * m
		if math.abs(p.x - wantX) > 0.01 or math.abs(p.y - (h - margin - c.y * m)) > 0.01 then fail(`{name} {w}x{h}: {c.id} was squeezed off its place`) end
	end
	local clash = TouchLayout.overlaps(placed)
	if #clash > 0 then fail(`{name} {w}x{h}: {clash[1][1]} overlaps {clash[1][2]}`) end
	-- two thumbs: a clear stretch between the stick and the nearest button, at least 15% of the width
	local stickRight = placed.stick.x + placed.stick.r
	local nearest = math.huge
	for _, c in TouchLayout.CONTROLS do
		if c.side == "right" then nearest = math.min(nearest, placed[c.id].x - placed[c.id].r) end
	end
	if nearest - stickRight < w * 0.15 then fail(`{name} {w}x{h}: only {math.floor(nearest - stickRight)} px between the stick and the buttons`) end
	-- the lobby: JUMP lifted over its button row (bottom right); the stick, at the left, stays put
	local lobby = TouchLayout.layout(w, h, nil, LOBBY_ROW)
	if lobby.jump.y + lobby.jump.r > h - margin - LOBBY_ROW + 0.01 then fail(`{name}: the lobby's JUMP sits on its button row`) end
	if lobby.jump.y - lobby.jump.r < TOP then fail(`{name} {w}x{h}: the lobby's JUMP reaches the top band`) end
	if math.abs(lobby.stick.y - placed.stick.y) > 0.01 then fail(`{name}: the lobby lifted the stick too`) end
end

-- the sizes are the thumb's: a phone's main button 56-70 px, a tablet's no bigger than 96
if TouchLayout.unit(568, 320) ~= 56 or math.abs(TouchLayout.unit(812, 375) - 63.75) > 0.01 or TouchLayout.unit(1366, 1024) ~= 96 then
	fail("the main button's size is not 17% of a phone's short side and at most 96 on a tablet")
end

-- customisation: kept as sanitize rebuilds it
do
	local c = TouchLayout.sanitize({ opacity = 3, phone = { light = { dx = 1, dy = "x", s = 9 }, nope = { dx = 1 }, jump = { dx = 0, dy = 0, s = 1 } },
		tablet = "bad" })
	if c.opacity ~= 1 or c.phone.light.dx ~= 1 or c.phone.light.dy ~= 0 or c.phone.light.s ~= TouchLayout.SCALE_MAX then fail("a customisation was kept out of range") end
	if c.phone.nope or c.phone.jump or next(c.tablet) ~= nil then fail("a customisation kept an unknown control, a no-op, or a bad table") end
	local d = TouchLayout.sanitize(nil)
	if d.opacity ~= TouchLayout.OPACITY or next(d.phone) ~= nil then fail("the default customisation is not empty") end
	if TouchLayout.sanitize({ opacity = 0 / 0 }).opacity ~= TouchLayout.OPACITY then fail("a NaN opacity was kept") end
	-- a drag: stored as an offset, placed back exactly where it was dropped, on the class it was made for
	local w, h = 812, 375
	local dx, dy = TouchLayout.offsetFor(w, h, "light", 500, 200)
	local custom = TouchLayout.sanitize({ phone = { light = { dx = dx, dy = dy, s = 1.3 } } })
	local p = TouchLayout.layout(w, h, custom).light
	if math.abs(p.x - 500) > 0.01 or math.abs(p.y - 200) > 0.01 then fail(`a dragged button came back at {p.x},{p.y}, not where it was dropped`) end
	if math.abs(p.r - 1.15 * TouchLayout.unit(w, h) * 1.3 / 2) > 0.01 then fail("a resized button kept its old size") end
	if math.abs(TouchLayout.layout(1180, 820, custom).light.x - TouchLayout.layout(1180, 820).light.x) > 0.01 then fail("a phone's change moved the tablet's button") end
	-- the left stick drags the right way too
	local sdx, sdy = TouchLayout.offsetFor(w, h, "stick", 200, 250)
	local sp = TouchLayout.layout(w, h, TouchLayout.sanitize({ phone = { stick = { dx = sdx, dy = sdy } } })).stick
	if math.abs(sp.x - 200) > 0.01 or math.abs(sp.y - 250) > 0.01 then fail("a dragged stick came back elsewhere") end
	-- never off screen, however far it is dragged
	local far = TouchLayout.layout(w, h, TouchLayout.sanitize({ phone = { light = { dx = -40, dy = 40, s = 1.6 } } })).light
	local margin = TouchLayout.margin(w, h)
	if far.x + far.r > w - margin + 0.01 or far.y - far.r < margin - 0.01 then fail("a button dragged far was put off the screen") end
	local farLeft = TouchLayout.layout(w, h, TouchLayout.sanitize({ phone = { light = { dx = 40, dy = -40 } } })).light
	if farLeft.x - farLeft.r < margin - 0.01 or farLeft.y + farLeft.r > h - margin + 0.01 then fail("a button dragged far the other way was put off the screen") end
	-- overlaps are found
	local stacked = TouchLayout.layout(w, h, TouchLayout.sanitize({ phone = { heavy = { dx = TouchLayout.BY_ID.light.x - TouchLayout.BY_ID.heavy.x,
		dy = TouchLayout.BY_ID.light.y - TouchLayout.BY_ID.heavy.y } } }))
	if #TouchLayout.overlaps(stacked) == 0 then fail("two buttons on top of each other were not found overlapping") end
end

-- the tutorial's cards name a touch screen's controls
if TouchLayout.labelFor("light") ~= "ATTACK" or TouchLayout.labelFor("guard") ~= "SHIELD" or TouchLayout.labelFor("left") ~= "STICK LEFT"
	or TouchLayout.labelFor("ult") ~= "ULT" then fail("a touch control is named wrongly for the tutorial's cards") end
for _, c in TouchLayout.CONTROLS do
	if c.action and TouchLayout.labelFor(c.action) ~= c.label then fail(`{c.id}'s card name is not its button's`) end
end
print(`PASS touch layout: {#TouchLayout.CONTROLS} controls on {#SCREENS} phones and tablets, each on screen, under the HUD, apart, thumb-sized and unsqueezed,`)
print("  two thumbs' room between stick and buttons, the lobby's lifted over its row; customisations sanitised, dropped where dragged, per class, never off screen")
