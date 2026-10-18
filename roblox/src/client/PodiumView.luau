--!strict
-- The results podium on Roblox: Podium.layout (the shared layout, held to web/src/render2d/podium.js)
-- drawn into a ScreenGui. Fighters stand on stepped pillars in finishing order, painted through the
-- same Fighter2D the match uses in a victory or defeat pose; a card of stats sits on each pillar.
-- tests/podium-view.luau checks what this puts on screen.
local Canvas2D = require(script.Parent.Canvas2D)
local Fighter2D = require(script.Parent.Fighter2D)
local PosedFighter = require(script.Parent.PosedFighter)
local Podium = require(script.Parent.Podium)
local HudColors = require(script.Parent.HudColors)
local Ui = require(script.Parent.Ui)

local PodiumView = {}
PodiumView.__index = PodiumView

-- The look is the shared cartoon kit's (Ui): a pixel dusk sky, stone plinths with a capstone in
-- the place's colour, ink-bordered cards with the place outlined in a band.
local FONT = Ui.LABEL
local GOLD = Ui.GOLD
local STAT = Color3.fromRGB(143, 184, 232)
local STONE = Color3.fromRGB(72, 82, 106)
local STONE_LIT = Color3.fromRGB(104, 116, 142)
local STONE_DARK = Color3.fromRGB(44, 50, 66)
local JOINT = Color3.fromRGB(58, 66, 86)
local CARD = Ui.PANEL
-- What draw paints, in order, so the test can find each part: the sky's bands across the whole
-- screen, then per pillar its body, lit edge, shadowed edge, two joints, the cap and the cap's
-- highlight.
PodiumView.SKY_BANDS = 12
PodiumView.PILLAR_RECTS = 7
PodiumView.CAP_AT = 6

