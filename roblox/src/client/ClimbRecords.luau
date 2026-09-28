--!strict
-- The Skyline Climb's leaderboards on screen: FASTEST (best full climbs) beside HIGHEST (furthest
-- checkpoint, then Summits), when they were read and how long until the next ones, and your own
-- record under them. Opened from the CLIMB RECORDS board at the foot of the climb, or from the
-- climb's own RECORDS button.
--
-- The server sends the boards (server/ClimbBoards) when you arrive and on every two-hour mark; this
-- only draws them. Rows are made once and refilled, so a new board costs no new instances.

local Shared = game:GetService("ReplicatedStorage").Shared
local PARKOUR: any = require(Shared.Data.Parkour)

local ClimbRecords = {}
ClimbRecords.__index = ClimbRecords

ClimbRecords.ROWS = 25

local PANEL = Color3.fromRGB(30, 34, 42)
local PANEL2 = Color3.fromRGB(46, 52, 63)
local TEXT = Color3.fromRGB(230, 225, 214)
local DIM = Color3.fromRGB(138, 148, 166)
local AMBER = Color3.fromRGB(232, 162, 74)
local CYAN = Color3.fromRGB(127, 168, 184)
local YOU = Color3.fromRGB(127, 190, 110)
local CHECKPOINTS = PARKOUR.course.checkpoints

-- 4995 frames -> "1:23.25", as the climb's own timer shows it.
function ClimbRecords.clock(frames: number): string
	local cs = math.floor(frames * 100 / 60 + 0.5)
	return string.format("%d:%02d.%02d", cs // 6000, (cs // 100) % 60, cs % 100)
end

-- Seconds until the next boards -> "1h 12m", "4m", "under a minute".
function ClimbRecords.wait(seconds: number): string
	if seconds < 60 then return "under a minute" end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then return `{minutes}m` end
	return `{minutes // 60}h {string.format("%02d", minutes % 60)}m`
end

-- A HIGHEST row's reach: "The Needle", or "Summit ×3" for those who made it.
function ClimbRecords.reach(best: number, summits: number): string
	if best >= #CHECKPOINTS - 1 and summits > 0 then return `Summit ×{summits}` end
	local cp = CHECKPOINTS[best + 1]
	return if cp then cp.name else "?"
end

local function text(parent: Instance, name: string, value: string, size: number, colour: Color3, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, value, Enum.Font.GothamBold, size
	t.BackgroundTransparency, t.TextColor3, t.TextXAlignment = 1, colour, align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local function column(parent: Instance, name: string, title: string, x: number): any
	local f = Instance.new("Frame")
	f.Name, f.BackgroundColor3, f.BorderSizePixel = name, PANEL2, 0
	f.Position, f.Size = UDim2.new(x, if x == 0 then 12 else 6, 0, 44), UDim2.new(0.5, -18, 1, -104)
	f.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 8), f
	local head = text(f, "Title", title, 15, AMBER)
	head.Position, head.Size = UDim2.fromOffset(10, 6), UDim2.new(1, -20, 0, 20)
	local list = Instance.new("ScrollingFrame")
	list.Name, list.BackgroundTransparency, list.BorderSizePixel = "List", 1, 0
	list.Position, list.Size = UDim2.fromOffset(4, 30), UDim2.new(1, -8, 1, -34)
	list.AutomaticCanvasSize, list.CanvasSize, list.ScrollBarThickness = Enum.AutomaticSize.Y, UDim2.new(), 4
	list.Parent = f
	local layout = Instance.new("UIListLayout")
	layout.Padding, layout.SortOrder, layout.Parent = UDim.new(0, 2), Enum.SortOrder.LayoutOrder, list
	local rows = {}
	for i = 1, ClimbRecords.ROWS do
		local row = Instance.new("Frame")
		row.Name, row.BackgroundTransparency, row.LayoutOrder, row.Visible = `Row{i}`, 1, i, false
		row.Size, row.Parent = UDim2.new(1, -6, 0, 22), list
		local rank = text(row, "Rank", tostring(i), 13, DIM, Enum.TextXAlignment.Right)
		rank.Position, rank.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(26, 22)
		local who = text(row, "Name", "", 13, TEXT)
		who.Position, who.Size = UDim2.fromOffset(34, 0), UDim2.new(1, -150, 0, 22)
		local value = text(row, "Value", "", 13, CYAN, Enum.TextXAlignment.Right)
		value.Position, value.Size = UDim2.new(1, -112, 0, 0), UDim2.fromOffset(108, 22)
		rows[i] = { frame = row, rank = rank, name = who, value = value }
	end
	local empty = text(f, "Empty", "", 13, DIM, Enum.TextXAlignment.Center)
	empty.Position, empty.Size, empty.TextWrapped = UDim2.fromOffset(10, 40), UDim2.new(1, -20, 0, 60), true
	empty.TextTruncate = Enum.TextTruncate.None
	return { frame = f, rows = rows, empty = empty }
end

-- opts: { localId = number, now = () -> number (os.time) }
function ClimbRecords.new(parent: Instance, opts: any): any
	local self: any = setmetatable({}, ClimbRecords)
	self.localId = opts.localId or 0
	self.now = opts.now or os.time
	self.view = nil
	self.mine = nil
	self.shownWait = nil

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "BlockfallRecords", false, true, 20
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui

	local p = Instance.new("Frame")
	p.Name, p.BackgroundColor3, p.BackgroundTransparency, p.BorderSizePixel = "Panel", PANEL, 0.03, 0
	p.AnchorPoint, p.Position, p.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(1, -32, 1, -64)
	p.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize, limit.Parent = Vector2.new(720, 520), p
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 12), p
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.Parent = AMBER, 2, p
	local title = text(p, "Title", "SKYLINE CLIMB  ·  RECORDS", 18, AMBER)
	title.Position, title.Size = UDim2.fromOffset(16, 10), UDim2.new(1, -120, 0, 26)
	local close = Instance.new("TextButton")
	close.Name, close.Text, close.Font, close.TextSize = "Close", "CLOSE", Enum.Font.GothamBold, 14
	close.BackgroundColor3, close.TextColor3, close.BorderSizePixel = PANEL2, TEXT, 0
	close.AnchorPoint, close.Position, close.Size = Vector2.new(1, 0), UDim2.new(1, -12, 0, 8), UDim2.fromOffset(90, 30)
	close.Parent = p
	local cc = Instance.new("UICorner")
	cc.CornerRadius, cc.Parent = UDim.new(0, 6), close
	close.Activated:Connect(function() self:close() end)
	self.closeButton = close

	self.fastest = column(p, "Fastest", "FASTEST CLIMBS", 0)
	self.highest = column(p, "Highest", "HIGHEST CLIMBERS", 0.5)
	local status = text(p, "Status", "", 13, DIM)
	status.AnchorPoint, status.Position, status.Size = Vector2.new(0, 1), UDim2.new(0, 16, 1, -34), UDim2.new(1, -32, 0, 20)
	self.status = status
	local mine = text(p, "Mine", "", 14, YOU)
	mine.AnchorPoint, mine.Position, mine.Size = Vector2.new(0, 1), UDim2.new(0, 16, 1, -10), UDim2.new(1, -32, 0, 22)
	self.mineLabel = mine
	self:render()
	return self
