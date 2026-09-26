--!strict
-- The match readout: percent, stocks, the timer and the callouts.
--
-- web/src/ui/hud.js is a DOM tree - divs, CSS classes, innerHTML - so unlike channels.js and
-- weapons2d.js there is nothing here to translate. What carries over is WHAT IT SAYS and where:
-- a band of per-fighter tiles along the bottom, a timer above them, a callout in the middle, and
-- a percent floating over each fighter's head. The arithmetic that cannot be checked by looking -
-- the damage colour ramp - lives in HudColors and is held to the JavaScript by a test.
--
-- This is its own ScreenGui, deliberately. Canvas2D owns a pool of Frames it hides and reuses
-- every frame, and a HUD sharing that pool would flicker or be recycled out from under itself.
--
-- EVERYTHING HERE READS THE SNAPSHOT. ultMeter and ultReady are computed from ultCharge rather
-- than sent, because they are a division and a comparison against a shared constant - putting them
-- on the wire would be sending an opinion the client can derive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HudColors = require(script.Parent.HudColors)
local Bindings = require(script.Parent.Bindings)
local AbilityStatus = require(script.Parent.AbilityStatus)

local DisasterShapes = require(script.Parent.DisasterShapes)
local PodiumView = require(script.Parent.PodiumView)
local Hud = {}
Hud.__index = Hud

local FONT = Enum.Font.GothamBold
local DIM = Color3.fromRGB(198, 204, 214)
local PANEL = Color3.fromRGB(18, 20, 26)

local function label(parent: Instance, size: UDim2, pos: UDim2, text: string, px: number, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.TextSize = px
	t.Font = FONT
	t.TextColor3 = colour
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

function Hud.new(parent: Instance): any
	local self = setmetatable({}, Hud)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlockfallHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 11          -- above the canvas (10): equal orders left it to creation order
	gui.Parent = parent
	self.gui = gui

	self.timer = label(gui, UDim2.fromOffset(280, 34), UDim2.new(0.5, -140, 0, 12), "", 26, DIM)
	self.timer.TextXAlignment = Enum.TextXAlignment.Center
	local hints = label(gui, UDim2.new(1, -24, 0, 38), UDim2.fromOffset(12, 48), Bindings.hint(), 13, DIM)
	hints.Name = "CombatBindings"
	hints.TextWrapped = true
	hints.TextXAlignment = Enum.TextXAlignment.Center
	self.abilities = label(gui, UDim2.new(1, -24, 0, 42), UDim2.fromOffset(12, 88), "", 13, Color3.fromRGB(239,176,90))
	self.abilities.Name = "YourAbilities"
	self.abilities.TextWrapped = true
	self.abilities.TextXAlignment = Enum.TextXAlignment.Center

	-- What natural disaster is coming and when: cool while it warns, hot once it strikes.
	self.disaster = label(gui, UDim2.fromOffset(420, 26), UDim2.new(0.5, -210, 0, 134), "", 18, Color3.new(1, 1, 1))
	self.disaster.Name = "DisasterBanner"
	self.disaster.TextXAlignment = Enum.TextXAlignment.Center

	-- The ultimate's name and caster, laid along the cutscene banner the canvas paints.
	self.ultName = label(gui, UDim2.fromOffset(10, 10), UDim2.fromOffset(0, 0), "", 20, Color3.new(1, 1, 1))
	self.ultName.Name = "UltimateName"
	self.ultName.AnchorPoint = Vector2.new(0.5, 0.5)
	self.ultName.TextXAlignment = Enum.TextXAlignment.Center
	self.ultName.Font = Enum.Font.Arcade
	self.ultCaster = label(gui, UDim2.fromOffset(10, 10), UDim2.fromOffset(0, 0), "", 10, Color3.new(1, 1, 1))
	self.ultCaster.Name = "UltimateCaster"
	self.ultCaster.AnchorPoint = Vector2.new(0.5, 0.5)
	self.ultCaster.TextXAlignment = Enum.TextXAlignment.Center
	self.ultCaster.Font = Enum.Font.Arcade

	self.callout = label(gui, UDim2.fromOffset(600, 90), UDim2.new(0.5, -300, 0.32, 0), "", 72, Color3.new(1, 1, 1))
	self.callout.TextXAlignment = Enum.TextXAlignment.Center
	self.callout.TextTransparency = 1

	self.tiles = {}
	self.floats = {}
	return self
end

-- One tile per fighter, built once a match. The mark is a shape as well as a colour, because at
-- tile size four coloured boxes are four boxes.
function Hud.bind(self: any, roster: { any }, chars: { any }, localIndex: number?)
	self.localIndex = localIndex
	for _, t in self.tiles do
		t.root:Destroy()
	end
	for _, f in self.floats do
		f:Destroy()
	end
	self.tiles, self.floats = {}, {}

	local n = #roster
	local W, H, GAP = math.clamp(math.floor((self.gui.AbsoluteSize.X - 36) / 2), 140, 190), 62, 10
	local columns = math.max(1, math.min(n, math.floor((self.gui.AbsoluteSize.X - 16) / (W + GAP))))
	local total = columns * W + (columns - 1) * GAP
	self.layoutWidth = self.gui.AbsoluteSize.X
	for i, entry in roster do
		local colour = HudColors.PLAYER[(entry.index % 8) + 1]
		local root = Instance.new("Frame")
		root.Size = UDim2.fromOffset(W, H)
		root.Position = UDim2.new(0.5, -total / 2 + ((i - 1) % columns) * (W + GAP), 1,
			-14 - (math.ceil(n / columns) - math.floor((i - 1) / columns)) * (H + GAP))
		root.BackgroundColor3 = PANEL
		root.BackgroundTransparency = 0.25
		root.BorderSizePixel = 0
		root.Parent = self.gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = root
		-- The player's colour as a stripe rather than a fill: a filled tile fights the percent for
		-- attention, and the percent is the number that decides how you play the next ten seconds.
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, 0)
		stripe.BackgroundColor3 = colour
		stripe.BorderSizePixel = 0
		stripe.Parent = root

		local name = label(root, UDim2.fromOffset(W - 16, 16), UDim2.fromOffset(12, 5),
			`{HudColors.MARKS[(entry.index % 8) + 1]} T{entry.team + 1} {entry.name}`, 12, colour)
		local weapon = label(root, UDim2.fromOffset(W - 16, 14), UDim2.fromOffset(12, 20),
			chars[i] and chars[i].name or entry.weapon, 11, DIM)
		weapon.TextTransparency = 0.35
		local pct = label(root, UDim2.fromOffset(85, 30), UDim2.fromOffset(10, 30), "0%", 24, Color3.new(1, 1, 1))
		local stocks = label(root, UDim2.fromOffset(50, 18), UDim2.fromOffset(W - 58, 36), "", 13, colour)
		stocks.TextXAlignment = Enum.TextXAlignment.Right

		-- The ultimate meter. Hidden outright for a loadout with no ultimate, so it never shows a
		-- bar that cannot fill.
		local ultBack = Instance.new("Frame")
		ultBack.Size = UDim2.new(1, -20, 0, 4)
		ultBack.Position = UDim2.fromOffset(10, H - 10)
		ultBack.BackgroundColor3 = Color3.fromRGB(52, 58, 70)
		ultBack.BorderSizePixel = 0
		ultBack.Visible = chars[i] ~= nil and chars[i].moves.Ultimate ~= nil
		ultBack.Parent = root
		local ultFill = Instance.new("Frame")
		ultFill.Size = UDim2.new(0, 0, 1, 0)
		ultFill.BackgroundColor3 = colour
		ultFill.BorderSizePixel = 0
		ultFill.Parent = ultBack

		table.insert(self.tiles, {
			root = root, pct = pct, stocks = stocks, name = name, weapon = weapon,
			ultBack = ultBack, ultFill = ultFill, colour = colour, index = entry.index,
		})

		-- The floating percent over the fighter's own head, which is what a player actually reads
		-- mid-fight: the tiles are for the glance between stocks.
		local float = label(self.gui, UDim2.fromOffset(90, 22), UDim2.fromOffset(0, 0), "0%", 16, Color3.new(1, 1, 1))
		float.TextXAlignment = Enum.TextXAlignment.Center
		float.Visible = false
		float.Parent = self.gui
		table.insert(self.floats, float)
	end