local function frame(parent: Instance, x: number, y: number, w: number, h: number, colour: Color3, alpha: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = 1 - alpha
	f.Parent = parent
	return f
end

local function text(parent: Instance, x: number, y: number, w: number, h: number, s: string, size: number, colour: Color3, align: any?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Text = s
	t.TextSize = math.max(12, Ui.px(size))
	t.Font = FONT
	t.TextColor3 = colour
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

-- See PosedFighter: shared with the character studio's preview.
PodiumView.posed = PosedFighter.posed

-- `res` is MatchService.results: rows in finishing order, winnerTeam, teams. `chars` is indexed
-- by fighter index + 1, as the client's roster is. `onGG` is what "Say: GG!" does.
function PodiumView.new(parent: Instance, res: any, chars: { any }, size: Vector2, onGG: (() -> ())?): any
	local self: any = setmetatable({}, PodiumView)
	local W, H = size.X, size.Y
	local rows = res.rows or {}
	self.rows, self.chars, self.res = rows, chars, res
	self.places = Podium.places(rows, res.teams)
	self.slots = Podium.layout(#rows, W, H)
	self.t0 = nil
	self.ggUntil = 0
	self.size = size

	local root = frame(parent, 0, 0, W, H, Color3.fromRGB(11, 21, 38), 0.93)
	root.Name = "Podium"
	root.ZIndex = 20
	self.root = root
	-- Figures and pillars on a canvas of their own; the cards are ordinary Frames above it.
	local stage = frame(root, 0, 0, W, H, Color3.new(), 0)
	stage.Name = "PodiumStage"
	self.canvas = Canvas2D.inFrame(stage)

	local title = text(root, 0, H * 0.1, W, H * 0.09, string.upper(Podium.title(rows, res.teams)), H * 0.06, GOLD, Enum.TextXAlignment.Center)
	title.Name = "PodiumTitle"
	title.Font = Ui.DISPLAY
	title.TextTruncate = Enum.TextTruncate.None
	Ui.outline(title, math.max(3, math.floor(H * 0.006)))

	local gg = Ui.button(root, "SAY GG!", Ui.GREEN, function()
		self.ggUntil = (self.clock or 0) + 2
		if onGG then onGG() end
	end)
	gg.Name = "SayGG"
	gg.Size = UDim2.fromOffset(150, 40)
	gg.Position = UDim2.fromOffset(W / 2 - 75, 12)
	self.gg = gg
	-- The bubble a GG puts over a figure, while it lasts (placed in draw).
	-- (ink letters on white, so no outline: on ink letters it only thickens them into a blot)
	local bubble = Ui.make("TextLabel", root, { Name = "GGBubble", Text = "GG!", Font = Ui.DISPLAY, TextSize = Ui.px(22),
		TextColor3 = Ui.INK, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0 })
	Ui.corner(bubble, 0)
	Ui.stroke(bubble, Ui.INK, 3)
	-- a stepped pixel tail under it, pointing down at the speaker
	for k, sz in { { 0, 12 }, { 1, 6 } } do
		Ui.make("Frame", bubble, { Name = "Tail" .. k, BackgroundColor3 = Ui.INK, BorderSizePixel = 0,
			Position = UDim2.new(0.3, sz[1] * 3, 1, sz[1] * 6), Size = UDim2.fromOffset(sz[2] + 4, 7) })
		Ui.make("Frame", bubble, { Name = "TailFill" .. k, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			Position = UDim2.new(0.3, sz[1] * 3 + 2, 1, sz[1] * 6 - 1), Size = UDim2.fromOffset(sz[2], 6) })
	end
	bubble.Visible = false
	self.bubble = bubble

	self.cards = {}
	-- one text size on every card (the smallest card's): the place shows in the pillar and the
	-- band, so the words need not shrink with it
	local rt = math.huge
	for _, s in self.slots do rt = math.min(rt, s.rowH) end
	for i, row in rows do
		local s = self.slots[i]
		local colour = if res.teams then HudColors.TEAM[(row.team % 2) + 1] else HudColors.PLAYER[(row.index % 8) + 1]
		local first = self.places[i] == 1
		-- an ink-bordered card (gold for the winners), its place outlined in a band of its colour
		local card = frame(root, s.card.x, s.card.y, s.card.w, s.card.h, CARD, 0.96)
		card.Name = `Card{i}`
		Ui.corner(card, 0)
		Ui.stroke(card, if first then GOLD else Ui.INK, 3)
		Ui.rim(card, if first then Ui.shade(GOLD, -0.35) else Ui.PANEL2, 2, 0)
		local rh = s.rowH
		local bandH = rh * 1.3
		local band = frame(card, 0, 0, s.card.w, bandH, if first then GOLD else colour, 1)
		band.Name = "Band"
		frame(band, 0, bandH - 3, s.card.w, 3, Ui.shade(if first then GOLD else colour, -0.45), 1).Name = "Ledge"
		local pad = s.card.w * 0.06
		local place = text(card, 0, rh * 0.1, s.card.w, rh * 1.1, string.upper(Podium.ordinal(self.places[i])), rh * 0.8, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
		place.Name = "Place"
		place.Font = Ui.DISPLAY
		Ui.outline(place, math.max(2, math.floor(rh * 0.08)))
		local name = text(card, pad, rh * 1.35, s.card.w - pad * 2, rh * 0.75, `{HudColors.MARKS[(row.index % 8) + 1]} {row.name}`, rt * 0.62, Ui.shade(colour, 0.45))
		name.Name = "Name"
		name.Font = Ui.DISPLAY
		Ui.outline(name, 2)
		for k, stat in Podium.STATS do
			local y = rh * (2.1 + (k - 1))
			text(card, pad, y, s.card.w * 0.6, rh, string.upper(stat[1]), rt * 0.46, STAT).Name = `Label{k}`
			local v = text(card, s.card.w * 0.5, y, s.card.w * 0.5 - pad, rh, tostring(Podium.statValue(row, stat[2])), rt * 0.6, Color3.new(1, 1, 1), Enum.TextXAlignment.Right)
			v.Name = `Value{k}`
			v.Font = Ui.DISPLAY
			Ui.outline(v, 2)
		end
		self.cards[i] = card
	end
	return self
end

-- Pillars and figures, redrawn every frame so the poses keep moving.
function PodiumView.draw(self: any, clock: number)
	self.clock = clock
	self.t0 = self.t0 or clock
	local t = clock - self.t0
	local sf = math.floor(t * 60)
	local c = self.canvas
	-- the sky: dusk in pixel bands, as the select screen's
	Canvas2D.screen(c)
	local W, H = self.size.X, self.size.Y
	for b = 0, PodiumView.SKY_BANDS - 1 do
		local k = b / (PodiumView.SKY_BANDS - 1)
		Canvas2D.rect(c, 0, b * H / PodiumView.SKY_BANDS, W, H / PodiumView.SKY_BANDS + 1,
			Color3.new(0.07 + 0.2 * k, 0.09 + 0.1 * k, 0.2 + 0.18 * k), 1)
	end
	for i, row in self.rows do
		local s = self.slots[i]
		Canvas2D.screen(c)
		local colour = if self.res.teams then HudColors.TEAM[(row.team % 2) + 1] else HudColors.PLAYER[(row.index % 8) + 1]
		-- a stone plinth: lit on the left, shadowed on the right, two joints across it
		local p = s.pillar
		Canvas2D.rect(c, p.x, p.y, p.w, p.h, STONE, 1)
		Canvas2D.rect(c, p.x, p.y, p.w * 0.12, p.h, STONE_LIT, 1)
		Canvas2D.rect(c, p.x + p.w * 0.9, p.y, p.w * 0.1, p.h, STONE_DARK, 1)
		Canvas2D.rect(c, p.x, p.y + p.h / 3, p.w, math.max(2, p.h * 0.02), JOINT, 1)
		Canvas2D.rect(c, p.x, p.y + p.h * 2 / 3, p.w, math.max(2, p.h * 0.02), JOINT, 1)
		-- the capstone in the place's colour, with a highlight along its top
		local capColour = if self.places[i] == 1 then GOLD else colour
		Canvas2D.rect(c, s.cap.x, s.cap.y, s.cap.w, s.cap.h, capColour, 1)
		Canvas2D.rect(c, s.cap.x, s.cap.y, s.cap.w, math.max(2, s.cap.h * 0.25), Ui.shade(capColour, 0.4), 1)
		local char = self.chars[row.index + 1]
		if char then
			local won = if self.res.teams then row.team == self.res.winnerTeam else i == 1
			local st = PodiumView.posed(char, row.index, if won then "victory" else "defeat", sf)
			local ppu = s.figureH / char.height
			Canvas2D.setTransform(c, ppu, 0, 0, -ppu, s.cx, s.top)
			pcall(Fighter2D.draw, c, st, char, t, nil)
		end
	end
	-- The GG bubble goes over the local player's figure when they are on the podium, else the winner.
	local saying = clock < self.ggUntil and self.slots[1] ~= nil
	self.bubble.Visible = saying
	if saying then
		local s = self.slots[self.localPlace or 1]
		self.bubble.Position = UDim2.fromOffset(s.cx - s.figureH * 0.32, s.top - s.figureH * 1.4)
		self.bubble.Size = UDim2.fromOffset(s.figureH * 0.64, s.figureH * 0.26)
		self.bubble.TextSize = Ui.px(s.figureH * 0.16)
	end
	Canvas2D.finish(c)
end

function PodiumView.destroy(self: any)
	self.root:Destroy()
end

return PodiumView
