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
local Callouts = require(ReplicatedStorage.Shared.Data.Callouts)
local WeaponData = require(ReplicatedStorage.Shared.Weapons)
local HudColors = require(script.Parent.HudColors)
local Bindings = require(script.Parent.Bindings)
local AbilityStatus = require(script.Parent.AbilityStatus)
local ComboHud = require(script.Parent.ComboHud)
local ComboGuide = require(script.Parent.ComboGuide)

local DisasterShapes = require(script.Parent.DisasterShapes)
local PodiumView = require(script.Parent.PodiumView)
local Ui = require(script.Parent.Ui)
local Hud = {}
Hud.__index = Hud

-- The look is the shared cartoon kit's (Ui): outlined display numbers, ink-bordered cards, key caps.
local FONT = Ui.LABEL
-- the floating label over each fighter: its width, and how near the screen's top or bottom it may go
local FLOAT_W, FLOAT_EDGE = 130, 26
local DIM = Color3.fromRGB(198, 204, 214)
local PANEL = Ui.PANEL
local GOLD = Ui.GOLD                            -- a timed link's colour (FxPlayer.PERFECT)
local BROKE = Color3.fromRGB(150, 156, 168)
local SLATE = Color3.fromRGB(40, 54, 80)        -- an empty ultimate block
local ULT_BLOCKS = 10                           -- the meter's blocks: two hits of charge each

