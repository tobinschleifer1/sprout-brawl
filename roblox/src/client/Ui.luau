--!strict
-- Blockfall's UI kit: the retro pixel look every screen is built from, so the plaza, the
-- character studio, the select screen and the fight all read as one game - the one the sprites
-- are drawn in.
--
--   type     one pixel face for everything (Press Start 2P, Roblox's Font.Arcade). Roblox draws it
--            at a little over half its TextSize per letter, so `px` scales the size every builder
--            is asked for; text 16 px or bigger wears an ink outline, smaller text stays bare so
--            it does not fill in
--   colour   the Endesga 32 palette (lospec.com/palette-list/endesga-32): a small fixed set, so
--            every panel, button and bar shares one light and one set of shadows
--   window   square corners, an ink border and a lighter rim just inside it - the double frame of
--            a 16-bit game's text box
--   button   a square block: ink border, a light pixel strip along its top and a dark lip along
--            its bottom, so it reads as raised and pressable
--   keycap   a pale square key with the key's letter on it, for every "press E" in the game
--   panel    a window; optionally with a coloured title bar across its top (the select screen's
--            player cards), its lower edge a darker ledge
--   pill     a dark square strip with a rim, for a line of status
--
-- `paint` recolours a button (shine and lip with it), for tabs and toggles. Pure helpers -
-- `shade`, `keyLabel`, `px` - are tested in tests/ui-kit.luau with the builders.
local Ui = {}

-- One face. DISPLAY, LABEL and BODY are kept as names so a screen still says what its words are
-- for, but they are the same pixel font: a second, smooth font beside it is what made the old UI
-- read as a different game from its sprites.
Ui.DISPLAY = Enum.Font.FredokaOne
Ui.LABEL = Enum.Font.BuilderSansExtraBold
Ui.BODY = Enum.Font.BuilderSansBold

-- Style themes, so directions can be compared on the real screens before one is chosen. A theme
-- must be picked (Ui.useTheme) before any screen module loads: they read the fonts at load.
--   radius   corner radius of every box (0: square)
--   borderK  scales every box's border; outlineK every text outline (0: none)
--   rim      the lighter inner line of a pixel window
--   bevel    "strip" (full-width pixel strips), "inset" (rounded shine and lip), "none" (flat)
--   scale    how much bigger sizes are drawn in the smooth fonts; Arcade always gets ARCADE_SCALE
--   advance  width per letter per TextSize of the widest face in use, for Ui.textWidth
local F = Enum.Font
Ui.THEMES = {
	pixel = { display = F.Arcade, label = F.Arcade, body = F.Arcade, radius = 0, borderK = 1, outlineK = 1, rim = true,
		bevel = "strip", scale = 1.25, advance = 0.5625 },
	pixellite = { display = F.Arcade, label = F.BuilderSansExtraBold, body = F.BuilderSansBold, radius = 0, borderK = 0.67,
		outlineK = 0.5, rim = false, bevel = "strip", scale = 1.1, advance = 0.5625 },
	soft = { display = F.Arcade, label = F.BuilderSansExtraBold, body = F.BuilderSansBold, radius = 10, borderK = 0.67,
		outlineK = 0.5, rim = true, bevel = "inset", scale = 1.1, advance = 0.5625 },
	cartoon = { display = F.LuckiestGuy, label = F.GothamBlack, body = F.GothamBold, radius = 10, borderK = 1, outlineK = 0.75,
		rim = false, bevel = "inset", scale = 1.0, advance = 0.62 },
	clean = { display = F.FredokaOne, label = F.BuilderSansExtraBold, body = F.BuilderSansBold, radius = 8, borderK = 0.5,
		outlineK = 0.4, rim = false, bevel = "none", scale = 1.05, advance = 0.56 },
}
Ui.ARCADE_SCALE = 1.25
local theme = Ui.THEMES.clean
Ui.theme = "clean"

-- Endesga 32
Ui.INK = Color3.fromRGB(24, 20, 37)
Ui.PANEL = Color3.fromRGB(38, 43, 68)
Ui.PANEL2 = Color3.fromRGB(58, 68, 102)
Ui.EDGE = Color3.fromRGB(90, 105, 136)
Ui.WHITE = Color3.fromRGB(255, 255, 255)
Ui.DIM = Color3.fromRGB(139, 155, 180)
Ui.GOLD = Color3.fromRGB(254, 231, 97)
Ui.ORANGE = Color3.fromRGB(247, 118, 34)
Ui.GREEN = Color3.fromRGB(99, 199, 77)
Ui.RED = Color3.fromRGB(228, 59, 68)
Ui.BLUE = Color3.fromRGB(0, 153, 219)
Ui.CYAN = Color3.fromRGB(44, 232, 245)
Ui.PINK = Color3.fromRGB(246, 117, 122)
Ui.PURPLE = Color3.fromRGB(181, 80, 136)
Ui.KEY = Color3.fromRGB(234, 238, 246)

-- How much bigger a size asked of the pixel face is drawn. Roblox fits Press Start 2P's square
-- letters into a little over half of TextSize (16 draws 9 px letters), so sizes chosen for the old
-- smooth fonts would come out small; this keeps the words about as big as they were. Measured in
-- Studio with TextService:GetTextBoundsAsync: 0.5625 px of width per TextSize per letter.
Ui.SCALE = 1.05
Ui.ADVANCE = 0.56
-- `font` is the face the size is for (the LABEL face if not said): Arcade is scaled by
-- ARCADE_SCALE whatever the theme, the smooth faces by the theme's own scale.
function Ui.px(size: number, font: any?): number
	local k = if (font or Ui.LABEL) == Enum.Font.Arcade then Ui.ARCADE_SCALE else Ui.SCALE
	return math.floor(size * k + 0.5)
end

function Ui.useTheme(name: string?)
	local t = Ui.THEMES[name or "clean"]
	if not t then return end
	theme, Ui.theme = t, name or "clean"
	Ui.DISPLAY, Ui.LABEL, Ui.BODY = t.display, t.label, t.body
	Ui.SCALE, Ui.ADVANCE = t.scale, t.advance
end

-- `c` moved toward white (k > 0) or black (k < 0) by |k|.
function Ui.shade(c: Color3, k: number): Color3
	if k >= 0 then
		return Color3.new(c.R + (1 - c.R) * k, c.G + (1 - c.G) * k, c.B + (1 - c.B) * k)
	end
	local m = 1 + k
	return Color3.new(c.R * m, c.G * m, c.B * m)
end

-- What a key is called on its cap: single letters as they are, the long names shortened so they
-- fit a square key.
local SHORT = { LeftControl = "CTRL", RightControl = "CTRL", LeftShift = "SHIFT", RightShift = "SHIFT",
	Space = "SPACE", Return = "ENTER", Escape = "ESC", Tab = "TAB" }
function Ui.keyLabel(key: string): string
	return SHORT[key] or string.upper(key)
end

-- How tall Roblox's own top bar is (its menu and chat buttons sit at the top left, over anything a
-- full-screen GUI puts there); 0 where there is none, as in a test.
function Ui.topInset(): number
	local ok, inset = pcall(function() return (game:GetService("GuiService") :: any):GetGuiInset() end)
	return if ok and type(inset) ~= "nil" and inset.Y then inset.Y else 0
