--!strict
-- The Skyline Climb on screen: the course (Data/Parkour) climbed with the real fighter (Parkour.luau),
-- drawn side-on over the night city, with the climb's HUD.
--
-- The climb runs here, on the client, frame by frame from the stick, so the fighter answers on the
-- frame it is pushed; the server is only told about checkpoints and the Summit (ClimbProgress
-- decides whether to believe them). Footholds are drawn by what they are, so a player can read the
-- course: solid roofs on tall lit buildings, planks you can drop through, cracked planks that give
-- way, steel girders that slide or ride cables. Checkpoint flags turn amber once reached.

local Shared = game:GetService("ReplicatedStorage").Shared
local Parkour = require(Shared.Parkour)
local Loadout = require(Shared.Loadout)
local Snapshot = require(Shared.Snapshot)
local Config = require(Shared.Config)
local InputClient = require(script.Parent.InputClient)
local Canvas = require(script.Parent.Canvas2D)
local RealmArt = require(script.Parent.RealmArt)
local Realms = require(Shared.Realms)
local Fighter2D = require(script.Parent.Fighter2D)
local ClimbRecords = require(script.Parent.ClimbRecords)
local Ui = require(script.Parent.Ui)

local PARKOUR: any = Parkour.DATA
local COURSE = PARKOUR.course

local ParkourView = {}
ParkourView.__index = ParkourView

local INK = Color3.fromRGB(15, 18, 24)
local NIGHT = Color3.fromRGB(26, 30, 38)
local SLATE = Color3.fromRGB(38, 43, 53)
local SLATE_HI = Color3.fromRGB(62, 68, 80)
local STEEL = Color3.fromRGB(110, 119, 136)
local STEEL_HI = Color3.fromRGB(138, 148, 166)
local WOOD = Color3.fromRGB(107, 74, 54)
local WOOD_DK = Color3.fromRGB(70, 49, 38)
local RUST = Color3.fromRGB(122, 68, 50)
local AMBER = Color3.fromRGB(232, 162, 74)
local TEAL = Color3.fromRGB(127, 168, 184)
local TEXT = Color3.fromRGB(230, 225, 214)
local DIM = Color3.fromRGB(138, 148, 166)
local TOP = 66          -- below Roblox's 58 px top bar

local function hash(a: number, b: number): number
	return ((a * 73856093 + b * 19349663) % 1000003) / 1000003
end