-- Hold H for your combo card mid-fight (it shows by itself through the countdown). Polled from
-- UserInputService rather than bound like the fight's keys: it changes nothing in the simulation.
Hud.COMBO_KEY = "H"
local UIS: any = nil
pcall(function() UIS = game:GetService("UserInputService") end)

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
-- Display words with the kit's ink outline; returns the label and the outline, which fades with it.
local function display(parent: Instance, size: UDim2, pos: UDim2, text: string, px: number, colour: Color3): (TextLabel, any)
	local t = label(parent, size, pos, text, px, colour)
	t.Font = Ui.DISPLAY
	return t, Ui.outline(t, math.max(1.5, px / 11))
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

	-- The clock, in a pill at the top; hidden with it in a stock match.
	local pill = Ui.pill(gui, "TimerPill", Ui.EDGE)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position, pill.Size = UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(124, 42)
	pill.Visible = false
	self.timerPill = pill
	self.timer = display(pill, UDim2.fromScale(1, 1), UDim2.new(), "", 30, DIM)
	self.timer.TextXAlignment = Enum.TextXAlignment.Center
	-- The keys that matter mid-fight, as caps, under the clock.
	local KB: any = Bindings.keyboard
	local hints = Ui.hintRow(gui, "CombatBindings", { { KB.ult[1], "ULTIMATE" }, { KB.guard[1], "SHIELD" },
		{ KB.pickup[1], "PICKUP" }, { Hud.COMBO_KEY, "COMBOS" } }, 22)
	hints.Position, hints.Size = UDim2.new(0, 0, 0, 60), UDim2.new(1, 0, 0, 24)
	self.hints = hints
	-- What your ultimate is waiting on, or what just happened to it, in a gold pill (empty: hidden).
	local abilityPill = Ui.pill(gui, "AbilityPill", GOLD)
	abilityPill.AnchorPoint = Vector2.new(0.5, 0)
	abilityPill.Position, abilityPill.Size = UDim2.new(0.5, 0, 0, 92), UDim2.fromOffset(500, 30)
	abilityPill.Visible = false
	self.abilityPill = abilityPill
	self.abilities = display(abilityPill, UDim2.fromScale(1, 1), UDim2.new(), "", 15, GOLD)
	self.abilities.Name = "YourAbilities"
	self.abilities.TextXAlignment = Enum.TextXAlignment.Center

	-- What natural disaster is coming and when: cool while it warns, hot once it strikes.
	self.disaster = display(gui, UDim2.fromOffset(520, 28), UDim2.new(0.5, -260, 0, 128), "", 22, Color3.new(1, 1, 1))
	self.disaster.Name = "DisasterBanner"
	self.disaster.TextXAlignment = Enum.TextXAlignment.Center

	-- The local player's combo routes (ComboGuide), read off their weapon and filled in by bind: a
	-- card through the countdown, then tucked away until COMBO_KEY is held.
	local card = Ui.panel(gui, "ComboCard", Color3.fromRGB(150, 96, 20), "YOUR COMBOS", 26)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position, card.Size = UDim2.new(0.5, 0, 0, 126), UDim2.new(1, -32, 0, 84)
	Ui.make("UISizeConstraint", card, { MaxSize = Vector2.new(760, 84) })
	card.Visible = false
	self.guideCard = card
	local hold = label(card, UDim2.new(0, 160, 0, 26), UDim2.new(1, -172, 0, 0), `HOLD {Hud.COMBO_KEY}`, 12, Ui.WHITE)
	hold.TextXAlignment = Enum.TextXAlignment.Right
	hold.ZIndex = 3
	self.guide = label(card, UDim2.new(1, -24, 0, 50), UDim2.fromOffset(12, 29), "", 13, GOLD)
	self.guide.Name = "ComboGuide"
	self.guide.TextWrapped = true
	self.guide.TextXAlignment = Enum.TextXAlignment.Center

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

	-- The stage's name as the match opens, above the countdown (which owns the callout).
	self.stageName, self.stageOutline = display(gui, UDim2.fromOffset(700, 50), UDim2.new(0.5, -350, 0.24, 0), "", 44, Color3.new(1, 1, 1))
	self.stageName.Name = "StageName"
	self.stageName.TextXAlignment = Enum.TextXAlignment.Center
	self.stageName.TextTransparency = 1

	-- The countdown, GO, KO and GAME: big cartoon words with a heavy outline.
	self.callout, self.calloutOutline = display(gui, UDim2.fromOffset(800, 100), UDim2.new(0.5, -400, 0.32, 0), "", 72, Color3.new(1, 1, 1))
	self.calloutOutline.Thickness = 5
	self.callout.TextXAlignment = Enum.TextXAlignment.Center
	self.callout.TextTransparency = 1

	-- Combos (Config.COMBO): ComboHud works out what to say; the tiles and this prompt say it.
	self.combo = ComboHud.new()
	-- Over the local player's head, during a freeze they can break out of.
	self.breakPrompt = display(gui, UDim2.fromOffset(120, 28), UDim2.fromOffset(0, 0), "DODGE!", 24, Color3.fromRGB(120, 220, 255))
	self.breakPrompt.Name = "BreakPrompt"
	self.breakPrompt.TextXAlignment = Enum.TextXAlignment.Center
	self.breakPrompt.Visible = false

	self.tiles = {}
	self.floats = {}
	return self
end

-- An event, released when the drawn picture reaches it (the same moment its effect plays).
function Hud.comboEvent(self: any, e: any)
	ComboHud.event(self.combo, e, os.clock())
end