end

function Ui.make(class: string, parent: Instance?, props: any?): any
	local o: any = Instance.new(class)
	for k, v in props or {} do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
-- Every box's corners are the theme's (square in the pixel theme): the caller's radius is kept
-- only so a screen still says which of its boxes are cards.
function Ui.corner(parent: Instance, _r: number): any
	return Ui.make("UICorner", parent, { CornerRadius = UDim.new(0, theme.radius) })
end
function Ui.stroke(parent: Instance, colour: Color3, thick: number): any
	return Ui.make("UIStroke", parent, { Color = colour, Thickness = if thick > 0 then math.max(1, math.floor(thick * theme.borderK + 0.5)) else 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = if theme.radius > 0 then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter })
end
-- the ink outline on a text's letters (not its box)
function Ui.outline(t: Instance, thick: number?): any
	local k = math.floor((thick or 2) * theme.outlineK + 0.5)
	return Ui.make("UIStroke", t, { Color = Ui.INK, Thickness = k, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = if theme.display == Enum.Font.Arcade then Enum.LineJoinMode.Miter else Enum.LineJoinMode.Round })
end
-- A lighter rim just inside a box's ink border: the second line of a pixel window's frame. Its
-- own stroke is drawn outside it, so it sits `inset` px in and is `thick` px wide. Returns the rim
-- and its stroke (to recolour).
function Ui.rim(parent: Instance, colour: Color3, thick: number?, inset: number?): (any, any)
	local t, i = thick or 2, (inset or 0) + (thick or 2)
	local r = Ui.make("Frame", parent, { Name = "Rim", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(i, i), Size = UDim2.new(1, -2 * i, 1, -2 * i) })
	local st = Ui.stroke(r, colour, t)
	if not theme.rim then st.Thickness = 0 end
	if theme.radius > 0 then Ui.corner(r, 0) end
	return r, st
