--!strict
-- Blockfall's UI kit: every screen is built from it, so the plaza, the studio, the select screen,
-- the shop and the fight read as one game. Themes (Ui.THEMES) change its fonts, corners, borders,
-- outlines and bevels; the game uses `arcade` (the owner's direction, 2026-10-19): a simulator
-- shop's pale windows, coloured title bands, saturated rarity cards and dark price pills, drawn with
-- a pixel kit's buttons and lettering.
--
--   words    one rule per surface: on a pale window dark and bare (Ui.TEXT, Ui.SUB); on a coloured
--            face white outlined in the face's own darker shade (Ui.faceText, Ui.tone), or ink and
--            bare where the face is pale (Ui.paintTitle, Ui.paintSecondary); over the world white or
--            gold outlined in ink
--   button   an outline in its own colour darkened, a light band over its top, a dark lip at its foot
--   card     a light-to-colour gradient, an own-shade border and lip (Ui.card, Ui.paintCard)
--   titles   window bands in the pixel kit's lettering at one size (Ui.TITLE, Ui.WINDOW_TITLE)
--   pixels   pixel icons drawn as Frames (Ui.icon, Ui.iconButton, Ui.currency); stepped corner
--            brackets for a selected art card (Ui.brackets); one selected face (Ui.SELECTED)
--
-- Pure helpers - `shade`, `keyLabel`, `px`, `contrast` - and every theme's promises are tested in
-- tests/ui-kit.luau with the builders.
local Ui = {}

-- One face. DISPLAY, LABEL and BODY are kept as names so a screen still says what its words are
-- for, but they are the same pixel font: a second, smooth font beside it is what made the old UI
-- read as a different game from its sprites.
Ui.DISPLAY = Enum.Font.FredokaOne
Ui.LABEL = Enum.Font.BuilderSansExtraBold
Ui.BODY = Enum.Font.BuilderSansBold
Ui.TITLE = Enum.Font.FredokaOne    -- a window's title on its band (the theme's `title`, else DISPLAY)
Ui.WINDOW_TITLE = 30                -- the size every window's pixel title is asked at (drawn ~21 px: at ~17 the title was smaller than the header's currency pills)

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
	clean = { display = F.FredokaOne, label = F.BuilderSansExtraBold, body = F.BuilderSansBold, radius = 8, borderK = 0.34,
		outlineK = 0.4, rim = false, bevel = "none", scale = 1.05, advance = 0.62 },
	-- The owner's direction (2026-10-19): a simulator shop's light windows, saturated cards and dark
	-- price pills, drawn with a pixel kit's chunky buttons - a thick outline in a darker shade of the
	-- button's own colour, a light band across its top and a dark lip along its foot - and outlined
	-- white words on every coloured face.
	--   light    windows are pale (palette below) and words on them dark: Ui.TEXT and Ui.SUB
	--   tone     a coloured box's border and its words' outline are its own colour darkened, not ink
	--   title    window titles in the pixel kit's lettering (Font.Arcade), the rest in Fredoka
	arcade = { display = F.FredokaOne, label = F.BuilderSansExtraBold, body = F.BuilderSansBold, radius = 10, borderK = 1,
		outlineK = 1, rim = false, bevel = "arcade", scale = 1.08, advance = 0.62, light = true, tone = true, title = F.Arcade },
}
-- Each theme's window colours: the dark ones share Endesga 32's; `light` themes their own.
--   PANEL a window's body, PANEL2 a section set into it, EDGE a hairline on it, TEXT and SUB the
--   words on it (main and secondary), INK the outline of boxes and of words over the world
local DARK = { PANEL = Color3.fromRGB(38, 43, 68), PANEL2 = Color3.fromRGB(58, 68, 102), EDGE = Color3.fromRGB(90, 105, 136),
	TEXT = Color3.fromRGB(255, 255, 255), SUB = Color3.fromRGB(139, 155, 180), INK = Color3.fromRGB(24, 20, 37) }
local LIGHT = { PANEL = Color3.fromRGB(255, 248, 236), PANEL2 = Color3.fromRGB(244, 231, 207), EDGE = Color3.fromRGB(222, 202, 166),
	TEXT = Color3.fromRGB(43, 33, 64), SUB = Color3.fromRGB(107, 90, 73), INK = Color3.fromRGB(35, 27, 51) }