-- One tile per fighter, built once a match. The mark is a shape as well as a colour, because at
-- tile size four coloured boxes are four boxes.
function Hud.bind(self: any, roster: { any }, chars: { any }, localIndex: number?, teams: boolean?)
	self.localIndex = localIndex
	self.guide.Text = table.concat(ComboGuide.lines(if localIndex ~= nil then chars[localIndex + 1] else nil), "\n")
	if teams ~= nil then self.teamsOn = teams end
	for _, t in self.tiles do
		t.root:Destroy()
	end
	for _, f in self.floats do
		f:Destroy()
	end
	self.tiles, self.floats, self.floatMarks = {}, {}, {}

	local n = #roster
	local W, H, GAP = math.clamp(math.floor((self.gui.AbsoluteSize.X - 36) / 2), 140, 190), 72, 10
	local columns = math.max(1, math.min(n, math.floor((self.gui.AbsoluteSize.X - 16) / (W + GAP))))
	local total = columns * W + (columns - 1) * GAP
	self.layoutWidth = self.gui.AbsoluteSize.X
	for i, entry in roster do
		-- In a team match the tile wears the team's colour, as the web's does.
		local colour = if self.teamsOn then HudColors.TEAM[((entry.team or 0) % 2) + 1] else HudColors.PLAYER[(entry.index % 8) + 1]
		local yours = entry.index == localIndex
		-- A card: ink border (gold on your own), a band in the player's colour with their mark and
		-- name outlined in it, the percent big under it. The colour is the band, not the fill: a
		-- filled card fights the percent for attention, and the percent is the number that decides
		-- how you play the next ten seconds.
		local root = Ui.make("Frame", self.gui, { Name = "Tile" .. i, BackgroundColor3 = PANEL, BackgroundTransparency = 0.08,
			BorderSizePixel = 0, Size = UDim2.fromOffset(W, H) })
		root.Position = UDim2.new(0.5, -total / 2 + ((i - 1) % columns) * (W + GAP), 1,
			-14 - (math.ceil(n / columns) - math.floor((i - 1) / columns)) * (H + GAP))
		Ui.corner(root, 12)
		Ui.stroke(root, if yours then GOLD else Ui.INK, 3)
		local band = Ui.make("Frame", root, { Name = "Band", BackgroundColor3 = colour, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 20) })
		Ui.corner(band, 12)
		Ui.make("Frame", band, { Name = "Square", BackgroundColor3 = colour, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 10) })

		local name = display(band, UDim2.fromOffset(W - 16, 20), UDim2.fromOffset(8, 0),
			`{HudColors.MARKS[(entry.index % 8) + 1]} {string.upper(entry.name)}`, 13, Color3.new(1, 1, 1))
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local weapon = label(root, UDim2.fromOffset(W - 16, 13), UDim2.fromOffset(8, 22),
			string.upper(chars[i] and chars[i].name or entry.weapon), 10, DIM)
		local pct = display(root, UDim2.fromOffset(96, 32), UDim2.fromOffset(8, 33), "0%", 30, Color3.new(1, 1, 1))
		-- Stocks as pixel blocks in the player's colour, right-aligned, capped at eight.
		local pips = {}
		for k = 1, 8 do
			local pip = Ui.make("Frame", root, { Name = "Stock" .. k, BackgroundColor3 = colour, BorderSizePixel = 0,
				Position = UDim2.fromOffset(W - 8 - k * 13, 26), Size = UDim2.fromOffset(10, 10), Visible = false })
			Ui.stroke(pip, Ui.INK, 1.5)
			Ui.make("Frame", pip, { Name = "Hi", BackgroundColor3 = Ui.shade(colour, 0.45), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2) })
			pips[k] = pip
		end

		-- The ultimate meter: a row of blocks along the card's foot. Hidden outright for a loadout
		-- with no ultimate, so it never shows a meter that cannot fill.
		local ultBack = Ui.make("Frame", root, { Name = "Ultimate", BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.new(1, -8 - 76, 1, -15), Size = UDim2.fromOffset(76, 8) })
		-- (with weapon drops a fighter starts on fists, which have none - but the meter fills on fists
		-- and waits for a weapon, so a fighter with a kit always shows it)
		ultBack.Visible = chars[i] ~= nil and (chars[i].moves.Ultimate ~= nil or entry.kit ~= nil)
		local blocks = {}
		for k = 1, ULT_BLOCKS do
			blocks[k] = Ui.make("Frame", ultBack, { BackgroundColor3 = SLATE, BorderSizePixel = 0,
				Position = UDim2.fromOffset((k - 1) * 7.6, 0), Size = UDim2.fromOffset(6, 8) })
		end
		-- Your own card says when your shield is up.
		local shield = nil
		if yours then
			shield = label(root, UDim2.fromOffset(76, 12), UDim2.new(1, -8 - 76, 1, -29), "SHIELD", 10, DIM)
			shield.Name = "Shield"
			shield.TextXAlignment = Enum.TextXAlignment.Right
		end

		-- The combo this fighter is running, above their tile: the hit count and damage, and their
		-- streak of timed links under it. Their own combo-break cooldown sits in the tile's corner.
		local combo = display(root, UDim2.fromOffset(W, 24), UDim2.fromOffset(0, -50), "", 20, Color3.new(1, 1, 1))
		combo.Name = "Combo"
		local perfect = display(root, UDim2.fromOffset(W, 18), UDim2.fromOffset(0, -26), "", 15, GOLD)
		perfect.Name = "Perfect"
		local breakCd = label(root, UDim2.fromOffset(70, 12), UDim2.fromOffset(W - 78, 22), "", 10, BROKE)
		breakCd.Name = "BreakCooldown"
		breakCd.TextXAlignment = Enum.TextXAlignment.Right

		table.insert(self.tiles, {
			root = root, pct = pct, pips = pips, name = name, weapon = weapon,
			ultBack = ultBack, ult = blocks, colour = colour, index = entry.index, shield = shield,
			kit = entry.kit, shownArmed = nil,
			combo = combo, perfect = perfect, breakCd = breakCd,
		})

		-- The floating percent over the fighter's own head, which is what a player actually reads
		-- mid-fight: the tiles are for the glance between stocks.
		local float = display(self.gui, UDim2.fromOffset(FLOAT_W, 22), UDim2.fromOffset(0, 0), "0%", 17, Color3.new(1, 1, 1))
		float.TextXAlignment = Enum.TextXAlignment.Center
		-- The player's mark in their (team) colour ahead of the percent, as the web's label has it.
		float.RichText = true
		local hex = string.format("%02X%02X%02X", math.floor(colour.R * 255 + 0.5), math.floor(colour.G * 255 + 0.5), math.floor(colour.B * 255 + 0.5))
		self.floatMarks[#self.floats + 1] = `<font color="#{hex}">{HudColors.MARKS[(entry.index % 8) + 1]}</font>`
		float.Visible = false
		float.Parent = self.gui
		table.insert(self.floats, float)
	end
end

-- Where a floating label goes for a head projected to `p` on a `vp` screen: over the head while
-- it is on screen; held at the nearest edge with an arrow pointing out at them while it is not, so
-- a fighter launched off screen is still somewhere you can read (the web clamps its labels the
-- same way). Returns the label's centre and the arrow ("" on screen).
function Hud.floatPlace(p: Vector2, vp: Vector2): (number, number, string)
	local arrow = if p.X < 0 then "◀ " elseif p.X > vp.X then "▶ " elseif p.Y < 0 then "▲ " elseif p.Y > vp.Y then "▼ " else ""
	return math.clamp(p.X, FLOAT_W / 2, vp.X - FLOAT_W / 2), math.clamp(p.Y, FLOAT_EDGE, vp.Y - FLOAT_EDGE), arrow
end

local function mmss(t: number): string
	local left = math.max(0, t)
	return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
end

-- A callout in the middle of the screen - the stage name, a KO, sudden death, GAME! - with the
-- text, colour and hold time of web/src/data/callouts.js. `text` overrides the table's own.
function Hud.announce(self: any, key: string, text: string?)
	local c = Callouts[key]
	if not c then return end
	local flash = { text = text or c.text or "", colour = Color3.fromHex(c.colour), start = os.clock(), dur = c.ms / 1000 }
	if key == "stage" then self.stageFlash = flash else self.flash = flash end
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

-- Is COMBO_KEY held (and not into a chat box)?
function Hud.comboHeld(_self: any): boolean
	if not UIS then return false end
	local ok, held = pcall(function()
		if UIS:GetFocusedTextBox() then return false end
		return UIS:IsKeyDown((Enum.KeyCode :: any)[Hud.COMBO_KEY])
	end)
	return ok and held == true
end

function Hud.update(self: any, states: { any }, snap: any, canvas: any, chars: { any }, cfg: any)
	if self.results then self.results:draw(os.clock()) end
	if self.layoutWidth ~= self.gui.AbsoluteSize.X and cfg then self:bind(cfg.fighters, chars, self.localIndex, self.teamsOn) end
	-- Timer. A stock match has no clock, and says so by showing nothing rather than 0:00.
	if snap and snap.state == "suddendeath" then
		self.timer.Text = "SUDDEN DEATH"
		self.timer.TextColor3 = Color3.fromRGB(232, 98, 42)
	elseif cfg and cfg.timed and snap then
		local left = (cfg.timeLimit or 180) - snap.time
		self.timer.Text = mmss(left)
		self.timer.TextColor3 = if left < 30 then Color3.fromRGB(232, 98, 42) else Ui.WHITE
	else
		self.timer.Text = ""
	end
	self.timerPill.Visible = self.timer.Text ~= ""
	self.timerPill.Size = UDim2.fromOffset(if #self.timer.Text > 6 then 250 else 124, 42)

	local banner = DisasterShapes.banner(self.disasterView)
	if banner then
		self.disaster.Text = if banner.seconds ~= nil then `⚠ {banner.text} · {banner.seconds}` else `⚠ {banner.text}`
		self.disaster.TextColor3 = Color3.fromHex(banner.colour)
	else
		self.disaster.Text = ""
	end

	-- The callout: the countdown, then the go call, then whatever was announced last.
	local now = os.clock()
	local sf = self.stageFlash
	if sf and now < sf.start + sf.dur then
		local k = (now - sf.start) / sf.dur
		self.stageName.Text, self.stageName.TextColor3 = sf.text, sf.colour
		self.stageName.TextTransparency = if k < 0.7 then 0 else (k - 0.7) / 0.3
	else
		self.stageName.TextTransparency = 1
	end
	self.callout.TextSize = 72
	if snap and snap.state == "countdown" then
		local n = math.ceil(snap.countdown / 60)
		self.callout.Text = if n > 0 then tostring(n) else Callouts.go.text
		self.callout.TextColor3 = if n > 0 then Color3.fromHex(Callouts.count.colour) else Color3.fromHex(Callouts.go.colour)
		self.callout.TextTransparency = 0
	elseif snap and snap.state == "fight" and snap.time < Callouts.go.ms / 1000 then
		self.callout.Text = Callouts.go.text
		self.callout.TextColor3 = Color3.fromHex(Callouts.go.colour)
		self.callout.TextTransparency = math.clamp(snap.time / (Callouts.go.ms / 1000), 0, 1)
	elseif self.flash and now < self.flash.start + self.flash.dur then
		-- held, then faded over the last third
		local k = (now - self.flash.start) / self.flash.dur
		self.callout.Text = self.flash.text
		self.callout.TextColor3 = self.flash.colour
		self.callout.TextSize = if #self.flash.text > 10 then 48 else 72
		self.callout.TextTransparency = if k < 0.7 then 0 else (k - 0.7) / 0.3
	else
		self.callout.TextTransparency = 1
	end
	self.calloutOutline.Transparency = self.callout.TextTransparency
	self.stageOutline.Transparency = self.stageName.TextTransparency
	-- the combo card: through the countdown, and while its key is held
	self.guideCard.Visible = self.guide.Text ~= "" and ((snap ~= nil and snap.state == "countdown") or self:comboHeld())
	-- (a disaster's banner steps down under the card while it shows)
	self.disaster.Position = UDim2.new(0.5, -260, 0, if self.guideCard.Visible then 218 else 128)

	local byIndex: { [number]: any } = {}
	for _, st in states do
		byIndex[st.index] = st
	end
	local mine = byIndex[self.localIndex]
	-- the gold pill: what just happened to your ultimate, or, once it is full, what it waits on
	local said = nil
	if mine and chars[self.localIndex + 1] then
		said = if self.abilityUntil and os.clock() < self.abilityUntil then self.abilityMessage else nil
		if not said then
			local ult = AbilityStatus.ultimate(mine, chars[self.localIndex + 1])
			if string.sub(ult, 1, 5) == "READY" then said = "ULTIMATE " .. ult end
		end
	end
	self.abilities.Text = said or ""
	self.abilityPill.Visible = said ~= nil
	if said then self.abilityPill.Size = UDim2.fromOffset(math.clamp(Ui.textWidth(said, 15) + 44, 200, 640), 30) end

	local combos = ComboHud.view(self.combo, states, now)
	for _, tile in self.tiles do
		local c = combos[tile.index]
		if c then
			local team = if c.team then "TEAM " else ""
			tile.combo.Text = if c.broken then `{team}{c.hits} HITS · BROKEN` else `{team}{c.hits} HITS  {c.damage}%`
			tile.combo.TextColor3 = if c.broken then BROKE elseif c.finisher then GOLD else Color3.new(1, 1, 1)
			tile.combo.TextTransparency = 1 - c.alpha
			tile.perfect.Text = if c.finisher then "FINISHER!" elseif c.perfect > 0 then `PERFECT ×{c.perfect}` else ""
			tile.perfect.TextTransparency = 1 - c.alpha
		else
			tile.combo.Text, tile.perfect.Text = "", ""
		end
		local b = ComboHud.breakView(byIndex[tile.index])
		tile.breakCd.Text = if b.cooldown > 0 then string.format("BREAK %.0fs", math.ceil(b.cooldown)) else ""
	end
	local prompt = ComboHud.breakView(mine)
	self.breakPrompt.Visible = false
	if prompt.prompt and mine and canvas then
		local ch = chars[self.localIndex + 1]
		local p = canvas:project(mine.x, mine.y + (if ch then ch.height else 5) + 3.2)
		self.breakPrompt.Position = UDim2.fromOffset(p.X - 60, p.Y - 24)
		self.breakPrompt.Visible = true
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
			-- weapon drops: both weapons on the tile, the one in hand in gold, written when it changes
			if tile.kit and tile.shownArmed ~= st.armed then
				tile.shownArmed = st.armed
				local parts = {}
				for k, id in tile.kit do
					local name = string.upper((WeaponData.BY_ID[id] or { name = id }).name)
					table.insert(parts, if st.armed == k - 1 then `<font color="#FFD24A">{name}</font>` else name)
				end
				tile.weapon.RichText = true
				tile.weapon.Text = table.concat(parts, "  ·  ")
			end
			local stocks = math.clamp(st.stocks, 0, 8)
			for k, pip in tile.pips do pip.Visible = k <= stocks end
			local out = st.stocks <= 0 and not st.alive
			tile.root.BackgroundTransparency = if out then 0.6 else 0.08
			tile.name.TextTransparency = if out then 0.6 else 0

			if tile.ultBack.Visible then
				local meter = math.min(1, st.ultCharge / Config.ULTIMATE.hitsRequired)
				local lit = math.floor(meter * ULT_BLOCKS + 1e-9)
				local ready = st.ultCharge >= Config.ULTIMATE.hitsRequired
				for k, block in tile.ult do
					block.BackgroundColor3 = if k > lit then SLATE elseif ready then GOLD else tile.colour
				end
			end
			if tile.shield then
				local up = st.state == "shield"
				tile.shield.Text = if up then "SHIELD UP" else "SHIELD"
				tile.shield.TextColor3 = if up then Color3.fromRGB(120, 220, 255) else DIM
			end

			-- The floating label, over the head and a little above it.
			local char = chars[i]
			local h = if char then char.height else 5
			if st.alive and st.state ~= "ko" and canvas then
				local x, y, arrow = Hud.floatPlace(canvas:project(st.x, st.y + h + 1.4), canvas:viewport())
				float.Visible = true
				float.Position = UDim2.fromOffset(x - FLOAT_W / 2, y - 22)
				-- your own fighter says so: in a room of six it is the first thing you look for
				local you = if tile.index == self.localIndex then "YOU " else ""
				float.Text = `{arrow}{you}{self.floatMarks[i] or ""} {pct}%`
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
