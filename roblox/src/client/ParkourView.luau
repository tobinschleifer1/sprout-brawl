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
local Backdrop = require(script.Parent.BackdropArt)
local Fighter2D = require(script.Parent.Fighter2D)

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

local function hash(a: number, b: number): number
	return ((a * 73856093 + b * 19349663) % 1000003) / 1000003
end

local function text(parent: Instance, name: string, value: string, size: number, colour: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, value, Enum.Font.GothamBold, size
	t.BackgroundTransparency, t.TextColor3, t.TextXAlignment = 1, colour or TEXT, Enum.TextXAlignment.Left
	t.TextStrokeTransparency = 0.6
	t.Parent = parent
	return t
end

local function button(parent: Instance, name: string, value: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.Font, b.TextSize = name, value, Enum.Font.GothamBold, 14
	b.BackgroundColor3, b.TextColor3, b.BorderSizePixel = SLATE, AMBER, 0
	b.Parent = parent
	local r = Instance.new("UICorner")
	r.CornerRadius, r.Parent = UDim.new(0, 8), b
	b.Activated:Connect(onClick)
	return b
end

-- 83.25 seconds -> "1:23.25"
function ParkourView.clock(frames: number): string
	local cs = math.floor(frames * 100 / 60 + 0.5)
	return string.format("%d:%02d.%02d", cs // 6000, (cs // 100) % 60, cs % 100)
end

-- `opts.send(msg)` goes to the Climb remote; `opts.leave()` puts the player back in the lobby.
function ParkourView.new(parent: Instance, opts: any): any
	local self: any = setmetatable({ opts = opts, active = false, camX = 0, camY = 6, progress = { best = 0, summits = 0 },
		labels = {}, bannerAt = -10 }, ParkourView)
	self.input = opts.input or InputClient.new()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled = "BlockfallClimb", false, true, 12, false
	gui.Parent = parent
	self.gui = gui
	local title = text(gui, "Title", "SKYLINE CLIMB", 22, AMBER)
	title.Position, title.Size = UDim2.fromOffset(16, 10), UDim2.fromOffset(400, 28)
	self.checkpointLabel = text(gui, "Checkpoint", "", 15)
	self.checkpointLabel.Position, self.checkpointLabel.Size = UDim2.fromOffset(16, 40), UDim2.fromOffset(500, 20)
	self.timerLabel = text(gui, "Timer", "0:00.00", 26, TEXT)
	self.timerLabel.Position, self.timerLabel.Size = UDim2.fromOffset(16, 62), UDim2.fromOffset(300, 30)
	self.fallsLabel = text(gui, "Falls", "", 13, DIM)
	self.fallsLabel.Position, self.fallsLabel.Size = UDim2.fromOffset(16, 94), UDim2.fromOffset(500, 18)
	self.bestLabel = text(gui, "Best", "", 13, DIM)
	self.bestLabel.Position, self.bestLabel.Size = UDim2.fromOffset(16, 112), UDim2.fromOffset(500, 18)
	local banner = text(gui, "Banner", "", 34, AMBER)
	banner.AnchorPoint, banner.TextXAlignment = Vector2.new(0.5, 0), Enum.TextXAlignment.Center
	banner.Position, banner.Size = UDim2.new(0.5, 0, 0, 120), UDim2.fromOffset(760, 84)
	banner.TextTransparency, banner.TextWrapped = 1, true
	self.banner = banner
	local hint = text(gui, "Controls", "A / D  run   •   Space  jump (again in the air to double jump)   •   S  drop through a plank", 13, DIM)
	hint.AnchorPoint, hint.TextXAlignment = Vector2.new(0.5, 1), Enum.TextXAlignment.Center
	hint.Position, hint.Size = UDim2.new(0.5, 0, 1, -12), UDim2.fromOffset(800, 20)
	local leave = button(gui, "Leave", "BACK TO NEON ROW", function() self:leave() end)
	leave.AnchorPoint, leave.Position, leave.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 12), UDim2.fromOffset(190, 38)
	local restart = button(gui, "Restart", "RESTART FROM THE BOTTOM", function()
		if self.opts.restart then self.opts.restart() end
	end)
	restart.AnchorPoint, restart.Position, restart.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 56), UDim2.fromOffset(250, 34)
	self.restartButton = restart
	return self
end

-- Begin (or resume) a climb in this character, from checkpoint `from`.
function ParkourView.start(self: any, avatarCode: string, from: number)
	self.char = Loadout.build(avatarCode, PARKOUR.weapon)
	self.pk = Parkour.new(COURSE, self.char, from)
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
	self.progress = { best = view.best or 0, summits = view.summits or 0, bestFrames = view.bestFrames }
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
		self.fallsLabel.Text = `{pk.deaths} {if pk.deaths == 1 then "fall" else "falls"}` .. (if self.from ~= 0 then "  ·  resumed: this run is not timed as a full climb" else "")
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
	Backdrop.sky(c, "Rooftops", self.camX * 0.6)
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
	self.gui:SetAttribute("Checkpoint", reached)
	self.gui:SetAttribute("ClimberX", f.x)
	self.gui:SetAttribute("ClimberY", f.y)
end

return ParkourView