end

-- `size` is the size asked for; the pixel face is drawn at Ui.px(size).
function Ui.text(parent: Instance?, value: string, size: number, colour: Color3?, font: any?): any
	local face = font or Ui.LABEL
	local t = Ui.make("TextLabel", parent, { BackgroundTransparency = 1, Text = value, TextSize = Ui.px(size, face),
		TextColor3 = colour or Ui.WHITE, Font = face, TextXAlignment = Enum.TextXAlignment.Center,
		BorderSizePixel = 0 })
	-- the pixel face outlines everything big enough not to fill in; a smooth theme its display words
	if size >= 16 and (theme.label == Enum.Font.Arcade or face == Ui.DISPLAY) then Ui.outline(t, if size >= 28 then 3 else 2) end
	return t
end

-- How far a button's shine and lip move from its face colour.
Ui.SHINE, Ui.LIP = 0.38, -0.42

-- A button's shine and lip, so `paint` can recolour them with it.
local parts: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

-- opts: small (no outline on the letters - it fills small ones in), textColour, font, size
function Ui.button(parent: Instance?, value: string, colour: Color3, onClick: (() -> ())?, opts: any?): any
	local o = opts or {}
	local face = o.font or Ui.DISPLAY
	local b = Ui.make("TextButton", parent, { Text = value, Font = face, TextSize = Ui.px(o.size or 16, face),
		TextColor3 = o.textColour or Ui.WHITE, BackgroundColor3 = colour, AutoButtonColor = true, BorderSizePixel = 0 })
	Ui.corner(b, 0)
	Ui.stroke(b, Ui.INK, 3)
	if not o.small then Ui.outline(b, 2) end
	-- the bevel: full-width pixel strips (pixel themes), a rounded shine and lip set in from the
	-- edges (rounded themes), or nothing (flat)
	local inset = theme.bevel == "inset"
	local shine = Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(colour, Ui.SHINE),
		BorderSizePixel = 0, Position = if inset then UDim2.fromOffset(6, 3) else UDim2.fromOffset(0, 0),
		Size = if inset then UDim2.new(1, -12, 0, 3) else UDim2.new(1, 0, 0, 3) })
	local lip = Ui.make("Frame", b, { Name = "Lip", BackgroundColor3 = Ui.shade(colour, Ui.LIP), BorderSizePixel = 0,
		Position = if inset then UDim2.new(0, 3, 1, -6) else UDim2.new(0, 0, 1, -4),
		Size = if inset then UDim2.new(1, -6, 0, 4) else UDim2.new(1, 0, 0, 4) })
	if inset then
		Ui.make("UICorner", shine, { CornerRadius = UDim.new(0, 2) })
		Ui.make("UICorner", lip, { CornerRadius = UDim.new(0, 3) })
	elseif theme.bevel == "none" then
		shine.BackgroundTransparency, lip.BackgroundTransparency = 1, 1
	end
	parts[b] = { shine = shine, lip = lip }
	if onClick then b.Activated:Connect(onClick) end
	return b