Ui.ARCADE_SCALE = 1.25
local theme = Ui.THEMES.arcade
Ui.theme = "arcade"

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
-- the words on a window, main and secondary (white and grey-blue on the dark windows)
Ui.TEXT = Color3.fromRGB(255, 255, 255)
Ui.SUB = Color3.fromRGB(139, 155, 180)
-- the arcade theme's card colours: saturated, each with its own darker outline (Ui.tone)
Ui.TEAL = Color3.fromRGB(46, 204, 170)
Ui.VIOLET = Color3.fromRGB(150, 104, 255)
Ui.SKY = Color3.fromRGB(77, 160, 255)
Ui.SUN = Color3.fromRGB(255, 205, 54)

-- How much bigger a size asked of the pixel face is drawn. Roblox fits Press Start 2P's square
-- letters into a little over half of TextSize (16 draws 9 px letters), so sizes chosen for the old
-- smooth fonts would come out small; this keeps the words about as big as they were. Measured in
-- Studio with TextService:GetTextBoundsAsync: 0.5625 px of width per TextSize per letter.
Ui.SCALE = 1.05
Ui.ADVANCE = 0.62
-- `font` is the face the size is for (the LABEL face if not said): Arcade is scaled by
-- ARCADE_SCALE whatever the theme, the smooth faces by the theme's own scale.
function Ui.px(size: number, font: any?): number
	local k = if (font or Ui.LABEL) == Enum.Font.Arcade then Ui.ARCADE_SCALE else Ui.SCALE
	return math.floor(size * k + 0.5)
end

-- Is the theme flat (no bevels, no outlines on solid surfaces)?
function Ui.flat(): boolean
	return theme.bevel == "none"
end
-- A meter block, a stat block, a stock pip: softened to match a rounded theme.
function Ui.pip(f: Instance): Instance
	if theme.radius > 0 then Ui.make("UICorner", f, { CornerRadius = UDim.new(0, 2) }) end
	return f