end

local function mmss(t: number): string
	local left = math.max(0, t)
	return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
end

function Hud.abilityEvent(self: any, event: any)
	if event.fighter ~= self.localIndex then return end
	local message = AbilityStatus.event(event)
	if message then self.abilityMessage, self.abilityUntil = message, os.clock() + 2 end
end

-- `states` are the decoded fighters being drawn this frame, `snap` the newest snapshot for the
-- match-level clock, and `canvas` is asked to project so the floating labels use the renderer's
-- own camera rather than a second copy of it.
-- B is a UltCinematic.bannerLayout in screen pixels, or nil to hide. Both screens share one pixel
-- space because both ScreenGuis ignore the inset.
function Hud.ultBanner(self: any, B: any, ult: any)
	if not B or not ult then
		self.ultName.Visible, self.ultCaster.Visible = false, false
		return
	end
	local deg = math.deg(B.rot)
	local size = B.text.size
	-- The caster's name sits above the ultimate's, perpendicular to the band's axis.
	local nx, ny = math.sin(B.rot) * size * 1.1, -math.cos(B.rot) * size * 1.1
	self.ultName.Visible, self.ultCaster.Visible = true, true
	self.ultName.Text = string.upper(ult.label)
	self.ultName.TextSize = math.floor(size + 0.5)
	self.ultName.Size = UDim2.fromOffset(B.h * 4, size * 1.3)
	self.ultName.Position = UDim2.fromOffset(B.text.x, B.text.y)
	self.ultName.Rotation = deg
	self.ultName.TextTransparency = 1 - B.alpha
	self.ultCaster.Text = string.upper(ult.name)
	self.ultCaster.TextSize = math.floor(size * 0.5 + 0.5)
	self.ultCaster.Size = UDim2.fromOffset(B.h * 4, size * 0.7)
	self.ultCaster.Position = UDim2.fromOffset(B.text.x + nx, B.text.y + ny)
	self.ultCaster.Rotation = deg
	self.ultCaster.TextTransparency = 1 - B.alpha * 0.85
