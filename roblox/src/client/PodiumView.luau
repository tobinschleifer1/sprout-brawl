--!strict
-- The results podium on Roblox: Podium.layout (the shared layout, held to web/src/render2d/podium.js)
-- drawn into a ScreenGui. Fighters stand on stepped pillars in finishing order, painted through the
-- same Fighter2D the match uses in a victory or defeat pose; a card of stats sits on each pillar.
-- tests/podium-view.luau checks what this puts on screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fighter = require(ReplicatedStorage.Shared.Fighter)
local Snapshot = require(ReplicatedStorage.Shared.Snapshot)
local Canvas2D = require(script.Parent.Canvas2D)
local Fighter2D = require(script.Parent.Fighter2D)
local Podium = require(script.Parent.Podium)
local HudColors = require(script.Parent.HudColors)

local PodiumView = {}
PodiumView.__index = PodiumView

local FONT = Enum.Font.GothamBold
local GOLD = Color3.fromRGB(255, 213, 138)
local STAT = Color3.fromRGB(143, 184, 232)
local PILLAR = Color3.fromRGB(36, 49, 66)
local PILLAR_LIT = Color3.fromRGB(46, 61, 81)
local CARD = Color3.fromRGB(20, 30, 44)

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
	t.TextSize = math.max(8, math.floor(size + 0.5))
	t.Font = FONT
	t.TextColor3 = colour
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

-- A fighter standing still in `state`, in the shape Fighter2D reads (Snapshot's field names), built
-- from a real Fighter so every field the pose code reads exists - the web does the same with
-- render2d/preview.js posedFighter.
function PodiumView.posed(char: any, index: number, state: string, sf: number): any
	local f: any = Fighter.new({ index = index, char = char, x = 0, y = 0, stocks = 1 })
	f.state, f.sf, f.frameCount, f.onGround = state, sf, sf, true
	local out: any = {}
	for _, pair in Snapshot.FIELDS do
		local name = pair[1]
		out[name] = f[Snapshot.FROM_FIGHTER[name] or name]
	end
	out.index, out.chillStacks = index, 0
	return out
end

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

	local root = frame(parent, 0, 0, W, H, Color3.fromRGB(11, 21, 38), 0.93)
	root.Name = "Podium"
	root.ZIndex = 20
	self.root = root
	-- Figures and pillars on a canvas of their own; the cards are ordinary Frames above it.
	local stage = frame(root, 0, 0, W, H, Color3.new(), 0)
	stage.Name = "PodiumStage"
	self.canvas = Canvas2D.inFrame(stage)

	local w = rows[1]
	local winner = if not w then "" elseif res.teams then (if w.team == 0 then "Green team" else "Orange team") else w.name
	local title = text(root, 0, H * 0.1, W, H * 0.08, `{winner} wins`, H * 0.065, GOLD, Enum.TextXAlignment.Center)
	title.Name = "PodiumTitle"

	local gg = Instance.new("TextButton")
	gg.Name = "SayGG"
	gg.Text = "Say: GG!"
	gg.Font = FONT
	gg.TextSize = 16
	gg.TextColor3 = Color3.new(1, 1, 1)
	gg.BackgroundColor3 = Color3.fromRGB(43, 57, 74)
	gg.BorderSizePixel = 0
	gg.Size = UDim2.fromOffset(140, 34)
	gg.Position = UDim2.fromOffset(W / 2 - 70, 12)
	gg.Parent = root
	gg.Activated:Connect(function()
		self.ggUntil = (self.clock or 0) + 2
		if onGG then onGG() end
	end)
	self.gg = gg

	self.cards = {}
	for i, row in rows do
		local s = self.slots[i]
		local colour = if res.teams then HudColors.TEAM[(row.team % 2) + 1] else HudColors.PLAYER[(row.index % 8) + 1]
		local first = self.places[i] == 1
		local card = frame(root, s.card.x, s.card.y, s.card.w, s.card.h, CARD, 0.95)
		card.Name = `Card{i}`
		local stroke = Instance.new("UIStroke")
		stroke.Color = if first then GOLD else Color3.fromRGB(59, 72, 88)
		stroke.Thickness = 2
		stroke.Parent = card
		frame(card, 0, 0, s.card.w, math.max(3, s.rowH * 0.18), if first then GOLD else colour, 1).Name = "Band"
		local rh = s.rowH
		local pad = s.card.w * 0.06
		local place = text(card, 0, rh * 0.2, s.card.w, rh * 1.1, Podium.ordinal(self.places[i]), rh * 0.95, GOLD, Enum.TextXAlignment.Center)
		place.Name = "Place"
		local name = text(card, pad, rh * 1.3, s.card.w - pad * 2, rh * 0.7, `{HudColors.MARKS[(row.index % 8) + 1]} {row.name}`, rh * 0.6, colour)
		name.Name = "Name"
		for k, stat in Podium.STATS do
			local y = rh * (2.1 + (k - 1))
			text(card, pad, y, s.card.w * 0.6, rh, stat[1], rh * 0.5, STAT).Name = `Label{k}`
			local v = text(card, s.card.w * 0.5, y, s.card.w * 0.5 - pad, rh, tostring(Podium.statValue(row, stat[2])), rh * 0.55, Color3.new(1, 1, 1), Enum.TextXAlignment.Right)
			v.Name = `Value{k}`
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
	for i, row in self.rows do
		local s = self.slots[i]
		Canvas2D.screen(c)
		local colour = if self.res.teams then HudColors.TEAM[(row.team % 2) + 1] else HudColors.PLAYER[(row.index % 8) + 1]
		Canvas2D.rect(c, s.pillar.x, s.pillar.y, s.pillar.w, s.pillar.h, PILLAR, 1)
		Canvas2D.rect(c, s.pillar.x, s.pillar.y, s.pillar.w * 0.12, s.pillar.h, PILLAR_LIT, 1)
		Canvas2D.rect(c, s.cap.x, s.cap.y, s.cap.w, s.cap.h, if self.places[i] == 1 then GOLD else colour, 1)
		local char = self.chars[row.index + 1]
		if char then
			local won = if self.res.teams then row.team == self.res.winnerTeam else i == 1
			local st = PodiumView.posed(char, row.index, if won then "victory" else "defeat", sf)
			local ppu = s.figureH / char.height
			Canvas2D.setTransform(c, ppu, 0, 0, -ppu, s.cx, s.top)
			pcall(Fighter2D.draw, c, st, char, t, nil)
		end
	end
	if clock < self.ggUntil and self.slots[1] then
		-- The bubble goes over the local player's figure when they are on the podium, else the winner.
		local s = self.slots[self.localPlace or 1]
		Canvas2D.screen(c)
		Canvas2D.rect(c, s.cx - s.figureH * 0.32, s.top - s.figureH * 1.38, s.figureH * 0.64, s.figureH * 0.24, Color3.new(1, 1, 1), 0.95)
	end
	Canvas2D.finish(c)
end

function PodiumView.destroy(self: any)
	self.root:Destroy()
end

return PodiumView
