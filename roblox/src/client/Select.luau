--!strict
-- The select screen: who you are, what you fight with, where, and against whom.
--
-- This retires the hard-coded slice. web/src/ui/menus.js is the reference for WHAT is offered -
-- mode, stocks, items, stage, and a slot per fighter - but it is 554 lines of DOM and none of it
-- ports, so this is a rewrite in the same spirit as the HUD.
--
-- It sends a config and nothing else. Every value here is a suggestion: `MatchConfig` on the
-- server decides what actually runs, and a client that sends something impossible gets an ordinary
-- match rather than what it asked for. Keeping the two in step matters - the lists below are the
-- same ids the server validates against - but a mistake here is a cosmetic bug, not an exploit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stages = require(ReplicatedStorage.Shared.Data.Stages)
local Weapons = require(ReplicatedStorage.Shared.Data.Weapons)
local Avatars = require(ReplicatedStorage.Shared.Data.Avatars)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local Select = {}
Select.__index = Select

local FONT = Enum.Font.GothamBold
local PANEL = Color3.fromRGB(18, 20, 26)
local CHIP = Color3.fromRGB(38, 43, 54)
local DIM = Color3.fromRGB(168, 176, 190)

local MODE_LABELS = {
	StockFFA = "Stock · free-for-all",
	TimedFFA = "Timed · free-for-all",
	StockTeams = "Stock · 2v2",
	TimedTeams = "Timed · 2v2",
}

local function label(parent: Instance, text: string, px: number, colour: Color3, pos: UDim2, size: UDim2): TextLabel
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

function Select.new(parent: Instance): any
	local self = setmetatable({}, Select)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlockfallSelect"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20            -- above the HUD, which is above the canvas
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(760, 560)
	panel.Position = UDim2.new(0.5, -380, 0.5, -280)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	self.panel = panel

	label(panel, "BLOCKFALL", 30, Color3.new(1, 1, 1), UDim2.fromOffset(26, 18), UDim2.fromOffset(400, 36))
	self.note = label(panel, "", 13, DIM, UDim2.fromOffset(26, 52), UDim2.fromOffset(700, 18))

	-- From MatchConfig, not from here. The screen and the server agreeing about what a default
	-- match is has to be structural: two copies would drift and both would look right alone.
	self.cfg = MatchConfig.default()
	self.onStart = nil :: ((any) -> ())?
	self.rows = {}
	self:build()
	return self
end

-- A row of chips. `get` says which is selected, `set` is told what was clicked, and the row
-- rebuilds itself rather than tracking per-button state.
function Select.row(self: any, y: number, title: string, items: { { id: string, text: string } },
	get: () -> any, set: (string) -> (), colour: Color3?)
	label(self.panel, title, 12, DIM, UDim2.fromOffset(26, y), UDim2.fromOffset(200, 16))
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(26, y + 18)
	holder.Size = UDim2.fromOffset(710, 30)
	holder.Parent = self.panel

	local buttons = {}
	local x = 0
	for _, item in items do
		local w = math.max(58, 11 + #item.text * 8)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(w, 26)
		b.Position = UDim2.fromOffset(x, 0)
		b.BackgroundColor3 = CHIP
		b.BorderSizePixel = 0
		b.Text = item.text
		b.TextSize = 13
		b.Font = FONT
		b.TextColor3 = DIM
		b.AutoButtonColor = false
		b.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 5)
		c.Parent = b
		b.Activated:Connect(function()
			set(item.id)
			self:refresh()
		end)
		table.insert(buttons, { button = b, id = item.id })
		x += w + 6
	end
	table.insert(self.rows, { buttons = buttons, get = get, colour = colour or Color3.new(1, 1, 1) })
end

function Select.refresh(self: any)
	for _, row in self.rows do
		local now = row.get()
		for _, entry in row.buttons do
			local on = entry.id == now
			entry.button.BackgroundColor3 = if on then row.colour else CHIP
			entry.button.TextColor3 = if on then PANEL else DIM
		end
	end
	local n = 0
	for _, sl in self.cfg.slots do
		if sl.type ~= "off" then n += 1 end
	end
	self.start.Text = `FIGHT   ({n} fighters)`

	-- The opponent slots are a CYCLE, not a selection, so there is nothing for the highlighting
	-- above to light up. Their state is written out instead.
	if self.oppNote then
		local parts = {}
		for i = 2, MatchConfig.MAX_FIGHTERS do
			local sl = self.cfg.slots[i]
			table.insert(parts, `slot {i}: {if sl.type == "off" then "—" else string.sub(sl.type, 5)}`)
		end
		self.oppNote.Text = table.concat(parts, "     ")
	end