-- The HUD is the shared cartoon kit's (Ui): body words in GothamBlack, display words outlined.
local function text(parent: Instance, name: string, value: string, size: number, colour: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, value, Ui.LABEL, size
	t.BackgroundTransparency, t.TextColor3, t.TextXAlignment = 1, colour or TEXT, Enum.TextXAlignment.Left
	t.TextStrokeTransparency = 0.6
	t.Parent = parent
	return t
end

-- Display words with the kit's ink outline (in place of the soft text stroke); returns the outline.
local function display(t: TextLabel, thick: number): any
	t.Font, t.TextStrokeTransparency = Ui.DISPLAY, 1
	return Ui.outline(t, thick)
end

local function button(parent: Instance, name: string, value: string, onClick: () -> (), colour: Color3?): TextButton
	local b = Ui.button(parent, value, colour or Ui.PANEL2, onClick, { size = 15 })
	b.Name = name
	return b
end

-- 83.25 seconds -> "1:23.25", the same on the climb and on its leaderboards.
ParkourView.clock = ClimbRecords.clock

-- `opts.send(msg)` goes to the Climb remote; `opts.leave()` puts the player back in the lobby;
-- `opts.records()` opens the leaderboards; `opts.skip(index)` asks to buy the skip into checkpoint
-- `index` and `opts.price(index)` says what it costs in Robux (both nil: no SKIP button).
function ParkourView.new(parent: Instance, opts: any): any
	local self: any = setmetatable({ opts = opts, active = false, camX = 0, camY = 6, progress = { best = 0, summits = 0 },
		labels = {}, bannerAt = -10 }, ParkourView)
	self.input = opts.input or InputClient.new()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled = "BlockfallClimb", false, true, 12, false
	gui.Parent = parent
	self.gui = gui
	local title = text(gui, "Title", "SKYLINE CLIMB", 26, AMBER)
	display(title, 2)
	-- This ScreenGui ignores the inset (so world labels line up with the canvas), which puts its top
	-- 58 px under Roblox's own top bar and its top right under the player list: seen in Studio, the
	-- SKIP button could not be clicked there. So the HUD text starts below the bar, and every button
	-- lives in a column at the bottom right, where Roblox draws nothing.
	title.Position, title.Size = UDim2.fromOffset(16, TOP), UDim2.fromOffset(400, 28)
	self.checkpointLabel = text(gui, "Checkpoint", "", 15)
	self.checkpointLabel.Position, self.checkpointLabel.Size = UDim2.fromOffset(16, TOP + 30), UDim2.fromOffset(500, 20)
	-- the clock in a pill (behind it, not its parent, so the label stays placed on the screen)
	local pill = Ui.pill(gui, "TimerPill", Ui.EDGE)
	pill.Position, pill.Size = UDim2.fromOffset(12, TOP + 50), UDim2.fromOffset(140, 36)
	self.timerLabel = text(gui, "Timer", "0:00.00", 26, TEXT)
	self.timerLabel.Position, self.timerLabel.Size = UDim2.fromOffset(12, TOP + 50), UDim2.fromOffset(140, 36)
	self.timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	display(self.timerLabel, 2)
	self.fallsLabel = text(gui, "Falls", "", 13, DIM)
	self.fallsLabel.Position, self.fallsLabel.Size = UDim2.fromOffset(16, TOP + 90), UDim2.fromOffset(500, 18)
	self.bestLabel = text(gui, "Best", "", 13, DIM)
	self.bestLabel.Position, self.bestLabel.Size = UDim2.fromOffset(16, TOP + 108), UDim2.fromOffset(500, 18)
	-- the lines under the title sit on a bright sky: an ink outline, not the soft stroke, keeps them
	for _, t in { self.checkpointLabel, self.fallsLabel, self.bestLabel } do
		t.TextStrokeTransparency = 1
		Ui.outline(t, 1.5)
	end
	self.fallsLabel.TextColor3, self.bestLabel.TextColor3 = Color3.fromRGB(214, 224, 240), Color3.fromRGB(214, 224, 240)
	local banner = text(gui, "Banner", "", 40, AMBER)
	self.bannerOutline = display(banner, 4)
	banner.AnchorPoint, banner.TextXAlignment = Vector2.new(0.5, 0), Enum.TextXAlignment.Center
	banner.Position, banner.Size = UDim2.new(0.5, 0, 0, TOP + 110), UDim2.fromOffset(760, 84)
	banner.TextTransparency, banner.TextWrapped = 1, true
	self.banner = banner
	-- how to climb, as key caps along the bottom (clear of the button column at the right)
	local hint = Ui.hintRow(gui, "Controls", { { "A D", "RUN" }, { "SPACE", "JUMP · AGAIN IN THE AIR" }, { "S", "DROP THROUGH" } }, 24)
	hint.Position, hint.Size = UDim2.new(0, 16, 1, -40), UDim2.new(1, -312, 0, 26)
	local leave = button(gui, "Leave", "◂ " .. string.upper(Realms.LOBBY.name), function() self:leave() end, Ui.BLUE)
	self.leaveButton = leave
	leave.AnchorPoint, leave.Position, leave.Size = Vector2.new(1, 1), UDim2.new(1, -16, 1, -134), UDim2.fromOffset(150, 38)
	local restart = button(gui, "Restart", "RESTART FROM THE BOTTOM", function()
		if self.opts.restart then self.opts.restart() end
	end, Color3.fromRGB(150, 96, 20))
	restart.AnchorPoint, restart.Position, restart.Size = Vector2.new(1, 1), UDim2.new(1, -16, 1, -90), UDim2.fromOffset(264, 38)
	self.restartButton = restart
	local records = button(gui, "Records", "RECORDS", function()
		if self.opts.records then self.opts.records() end
	end, Ui.PURPLE)
	records.AnchorPoint, records.Position, records.Size = Vector2.new(1, 1), UDim2.new(1, -172, 1, -134), UDim2.fromOffset(108, 38)
	self.recordsButton = records
	-- SKIP: buy the next checkpoint (SkipProducts). The server moves you once the purchase is
	-- saved (ClimbView.skipTo -> skipTo), so nothing moves on the click itself.
	local skip = button(gui, "Skip", "", function()
		local pk = self.pk
		if pk and self.opts.skip then self.opts.skip(pk.reached + 1) end       -- hidden at the Summit
	end, Color3.fromRGB(52, 160, 84))
	skip.AnchorPoint, skip.Position, skip.Size = Vector2.new(1, 1), UDim2.new(1, -16, 1, -44), UDim2.fromOffset(264, 40)
	skip.Visible = false
	self.skipButton = skip
	return self
end

-- The server granted a bought skip: stand on that checkpoint now (Parkour.skipTo - no checkpoint
-- event, so nothing is claimed back to the server as climbed).
function ParkourView.skipTo(self: any, index: number)
	local pk = self.pk
	if not pk or not pk:skipTo(index) then return end
	local f = pk.fighter
	self.camX, self.camY = f.x, f.y + 6
	self:say(if pk.done then "THE SUMMIT  ·  SKIPPED" else `SKIPPED TO  ·  {string.upper(COURSE.checkpoints[index + 1].name)}`, AMBER)
	self:refreshHud()
end

-- Begin (or resume) a climb in this character, from checkpoint `from`.
function ParkourView.start(self: any, avatarCode: string, from: number)
	self.char = Loadout.build(avatarCode, PARKOUR.weapon)
	-- What you have climbed to before, and own, decides which rewards you can pick up.
	self.pk = Parkour.new(COURSE, self.char, from, { climbed = self.progress.climbed or 0, collected = self.progress.rewards or {} })
	self.from = from
	self.active, self.gui.Enabled = true, true
	self.input:reset()
	local f = self.pk.fighter
	self.camX, self.camY = f.x, f.y + 6
	self:say(if from == 0 then "THE SKYLINE CLIMB" else `RESUMING · {COURSE.checkpoints[from + 1].name}`, AMBER)
	self:refreshHud()
end

function ParkourView.stop(self: any)
	self.active, self.gui.Enabled = false, false
	self.pk = nil
end

function ParkourView.leave(self: any)
	if not self.active then return end
	self:stop()
	if self.opts.leave then self.opts.leave() end
end

function ParkourView.setProgress(self: any, view: any)
	if type(view) ~= "table" then return end
	self.progress = { best = view.best or 0, summits = view.summits or 0, bestFrames = view.bestFrames,
		climbed = view.climbed or 0, rewards = if type(view.rewards) == "table" then view.rewards else {} }
	self:refreshHud()
end

function ParkourView.say(self: any, value: string, colour: Color3)
	self.banner.Text, self.banner.TextColor3 = value, colour
	self.bannerAt = os.clock()
end

function ParkourView.refreshHud(self: any)
	local pk = self.pk
	local n = #COURSE.checkpoints - 1
	if pk then
		local cp = COURSE.checkpoints[pk.reached + 1]
		self.checkpointLabel.Text = if pk.done then "THE SUMMIT" else `CHECKPOINT {pk.reached}/{n}  ·  {string.upper(cp.name)}`
		self.timerLabel.Text = ParkourView.clock(pk.frames)
		self.timerLabel.TextColor3 = if pk.done then AMBER elseif self.from == 0 then TEXT else DIM
		self.fallsLabel.Text = `{pk.deaths} {if pk.deaths == 1 then "fall" else "falls"}`
			.. (if pk.skipped then "  ·  skipped: this run is not timed or ranked"
				elseif self.from ~= 0 then "  ·  resumed: this run is not timed as a full climb" else "")
	end
	-- The next skip and its price, while there is one to buy. Written only when it changes: this
	-- runs every frame.
	local nextIndex = if pk and not pk.done and self.opts.skip then pk.reached + 1 else nil
	local price = if nextIndex then self.opts.price and self.opts.price(nextIndex) else nil
	local skipText = if nextIndex and price
		then `SKIP ▸ {string.upper(COURSE.checkpoints[nextIndex + 1].name)}  ·  R$ {price}` else nil
	if skipText ~= self.skipText then
		self.skipText = skipText
		self.skipButton.Visible = skipText ~= nil
		if skipText then self.skipButton.Text = skipText end
	end
	local p = self.progress
	self.bestLabel.Text = `Furthest: {COURSE.checkpoints[p.best + 1].name}` .. (if p.summits > 0 then `  ·  Summits: {p.summits}` else "")
		.. (if p.bestFrames then `  ·  Best climb: {ParkourView.clock(p.bestFrames)}` else "")
	self.restartButton.Visible = pk ~= nil and (self.from ~= 0 or pk.reached > 0)
end

function ParkourView.step(self: any, dt: number, blocked: boolean?)
	local pk = self.pk                        -- nil once stopped: start and stop set both together
	if not pk then return end
	for _, frame in self.input:sample(dt, Config.FRAME) do
		local input = if blocked then { x = 0, y = 0 } else frame
		pk:step(input)
		for _, e in pk:drain() do
			if e.type == "checkpoint" then
				local cp = COURSE.checkpoints[e.checkpoint + 1]
				if e.checkpoint < #COURSE.checkpoints - 1 then self:say(`CHECKPOINT  ·  {string.upper(cp.name)}`, AMBER) end
				self.opts.send({ action = "checkpoint", index = e.checkpoint })
			elseif e.type == "summit" then
				self:say(`THE SUMMIT\n{ParkourView.clock(e.frames)}  ·  {e.deaths} {if e.deaths == 1 then "fall" else "falls"}`, AMBER)
				self.opts.send({ action = "summit", frames = e.frames })
			elseif e.type == "reward" then
				-- Picked up here; the server grants it (ClimbProgress.reward) and unlocks its part.
				for _, r in COURSE.rewards do
					if r.id == e.id then self:say(`{string.upper(r.name)} UNLOCKED\nWear it from the Wardrobe`, AMBER) end
				end
				self.opts.send({ action = "reward", id = e.id })
			elseif e.type == "fall" then
				self.fell = os.clock()
			end
		end
	end
	self:refreshHud()
end

-- ------------------------------------------------------------------ drawing ----
local function label(self: any, c: any, id: string, value: string, x: number, y: number, size: number, colour: Color3)
	local t = self.labels[id]
	if not t then
		t = text(self.gui, "World_" .. id, value, size, colour)
		t.TextXAlignment = Enum.TextXAlignment.Center
		display(t, 2)
		self.labels[id] = t
	end
	local at = c:project(x, y)
	t.Text, t.TextColor3, t.Visible = value, colour, true
	t.Position, t.Size = UDim2.fromOffset(at.X - 110, at.Y - size), UDim2.fromOffset(220, size * 2)
	self.used[id] = true
end

local function building(c: any, p: any, bottom: number)
	-- A roof on a tall building: the body falls away below the view, windows lit at random.
	Canvas.rect(c, p.x1, bottom, p.x2 - p.x1, p.top - bottom, SLATE)
	Canvas.rect(c, p.x1, p.top - 0.5, p.x2 - p.x1, 0.5, SLATE_HI)
	Canvas.rect(c, p.x1, p.top - 0.12, p.x2 - p.x1, 0.12, STEEL_HI)
	local cols = math.max(1, math.floor((p.x2 - p.x1) / 2.4))
	for i = 0, cols - 1 do
		for j = 1, 5 do
			local v = hash(math.floor(p.x1 * 10) + i, j)
			if v < 0.3 then
				local colour = if v < 0.12 then AMBER elseif v < 0.18 then TEAL else NIGHT
				Canvas.rect(c, p.x1 + 0.7 + i * 2.4, p.top - 2.5 - j * 3.2, 0.9, 1.3, colour, if v < 0.18 then 0.75 else 1)
			end
		end
	end
end

function ParkourView.draw(self: any, c: any, dt: number)
	if not self.active or not self.pk then return end
	self.used = {}
	local pk = self.pk
	local f = pk.fighter
	local clock = os.clock()
	local vp = c:viewport()
	local ppu = math.clamp(vp.Y / 46, 6, 22)
	self.camX += (f.x + f.facing * 5 - self.camX) * math.min(1, dt * 5)
	self.camY += (f.y + 6 - self.camY) * math.min(1, dt * 4)
	RealmArt.sky(c, Realms.LOBBY, self.camX * 0.6, os.clock())
	c:world(self.camX, self.camY, ppu, 0, 0)
	local half = vp.X / ppu / 2 + 4
	local left, right = self.camX - half, self.camX + half
	local bottom = self.camY - vp.Y / ppu
	local reached = pk.reached
	for _, p in pk.stage.platforms do
		if p.x2 < left or p.x1 > right then continue end
		if p.moving then
			-- A steel girder: cables up out of view for a lift, a rail overhead for a slider.
			if p.moving.y then
				Canvas.rect(c, p.x1 + 0.15, p.top, 0.12, 60, STEEL, 0.7)
				Canvas.rect(c, p.x2 - 0.27, p.top, 0.12, 60, STEEL, 0.7)
			else
				Canvas.rect(c, p.moving.x.from - p.w / 2, p.top + 9, (p.moving.x.to - p.moving.x.from) + p.w, 0.3, STEEL, 0.6)
				Canvas.rect(c, p.cx - 0.06, p.top, 0.12, 9, STEEL, 0.6)
			end
			Canvas.rect(c, p.x1, p.top - 0.9, p.x2 - p.x1, 0.9, STEEL)
			Canvas.rect(c, p.x1, p.top - 0.2, p.x2 - p.x1, 0.2, STEEL_HI)
			for x = p.x1 + 0.4, p.x2 - 0.3, 1.2 do Canvas.rect(c, x, p.top - 0.6, 0.18, 0.18, INK) end
		elseif p.sinking then
			-- A plank that gives way: cracked, and sagging under whoever stands on it.
			Canvas.rect(c, p.x1, p.top - 0.5, p.x2 - p.x1, 0.5, RUST)
			Canvas.rect(c, p.x1, p.top - 0.12, p.x2 - p.x1, 0.12, WOOD)
			Canvas.rect(c, (p.x1 + p.x2) / 2 - 0.1, p.top - 0.5, 0.2, 0.5, INK)
			Canvas.rect(c, p.x1 + 0.2, p.top - 3, 0.2, 2.5, WOOD_DK, 0.8)
			Canvas.rect(c, p.x2 - 0.4, p.top - 3, 0.2, 2.5, WOOD_DK, 0.8)
		elseif p.solid then
			building(c, p, bottom)
		else
			-- A plank you can drop through, on brackets.
			Canvas.rect(c, p.x1, p.top - 0.45, p.x2 - p.x1, 0.45, WOOD)
			Canvas.rect(c, p.x1, p.top - 0.12, p.x2 - p.x1, 0.12, Color3.fromRGB(140, 100, 72))
			for x = p.x1 + 0.6, p.x2 - 0.4, 2.2 do Canvas.rect(c, x, p.top - 1.4, 0.22, 1, WOOD_DK) end
		end
	end
	-- Checkpoint flags.
	for i, cp in COURSE.checkpoints do
		local pad
		for _, p in pk.stage.platforms do if p.id == cp.pad then pad = p end end
		if pad and pad.x2 > left and pad.x1 < right then
			local x = if i == 1 then pad.x1 + 6 else (pad.x1 + pad.x2) / 2 + math.min(3, (pad.x2 - pad.x1) / 3)
			local got = i - 1 <= reached
			local colour = if got then AMBER else STEEL
			Canvas.rect(c, x - 0.1, pad.top, 0.2, 6, STEEL_HI)
			local wave = math.sin(clock * 3 + i) * 0.2
			Canvas.rect(c, x + 0.1, pad.top + 4.6 + wave, 2.4, 1.4, colour)
			if i == #COURSE.checkpoints then
				Canvas.rect(c, x - 3, pad.top + 5, 6, 6, AMBER, 0.08 + 0.05 * math.sin(clock * 2))
			end
			label(self, c, "cp" .. i, string.upper(cp.name), x, pad.top + 8, 14, colour)
		end
	end
	-- The rewards at the top: gold and pulsing for whoever can take one, steel and labelled for a
	-- climber who skipped there, gone once taken.
	for _, r in COURSE.rewards or {} do
		if r.x > left and r.x < right and not pk.collected[r.id] then
			local open = pk:available(r)
			local colour = if open then AMBER else STEEL
			local bob = math.sin(clock * 2.4) * 0.25
			if open then Canvas.circle(c, r.x, r.y + bob, 2.2 + math.sin(clock * 4) * 0.25, AMBER, 0.18) end
			local y = r.y + bob
			if r.id == "summitMantle" then
				-- A cloak on its clasp: shoulders, a long drape widening to its hem.
				Canvas.rect(c, r.x - 1.1, y + 0.6, 2.2, 0.5, colour)
				Canvas.rect(c, r.x - 0.9, y - 1.2, 1.8, 1.8, if open then RUST else SLATE_HI)
				Canvas.rect(c, r.x - 1.1, y - 1.5, 2.2, 0.3, colour)
				Canvas.rect(c, r.x - 0.2, y + 0.7, 0.4, 0.4, if open then TEAL else DIM)
			else
				-- A crown: a band and three spires, light at their tips.
				Canvas.rect(c, r.x - 1, y - 0.8, 2, 0.8, colour)
				for _, dx in { -0.85, -0.15, 0.55 } do
					Canvas.rect(c, r.x + dx, y, 0.3, 0.8, colour)
					Canvas.rect(c, r.x + dx, y + 0.8, 0.3, 0.3, if open then TEAL else DIM)
				end
			end
			Canvas.rect(c, r.x - 1.6, r.y - 2.4, 3.2, 0.5, STEEL_HI)                     -- the plinth
			-- Named beneath, so it never sits on the checkpoint's own name above the flag.
			label(self, c, "reward_" .. r.id, if open then string.upper(r.name) else "CLIMB HERE TO CLAIM", r.x, r.y - 3.2, 13, colour)
		end
	end
	-- The climber, drawn as they fight (no spawn blink: Parkour clears it).
	local st = Snapshot.decode(Snapshot.encode(f))
	local teams = Fighter2D.teamColours
	Fighter2D.teamColours = nil
	Fighter2D.draw(c, st, self.char, clock, if f.platform then f.platform.top else nil)
	Fighter2D.teamColours = teams
	c:finish()
	for id, t in self.labels do if not self.used[id] then t.Visible = false end end
	local age = clock - self.bannerAt
	self.banner.TextTransparency = if age < 2.2 then 0 elseif age < 3 then (age - 2.2) / 0.8 else 1
	self.bannerOutline.Transparency = self.banner.TextTransparency
	self.gui:SetAttribute("Checkpoint", reached)
	self.gui:SetAttribute("ClimberX", f.x)
	self.gui:SetAttribute("ClimberY", f.y)
end

return ParkourView