end
-- How light a colour is (0 black .. 1 white), for picking ink or white text on it.
function Ui.light(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

function Ui.useTheme(name: string?)
	local t = Ui.THEMES[name or "arcade"]
	if not t then return end
	theme, Ui.theme = t, name or "arcade"
	Ui.DISPLAY, Ui.LABEL, Ui.BODY = t.display, t.label, t.body
	Ui.TITLE = t.title or t.display
	Ui.SCALE, Ui.ADVANCE = t.scale, t.advance
	local pal = if t.light then LIGHT else DARK
	Ui.PANEL, Ui.PANEL2, Ui.EDGE, Ui.TEXT, Ui.SUB, Ui.INK = pal.PANEL, pal.PANEL2, pal.EDGE, pal.TEXT, pal.SUB, pal.INK
end
-- Is the theme's window pale (words on it dark)?
function Ui.lightPanels(): boolean
	return theme.light == true
end
-- The outline of a box or of the words on a face of colour `c`: its own colour darkened in a toned
-- theme (a green button wears dark green), ink otherwise.
function Ui.tone(c: Color3): Color3
	if not theme.tone then return Ui.INK end
	return Ui.shade(c, -0.58)
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
function Ui.outline(t: Instance, thick: number?, colour: Color3?): any
	local k = math.floor((thick or 2) * theme.outlineK + 0.5)
	return Ui.make("UIStroke", t, { Color = colour or Ui.INK, Thickness = k, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
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
-- `bare`: no outline whatever the size (words on a solid bar or card in a flat theme).
function Ui.text(parent: Instance?, value: string, size: number, colour: Color3?, font: any?, bare: boolean?): any
	local face = font or Ui.LABEL
	local t = Ui.make("TextLabel", parent, { BackgroundTransparency = 1, Text = value, TextSize = Ui.px(size, face),
		TextColor3 = colour or Ui.WHITE, Font = face, TextXAlignment = Enum.TextXAlignment.Center,
		BorderSizePixel = 0 })
	-- the pixel face outlines everything big enough not to fill in; a smooth theme its display words
	-- (a flat theme only outlines big words, the ones drawn over the world; small ones sit on cards)
	local min = if theme.bevel == "none" then 28 else 16
	-- (dark words - on a pale window - are never outlined: the outline is for light words)
	local dark = colour ~= nil and Ui.light(colour) < 0.45
	if not bare and not dark and size >= min and (theme.label == Enum.Font.Arcade or face == Ui.DISPLAY) then Ui.outline(t, if size >= 28 then 3 else 2) end
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
	local border = Ui.stroke(b, Ui.tone(colour), 3)
	-- (small words outlined too in a toned theme, at 1 px: bare white on a mid-tone face read at 2-3:1)
	-- (2 px in a toned theme, small words too: at 1 px the dock's 12 px words measured 2.8-3.2:1)
	local outline = if theme.bevel == "none" or (o.small and not theme.tone) then nil else Ui.outline(b, if o.small and not theme.tone then 1 else 2, Ui.tone(colour))
	-- the bevel: full-width pixel strips (pixel themes), a rounded shine and lip set in from the
	-- edges (rounded themes), a pixel kit's light band across the top third and a dark lip along the
	-- foot (arcade), or nothing (flat)
	local inset, arcade = theme.bevel == "inset", theme.bevel == "arcade"
	local shine = Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(colour, if arcade then 0.28 else Ui.SHINE),
		BorderSizePixel = 0, Position = if inset then UDim2.fromOffset(6, 3) elseif arcade then UDim2.fromOffset(4, 3) else UDim2.fromOffset(0, 0),
		Size = if inset then UDim2.new(1, -12, 0, 3) elseif arcade then UDim2.new(1, -8, 0.3, -2) else UDim2.new(1, 0, 0, 3) })
	local lip = Ui.make("Frame", b, { Name = "Lip", BackgroundColor3 = Ui.shade(colour, if arcade then -0.3 else Ui.LIP), BorderSizePixel = 0,
		Position = if inset then UDim2.new(0, 3, 1, -6) elseif arcade then UDim2.new(0, 0, 1, -5) else UDim2.new(0, 0, 1, -4),
		Size = if inset then UDim2.new(1, -6, 0, 4) elseif arcade then UDim2.new(1, 0, 0, 5) else UDim2.new(1, 0, 0, 4) })
	if arcade then
		-- the shine is a rounded band; the lip follows the button's own rounded foot
		Ui.make("UICorner", shine, { CornerRadius = UDim.new(0, math.max(2, theme.radius - 4)) })
		Ui.make("UICorner", lip, { CornerRadius = UDim.new(0, theme.radius) })
		shine.ZIndex, lip.ZIndex = b.ZIndex, b.ZIndex
	elseif inset then
		Ui.make("UICorner", shine, { CornerRadius = UDim.new(0, 2) })
		Ui.make("UICorner", lip, { CornerRadius = UDim.new(0, 3) })
	elseif theme.bevel == "none" then
		shine.BackgroundTransparency, lip.BackgroundTransparency = 1, 1
	end
	parts[b] = { shine = shine, lip = lip, outline = outline, border = border }
	if not o.textColour and Ui.light(colour) > 0.62 then
		-- (on a pale face the words go dark and bare: the theme's text colour on a light window)
		b.TextColor3 = if theme.light then Ui.TEXT elseif theme.tone then Ui.tone(colour) else Ui.INK
		if outline then outline.Thickness = 0 end
	end
	parts[b].small = o.small
	if onClick then b.Activated:Connect(onClick) end
	return b
end

-- Recolour a button, its shine and lip with it.
-- On a light face (gold, a pale key) the words go ink with no outline, whatever was asked: white
-- on yellow is unreadable.
function Ui.paint(b: any, colour: Color3, textColour: Color3?)
	b.BackgroundColor3 = colour
	local lightFace = Ui.light(colour) > 0.62
	if lightFace then b.TextColor3 = if theme.light then Ui.TEXT elseif theme.tone then Ui.tone(colour) else Ui.INK
	elseif textColour then b.TextColor3 = textColour
	elseif theme.tone then b.TextColor3 = Ui.WHITE end
	local p = parts[b]
	if p then
		local arcade = theme.bevel == "arcade"
		p.shine.BackgroundColor3 = Ui.shade(colour, if arcade then 0.28 else Ui.SHINE)
		p.lip.BackgroundColor3 = Ui.shade(colour, if arcade then -0.3 else Ui.LIP)
		if p.border and theme.tone then p.border.Color = Ui.tone(colour) end
		if p.outline then
			p.outline.Thickness = if lightFace then 0 else math.floor((if p.small then 1 else 2) * theme.outlineK + 0.5)
			if theme.tone then p.outline.Color = Ui.tone(colour) end
		end
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
	if theme.bevel == "none" then lip.BackgroundTransparency = 1 end
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
-- Width per letter per TextSize of each face (TextService:GetTextBoundsAsync in Studio, upper
-- and mixed case); `font` is the face it is drawn in (the theme's widest, if not said).
local ADV = { [tostring(Enum.Font.Arcade)] = 0.5625, [tostring(Enum.Font.FredokaOne)] = 0.55,
	[tostring(Enum.Font.BuilderSansExtraBold)] = 0.53, [tostring(Enum.Font.BuilderSansBold)] = 0.51,
	[tostring(Enum.Font.LuckiestGuy)] = 0.62, [tostring(Enum.Font.GothamBlack)] = 0.62, [tostring(Enum.Font.GothamBold)] = 0.6 }
function Ui.textWidth(value: string, size: number, font: any?): number
	local adv = if font then ADV[tostring(font)] or Ui.ADVANCE else Ui.ADVANCE
	local k = if (font or Ui.LABEL) == Enum.Font.Arcade then Ui.ARCADE_SCALE else Ui.SCALE
	return math.ceil((utf8.len(value) or #value) * size * k * adv * 1.04 - 1e-9)
end

-- The width a key-cap-and-word chip needs with a cap `size` px tall: the cap, and the whole chip.
function Ui.chipWidth(key: string, word: string, size: number): (number, number)
	local capW = math.max(size + 6, Ui.textWidth(Ui.keyLabel(key), math.floor(size * 0.5), Ui.DISPLAY) + 14)
	return capW, capW + 8 + Ui.textWidth(word, math.floor(size * 0.5), Ui.DISPLAY) + 4
end

-- A centred row of key caps with what each does: [WASD] WALK  [SPACE] HOP  [E] USE. `items` are
-- { key, word } pairs; `size` is the cap's height. Returns the row (placed by the caller, full
-- width of its parent by default) and its total width.
-- `backed`: on a translucent dark strip, for a row drawn straight over the busy world.
function Ui.hintRow(parent: Instance?, name: string, items: { { string } }, size: number, colour: Color3?, backed: boolean?): (any, number)
	local row = Ui.make("Frame", parent, { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0 })
	local widths, total = {}, 0
	for i, item in items do
		local _, w = Ui.chipWidth(item[1], item[2], size)
		widths[i] = w
		total += w + (if i > 1 then 18 else 0)
	end
	if backed then
		local back = Ui.make("Frame", row, { Name = "Back", BackgroundColor3 = Ui.INK, BackgroundTransparency = 0.35, BorderSizePixel = 0,
			Position = UDim2.new(0.5, -total / 2 - 10, 0.5, -size / 2 - 5), Size = UDim2.fromOffset(total + 20, size + 10) })
		Ui.corner(back, 0)
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
		-- small words still need to stand off whatever the row is drawn over (unless it has a strip)
		-- (not dark words on a pale window: those read bare, as every dark word does)
		if size * 0.5 < 16 and not backed and Ui.light(colour or Ui.WHITE) > 0.45 then Ui.outline(word, 2) end
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
	if theme.bevel == "arcade" then
		-- a light band across its top, as on the buttons
		local sh = Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(colour, 0.22), BorderSizePixel = 0,
			Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0.28, 0) })
		Ui.make("UICorner", sh, { CornerRadius = UDim.new(0, math.max(2, theme.radius - 4)) })
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
	-- (the pixel face is drawn a quarter bigger than asked: ask it smaller to fit the same band)
	-- pixel lettering only on a window's own band (40 px or more), at one size for every window; the
	-- smaller bands of panels inside windows keep Fredoka (the pixel face under 12 px is noise)
	local pixel = Ui.TITLE == Enum.Font.Arcade and h >= 40
	local titleSize = if pixel then Ui.WINDOW_TITLE else math.floor(h * 0.48)
	local t = Ui.text(b, title or "", titleSize, Ui.WHITE, if pixel then Ui.TITLE else Ui.DISPLAY, theme.bevel == "none" or theme.tone)
	if theme.tone then Ui.outline(t, if h >= 40 then 3 else 2, Ui.tone(band))
	elseif math.floor(h * 0.48) < 16 and theme.bevel ~= "none" then Ui.outline(t, 2) end
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
	if shine then shine.BackgroundColor3 = Ui.shade(colour, if theme.bevel == "arcade" then 0.22 else 0.35) end
	if ledge then ledge.BackgroundColor3 = Ui.shade(colour, -0.45) end
	-- its title's outline follows (a red band kept its old blue band's shade round the title)
	local title = band:FindFirstChild("Title")
	if title and theme.tone and title.GetChildren then
		for _, ch in title:GetChildren() do
			if ch.ClassName == "UIStroke" then ch.Color = Ui.tone(colour) end
		end
	end
end

-- Every window's close: one red X, centred in its title band `bandH` tall, at the right.
function Ui.closeButton(parent: Instance, onClick: () -> (), bandH: number): any
	local b = Ui.button(parent, "X", Ui.RED, onClick, { size = 18 })
	b.Name, b.ZIndex, b.AnchorPoint = "Close", 3, Vector2.new(1, 0.5)
	b.Position, b.Size = UDim2.new(1, -10, 0, bandH / 2), UDim2.fromOffset(38, 34)
	return b
end

-- A saturated card (the simulator shop's): a vertical light-to-colour gradient, a thick border in
-- its own darker shade and a lip along its foot. The caller sizes and places it.
function Ui.card(parent: Instance?, name: string, colour: Color3): any
	local c = Ui.make("Frame", parent, { Name = name, BackgroundColor3 = colour, BorderSizePixel = 0 })
	Ui.corner(c, 0)
	Ui.stroke(c, Ui.tone(colour), 3)
	if theme.bevel == "arcade" then
		Ui.make("UIGradient", c, { Rotation = 90, Color = ColorSequence.new(Ui.shade(colour, 0.32), colour) })
		local lip = Ui.make("Frame", c, { Name = "Lip", BackgroundColor3 = Ui.shade(colour, -0.28), BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -5), Size = UDim2.new(1, 0, 0, 5) })
		Ui.make("UICorner", lip, { CornerRadius = UDim.new(0, theme.radius) })
	end
	return c
end

-- A vertical gradient over a box, `top` fading to `bottom` (UIGradient tints the box's colour).
function Ui.gradient(f: Instance, top: Color3, bottom: Color3): any
	return Ui.make("UIGradient", f, { Rotation = 90, Color = ColorSequence.new(top, bottom) })
end

-- Recolour a card: its face, gradient, border and lip together.
-- An art well's mount, the pixel kit's stepped box: a pale tint of the card's colour inside a slightly
-- deeper edge, each corner cut in two three-pixel steps (three overlapping rects per shape, so no
-- corner radius). The one pixel motif every card carries. A child of the art frame, at its back: the
-- art's first frame shares its ZIndex and comes later, so draws over it.
Ui.MOUNT_STEP, Ui.MOUNT_EDGE = 3, 3
local function mountColours(colour: Color3): (Color3, Color3)
	return Ui.shade(colour, -0.22), Ui.shade(colour, 0.6)
end
function Ui.mount(art: any, colour: Color3): any
	art.BackgroundTransparency = 1
	local s, t = Ui.MOUNT_STEP, Ui.MOUNT_EDGE
	local edgeC, fillC = mountColours(colour)
	local holder = Ui.make("Frame", art, { Name = "Mount", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
		Size = UDim2.fromScale(1, 1) })
	local function shape(name: string, inset: number, c: Color3)
		for k = 0, 2 do
			Ui.make("Frame", holder, { Name = name, BackgroundColor3 = c, BorderSizePixel = 0, ZIndex = 1,
				Position = UDim2.fromOffset(inset + (2 - k) * s, inset + k * s),
				Size = UDim2.new(1, -2 * inset - 2 * (2 - k) * s, 1, -2 * inset - 2 * k * s) })
		end
	end
	shape("Edge", 0, edgeC)
	shape("Fill", t, fillC)
	return holder
end
function Ui.paintMount(m: any, colour: Color3)
	local edgeC, fillC = mountColours(colour)
	for _, r in m:GetChildren() do r.BackgroundColor3 = if r.Name == "Edge" then edgeC else fillC end
end

function Ui.paintCard(c: any, colour: Color3)
	c.BackgroundColor3 = colour
	for _, ch in c:GetChildren() do
		if ch.ClassName == "UIGradient" then ch.Color = ColorSequence.new(Ui.shade(colour, 0.32), colour)
		elseif ch.ClassName == "UIStroke" then ch.Color = Ui.tone(colour)
		elseif ch.Name == "Lip" then ch.BackgroundColor3 = Ui.shade(colour, -0.28)
		elseif ch.Name == "Thumb" then
			for _, m in ch:GetChildren() do if m.Name == "Mount" then Ui.paintMount(m, colour) end end
		end
	end
end

-- Words on a coloured face (a card, a band): white, outlined in the face's own darker shade, so
-- they read on any colour - pale grey, gold or violet alike. Returns the label and its outline.
function Ui.faceText(parent: Instance?, value: string, size: number, face: Color3, font: any?): (any, any)
	local t = Ui.text(parent, value, size, Ui.WHITE, font or Ui.DISPLAY, true)
	-- (never under 2 px: at 1 the dock's and badges' small white words measured 2.0-3.2:1 bare)
	local o = Ui.outline(t, if size >= 20 then 3 else 2, Ui.tone(face))
	return t, o
end

-- Pixel icons, as a pixel kit draws them: a small grid of letters, each a colour ("." empty).
-- Drawn as Frames (one per run of a colour along a row), so they need no uploaded image.
Ui.ICONS = {
	gem = { w = 7, rows = { "..OOO..", ".OWwwO.", "OWwwppO", "OwwppPO", ".OppPO.", "..OPO..", "...O..." },
		colours = { O = "#5A1A4A", W = "#FFFFFF", w = "#FFB3E1", p = "#FF5FB4", P = "#C2338A" } },
	key = { w = 9, rows = { ".OOO.....", "OyYyO....", "OY.YOOOOO", "OyYyOyyYO", ".OOO.O.O." },
		colours = { O = "#5A3A0A", Y = "#FFD84A", y = "#FFF0A0" } },
	coin = { w = 7, rows = { "..OOO..", ".OyyyO.", "OyYYYyO", "OyYoYyO", "OyYYYyO", ".OyyyO.", "..OOO.." },
		colours = { O = "#6A4A08", Y = "#FFC935", y = "#FFE98A", o = "#D9971A" } },
	star = { w = 7, rows = { "...O...", "..OyO..", "OOyYyOO", ".OYYYO.", ".OYOYO.", "OO...OO" },
		colours = { O = "#6A4A08", Y = "#FFC935", y = "#FFF0A0" } },
	chest = { w = 9, rows = { ".OOOOOOO.", "OwwwwwwwO", "OwbbbbbwO", "OOOOyOOOO", "ObbbYbbbO", "ObbbbbbbO", "ObbbbbbbO", "OOOOOOOOO" },
		colours = { O = "#3D2410", w = "#D99A5B", b = "#A8642E", y = "#FFE98A", Y = "#E0A920" } },
	heart = { w = 7, rows = { ".OO.OO.", "OpPOppO", "OpppppO", ".OpppO.", "..OpO..", "...O..." },
		colours = { O = "#5A1020", p = "#FF5F7E", P = "#FFFFFF" } },
	bubble = { w = 9, rows = { ".OOOOOOO.", "OwwwwwwwO", "OwkwkwkwO", "OwwwwwwwO", ".OOwOOOO.", "..OO....." },
		colours = { O = "#14264A", w = "#FFFFFF", k = "#14264A" } },
	people = { w = 9, rows = { ".OO...OO.", "OffO.OffO", ".OO...OO.", "OOOO.OOOO", "OssO.OttO", "OssO.OttO", "OOOO.OOOO" },
		colours = { O = "#3A1A08", f = "#F0C49A", s = "#FF9A3D", t = "#5FB8FF" } },
	map = { w = 9, rows = { "OOOOOOOOO", "OyygggyyO", "OygggyRyO", "OyyggRyRO", "OygggyRyO", "OyyyggyyO", "OOOOOOOOO" },
		colours = { O = "#4A3010", y = "#F2D9A0", g = "#6CC45A", R = "#D93030" } },
	shirt = { w = 9, rows = { "..OO.OO..", ".OsOOOsO.", "OssssssSO", "OOssssSOO", ".OssssSO.", ".OssssSO.", ".OOOOOOO." },
		colours = { O = "#14264A", s = "#6FB6FF", S = "#3D7FD0" } },
} :: { [string]: any }
-- An icon `px` screen pixels to the art pixel, in a transparent frame the caller places.
function Ui.icon(parent: Instance?, kind: string, px: number): any
	local def = Ui.ICONS[kind]
	local f = Ui.make("Frame", parent, { Name = "Icon", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(def.w * px, #def.rows * px) })
	for y, row in def.rows do
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			local run = x
			while run < #row and string.sub(row, run + 1, run + 1) == ch do run += 1 end
			if ch ~= "." then
				Ui.make("Frame", f, { Name = "Px", BackgroundColor3 = Color3.fromHex(def.colours[ch]), BorderSizePixel = 0,
					Position = UDim2.fromOffset((x - 1) * px, (y - 1) * px), Size = UDim2.fromOffset((run - x + 1) * px, px) })
			end
			x = run + 1
		end
	end
	return f
end

-- A square button with a pixel icon over its name (the reference simulator's side buttons), and
-- optionally its keyboard key on a cap at the top left. `size` is its side. Returns the button.
function Ui.iconButton(parent: Instance?, kind: string, value: string, colour: Color3, onClick: (() -> ())?, size: number, key: string?): any
	local b = Ui.button(parent, "", colour, onClick)
	b.Size = UDim2.fromOffset(size, size)
	-- every icon on one pixel grid (a 9-cell basis), whatever its own width, so the row matches
	local px = math.max(2, math.floor(size * 0.6 / 9))
	local ic = Ui.icon(b, kind, px)
	ic.Name, ic.AnchorPoint, ic.Position, ic.ZIndex = "Icon", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, math.floor(size * 0.18)), (b.ZIndex or 1) + 1
	-- the word shrunk to fit inside the square, never under 10
	local wordSize = math.max(11, math.floor(size * 0.17))
	while wordSize > 10 and Ui.textWidth(value, wordSize, Ui.DISPLAY) > size - 10 do wordSize -= 1 end
	local word = Ui.faceText(b, value, wordSize, colour)
	word.Name, word.AnchorPoint = "Word", Vector2.new(0.5, 1)
	word.Position, word.Size = UDim2.new(0.5, 0, 1, -math.floor(size * 0.1)), UDim2.new(1, -6, 0, math.floor(size * 0.24))
	if key then
		local cap = Ui.keycap(b, key, 10)
		cap.Position, cap.Size, cap.ZIndex = UDim2.fromOffset(3, 3), UDim2.fromOffset(15, 15), (b.ZIndex or 1) + 2
	end
	return b
end

-- The pixel kit's selected mark for an art card: four stepped corner brackets just outside it, in
-- `colour`, each an L of two arms `arm` long and `thick` wide with a one-pixel step at its elbow.
-- Returns the holder (toggle its Visible); it is the caller's box's child, so it moves with it.
Ui.BRACKET_INK = 2
-- the brackets' outer edge sits this far outside the box: on its 3 px stroke's outer edge, the arms
-- lying over the stroke (outside it, ink and all, they reached 9 px out and crowded the next card)
Ui.BRACKET_OUT = 3
-- the gap between boxes that can be chosen: room for one's brackets (BRACKET_OUT + BRACKET_INK), 8 px,
-- and the next one's 3 px stroke
Ui.CHOSEN_GAP = Ui.BRACKET_OUT + Ui.BRACKET_INK + 8 + 3
function Ui.brackets(parent: Instance, colour: Color3?, arm: number?, thick: number?): any
	local a, t, out = arm or 14, thick or 4, Ui.BRACKET_OUT
	local col = colour or Ui.SELECTED
	local holder = Ui.make("Frame", parent, { Name = "Brackets", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(-out, -out), Size = UDim2.new(1, 2 * out, 1, 2 * out), ZIndex = 4, Visible = false })
	-- each stair twice: in ink, a pixel and a half bigger all round, then in its colour over it, so
	-- the mark reads on the pale windows (gold on cream is 1.2:1) as on the sky. All the ink first,
	-- or a later arm's ink would cut across an earlier arm's gold.
	local o = Ui.BRACKET_INK
	local passes: { { name: string, colour: Color3, e: number } } = { { name = "Ink", colour = Ui.INK, e = o }, { name = "Px", colour = col, e = 0 } }
	for _, pass in passes do
		for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
			local sx, sy = corner[1], corner[2]
			local function bar(w: number, h: number, dx: number, dy: number)
				local e = pass.e
				Ui.make("Frame", holder, { Name = pass.name, BackgroundColor3 = pass.colour, BorderSizePixel = 0, ZIndex = 4,
					AnchorPoint = Vector2.new(sx, sy), Position = UDim2.new(sx, (1 - 2 * sx) * (dx - e), sy, (1 - 2 * sy) * (dy - e)),
					Size = UDim2.fromOffset(w + 2 * e, h + 2 * e) })
			end
			bar(a, t, t, 0)          -- the horizontal arm, set in by one step
			bar(t, a, 0, t)          -- the vertical arm, set in by one step
			bar(t, t, t, t)          -- the elbow's inner pixel: the stair
		end
	end
	return holder
end

-- A balance on a dark pill with its icon: [gem] 2,340. Returns the pill and its label.
function Ui.currency(parent: Instance?, kind: string, value: string): (any, any)
	local p = Ui.make("Frame", parent, { Name = "Currency_" .. kind, BackgroundColor3 = Color3.fromRGB(35, 27, 51),
		BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.fromOffset(110, 30) })
	Ui.make("UICorner", p, { CornerRadius = UDim.new(1, 0) })
	local ic = Ui.icon(p, kind, 3)
	ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0)
	local t = Ui.text(p, value, 15, Ui.WHITE, Ui.DISPLAY, true)
	t.Name, t.TextXAlignment = "Value", Enum.TextXAlignment.Left
	t.Position, t.Size = UDim2.fromOffset(Ui.ICONS[kind].w * 3 + 14, 0), UDim2.new(1, -(Ui.ICONS[kind].w * 3 + 20), 1, 0)
	return p, t
end

-- A card's secondary line (rarity, serial, price) on its face: white outlined in the face's shade on a
-- mid or deep face; on a pale one (gold, light green, grey) bare, in the face's own deep shade - white
-- there leaned wholly on a 1 px outline at 13 px.
-- A one-line label that shrinks to its box rather than spilling past it or cutting its end off: its
-- size now is the most it grows to, `least` (10 by default) the least. (Long item names - Ridgeguard
-- Trousers on a phone's Shop card - ran 8 px past the card's face.)
function Ui.fit(t: any, least: number?): any
	local most = t.TextSize
	t.TextWrapped, t.TextScaled, t.TextTruncate = false, true, Enum.TextTruncate.None
	Ui.make("UITextSizeConstraint", t, { MaxTextSize = most, MinTextSize = least or 10 })
	return t
end

-- WCAG contrast of two colours.
function Ui.contrast(a: Color3, b: Color3): number
	local function lum(c: Color3): number
		local function ch(v: number): number return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4 end
		return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B)
	end
	local x, y = lum(a), lum(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end
-- (decided by measured contrast, not lightness: blue and mint faces fell on the wrong side of a
-- lightness line and kept white lines at 2.4-2.9:1; ink reads at 5:1 or better on all of them)
-- The words sit on the card's gradient (shade(face, 0.32) at the top down to the face), so each
-- choice is measured at its worst: white against the lightest colour, ink against the darkest; the
-- better of the two wins. Dark words are INK, the deepest the kit has (TEXT left Epic's darkest stop at
-- 4.2:1). (White measured against the base alone kept Mythic's lines at 2.9:1 on the
-- surface they are actually drawn on.)
function Ui.paintSecondary(t: any, stroke: any, face: Color3)
	if Ui.contrast(Ui.INK, face) >= Ui.contrast(Ui.WHITE, Ui.shade(face, 0.32)) then
		t.TextColor3, stroke.Thickness = Ui.INK, 0
	else
		t.TextColor3, stroke.Thickness, stroke.Color = Ui.WHITE, 2, Ui.tone(face)
	end
end
-- A card's name or a band's title on its face: white outlined in its shade, unless the face is pale
-- (gold, yellow, light grey - lightness over 0.62, the rule Ui.paint uses for buttons): ink, bare.
-- One rule for every pale face, buttons, bands and cards alike.
function Ui.paintTitle(t: any, stroke: any, face: Color3)
	if Ui.light(face) > 0.62 then
		t.TextColor3, stroke.Thickness = Ui.TEXT, 0
	else
		t.TextColor3, stroke.Color = Ui.WHITE, Ui.tone(face)
		if stroke.Thickness == 0 then stroke.Thickness = 2 end
	end
end

-- A price on a dark pill: "29 R$". Prices are always plain Robux. The caller sizes and places it.
function Ui.pricePill(parent: Instance?, value: string): any
	local p = Ui.make("TextLabel", parent, { Name = "Price", Text = value, Font = Ui.DISPLAY, TextSize = Ui.px(15, Ui.DISPLAY),
		TextColor3 = Ui.WHITE, BackgroundColor3 = Color3.fromRGB(35, 27, 51), BackgroundTransparency = 0.12, BorderSizePixel = 0 })
	Ui.make("UICorner", p, { CornerRadius = UDim.new(1, 0) })
	return p
end

-- A dark square strip with a rim, for a line of status.
-- the one "selected" face for every tab, filter and toggle (dark words on it: a light face)
-- Space between two buttons side by side, box to box: 8 px between their outer strokes plus the 3 px
-- stroke each draws outside its box (4-6 px box gaps left neighbouring outlines touching).
Ui.GAP = 14
Ui.SELECTED = Color3.fromRGB(254, 231, 97)
Ui.INDIGO = Color3.fromRGB(70, 74, 150)       -- a status pill's face in the arcade theme
function Ui.pill(parent: Instance?, name: string, edge: Color3?): any
	-- (a coloured face like every card in a light theme - gradient, own-shade border, lip - not a flat strip)
	if theme.light then return Ui.card(parent, name, Ui.INDIGO) end
	local p = Ui.make("Frame", parent, { Name = name, BackgroundColor3 = Ui.INK, BackgroundTransparency = 0.08, BorderSizePixel = 0 })
	Ui.corner(p, 0)
	Ui.stroke(p, Ui.INK, 3)
	Ui.rim(p, edge or Ui.EDGE, 2, 0)
	return p
end

Ui.useTheme(Ui.theme)
return Ui