end

function Select.build(self: any)
	local me = self.cfg.slots[1]

	local weapons = {}
	for _, w in Weapons.LIST do
		table.insert(weapons, { id = w.id, text = w.name })
	end
	self:row(86, "YOUR WEAPON — this is how you play", weapons,
		function() return me.weaponId end,
		function(id) me.weaponId = id end, Color3.fromRGB(242, 201, 76))

	local looks = {}
	for _, a in Avatars.LIST do
		table.insert(looks, { id = a.id, text = a.name })
	end
	self:row(150, "YOUR LOOK — cosmetic only, every avatar shares one stat line", looks,
		function() return me.avatarId end,
		function(id) me.avatarId = id end, Color3.fromRGB(63, 127, 214))

	local stages = {}
	for _, s in Stages.LIST do
		table.insert(stages, { id = s.id, text = s.name or s.id })
	end
	self:row(214, "STAGE", stages,
		function() return self.cfg.stageId end,
		function(id) self.cfg.stageId = id end, Color3.fromRGB(47, 163, 154))

	local modes = {}
	for _, m in MatchConfig.MODES do
		table.insert(modes, { id = m, text = MODE_LABELS[m] or m })
	end
	self:row(278, "MODE", modes,
		function() return self.cfg.mode end,
		function(id) self.cfg.mode = id end, Color3.fromRGB(154, 95, 200))

	local stocks = {}
	for n = MatchConfig.STOCKS.min, MatchConfig.STOCKS.max do
		table.insert(stocks, { id = tostring(n), text = tostring(n) })
	end
	table.insert(stocks, { id = "items", text = "ITEMS" })
	self:row(342, "STOCKS   ·   and whether items spawn", stocks,
		function() return if self.cfg.items then "items" else tostring(self.cfg.stocks) end,
		function(id)
			if id == "items" then
				self.cfg.items = not self.cfg.items
			else
				self.cfg.stocks = tonumber(id) :: number
			end
		end, Color3.fromRGB(222, 98, 28))

	-- Opponents. Each of the three other slots cycles off -> easy -> normal -> hard, and picks its
	-- own weapon by cycling the roster, because a bot that is always Scythe is a bot you learn once.
	local opp = {}
	for i = 2, MatchConfig.MAX_FIGHTERS do
		table.insert(opp, { id = tostring(i), text = `SLOT {i}` })
	end
	self:row(406, "OPPONENTS — click a slot to cycle off · easy · normal · hard", opp,
		function() return "" end,
		function(id)
			local sl = self.cfg.slots[tonumber(id) :: number]
			local order = { "off", "bot-easy", "bot-normal", "bot-hard" }
			local at = 1
			for k, v in order do
				if v == sl.type then at = k end
			end
			sl.type = order[(at % #order) + 1]
		end)
	self.oppNote = label(self.panel, "", 12, DIM, UDim2.fromOffset(26, 440), UDim2.fromOffset(700, 18))

	local start = Instance.new("TextButton")
	start.Size = UDim2.fromOffset(708, 46)
	start.Position = UDim2.fromOffset(26, 480)
	start.BackgroundColor3 = Color3.fromRGB(62, 138, 46)
	start.BorderSizePixel = 0
	start.Text = "FIGHT"
	start.TextSize = 20
	start.Font = FONT
	start.TextColor3 = Color3.new(1, 1, 1)
	start.Parent = self.panel
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 7)
	sc.Parent = start
	start.Activated:Connect(function()
		if self.onStart then
			self.onStart(self.cfg)
		end
	end)
	self.start = start
	self:refresh()
end

function Select.show(self: any, note: string?)
	self.note.Text = note or "Pick your fighter and the match you want."
	self.gui.Enabled = true
	self:refresh()
end

function Select.hide(self: any)
	self.gui.Enabled = false
end

return Select