end

-- Recolour a button, its shine and lip with it.
function Ui.paint(b: any, colour: Color3, textColour: Color3?)
	b.BackgroundColor3 = colour
	if textColour then b.TextColor3 = textColour end
	local p = parts[b]
	if p then
		p.shine.BackgroundColor3 = Ui.shade(colour, Ui.SHINE)
		p.lip.BackgroundColor3 = Ui.shade(colour, Ui.LIP)
	end
end

-- A pale square key with its letter. The caller sizes and places it.
function Ui.keycap(parent: Instance?, key: string, size: number?): any
	local k = Ui.make("TextLabel", parent, { Name = "Key", Text = Ui.keyLabel(key), Font = Ui.DISPLAY, TextSize = Ui.px(size or 14, Ui.DISPLAY),
		TextColor3 = Ui.INK, BackgroundColor3 = Ui.KEY, BorderSizePixel = 0 })
	local round = theme.radius > 0
	if round then Ui.make("UICorner", k, { CornerRadius = UDim.new(0, math.min(theme.radius, 5)) }) else Ui.corner(k, 0) end
	Ui.stroke(k, Ui.INK, 2)
	local shine = Ui.make("Frame", k, { Name = "Shine", BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 2) })
	local lip = Ui.make("Frame", k, { Name = "Lip", BackgroundColor3 = Color3.fromRGB(139, 155, 180), BorderSizePixel = 0,
		Position = if round then UDim2.new(0, 2, 1, -4) else UDim2.new(0, 0, 1, -3), Size = if round then UDim2.new(1, -4, 0, 3) else UDim2.new(1, 0, 0, 3) })
	if round then
		shine.BackgroundTransparency = 1
		Ui.make("UICorner", lip, { CornerRadius = UDim.new(0, 2) })
	end
	return k
end

-- A button with its keyboard key on a cap at its left: "[T] STAMP". `h` is its height, so the
-- cap can be sized to it; returns the button and the cap.
function Ui.keyButton(parent: Instance?, key: string, value: string, colour: Color3, onClick: (() -> ())?, h: number?, opts: any?): (any, any)
	local height = h or 40
	local b = Ui.button(parent, value, colour, onClick, opts)
	local capH = math.floor(height * 0.56)
	local capSize = math.floor(capH * 0.5)
	local cap = Ui.keycap(b, key, capSize)
	local capW = math.max(capH, Ui.textWidth(Ui.keyLabel(key), capSize) + 10)
	cap.Position, cap.Size = UDim2.new(0, 8, 0.5, -capH / 2 - 1), UDim2.fromOffset(capW, capH)
	cap.ZIndex = 2
	Ui.make("UIPadding", b, { PaddingLeft = UDim.new(0, capW + 12), PaddingRight = UDim.new(0, 6) })
	return b, cap
end

