--!strict
-- The UI kit (src/client/Ui.luau) every screen is built from.
--
--   * shade moves a colour toward white or black by the amount asked, and leaves it alone at 0;
--   * a key's cap says its letter, with the long names shortened (CTRL, SPACE);
--   * a button is its text on its colour with an ink border, a lighter shine and a darker lip,
--     an ink outline on its letters unless small, and calls back when pressed; paint recolours the
--     face, the shine and the lip together;
--   * display text wears the outline, body text does not; a keycap is a pale key in ink; a panel
--     with a band carries its title in the band, one without has no band;
--   * a key button has its cap inside it and its words padded clear of it; a hint row lays caps
--     and words left to right without overlap, centred; text widths scale with length and size.
--
--     lune run tests/ui-kit
local Rbx = require("@lune/roblox")
local Color3 = Rbx.Color3
local Loader = require("./loader")

local function fail(msg: string): never
	error(msg, 0)
end

local function signal(): any
	local fns = {}
	return { Connect = function(_, fn) table.insert(fns, fn) end, Fire = function(_, ...) for _, fn in fns do fn(...) end end }
end
local function new(class: string): any
	local props: any = { ClassName = class, Activated = signal(), Name = class, _children = {} }
	props.FindFirstChild = function(_, name) for _, ch in props._children do if ch.Name == name then return ch end end return nil end
	local self: any
	self = setmetatable({}, { __index = props, __newindex = function(_, k, v)
		props[k] = v
		if k == "Parent" and v then table.insert(v._children, self) end
	end })
	return self
