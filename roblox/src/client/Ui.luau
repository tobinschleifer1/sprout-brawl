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
Ui.DISPLAY = Enum.Font.Arcade
Ui.LABEL = Enum.Font.Arcade
Ui.BODY = Enum.Font.Arcade

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
Ui.SCALE = 1.25
Ui.ADVANCE = 0.5625
function Ui.px(size: number): number
	return math.floor(size * Ui.SCALE + 0.5)
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
-- Pixel art has no round corners: every caller's radius is kept (so a screen still says which of
-- its boxes are cards) but drawn square.
function Ui.corner(parent: Instance, _r: number): any
	return Ui.make("UICorner", parent, { CornerRadius = UDim.new(0, 0) })
end
function Ui.stroke(parent: Instance, colour: Color3, thick: number): any
	return Ui.make("UIStroke", parent, { Color = colour, Thickness = thick, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter })
end
-- the ink outline on a text's letters (not its box)
function Ui.outline(t: Instance, thick: number?): any
	return Ui.make("UIStroke", t, { Color = Ui.INK, Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Miter })
end
-- A lighter rim just inside a box's ink border: the second line of a pixel window's frame. Its
-- own stroke is drawn outside it, so it sits `inset` px in and is `thick` px wide. Returns the rim
-- and its stroke (to recolour).
function Ui.rim(parent: Instance, colour: Color3, thick: number?, inset: number?): (any, any)
	local t, i = thick or 2, (inset or 0) + (thick or 2)
	local r = Ui.make("Frame", parent, { Name = "Rim", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(i, i), Size = UDim2.new(1, -2 * i, 1, -2 * i) })
	return r, Ui.stroke(r, colour, t)
end

-- `size` is the size asked for; the pixel face is drawn at Ui.px(size).
function Ui.text(parent: Instance?, value: string, size: number, colour: Color3?, font: any?): any
	local px = Ui.px(size)
	local t = Ui.make("TextLabel", parent, { BackgroundTransparency = 1, Text = value, TextSize = px,
		TextColor3 = colour or Ui.WHITE, Font = font or Ui.LABEL, TextXAlignment = Enum.TextXAlignment.Center,
		BorderSizePixel = 0 })
	if size >= 16 then Ui.outline(t, if size >= 28 then 3 else 2) end
	return t
end

-- How far a button's shine and lip move from its face colour.
Ui.SHINE, Ui.LIP = 0.38, -0.42

-- A button's shine and lip, so `paint` can recolour them with it.
local parts: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

-- opts: small (no outline on the letters - it fills small ones in), textColour, font, size
function Ui.button(parent: Instance?, value: string, colour: Color3, onClick: (() -> ())?, opts: any?): any
	local o = opts or {}
	local b = Ui.make("TextButton", parent, { Text = value, Font = o.font or Ui.DISPLAY, TextSize = Ui.px(o.size or 16),
		TextColor3 = o.textColour or Ui.WHITE, BackgroundColor3 = colour, AutoButtonColor = true, BorderSizePixel = 0 })
	Ui.corner(b, 0)
	Ui.stroke(b, Ui.INK, 3)
	if not o.small then Ui.outline(b, 2) end
	-- a pixel bevel: a light strip along the top, a dark one along the bottom, both full width
	local shine = Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(colour, Ui.SHINE),
		BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 3) })
	local lip = Ui.make("Frame", b, { Name = "Lip", BackgroundColor3 = Ui.shade(colour, Ui.LIP), BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 4) })
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
	local k = Ui.make("TextLabel", parent, { Name = "Key", Text = Ui.keyLabel(key), Font = Ui.DISPLAY, TextSize = Ui.px(size or 14),
		TextColor3 = Ui.INK, BackgroundColor3 = Ui.KEY, BorderSizePixel = 0 })
	Ui.corner(k, 0)
	Ui.stroke(k, Ui.INK, 2)
	Ui.make("Frame", k, { Name = "Shine", BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 2) })
	Ui.make("Frame", k, { Name = "Lip", BackgroundColor3 = Color3.fromRGB(139, 155, 180), BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3) })
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
	return capW, capW + 6 + Ui.textWidth(word, math.floor(size * 0.5)) + 4
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
		word.Position, word.Size = UDim2.new(0.5, x + capW + 6, 0.5, -size / 2), UDim2.fromOffset(widths[i] - capW - 6, size)
		x += widths[i] + 18
	end
	return row, total
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
	local b = Ui.make("Frame", p, { Name = "Band", BackgroundColor3 = band, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h), ZIndex = 2 })
	Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(band, 0.35), BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 3) })
	Ui.make("Frame", b, { Name = "Ledge", BackgroundColor3 = Ui.shade(band, -0.45), BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3) })
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
	local shine, ledge = band:FindFirstChild("Shine"), band:FindFirstChild("Ledge")
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