-- How wide `value` is in the pixel face asked for at `size` (so drawn at Ui.px(size)), for sizing
-- what holds it without waiting a frame for TextBounds. The face is monospaced, so this is near
-- exact; the 4% covers px rounding the size up by up to half a pixel.
function Ui.textWidth(value: string, size: number): number
	return math.ceil((utf8.len(value) or #value) * size * Ui.SCALE * Ui.ADVANCE * 1.04 - 1e-9)
end

-- The width a key-cap-and-word chip needs with a cap `size` px tall: the cap, and the whole chip.
function Ui.chipWidth(key: string, word: string, size: number): (number, number)
	local capW = math.max(size + 6, Ui.textWidth(Ui.keyLabel(key), math.floor(size * 0.5)) + 12)
	return capW, capW + 8 + Ui.textWidth(word, math.floor(size * 0.5)) + 4
end

-- A centred row of key caps with what each does: [WASD] WALK  [SPACE] HOP  [E] USE. `items` are
-- { key, word } pairs; `size` is the cap's height. Returns the row (placed by the caller, full
-- width of its parent by default) and its total width.
function Ui.hintRow(parent: Instance?, name: string, items: { { string } }, size: number, colour: Color3?): (any, number)
	local row = Ui.make("Frame", parent, { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0 })
	local widths, total = {}, 0
	for i, item in items do
		local _, w = Ui.chipWidth(item[1], item[2], size)
		widths[i] = w
		total += w + (if i > 1 then 18 else 0)
	end
	local x = -total / 2
	for i, item in items do
		local capW = Ui.chipWidth(item[1], item[2], size)
		local cap = Ui.keycap(row, item[1], math.floor(size * 0.5))
		cap.Name = "Key" .. i
		cap.Position, cap.Size = UDim2.new(0.5, x, 0.5, -size / 2), UDim2.fromOffset(capW, size)
		local word = Ui.text(row, item[2], math.floor(size * 0.5), colour or Ui.WHITE, Ui.DISPLAY)
		word.Name = "Word" .. i
		word.TextXAlignment = Enum.TextXAlignment.Left
		-- small words still need to stand off whatever the row is drawn over
		if size * 0.5 < 16 then Ui.outline(word, 2) end
		word.Position, word.Size = UDim2.new(0.5, x + capW + 8, 0.5, -size / 2), UDim2.fromOffset(widths[i] - capW - 8, size)
		x += widths[i] + 18
	end
	return row, total
end

-- A coloured header bar `h` tall across the top of a card, in the theme's shape: rounded on top
-- with a rounded card (square where it meets the card's body), and in the pixel themes a light
-- shine along its top and a dark ledge along its foot. Returns the bar.
function Ui.band(parent: Instance, colour: Color3, h: number, name: string?): any
	local b = Ui.make("Frame", parent, { Name = name or "Band", BackgroundColor3 = colour, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h) })
	if theme.radius > 0 then
		Ui.corner(b, 0)
		Ui.make("Frame", b, { Name = "Square", BackgroundColor3 = colour, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0.5, 0) })
	end
	if theme.bevel == "strip" then
		Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(colour, 0.35), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2) })
		Ui.make("Frame", b, { Name = "Ledge", BackgroundColor3 = Ui.shade(colour, -0.45), BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2) })
	end
	return b
end

-- A pixel window: square, an ink border and a lighter rim inside it. With `band`, a coloured title
-- bar `bandH` tall across its top with `title` in it, a darker ledge along its lower edge;
-- returns the card, the band and the title.
function Ui.panel(parent: Instance?, name: string, band: Color3?, title: string?, bandH: number?): (any, any, any)
	local p = Ui.make("Frame", parent, { Name = name, BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0 })
	Ui.corner(p, 0)
	Ui.stroke(p, Ui.INK, 3)
	Ui.rim(p, Ui.PANEL2, 2, 0)
	if not band then return p, nil, nil end
	local h = bandH or 34
	local b = Ui.band(p, band, h)
	b.ZIndex = 2
	local t = Ui.text(b, title or "", math.floor(h * 0.48), Ui.WHITE, Ui.DISPLAY)
	if math.floor(h * 0.48) < 16 then Ui.outline(t, 2) end
	t.Name = "Title"
	t.Position, t.Size = UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 2
	return p, b, t
end

-- Recolour a panel's title bar, its shine and ledge with it.
function Ui.paintBand(band: any, colour: Color3)
	band.BackgroundColor3 = colour
	local shine, ledge, square = band:FindFirstChild("Shine"), band:FindFirstChild("Ledge"), band:FindFirstChild("Square")
	if square then square.BackgroundColor3 = colour end
	if shine then shine.BackgroundColor3 = Ui.shade(colour, 0.35) end
	if ledge then ledge.BackgroundColor3 = Ui.shade(colour, -0.45) end
end

-- A dark square strip with a rim, for a line of status.
function Ui.pill(parent: Instance?, name: string, edge: Color3?): any
	local p = Ui.make("Frame", parent, { Name = name, BackgroundColor3 = Ui.INK, BackgroundTransparency = 0.08, BorderSizePixel = 0 })
	Ui.corner(p, 0)
	Ui.stroke(p, Ui.INK, 3)
	Ui.rim(p, edge or Ui.EDGE, 2, 0)
	return p
end

return Ui