end
local codes = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
Loader.gui = { Instance = { new = new }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = codes }
local Ui = Loader.loadFrom("src/client/", "Ui")
-- the bevelled kit's checks below are the pixel theme's; the clean theme (the game's) has its own
Ui.useTheme("pixel")

local function child(o: any, name: string): any
	for _, ch in o._children do if ch.Name == name then return ch end end
	return nil
end
local function strokes(o: any, mode: string): number
	local n = 0
	for _, ch in o._children do if ch.ClassName == "UIStroke" and ch.ApplyStrokeMode == "ApplyStrokeMode." .. mode then n += 1 end end
	return n
end
local function lum(c: any): number return c.R + c.G + c.B end
local function near(a: number, b: number): boolean return math.abs(a - b) < 1e-9 end

-- shade
do
	local c = Color3.fromRGB(100, 50, 200)
	local same = Ui.shade(c, 0)
	if not (near(same.R, c.R) and near(same.G, c.G) and near(same.B, c.B)) then fail("shade 0 changed the colour") end
	local w, k = Ui.shade(c, 1), Ui.shade(c, -1)
	if not (near(w.R, 1) and near(w.G, 1) and near(w.B, 1)) then fail("shade 1 is not white") end
	if not (near(k.R, 0) and near(k.G, 0) and near(k.B, 0)) then fail("shade -1 is not black") end
	local up, down = Ui.shade(c, 0.5), Ui.shade(c, -0.5)
	if not near(up.G, c.G + (1 - c.G) * 0.5) or not near(down.B, c.B * 0.5) then fail("shade 0.5 is not halfway") end
end
-- key labels
if Ui.keyLabel("e") ~= "E" or Ui.keyLabel("LeftControl") ~= "CTRL" or Ui.keyLabel("Space") ~= "SPACE" then fail("key labels") end

-- a button
do
	local pressed = 0
	local face = Color3.fromRGB(46, 104, 178)
	local b = Ui.button(new("Frame"), "GO", face, function() pressed += 1 end)
	if b.ClassName ~= "TextButton" or b.Text ~= "GO" or b.BackgroundColor3 ~= face then fail("the button is not its text on its colour") end
	if strokes(b, "Border") ~= 1 or strokes(b, "Contextual") ~= 1 then fail("a button lacks its ink border or its letters' outline") end
	local shine, lip = child(b, "Shine"), child(b, "Lip")
	if not shine or not lip then fail("a button has no shine or lip") end
	if lum(shine.BackgroundColor3) <= lum(face) or lum(lip.BackgroundColor3) >= lum(face) then fail("the shine is not lighter or the lip not darker") end
	b.Activated:Fire()
	if pressed ~= 1 then fail("pressing the button did not call back") end
	local red = Color3.fromRGB(232, 92, 84)
	Ui.paint(b, red, Ui.INK)
	if b.BackgroundColor3 ~= red or b.TextColor3 ~= Ui.INK then fail("paint did not recolour the face and text") end
	if not near(shine.BackgroundColor3.R, Ui.shade(red, Ui.SHINE).R) or not near(lip.BackgroundColor3.G, Ui.shade(red, Ui.LIP).G) then
		fail("paint left the shine or lip in the old colour")
	end
	local small = Ui.button(new("Frame"), "x", face, nil, { small = true })
	if strokes(small, "Contextual") ~= 0 then fail("a small button's letters are outlined") end
end
-- text, keycap, panel
do
	if strokes(Ui.text(new("Frame"), "BIG", 30, nil, Ui.DISPLAY), "Contextual") ~= 1 then fail("display text has no outline") end
	if strokes(Ui.text(new("Frame"), "small", 12), "Contextual") ~= 0 then fail("body text is outlined") end
	local k = Ui.keycap(new("Frame"), "e")
	if k.Text ~= "E" or k.TextColor3 ~= Ui.INK or lum(k.BackgroundColor3) < 2.5 then fail("a keycap is not a pale key with its letter in ink") end
	local p, band, title = Ui.panel(new("Frame"), "Card", Ui.GREEN, "PLAYER 1")
	if not band or child(p, "Band") ~= band or band.BackgroundColor3 ~= Ui.GREEN or title.Text ~= "PLAYER 1" or child(band, "Title") ~= title then
		fail("a banded panel does not carry its title in its band")
	end
	local plain = Ui.panel(new("Frame"), "Plain")
	if child(plain, "Band") then fail("a plain panel has a band") end
end

-- a key button: its key on a cap inside it, the words padded clear of the cap
do
	local b, cap = Ui.keyButton(new("Frame"), "t", "STAMP", Ui.PINK, nil, 40)
	if cap.Parent ~= b or cap.Text ~= "T" or b.Text ~= "STAMP" then fail("a key button lacks its cap or its word") end
	local pad = child(b, "UIPadding")
	if not pad or pad.PaddingLeft.Offset < cap.Position.X.Offset + cap.Size.X.Offset then fail("a key button's words start under its cap") end
	if cap.Size.Y.Offset >= 40 then fail("the cap is as tall as the button") end
end
-- a hint row: caps and words left to right, none overlapping, centred on the row
do
	local row, total = Ui.hintRow(new("Frame"), "Row", { { "a", "WALK" }, { "Space", "HOP" } }, 24)
	local k1, w1, k2, w2 = child(row, "Key1"), child(row, "Word1"), child(row, "Key2"), child(row, "Word2")
	if not (k1 and w1 and k2 and w2) or k1.Text ~= "A" or k2.Text ~= "SPACE" or w1.Text ~= "WALK" or w2.Text ~= "HOP" then fail("a hint row lacks its caps or words") end
	local function x(o: any): number return o.Position.X.Offset end
	local function right(o: any): number return x(o) + o.Size.X.Offset end
	if right(k1) > x(w1) or right(w1) > x(k2) or right(k2) > x(w2) then fail("a hint row's pieces overlap") end
	if math.abs(x(k1) + total / 2) > 0.5 or math.abs(right(w2) - total / 2) > 0.5 then fail(`a hint row spans {x(k1)}..{right(w2)}, not centred on {total}`) end
	if k2.Size.X.Offset <= k1.Size.X.Offset then fail("a long key's cap is no wider than a letter's") end
end
-- the pixel theme: nothing is rounded; a window has its ink border and a lighter rim inside it;
-- sizes asked of the pixel face come out bigger, never smaller
Ui.useTheme("pixel")
do
	local function radius(o: any): number
		local c = child(o, "UICorner")
		return if c then c.CornerRadius.Offset + c.CornerRadius.Scale * 1000 else 0
	end
	local b = Ui.button(new("Frame"), "GO", Ui.BLUE)
	local p = Ui.panel(new("Frame"), "Card", Ui.GREEN, "P1")
	local pill = Ui.pill(new("Frame"), "Pill")
	local k = Ui.keycap(new("Frame"), "e")
	for _, o in { b, p, pill, k, Ui.corner(new("Frame"), 12).Parent or b } do
		if radius(o) ~= 0 then fail("a box is rounded") end
	end
	for _, o in { p, pill } do
		local rim = child(o, "Rim")
		if not rim or rim.BackgroundTransparency ~= 1 or strokes(rim, "Border") ~= 1 then fail("a window has no see-through rim inside its border") end
		if rim.Position.X.Offset < 1 or rim.Size.X.Offset > -2 then fail("a window's rim is not inside it") end
	end
	local shine = child(b, "Shine")
	if shine.Size.X.Scale ~= 1 or shine.Size.X.Offset ~= 0 then fail("a button's shine is not a full-width pixel strip") end
	for _, n in { 8, 14, 22, 40 } do
		if Ui.px(n) < n or Ui.px(n) ~= math.floor(Ui.px(n)) then fail(`px({n}) is {Ui.px(n)}`) end
	end
	if Ui.text(new("Frame"), "x", 22).TextSize ~= Ui.px(22) then fail("text is not drawn at px of its size") end
end

-- the clean theme (the game's): rounded boxes, no inner rim, flat buttons, smooth faces; a header
-- bar is rounded on top and square where it meets its card
Ui.useTheme("clean")
do
	local T = Ui.THEMES.clean
	if string.find(tostring(Ui.DISPLAY), "Arcade") or string.find(tostring(Ui.LABEL), "Arcade") then fail("the clean theme kept the pixel face") end
	local b = Ui.button(new("Frame"), "GO", Ui.BLUE)
	local c = child(b, "UICorner")
	if not c or c.CornerRadius.Offset ~= T.radius or T.radius <= 0 then fail("a clean button is not rounded") end
	if child(b, "Shine").BackgroundTransparency ~= 1 or child(b, "Lip").BackgroundTransparency ~= 1 then fail("a clean button has a bevel") end
	local p = Ui.panel(new("Frame"), "Card", Ui.GREEN, "P1")
	local rim = child(p, "Rim")
	local rimStroke = nil
	for _, ch in rim._children do if ch.ClassName == "UIStroke" then rimStroke = ch end end
	if not rimStroke or rimStroke.Thickness ~= 0 then fail("a clean window draws an inner rim") end
	local band = Ui.band(new("Frame"), Ui.RED, 30)
	if not child(band, "UICorner") or not child(band, "Square") or child(band, "Ledge") then fail("a clean header bar is not rounded on top and flat") end
	Ui.paintBand(band, Ui.GREEN)
	if child(band, "Square").BackgroundColor3 ~= Ui.GREEN then fail("paintBand left the bar's square half in the old colour") end
	if child(b, "UIStroke") and #b._children > 0 then
		for _, ch in b._children do if ch.ClassName == "UIStroke" and ch.ApplyStrokeMode == "ApplyStrokeMode.Contextual" then fail("a clean button outlines its letters") end end
	end
	-- white on a light face is unreadable: gold takes ink letters, a dark face keeps what was asked
	Ui.paint(b, Ui.GOLD, Ui.WHITE)
	if b.TextColor3 ~= Ui.INK then fail("a gold button kept white letters") end
	Ui.paint(b, Ui.PANEL2, Ui.WHITE)
	if b.TextColor3 ~= Ui.WHITE then fail("a dark button did not take the letters asked for") end
	if child(Ui.keycap(new("Frame"), "e"), "Lip").BackgroundTransparency ~= 1 then fail("a clean keycap has a bevel lip") end
	-- a smooth face is scaled by the theme's own scale; the pixel face always by ARCADE_SCALE
	if Ui.px(20) ~= math.floor(20 * T.scale + 0.5) or Ui.px(20, "Font.Arcade") ~= math.floor(20 * Ui.ARCADE_SCALE + 0.5) then fail("px does not scale by face") end
end

-- widths grow with the words; no top bar outside Roblox
if Ui.textWidth("ABCDEFGHIJ", 10) ~= 2 * Ui.textWidth("ABCDE", 10) or Ui.textWidth("ABCDE", 20) ~= 2 * Ui.textWidth("ABCDE", 10) then fail("text widths do not scale") end
if Ui.topInset() ~= 0 then fail("a top inset outside Roblox") end

print("PASS ui kit: clean theme (rounded, flat, smooth faces, rounded header bars), pixel theme (square windows with rims), shade, key labels, bevelled buttons (shine, lip, outlines, paint), outlined display text, keycaps, banded panels, key buttons, hint rows, text widths")