end

function Hud.update(self: any, states: { any }, snap: any, canvas: any, chars: { any }, cfg: any)
	if self.results then self.results:draw(os.clock()) end
	if self.layoutWidth ~= self.gui.AbsoluteSize.X and cfg then self:bind(cfg.fighters, chars, self.localIndex) end
	-- Timer. A stock match has no clock, and says so by showing nothing rather than 0:00.
	if snap and snap.state == "suddendeath" then
		self.timer.Text = "SUDDEN DEATH"
		self.timer.TextColor3 = Color3.fromRGB(232, 98, 42)
	elseif cfg and cfg.timed and snap then
		local left = (cfg.timeLimit or 180) - snap.time
		self.timer.Text = mmss(left)
		self.timer.TextColor3 = if left < 30 then Color3.fromRGB(232, 98, 42) else DIM
	else
		self.timer.Text = ""
	end

	local banner = DisasterShapes.banner(self.disasterView)
	if banner then
		self.disaster.Text = if banner.seconds ~= nil then `⚠ {banner.text} · {banner.seconds}` else `⚠ {banner.text}`
		self.disaster.TextColor3 = Color3.fromHex(banner.colour)
	else
		self.disaster.Text = ""
	end

	-- The callout: the countdown, then GO, then nothing.
	if snap and snap.state == "countdown" then
		local n = math.ceil(snap.countdown / 60)
		self.callout.Text = if n > 0 then tostring(n) else "GO"
		self.callout.TextTransparency = 0
	elseif snap and snap.state == "fight" and snap.time < 0.9 then
		self.callout.Text = "GO"
		self.callout.TextTransparency = math.clamp(snap.time / 0.9, 0, 1)
	else
		self.callout.TextTransparency = 1
	end

	local byIndex: { [number]: any } = {}
	for _, st in states do
		byIndex[st.index] = st
	end
	local mine = byIndex[self.localIndex]
	if mine and chars[self.localIndex + 1] then
		self.abilities.Text = if self.abilityUntil and os.clock() < self.abilityUntil then self.abilityMessage
			else AbilityStatus.describe(mine, chars[self.localIndex + 1])
	end

	for i, tile in self.tiles do
		local st = byIndex[tile.index]
		local float = self.floats[i]
		if not st then
			float.Visible = false
		else
			local pct = math.floor(st.percent + 0.5)
			tile.pct.Text = `{pct}%`
			tile.pct.TextColor3 = HudColors.percent(st.percent)
			-- Stocks as pips, capped: past eight the count stops being readable at a glance and
			-- the number would be better, but no mode here goes past a handful.
			tile.stocks.Text = string.rep("●", math.clamp(st.stocks, 0, 8))
			local out = st.stocks <= 0 and not st.alive
			tile.root.BackgroundTransparency = if out then 0.7 else 0.25
			tile.name.TextTransparency = if out then 0.6 else 0

			if tile.ultBack.Visible then
				local meter = math.min(1, st.ultCharge / Config.ULTIMATE.hitsRequired)
				tile.ultFill.Size = UDim2.new(meter, 0, 1, 0)
				local ready = st.ultCharge >= Config.ULTIMATE.hitsRequired
				tile.ultFill.BackgroundColor3 = if ready then Color3.new(1, 1, 1) else tile.colour
			end

			-- The floating label, over the head and a little above it.
			local char = chars[i]
			local h = if char then char.height else 5
			if st.alive and st.state ~= "ko" and canvas then
				local p = canvas:project(st.x, st.y + h + 1.4)
				local vp = canvas:viewport()
				float.Visible = p.X > -60 and p.X < vp.X + 60 and p.Y > -40 and p.Y < vp.Y + 40
				float.Position = UDim2.fromOffset(p.X - 45, p.Y - 22)
				float.Text = `{pct}%`
				float.TextColor3 = HudColors.percent(st.percent)
			else
				float.Visible = false
			end
		end
	end
end

-- The scoreboard, held up until the next match starts. Built fresh each time rather than kept
-- around hidden: it is shown once every sixty seconds and a stale one is worse than none.
-- The results podium (PodiumView, laid out by the shared Podium). "Say: GG!" posts to the
-- experience's text chat, so the other players see it, not only the one who pressed it.
function Hud.showResults(self: any, res: any, chars: { any }?)
	self:clearResults()
	local view = PodiumView.new(self.gui, res, chars or {}, self.gui.AbsoluteSize, function()
		pcall(function()
			local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
			local general = channels and channels:FindFirstChild("RBXGeneral")
			if general then (general :: any):SendAsync("GG!") end
		end)
	end)
	for i, row in res.rows or {} do
		if row.index == self.localIndex then view.localPlace = i end
	end
	self.results = view
	self.callout.TextTransparency = 1
end

function Hud.clearResults(self: any)
	if self.results then
		self.results:destroy()
		self.results = nil
	end
end

function Hud.destroy(self: any)
	self.gui:Destroy()
end

return Hud
