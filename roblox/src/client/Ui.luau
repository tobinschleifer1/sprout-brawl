--!strict
-- Blockfall's UI kit: the cartoon pixel look every screen is built from, so the plaza, the
-- character studio, the select screen and the fight all read as one game.
--
--   text     display words (LuckiestGuy) wear a heavy ink outline, the way the genre's UI does;
--            body words are GothamBlack, without one, so small text stays legible
--   button   a chunky bevelled block: an ink border, a light shine strip along the top and a
--            darker pixel lip along the bottom - pressable at a glance
--   keycap   a pale key with the key's letter on it, for every "press E" in the game
--   panel    a navy card with an ink border and, optionally, a coloured band across the top with
--            its title in it (the select screen's player cards)
--   pill     a dark rounded strip for a line of status
--
-- `paint` recolours a button (shine and lip with it), for tabs and toggles. Pure helpers -
-- `shade`, `keyLabel` - are tested in tests/ui-kit.luau with the builders.
local Ui = {}

Ui.DISPLAY = Enum.Font.LuckiestGuy
Ui.LABEL = Enum.Font.GothamBlack
Ui.BODY = Enum.Font.GothamBold

Ui.INK = Color3.fromRGB(11, 16, 32)
Ui.PANEL = Color3.fromRGB(16, 24, 42)
Ui.PANEL2 = Color3.fromRGB(30, 42, 68)
Ui.EDGE = Color3.fromRGB(64, 98, 150)
Ui.WHITE = Color3.fromRGB(240, 244, 252)
Ui.DIM = Color3.fromRGB(150, 168, 196)
Ui.GOLD = Color3.fromRGB(255, 210, 74)
Ui.GREEN = Color3.fromRGB(92, 224, 122)
Ui.RED = Color3.fromRGB(232, 92, 84)
Ui.BLUE = Color3.fromRGB(46, 104, 178)
Ui.CYAN = Color3.fromRGB(110, 200, 255)
Ui.PINK = Color3.fromRGB(240, 120, 150)
Ui.PURPLE = Color3.fromRGB(112, 82, 186)
Ui.KEY = Color3.fromRGB(232, 238, 250)

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
function Ui.corner(parent: Instance, r: number): any
	return Ui.make("UICorner", parent, { CornerRadius = UDim.new(0, r) })
end
function Ui.stroke(parent: Instance, colour: Color3, thick: number): any
	return Ui.make("UIStroke", parent, { Color = colour, Thickness = thick, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
-- the ink outline on a text's letters (not its box)
function Ui.outline(t: Instance, thick: number?): any
	return Ui.make("UIStroke", t, { Color = Ui.INK, Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

function Ui.text(parent: Instance?, value: string, size: number, colour: Color3?, font: any?): any
	local t = Ui.make("TextLabel", parent, { BackgroundTransparency = 1, Text = value, TextSize = size,
		TextColor3 = colour or Ui.WHITE, Font = font or Ui.LABEL, TextXAlignment = Enum.TextXAlignment.Center,
		BorderSizePixel = 0 })
	if (font or Ui.LABEL) == Ui.DISPLAY then Ui.outline(t, math.max(1.5, size / 12)) end
	return t
end

-- A button's shine and lip, so `paint` can recolour them with it.
local parts: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

-- opts: small (no outline on the letters - it fills small ones in), textColour, font, radius
function Ui.button(parent: Instance?, value: string, colour: Color3, onClick: (() -> ())?, opts: any?): any
	local o = opts or {}
	local b = Ui.make("TextButton", parent, { Text = value, Font = o.font or Ui.DISPLAY, TextSize = o.size or 18,
		TextColor3 = o.textColour or Ui.WHITE, BackgroundColor3 = colour, AutoButtonColor = true, BorderSizePixel = 0 })
	Ui.corner(b, o.radius or 8)
	Ui.stroke(b, Ui.INK, 2)
	if not o.small then Ui.outline(b, 1.5) end
	local shine = Ui.make("Frame", b, { Name = "Shine", BackgroundColor3 = Ui.shade(colour, 0.32), BackgroundTransparency = 0.1,
		BorderSizePixel = 0, Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0, 3) })
	Ui.corner(shine, 2)
	local lip = Ui.make("Frame", b, { Name = "Lip", BackgroundColor3 = Ui.shade(colour, -0.38), BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 1, -6), Size = UDim2.new(1, -6, 0, 4) })
	Ui.corner(lip, 3)
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
		p.shine.BackgroundColor3 = Ui.shade(colour, 0.32)
		p.lip.BackgroundColor3 = Ui.shade(colour, -0.38)
	end
end

-- A pale key with its letter. The caller sizes and places it.
function Ui.keycap(parent: Instance?, key: string, size: number?): any
	local k = Ui.make("TextLabel", parent, { Name = "Key", Text = Ui.keyLabel(key), Font = Ui.DISPLAY, TextSize = size or 16,
		TextColor3 = Ui.INK, BackgroundColor3 = Ui.KEY, BorderSizePixel = 0 })
	Ui.corner(k, 5)
	Ui.stroke(k, Ui.INK, 2)
	local lip = Ui.make("Frame", k, { Name = "Lip", BackgroundColor3 = Ui.shade(Ui.KEY, -0.32), BorderSizePixel = 0,
		Position = UDim2.new(0, 2, 1, -4), Size = UDim2.new(1, -4, 0, 3) })
	Ui.corner(lip, 2)
	return k
end

-- A button with its keyboard key on a cap at its left: "[T] STAMP". `h` is its height, so the
-- cap can be sized to it; returns the button and the cap.
function Ui.keyButton(parent: Instance?, key: string, value: string, colour: Color3, onClick: (() -> ())?, h: number?, opts: any?): (any, any)
	local height = h or 40
	local b = Ui.button(parent, value, colour, onClick, opts)
	local capH = math.floor(height * 0.6)
	local cap = Ui.keycap(b, key, math.floor(capH * 0.62))
	local capW = math.max(capH, #Ui.keyLabel(key) * math.floor(capH * 0.5) + 8)
	cap.Position, cap.Size = UDim2.new(0, 7, 0.5, -capH / 2 - 1), UDim2.fromOffset(capW, capH)
	cap.ZIndex = 2
	Ui.make("UIPadding", b, { PaddingLeft = UDim.new(0, capW + 10), PaddingRight = UDim.new(0, 6) })
	return b, cap
end

-- About how wide `value` is in display letters `px` tall (LuckiestGuy runs a little over half its
-- height per letter), for sizing what holds it without waiting a frame for TextBounds.
function Ui.textWidth(value: string, px: number): number
	return math.floor(#value * px * 0.58 + 0.5)
end

-- The width a key-cap-and-word chip needs with a cap `size` px tall: the cap, and the whole chip.
function Ui.chipWidth(key: string, word: string, size: number): (number, number)
	local capW = math.max(size + 8, Ui.textWidth(Ui.keyLabel(key), math.floor(size * 0.6)) + 12)
	return capW, capW + 6 + Ui.textWidth(word, math.floor(size * 0.62)) + 4
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
		local cap = Ui.keycap(row, item[1], math.floor(size * 0.6))
		cap.Name = "Key" .. i
		cap.Position, cap.Size = UDim2.new(0.5, x, 0.5, -size / 2), UDim2.fromOffset(capW, size)
		local word = Ui.text(row, item[2], math.floor(size * 0.62), colour or Ui.WHITE, Ui.DISPLAY)
		word.Name = "Word" .. i
		word.TextXAlignment = Enum.TextXAlignment.Left
		word.Position, word.Size = UDim2.new(0.5, x + capW + 6, 0.5, -size / 2), UDim2.fromOffset(widths[i] - capW - 6, size)
		x += widths[i] + 18
	end
	return row, total
end

-- A navy card with an ink border. With `band`, a coloured band `bandH` tall across its top with
-- `title` in it; returns the card, the band and the title.
function Ui.panel(parent: Instance?, name: string, band: Color3?, title: string?, bandH: number?): (any, any, any)
	local p = Ui.make("Frame", parent, { Name = name, BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0 })
	Ui.corner(p, 12)
	Ui.stroke(p, Ui.INK, 3)
	if not band then return p, nil, nil end
	local h = bandH or 34
	local b = Ui.make("Frame", p, { Name = "Band", BackgroundColor3 = band, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h) })
	Ui.corner(b, 12)
	-- squares off the band's lower corners, so it reads as a header, not a pill
	Ui.make("Frame", b, { Name = "Square", BackgroundColor3 = band, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12) })
	local t = Ui.text(b, title or "", math.floor(h * 0.56), Ui.WHITE, Ui.DISPLAY)
	t.Name = "Title"
	t.Position, t.Size = UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 2
	return p, b, t
end

-- A dark rounded strip for a line of status.
function Ui.pill(parent: Instance?, name: string, edge: Color3?): any
	local p = Ui.make("Frame", parent, { Name = name, BackgroundColor3 = Ui.INK, BackgroundTransparency = 0.12, BorderSizePixel = 0 })
	Ui.corner(p, 999)
	Ui.stroke(p, edge or Ui.EDGE, 2)
	return p
end

return Ui