end

local function fill(col: any, rows: { any }?, localId: number, value: (any) -> string, none: string)
	local list = rows or {}
	for i, r in col.rows do
		local row = list[i]
		r.frame.Visible = row ~= nil
		if row then
			local you = row.userId == localId
			r.rank.Text = tostring(row.rank)
			r.name.Text = if you then `{row.name}  (you)` else tostring(row.name)
			r.name.TextColor3 = if you then YOU elseif row.rank <= 3 then AMBER else TEXT
			r.value.Text = value(row)
		end
	end
	col.empty.Visible = #list == 0
	col.empty.Text = none
end

-- What the server sent: { speed, levels, offline, updatedAt, nextAt }.
function ClimbRecords.set(self: any, view: any)
	if type(view) ~= "table" then return end
	self.view = view
	self:render()
end

-- Your own record (ClimbView): shown whatever the boards say, since the boards are two hours old.
function ClimbRecords.setMine(self: any, progress: any)
	if type(progress) ~= "table" then return end
	self.mine = progress
	self:render()
end

function ClimbRecords.render(self: any)
	local v = self.view or {}
	local offline = v.offline == true
	fill(self.fastest, v.speed, self.localId, function(row) return ClimbRecords.clock(row.frames) end,
		if offline then "Leaderboards are offline on this server." elseif not self.view then "Loading…" else "No full climbs yet. Be the first to the Summit from the bottom.")
	fill(self.highest, v.levels, self.localId, function(row) return ClimbRecords.reach(row.best, row.summits) end,
		if offline then "Leaderboards are offline on this server." elseif not self.view then "Loading…" else "Nobody has reached a checkpoint yet.")
	self:tick()
	local m = self.mine
	if m and (m.best or 0) > 0 then
		local parts = { `You: {ClimbRecords.reach(m.best, m.summits or 0)}` }
		if (m.summits or 0) > 0 and m.best < #CHECKPOINTS - 1 then table.insert(parts, `Summits {m.summits}`) end
		if m.bestFrames then table.insert(parts, `best time {ClimbRecords.clock(m.bestFrames)}`) end
		self.mineLabel.Text = table.concat(parts, "  ·  ")
	else
		self.mineLabel.Text = "You: not on the boards yet. Reach the first checkpoint."
	end
end

-- The countdown. Cheap to call every frame: the label only changes when its text would.
function ClimbRecords.tick(self: any)
	local v = self.view or {}
	local line
	if v.offline then
		line = "Records are kept on live servers."
	elseif not v.nextAt then
		line = "Waiting for the first boards…"
	else
		local left = math.max(0, v.nextAt - self.now())
		line = `Updated every 2 hours  ·  next update in {ClimbRecords.wait(left)}  ·  new records show then`
	end
	if line ~= self.shownWait then
		self.shownWait = line
		self.status.Text = line
	end
end

function ClimbRecords.isOpen(self: any): boolean
	return self.gui.Enabled
end

function ClimbRecords.open(self: any)
	self:render()
	self.gui.Enabled = true
	self.openedAt = os.clock()
end

-- E closes the boards, as it opened them. Not on the same press: the lobby hears that E too, and
-- which of the two hears it first is up to Roblox.
function ClimbRecords.key(self: any, code: any): boolean
	if not self.gui.Enabled or code ~= Enum.KeyCode.E or os.clock() - (self.openedAt or 0) < 0.25 then return false end
	self:close()
	return true
end

function ClimbRecords.close(self: any)
	self.gui.Enabled = false
end

function ClimbRecords.toggle(self: any)
	if self.gui.Enabled then self:close() else self:open() end
end

return ClimbRecords
