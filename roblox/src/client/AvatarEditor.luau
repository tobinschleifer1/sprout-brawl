--!strict
-- The character studio: build a kit character (AvatarKit) out of ready-made parts, save it, wear it.
--
-- Opened from the concourse's wardrobe station or the CHARACTER button, never from a fight's
-- preparation room: who you are is chosen once, not per fight.
--
-- What makes it quick to use, in order of how often it matters:
--   - every option is shown ON YOUR CHARACTER (each hair tile is your face with that hair, in your
--     colours), so choosing is recognising, not imagining;
--   - the big preview is the real fighter renderer (Fighter2D), animated, holding your weapon, and
--     can stand, run, jump, attack and cheer - you see the character the way the fight will;
--   - every change is instant and undoable (Ctrl+Z / Ctrl+Y, and buttons);
--   - Randomise respects locks, so "keep this face, surprise me on the outfit" is two clicks;
--   - the keyboard walks everything: arrows for option and part, Q/E for the tab.
--
-- The editor only ever sends the server a code and a name (AvatarStore does the rest), so nothing
-- here is trusted: the server rebuilds the code and cleans the name.

local UIS = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage").Shared
local AvatarKit = require(Shared.AvatarKit)
local Loadout = require(Shared.Loadout)
local Canvas2D = require(script.Parent.Canvas2D)
local Fighter2D = require(script.Parent.Fighter2D)
local KitPortrait = require(script.Parent.KitPortrait)
local PosedFighter = require(script.Parent.PosedFighter)
local Ui = require(script.Parent.Ui)

local KIT: any = AvatarKit.KIT
local PARKOUR: any = require(Shared.Data.Parkour)
local Clothing: any = require(Shared.RobloxClothing)
local Products: any = require(Shared.Products)

local AvatarEditor = {}
AvatarEditor.__index = AvatarEditor

-- the look is the shared kit's (Ui)
local INK = Ui.INK
local PANEL = Ui.PANEL
local PANEL2 = Ui.PANEL2
local LINE = Ui.EDGE
local TEXT = Ui.TEXT                             -- words on the window (dark on a pale one)
local DIM = Ui.SUB
local LIGHT = Ui.lightPanels()
local PICKED = if LIGHT then Color3.fromRGB(150, 60, 0) else Ui.GOLD    -- a picked tile's name (6:1 on cream)
local AMBER = Ui.GOLD
local GOOD = Ui.GREEN
local HEADER = Ui.BLUE                           -- the studio's top band

AvatarEditor.MAX_UNDO = 60
local POSES = { { "idle", "Stand" }, { "run", "Run" }, { "air", "Jump" }, { "attack", "Attack" }, { "victory", "Cheer" } }
AvatarEditor.POSES = POSES

-- ------------------------------------------------------------------ helpers ----
local function corner(parent: Instance, px: number)
	Ui.corner(parent, px)
end

local function frame(parent: Instance, name: string, colour: Color3?, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = colour or PANEL
	f.BackgroundTransparency = if colour then (alpha or 0) else 1
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, text: string, size: number, colour: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Ui.LABEL
	t.TextSize = Ui.px(size)
	t.TextColor3 = colour or TEXT
	t.Text = text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Parent = parent
	return t
end

-- A worded control: the kit's bevelled button.
local function button(parent: Instance, name: string, text: string, onClick: () -> (), colour: Color3?): TextButton
	local b = Ui.button(parent, text, colour or PANEL2, onClick, { size = 12 })
	b.Name = name
	return b
end

-- A picture tile (an option, a colour, a saved character): a square block with a darker lip and
-- no border of its own, so the picked ring (stroke "Pick") is the only outline it wears.
local function tile(parent: Instance, name: string, onClick: () -> (), colour: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = colour
	b.Parent = parent
	corner(b, 8)
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BorderSizePixel = 0
	lip.BackgroundColor3 = Ui.shade(colour, -0.4)
	lip.Position, lip.Size = UDim2.new(0, 0, 1, -3), UDim2.new(1, 0, 0, 3)
	lip.Parent = b
	if Ui.flat() then lip.BackgroundTransparency = 1 end
	-- (a card in a light theme: an outline in its own colour darkened, as every box wears)
	if Ui.lightPanels() then Ui.stroke(b, Ui.tone(colour), 2) end
	b.Activated:Connect(onClick)
	return b
end

local function stroke(parent: Instance, colour: Color3, px: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Name = "Pick"
	s.Color = colour
	s.Thickness = px
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function clone(spec: AvatarKit.Spec): AvatarKit.Spec
	return { parts = table.clone(spec.parts), colours = table.clone(spec.colours) }
end

-- 105972572160000000 -> "105,972,572,160,000,000"
function AvatarEditor.commas(n: number): string
	local s = string.format("%.0f", n)
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- The same cleaning the server does (AvatarStore.cleanName), so what the box shows is what saves.
local function cleanName(raw: string): string
	local s = string.gsub(raw, "[^%w %.%-_']", "")
	s = string.gsub(s, "%s+", " ")
	s = string.match(s, "^%s*(.-)%s*$") or ""
	return string.sub(s, 1, 20)
end

-- The parts under a tab, in the tab's display order (Data/AvatarKit groups[].parts).
local function groupCategories(groupId: string): { any }
	local out = {}
	for _, g in KIT.groups do
		if g.id == groupId then
			for _, id in g.parts do
				table.insert(out, AvatarKit.category(id))
			end
		end
	end
	return out
end
AvatarEditor.groupCategories = groupCategories

-- ------------------------------------------------------------------ construction ----
-- `opts.send(msg)` delivers a request to the server's Avatar remote; `opts.weapon()` names the
-- weapon the preview holds.
function AvatarEditor.new(parent: Instance, opts: any): any
	local self: any = setmetatable({}, AvatarEditor)
	self.send = opts.send
	self.weaponOf = opts.weapon or function() return "Sword" end
	self.rng = opts.random or Random.new()
	self.spec = AvatarKit.sanitize(nil)
	self.name = "Fighter 1"
	self.slots = {}
	self.active = 1
	self.editing = 1
	self.saving = false
	self.undoStack, self.redoStack = {}, {}
	self.locks = {}
	self.owned = {}                    -- earned parts' reward ids (the server's AvatarView.unlocked)
	self.pieces = {}                   -- clothing owned (the server's AvatarView.pieces)
	self.group, self.category = "body", "build"
	self.pose, self.facing, self.zoom = "idle", 1, "body"
	self.tiles, self.chips, self.swatches = {}, {}, {}
	self.baseCode, self.baseName = AvatarKit.encode(self.spec), self.name
	self.opened = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "BlockfallCreator"
	gui.ResetOnSpawn = false
	-- below Roblox's top bar: its menu and chat buttons sat over the studio's title
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui

	local root = frame(gui, "Root", INK, 0.2)
	root.Size = UDim2.fromScale(1, 1)
	root.Active = true                              -- clicks do not fall through to the lobby
	local panel = frame(root, "Panel", PANEL, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -24, 1, -24)
	corner(panel, 0)
	Ui.stroke(panel, INK, 3)
	Ui.rim(panel, PANEL2, 2, 0)
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(1440, 900)
	cap.Parent = panel
	self.panel = panel

	-- Top bar: title, your characters, undo / redo / randomise / close.
	local top = Ui.band(panel, HEADER, 56, "Top")
	self.top = top
	-- (white on the blue bar: gold on it is barely there)
	local title = if LIGHT then (Ui.faceText(top, "CHARACTER STUDIO", Ui.WINDOW_TITLE, HEADER, Ui.TITLE)) else Ui.text(top, "CHARACTER STUDIO", 18, TEXT, Ui.DISPLAY)
	title.Name = "Title"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position, title.Size = UDim2.fromOffset(18, 0), UDim2.new(0, 230, 1, 0)
	self.title = title
	local chips = frame(top, "Slots")
	chips.Position, chips.Size = UDim2.new(0, 250, 0, 6), UDim2.new(1, -520, 0, 44)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = chips
	self.chipBar = chips
	local tools = frame(top, "Tools")
	tools.AnchorPoint = Vector2.new(1, 0)
	-- (inset in the bar, with room between them)
	tools.Position, tools.Size = UDim2.new(1, -14, 0, 11), UDim2.fromOffset(268, 34)
	local undo = button(tools, "Undo", "UNDO", function() self:undo() end, PANEL2)
	undo.Position, undo.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(58, 34)
	local redo = button(tools, "Redo", "REDO", function() self:redo() end, PANEL2)
	redo.Position, redo.Size = UDim2.fromOffset(66, 0), UDim2.fromOffset(58, 34)
	local rand = button(tools, "Random", "RANDOM", function() self:randomize() end, Ui.PURPLE)
	rand.Position, rand.Size = UDim2.fromOffset(132, 0), UDim2.fromOffset(80, 34)
	local close = button(tools, "Close", "X", function() self:close() end, Ui.RED)
	close.Position, close.Size = UDim2.fromOffset(220, 0), UDim2.fromOffset(48, 34)
	self.undoButton, self.redoButton = undo, redo

	-- Preview: the real fighter, posed, with its controls.
	-- (the character stands on a sky-blue stage in a light theme, as the plaza's sky)
	local preview = frame(panel, "Preview", if LIGHT then Color3.fromRGB(196, 228, 255) else INK, 0)
	if LIGHT then
		-- a sky behind the character, deeper at the top, as the plaza's
		Ui.gradient(preview, Color3.fromRGB(150, 205, 255), Color3.new(1, 1, 1))
		Ui.stroke(preview, Ui.tone(Color3.fromRGB(150, 205, 255)), 2)
	end
	corner(preview, 12)
	Ui.stroke(preview, LINE, 2)
	self.preview = preview
	local stage = frame(preview, "PreviewCanvas")
	self.stage = stage
	self.previewCanvas = Canvas2D.inFrame(stage)
	local poses = frame(preview, "Poses")
	self.poseBar = poses
	self.poseButtons = {}
	for i, p in POSES do
		local b = button(poses, "Pose_" .. p[1], string.upper(p[2]), function() self:setPose(p[1]) end)
		b.LayoutOrder = i
		self.poseButtons[p[1]] = b
	end
	local poseList = Instance.new("UIGridLayout")
	poseList.CellPadding = UDim2.fromOffset(4, 4)
	poseList.SortOrder = Enum.SortOrder.LayoutOrder
	poseList.Parent = poses
	self.poseGrid = poseList
	local turn = button(preview, "Turn", "TURN", function() self.facing = -self.facing end)
	local zoom = button(preview, "Zoom", "FACE", function() self:setZoom(if self.zoom == "body" then "face" else "body") end)
	self.turnButton, self.zoomButton = turn, zoom
	local nameBox = Instance.new("TextBox")
	nameBox.Name = "Name"
	nameBox.BackgroundColor3 = PANEL2
	nameBox.BorderSizePixel = 0
	nameBox.Font = Ui.DISPLAY
	nameBox.TextSize = Ui.px(14)
	nameBox.TextColor3 = TEXT
	nameBox.PlaceholderText = "Name your fighter"
	nameBox.PlaceholderColor3 = DIM
	nameBox.ClearTextOnFocus = false
	nameBox.Text = self.name
	nameBox.Parent = preview
	corner(nameBox, 8)
	Ui.stroke(nameBox, INK, 2)
	nameBox.FocusLost:Connect(function()
		local clean = cleanName(nameBox.Text)
		self.name = if #clean > 0 then clean else self.name
		nameBox.Text = self.name
		self:refreshFooter()
	end)
	self.nameBox = nameBox
	local count = label(preview, "Count", "", if LIGHT then 11 else 9, if LIGHT then TEXT else DIM)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.TextWrapped = false
	count.TextTruncate = Enum.TextTruncate.AtEnd
	count.Text = `{AvatarEditor.commas(AvatarKit.partCombinations())} LOOKS, BEFORE COLOUR`
	self.countLabel = count

	-- Editor: tabs, parts, the option grid, colours.
	local editor = frame(panel, "Editor")
	self.editor = editor
	local groups = frame(editor, "Groups")
	local gl = Instance.new("UIListLayout")
	gl.FillDirection = Enum.FillDirection.Horizontal
	gl.Padding = UDim.new(0, 6)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = groups
	self.groupBar = groups
	self.groupButtons = {}
	for i, g in KIT.groups do
		local b = button(groups, "Group_" .. g.id, string.upper(g.name), function() self:selectGroup(g.id) end)
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #KIT.groups, -6, 1, 0)
		self.groupButtons[g.id] = b
	end
	local cats = frame(editor, "Categories")
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.Padding = UDim.new(0, 6)
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = cats
	self.catBar = cats
	local lock = button(editor, "Lock", "LOCK", function() self:toggleLock(self.category) end)
	local randPart = button(editor, "RandomPart", "RANDOM PART", function() self:randomizePart(self.category) end)
	self.lockButton, self.randPartButton = lock, randPart
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundColor3 = if LIGHT then PANEL2 else INK
	grid.BackgroundTransparency = 0
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3, grid.ScrollBarImageTransparency = Ui.KEY, 0.2   -- (visible, so it says there is more)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = editor
	corner(grid, 10)
	Ui.stroke(grid, LINE, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = grid
	-- "more below": a chip on the grid's lower edge while its tiles run past what it shows
	-- (a dark pill straddling the grid's border, like the shop's price pills: over the frame, not a name)
	local more = Ui.make("TextLabel", editor, { Name = "More", Text = "SCROLL FOR MORE  ▼", Font = Ui.LABEL, TextSize = Ui.px(11),
		TextColor3 = if LIGHT then Ui.WHITE else Ui.INK, BackgroundColor3 = if LIGHT then Color3.fromRGB(35, 27, 51) else AMBER,
		BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), ZIndex = 5, Visible = false })
	if LIGHT then Ui.make("UICorner", more, { CornerRadius = UDim.new(1, 0) }) else Ui.corner(more, 0) end
	self.moreChip = more
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	self.grid, self.gridLayout = grid, gridLayout
	local colours = frame(editor, "Colours")
	self.colourBar = colours

	-- Footer: status, delete, save.
	local footer = frame(panel, "Footer")
	self.footer = footer
	local status = label(footer, "Status", "", 13, DIM)
	self.status = status
	-- the keys as caps, the way the plaza and the fight teach theirs
	local hint, hintW = Ui.hintRow(footer, "Hint", { { "ARROWS", "PICK" }, { "Q E", "TAB" }, { "R", "RANDOM" }, { "CTRL Z", "UNDO" } }, 22, Ui.KEY)
	self.hint, self.hintW = hint, hintW
	local delete = button(footer, "Delete", "DELETE", function() self:confirm("Delete this character?", function() self:delete() end) end, Color3.fromRGB(150, 52, 58))
	local saveNew = button(footer, "SaveNew", "SAVE AS NEW", function() self:save(true) end, Ui.BLUE)
	local save = button(footer, "Save", "SAVE & WEAR", function() self:save(false) end, Color3.fromRGB(52, 160, 84))
	self.deleteButton, self.saveNewButton, self.saveButton = delete, saveNew, save

	-- A small confirmation, for the two things that lose work.
	local confirm = frame(panel, "Confirm", PANEL, 0)
	confirm.AnchorPoint = Vector2.new(0.5, 0.5)
	confirm.Position, confirm.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(360, 140)
	confirm.Visible = false
	confirm.ZIndex = 50
	corner(confirm, 10)
	stroke(confirm, AMBER, 3)
	local question = label(confirm, "Question", "", 16)
	question.TextXAlignment = Enum.TextXAlignment.Center
	question.Position, question.Size = UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 60)
	question.ZIndex = 51
	local yes = button(confirm, "Yes", "YES", function() confirm.Visible = false; if self.onYes then self.onYes() end end, Color3.fromRGB(176, 60, 60))
	yes.Position, yes.Size, yes.ZIndex = UDim2.new(0, 16, 1, -52), UDim2.new(0.5, -24, 0, 40), 51
	local no = button(confirm, "No", "NO", function() confirm.Visible = false end)
	no.Position, no.Size, no.ZIndex = UDim2.new(0.5, 8, 1, -52), UDim2.new(0.5, -24, 0, 40), 51
	self.confirmBox, self.question = confirm, question

	self:selectGroup("body")
	-- A resized window (or a phone turned sideways) re-lays the studio out while it is open.
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if gui.Enabled then self:layout() end
	end)
	return self
end

-- ------------------------------------------------------------------ layout ----
-- Wide screens put the preview beside the editor; tall or narrow ones (a phone held upright) put
-- it above. Everything is placed from the panel's pixel size so it is the same at every size.
function AvatarEditor.layout(self: any, size: Vector2?)
	local vp = size or self.gui.AbsoluteSize or self.viewport
	self.viewport = vp
	local W, H = math.min(vp.X - 24, 1440), math.min(vp.Y - 24, 900)
	self.size = Vector2.new(W, H)
	local wide = W >= 760 and W >= H * 1.05
	self.wide = wide
	local topH, footH = 56, 56
	local bodyY, bodyH = topH, H - topH - footH
	self.top.Size = UDim2.new(1, 0, 0, topH)
	self.title.Visible = W >= 640
	-- (the saved characters start after the title's own width: the pixel title ran under them)
	local chipsX = if W < 640 then 12 elseif LIGHT then 30 + Ui.textWidth("CHARACTER STUDIO", Ui.WINDOW_TITLE, Ui.TITLE) + 16 else 250
	self.chipBar.Position = UDim2.fromOffset(chipsX, 6)
	self.chipBar.Size = UDim2.fromOffset(math.max(60, W - chipsX - 276), 44)
	local pw, ph, ex, ey, ew, eh
	if wide then
		pw = math.clamp(W * 0.34, 260, 470)
		ph = bodyH - 8
		ex, ey, ew, eh = pw + 24, bodyY, W - pw - 36, bodyH - 8
	else
		pw, ph = W - 24, math.clamp(bodyH * 0.40, 190, 360)
		ex, ey, ew, eh = 12, bodyY + ph + 8, W - 24, bodyH - ph - 16
	end
	self.preview.Position, self.preview.Size = UDim2.fromOffset(12, bodyY), UDim2.fromOffset(pw, ph)
	-- Inside the preview: name on top, the stage, poses and view controls under it.
	-- a short wide screen (a phone on its side) keeps the preview: no pose row, no count line
	local short = wide and H < 500
	local controlsH = if wide and not short then 96 else 44
	self.nameBox.Position, self.nameBox.Size = UDim2.fromOffset(10, 10), UDim2.fromOffset(pw - 20, 34)
	self.countLabel.Visible = wide and not short
	self.countLabel.Position, self.countLabel.Size = UDim2.new(0, 10, 1, -22), UDim2.fromOffset(pw - 20, 16)
	-- (monospaced: sized so the line fits the panel it is in)
	self.countLabel.TextSize = math.min(Ui.px(9), math.floor((pw - 20) / (#self.countLabel.Text * Ui.ADVANCE)))
	local stageTop, stageH = 50, ph - 50 - controlsH - (if wide and not short then 24 else 6)
	self.stage.Position, self.stage.Size = UDim2.fromOffset(0, stageTop), UDim2.fromOffset(pw, stageH)
	self.stagePx = Vector2.new(pw, stageH)
	local cy = stageTop + stageH + 4
	self.poseBar.Visible = not short
	if short then
		self.turnButton.Position, self.turnButton.Size = UDim2.fromOffset(10, cy), UDim2.fromOffset((pw - 26) / 2, 36)
		self.zoomButton.Position, self.zoomButton.Size = UDim2.fromOffset(16 + (pw - 26) / 2, cy), UDim2.fromOffset((pw - 26) / 2, 36)
	elseif wide then
		self.poseBar.Position, self.poseBar.Size = UDim2.fromOffset(10, cy), UDim2.fromOffset(pw - 20, 40)
		self.poseGrid.CellSize = UDim2.fromOffset(math.floor((pw - 20 - 16) / 5), 40)
		self.turnButton.Position, self.turnButton.Size = UDim2.fromOffset(10, cy + 46), UDim2.fromOffset((pw - 26) / 2, 36)
		self.zoomButton.Position, self.zoomButton.Size = UDim2.fromOffset(16 + (pw - 26) / 2, cy + 46), UDim2.fromOffset((pw - 26) / 2, 36)
	else
		local bw = math.floor((pw - 20 - 6 * 4) / 7)
		self.poseBar.Position, self.poseBar.Size = UDim2.fromOffset(10, cy), UDim2.fromOffset(bw * 5 + 16, 40)
		self.poseGrid.CellSize = UDim2.fromOffset(bw, 40)
		self.turnButton.Position, self.turnButton.Size = UDim2.fromOffset(10 + (bw + 4) * 5, cy), UDim2.fromOffset(bw, 40)
		self.zoomButton.Position, self.zoomButton.Size = UDim2.fromOffset(10 + (bw + 4) * 6, cy), UDim2.fromOffset(bw, 40)
	end
	-- The editor column.
	self.editor.Position, self.editor.Size = UDim2.fromOffset(ex, ey), UDim2.fromOffset(ew, eh)
	self.groupBar.Position, self.groupBar.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(ew, 38)
	self.catBar.Position, self.catBar.Size = UDim2.fromOffset(0, 44), UDim2.fromOffset(ew - 250, 34)
	self.lockButton.Position, self.lockButton.Size = UDim2.fromOffset(ew - 242, 44), UDim2.fromOffset(100, 34)
	self.randPartButton.Position, self.randPartButton.Size = UDim2.fromOffset(ew - 136, 44), UDim2.fromOffset(136, 34)
	local colourRows = if self.group == "presets" then 0 else #self:paintSlots()
	local colourH = colourRows * 64
	local gridTop = 84
	local gridH = eh - gridTop - colourH - (if colourRows > 0 then 8 else 0)
	self.grid.Position, self.grid.Size = UDim2.fromOffset(0, gridTop), UDim2.fromOffset(ew, math.max(80, gridH))
	self.colourBar.Position, self.colourBar.Size = UDim2.fromOffset(0, gridTop + math.max(80, gridH) + 8), UDim2.fromOffset(ew, colourH)
	-- Tiles: as many columns as fit at 84-128 px, body pictures taller than faces.
	local view = self:view()
	local inner = ew - 16 - 6
	local cols = math.max(2, math.floor((inner + 8) / (if wide then 120 else 96)))
	local tile = math.floor((inner - (cols - 1) * 8) / cols)
	local tileH = tile + (if view == "body" then math.floor(tile * 0.45) else 0) + 20
	-- never taller than the grid shows, so a short (phone) grid still shows each tile's name
	tileH = math.min(tileH, math.max(60, math.max(80, gridH) - 14))
	self.gridLayout.CellSize = UDim2.fromOffset(tile, tileH)
	self.gridCols, self.gridTileH, self.gridShownH = cols, tileH, math.max(80, gridH)
	self.moreChip.Position = UDim2.fromOffset(ew - 24, gridTop + math.max(80, gridH))
	self.moreChip.Size = UDim2.fromOffset(Ui.textWidth(self.moreChip.Text, 11, Ui.LABEL) + 20, 22)
	self:updateMore()
	self.tilePx = Vector2.new(tile - 8, tileH - 28)
	-- Footer.
	self.footer.Position, self.footer.Size = UDim2.new(0, 0, 1, -footH), UDim2.new(1, 0, 0, footH)
	local saveW = if W >= 640 then 150 else 110
	self.saveButton.Position, self.saveButton.Size = UDim2.new(1, -12 - saveW, 0, 8), UDim2.fromOffset(saveW, 40)
	self.saveNewButton.Position, self.saveNewButton.Size = UDim2.new(1, -20 - saveW * 2, 0, 8), UDim2.fromOffset(saveW, 40)
	self.deleteButton.Position, self.deleteButton.Size = UDim2.new(1, -28 - saveW * 2 - 90, 0, 8), UDim2.fromOffset(90, 40)
	local statusW = math.max(80, W - 60 - saveW * 2 - 90 - 24)
	self.status.Position, self.status.Size = UDim2.fromOffset(16, 4), UDim2.fromOffset(statusW, 24)
	self.hint.Visible = W >= 900 and self.hintW <= statusW
	self.hint.Position, self.hint.Size = UDim2.fromOffset(16, 24), UDim2.fromOffset(self.hintW, 24)
	self:rebuildTiles()
	self:rebuildColours()
end

-- ------------------------------------------------------------------ state ----
function AvatarEditor.code(self: any): string
	return AvatarKit.encode(self.spec)
end

function AvatarEditor.dirty(self: any): boolean
	return self:code() ~= self.baseCode or self.name ~= self.baseName
end

function AvatarEditor.view(self: any): string
	if self.group == "presets" then
		return "body"
	end
	local cat = AvatarKit.category(self.category)
	return if cat then cat.view else "body"
end

function AvatarEditor.paintSlots(self: any): { string }
	local cat = AvatarKit.category(self.category)
	return if cat and self.group ~= "presets" then cat.paint else {}
end

-- Every edit goes through here: the old code goes on the undo stack, redo is cleared.
function AvatarEditor.change(self: any, fn: (AvatarKit.Spec) -> ())
	local before = self:code()
	local nextSpec = clone(self.spec)
	fn(nextSpec)
	nextSpec = AvatarKit.sanitize(nextSpec)
	if AvatarKit.encode(nextSpec) == before then
		return
	end
	table.insert(self.undoStack, before)
	if #self.undoStack > AvatarEditor.MAX_UNDO then
		table.remove(self.undoStack, 1)
	end
	table.clear(self.redoStack)
	self.spec = nextSpec
	self.message = nil
	self:refresh()
end

function AvatarEditor.undo(self: any)
	local code = table.remove(self.undoStack)
	if not code then return end
	table.insert(self.redoStack, self:code())
	self.spec = AvatarKit.decode(code) :: AvatarKit.Spec
	self.message = nil
	self:refresh()
end

function AvatarEditor.redo(self: any)
	local code = table.remove(self.redoStack)
	if not code then return end
	table.insert(self.undoStack, self:code())
	self.spec = AvatarKit.decode(code) :: AvatarKit.Spec
	self.message = nil
	self:refresh()
end

-- A category's options in the creator: its free parts, then its clothing pieces (k2; Roblox only).
function AvatarEditor.optionsOf(_self: any, c: any): { any }
	local out = table.clone(c.options)
	for _, it in Clothing.items do
		if it.category == c.id then table.insert(out, AvatarKit.option(c.id, it.id)) end
	end
	return out
end

-- An earned part (the Skyline Climb's rewards) can be worn once it is earned, a clothing piece once
-- it is owned; anything else always.
function AvatarEditor.wearable(self: any, catId: string, optionId: string): boolean
	if AvatarKit.piece(optionId) then return self.pieces[optionId] == true end
	local need = AvatarKit.unlockOf(catId, optionId)
	return need == nil or self.owned[need] == true
end

-- Where a locked part is earned (or bought), for the creator to say when it is picked.
function AvatarEditor.whereEarned(_self: any, catId: string, optionId: string): string
	for _, it in Clothing.items do
		if it.id == optionId then
			local price = Products.CLOTHING[it.priceTier] and Products.CLOTHING[it.priceTier].price
			local pack
			for _, p in Clothing.packs do if p.id == it.pack then pack = p end end
			return `In the Shop: {it.name}, {price} R$ on its own{if pack then `, or in the {pack.name} pack` else ""}.`
		end
	end
	local need = AvatarKit.unlockOf(catId, optionId)
	for _, r in PARKOUR.course.rewards do
		if r.unlock == need then
			local cp = PARKOUR.course.checkpoints[r.checkpoint + 1]
			return `Locked: collect the {r.name} at {cp.name}, level {r.checkpoint} of the Skyline Climb.`
		end
	end
	return "Locked."
end

function AvatarEditor.pick(self: any, catId: string, optionId: string)
	if not self:wearable(catId, optionId) then
		self:say(self:whereEarned(catId, optionId), AMBER)
		return
	end
	self:change(function(s) s.parts[catId] = optionId end)
end

-- The options of a category a player can put on: randomising never hands out a locked part.
local function wearableOptions(self: any, c: any): { any }
	local out = {}
	for _, o in self:optionsOf(c) do
		if self:wearable(c.id, o.id) then table.insert(out, o) end
	end
	return out
end

function AvatarEditor.paint(self: any, slot: string, index: number)
	self:change(function(s) s.colours[slot] = index end)
end

function AvatarEditor.applyPreset(self: any, presetId: string)
	for _, p in KIT.presets do
		if p.id == presetId then
			local spec = AvatarKit.decode(p.code) :: AvatarKit.Spec
			self:change(function(s)
				s.parts, s.colours = spec.parts, spec.colours
			end)
		end
	end
end

function AvatarEditor.toggleLock(self: any, catId: string)
	self.locks[catId] = not self.locks[catId] or nil
	self:refresh()
end

-- A colour slot is kept by Randomise when every part painted in it is locked: locking your hair
-- keeps its colour; locking only your eyebrows does not freeze your hair colour.
function AvatarEditor.colourLocked(self: any, slot: string): boolean
	local any = false
	for _, c in KIT.categories do
		if table.find(c.paint, slot) then
			any = true
			if not self.locks[c.id] then return false end
		end
	end
	return any
end

function AvatarEditor.randomize(self: any, rng: Random?)
	local r = rng or self.rng
	self:change(function(s)
		for _, c in KIT.categories do
			if not self.locks[c.id] then
				local options = wearableOptions(self, c)
				s.parts[c.id] = options[r:NextInteger(1, #options)].id
			end
		end
		for _, c in KIT.colours do
			if not self:colourLocked(c.id) then
				s.colours[c.id] = r:NextInteger(0, #c.list - 1)
			end
		end
	end)
end

function AvatarEditor.randomizePart(self: any, catId: string, rng: Random?)
	local c = AvatarKit.category(catId)
	if not c then return end
	local r = rng or self.rng
	local current = self.spec.parts[catId]
	self:change(function(s)
		-- A different option every press, so the button always visibly does something.
		local options = wearableOptions(self, c)
		local pickId = current
		while pickId == current and #options > 1 do
			pickId = options[r:NextInteger(1, #options)].id
		end
		s.parts[catId] = pickId
	end)
end

-- Step the chosen option in the current category, wrapping: the keyboard's left and right.
function AvatarEditor.step(self: any, dir: number)
	if self.group == "presets" then return end
	local c = AvatarKit.category(self.category)
	local options = self:optionsOf(c)
	for i, o in options do
		if o.id == self.spec.parts[c.id] then
			-- Past any part not yet earned: the arrows move between what you can wear.
			local j = i
			repeat
				j = (j - 1 + dir) % #options + 1
			until self:wearable(c.id, options[j].id) or j == i
			self:pick(c.id, options[j].id)
			return
		end
	end
end

function AvatarEditor.selectGroup(self: any, groupId: string)
	self.group = groupId
	local cats = groupCategories(groupId)
	if #cats > 0 and not table.find(cats, AvatarKit.category(self.category)) then
		self.category = cats[1].id
	end
	self:rebuildCategories()
	if self.size then self:layout(self.size + Vector2.new(24, 24)) end
	self:refresh()
end

function AvatarEditor.selectCategory(self: any, catId: string)
	local c = AvatarKit.category(catId)
	if not c then return end
	self.category, self.group = catId, c.group
	self:rebuildCategories()
	if self.size then self:layout(self.size + Vector2.new(24, 24)) end
	self:refresh()
end

-- Up and down: the next part, across tabs.
function AvatarEditor.stepCategory(self: any, dir: number)
	local list = KIT.categories
	local at = 1
	for i, c in list do
		if c.id == self.category then at = i end
	end
	local order = {}
	for _, g in KIT.groups do
		for _, c in groupCategories(g.id) do table.insert(order, c.id) end
	end
	local pos = table.find(order, list[at].id) or 1
	self:selectCategory(order[(pos - 1 + dir) % #order + 1])
end

function AvatarEditor.stepGroup(self: any, dir: number)
	for i, g in KIT.groups do
		if g.id == self.group then
			self:selectGroup(KIT.groups[(i - 1 + dir) % #KIT.groups + 1].id)
			return
		end
	end
end

function AvatarEditor.setPose(self: any, pose: string)
	self.pose, self.poseAt = pose, self.clock or 0
	self:refresh()
end

function AvatarEditor.setZoom(self: any, zoom: string)
	self.zoom = zoom
	self.zoomButton.Text = if zoom == "body" then "FACE" else "BODY"
end

-- ------------------------------------------------------------------ server ----
-- The server's view of this player's saved characters.
function AvatarEditor.setView(self: any, view: any)
	if type(view) ~= "table" or type(view.slots) ~= "table" then return end
	local first = #self.slots == 0
	self.slots, self.active, self.saving, self.note = view.slots, view.active or 1, view.saving == true, view.note
	local owned, sig = {}, {}
	for _, id in (if type(view.unlocked) == "table" then view.unlocked else {}) do
		owned[id] = true
		table.insert(sig, tostring(id))
	end
	local pieces = {}
	for _, id in (if type(view.pieces) == "table" then view.pieces else {}) do
		if type(id) == "string" then
			pieces[id] = true
			table.insert(sig, "piece:" .. id)
		end
	end
	table.sort(sig)
	if table.concat(sig, ",") ~= self.ownedSig then
		self.owned, self.pieces, self.ownedSig = owned, pieces, table.concat(sig, ",")
		self.tileKey = nil               -- a part was earned: its tile loses its lock
	end
	self.max = view.max or 8
	if first or not self.slots[self.editing] or self.pendingLoad then
		self.pendingLoad = nil
		self:loadSlot(if first then self.active else math.min(self.editing, #self.slots))
	elseif self.lastSaved and self.slots[self.editing] and self.slots[self.editing].code == self.lastSaved then
		-- Our save came back: this is now the saved state.
		self.baseCode, self.baseName = self.slots[self.editing].code, self.slots[self.editing].name
	end
	self.lastSaved = nil
	self.message = nil
	if view.error then
		self.message = { text = view.error, colour = AMBER }
	elseif self.saidSaved then
		self.message = { text = if self.saving then "Saved. You are wearing it." else "Wearing it - saving is off, so it lasts until you leave.", colour = GOOD }
	end
	self.saidSaved = nil
	self:rebuildChips()
	self:refreshFooter()
	if self.tileKey == nil then self:rebuildTiles() end
end

function AvatarEditor.loadSlot(self: any, i: number)
	local slot = self.slots[i]
	if not slot then return end
	self.editing = i
	self.spec = AvatarKit.decode(slot.code) or AvatarKit.sanitize(nil)
	self.name = slot.name
	self.nameBox.Text = slot.name
	self.baseCode, self.baseName = AvatarKit.encode(self.spec), slot.name
	self.message = nil
	table.clear(self.undoStack)
	table.clear(self.redoStack)
	self:rebuildChips()
	self:refresh()
end

-- Switching to another character with unsaved changes asks first.
function AvatarEditor.openSlot(self: any, i: number)
	if i == self.editing then return end
	if self:dirty() then
		self:confirm("Discard your unsaved changes?", function() self:loadSlot(i) end)
	else
		self:loadSlot(i)
	end
end

function AvatarEditor.newSlot(self: any)
	local n = #self.slots + 1
	if n > (self.max or 8) then
		self:say(`You can keep {self.max or 8} characters. Delete one first.`, AMBER)
		return
	end
	self.editing = n
	self.name = `Fighter {n}`
	self.nameBox.Text = self.name
	self.baseCode, self.baseName = "", ""              -- never saved: always dirty
	self:rebuildChips()
	self:refresh()
end

function AvatarEditor.save(self: any, asNew: boolean)
	local slot = if asNew then #self.slots + 1 else self.editing
	if slot > (self.max or 8) then
		self:say(`You can keep {self.max or 8} characters. Delete one first.`, AMBER)
		return
	end
	local code = self:code()
	self.editing, self.lastSaved, self.saidSaved = slot, code, true
	self.send({ action = "save", slot = slot, code = code, name = self.name })
	self:say("Saving...", DIM)
end

function AvatarEditor.delete(self: any)
	if #self.slots <= 1 or not self.slots[self.editing] then
		self:say("You need at least one character.", AMBER)
		return
	end
	self.pendingLoad = true
	self.send({ action = "delete", slot = self.editing })
end

function AvatarEditor.confirm(self: any, text: string, onYes: () -> ())
	self.question.Text = text
	self.onYes = onYes
	self.confirmBox.Visible = true
end

-- The status line shows, in priority order: a fresh message (an error, a confirmed save), the
-- saving-is-off note, "Unsaved changes", or nothing. Any edit clears the message.
function AvatarEditor.say(self: any, text: string?, colour: Color3?)
	self.message = if text and #text > 0 then { text = text, colour = colour or DIM } else nil
	self:refreshFooter()
end

-- ------------------------------------------------------------------ open / close ----
function AvatarEditor.open(self: any)
	self.gui.Enabled = true
	self.opened += 1
	self:layout()
	self:refresh()
end

function AvatarEditor.close(self: any)
	if self:dirty() and #self.slots > 0 then
		self:confirm("Close without saving?", function()
			if self.slots[self.editing] then self:loadSlot(self.editing) end
			self.gui.Enabled = false
		end)
		return
	end
	self.gui.Enabled = false
end

function AvatarEditor.isOpen(self: any): boolean
	return self.gui.Enabled
end

-- Keys, while open. Returns true when it used the key.
function AvatarEditor.key(self: any, code: Enum.KeyCode, ctrl: boolean): boolean
	if not self.gui.Enabled or UIS:GetFocusedTextBox() then return false end
	if self.confirmBox.Visible then
		if code == Enum.KeyCode.Escape then self.confirmBox.Visible = false; return true end
		return false
	end
	if ctrl and code == Enum.KeyCode.Z then self:undo()
	elseif ctrl and code == Enum.KeyCode.Y then self:redo()
	elseif code == Enum.KeyCode.Left then self:step(-1)
	elseif code == Enum.KeyCode.Right then self:step(1)
	elseif code == Enum.KeyCode.Up then self:stepCategory(-1)
	elseif code == Enum.KeyCode.Down then self:stepCategory(1)
	elseif code == Enum.KeyCode.Q then self:stepGroup(-1)
	elseif code == Enum.KeyCode.E then self:stepGroup(1)
	elseif code == Enum.KeyCode.R then self:randomize()
	elseif code == Enum.KeyCode.Escape then self:close()
	else return false end
	return true
end

-- ------------------------------------------------------------------ drawing ----
function AvatarEditor.rebuildCategories(self: any)
	for _, child in self.catBar:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
	local cats = groupCategories(self.group)
	self.catButtons = {}
	for i, c in cats do
		local b = button(self.catBar, "Cat_" .. c.id, string.upper(c.name), function() self:selectCategory(c.id) end)
		b.LayoutOrder = i
		b.TextSize = Ui.px(11)
		b.Size = UDim2.new(1 / math.max(1, #cats), -6, 1, 0)
		self.catButtons[c.id] = b
	end
	local presets = self.group == "presets"
	self.lockButton.Visible, self.randPartButton.Visible = not presets, not presets
end

-- The tiles for the current category (or the presets), each your character with that option.
function AvatarEditor.rebuildTiles(self: any)
	local key = if self.group == "presets" then "presets" else self.category
	if self.tileKey ~= key then
		for _, t in self.tiles do t.button:Destroy() end
		self.tiles = {}
		self.tileKey = key
		local entries = {}
		if self.group == "presets" then
			for _, p in KIT.presets do table.insert(entries, { kind = "Preset_", id = p.id, name = p.name }) end
		else
			for _, o in self:optionsOf(AvatarKit.category(self.category)) do
				-- An earned part not yet earned still shows on your character - it is the reason to go
				-- and earn it - behind a lock; so does clothing not yet bought.
				local locked = not self:wearable(self.category, o.id)
				local tag = if AvatarKit.piece(o.id) then "SHOP" else "LOCKED"
				table.insert(entries, { kind = "Option_", id = o.id, name = if locked then `{tag} · {o.name}` else o.name, locked = locked })
			end
		end
		self.tileCount = #entries
		self:updateMore()
		for i, e in entries do
			local b = tile(self.grid, e.kind .. e.id, function()
				if e.kind == "Preset_" then self:applyPreset(e.id) else self:pick(self.category, e.id) end
			end, if LIGHT then Ui.PANEL else PANEL2)
			b.LayoutOrder = i
			-- (a card even before its fighter is drawn: white at the top fading to the warm cream)
			if LIGHT then Ui.gradient(b, Color3.new(1, 1, 1), Ui.PANEL2) end
			local thumb = frame(b, "Thumb")
			thumb.Position, thumb.Size = UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -28)
			local name = label(b, "Label", string.upper(e.name), if LIGHT then 12 else 10, if LIGHT then TEXT else Ui.KEY)
			if e.locked then b.BackgroundTransparency = 0.5 end
			name.TextXAlignment = Enum.TextXAlignment.Center
			name.Position, name.Size = UDim2.new(0, 2, 1, -22), UDim2.new(1, -4, 0, 20)
			local pick = stroke(b, AMBER, 4)
			pick.Enabled = false
			self.tiles[e.id] = { button = b, canvas = Canvas2D.inFrame(thumb), pick = pick, label = name, kind = e.kind }
		end
	end
	self:renderTiles()
end

-- The code each tile shows, and redraw only the tiles whose picture changed. Clicking an option in
-- the category you are looking at changes no tile's picture - only which one is picked.
function AvatarEditor.tileCode(self: any, id: string): string
	if self.group == "presets" then
		for _, p in KIT.presets do if p.id == id then return p.code end end
	end
	local s = clone(self.spec)
	s.parts[self.category] = id
	return AvatarKit.encode(s)
end

-- Do the grid's tiles run past what it shows? Then the chip says so.
function AvatarEditor.updateMore(self: any)
	if not (self.moreChip and self.gridCols and self.tileCount) then return end
	local rows = math.ceil(self.tileCount / self.gridCols)
	self.moreChip.Visible = rows * (self.gridTileH + 8) + 8 > self.gridShownH + 1
end

function AvatarEditor.renderTiles(self: any)
	local px = self.tilePx or Vector2.new(96, 96)
	local view = self:view()
	local mine = self:code()
	for id, t in self.tiles do
		local code = self:tileCode(id)
		local picked = if t.kind == "Preset_" then code == mine else self.spec.parts[self.category] == id
		t.pick.Enabled = picked
		t.label.TextColor3 = if picked then PICKED elseif LIGHT then TEXT else Ui.KEY
		local key = `{code}|{view}|{px.X}x{px.Y}`
		if t.drawn ~= key then
			KitPortrait.draw(t.canvas, code, view, px.X, px.Y)
			t.drawn = key
		end
	end
end

function AvatarEditor.rebuildColours(self: any)
	for _, child in self.colourBar:GetChildren() do child:Destroy() end
	self.swatches = {}
	local w = self.editor.Size.X.Offset
	for row, slot in self:paintSlots() do
		local c = AvatarKit.colourSlot(slot)
		local holder = frame(self.colourBar, "Row_" .. slot)
		holder.Position, holder.Size = UDim2.fromOffset(0, (row - 1) * 64), UDim2.fromOffset(w, 60)
		local name = label(holder, "Label", string.upper(c.name), 12, DIM)
		name.Position, name.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(w, 14)
		local sw = frame(holder, "Swatches")
		local perRow = math.ceil(#c.list / 2)
		local cell = math.clamp(math.floor((w - (perRow - 1) * 4) / perRow), 12, 30)
		-- exactly half the palette a row: the full width let one more fit and left one alone below
		sw.Position, sw.Size = UDim2.fromOffset(0, 16), UDim2.fromOffset(perRow * (cell + 4) - 4, 44)
		local g = Instance.new("UIGridLayout")
		g.CellSize = UDim2.fromOffset(cell, 20)
		g.CellPadding = UDim2.fromOffset(4, 4)
		g.SortOrder = Enum.SortOrder.LayoutOrder
		g.Parent = sw
		for i, hex in c.list do
			local b = tile(sw, `Swatch_{slot}_{i - 1}`, function() self:paint(slot, i - 1) end, Canvas2D.hex(hex, INK))
			b.LayoutOrder = i
			local pick = stroke(b, AMBER, 3)          -- (one 'chosen' colour everywhere: gold)
			pick.Enabled = false
			self.swatches[`{slot}_{i - 1}`] = pick
		end
	end
	self:renderColours()
end

function AvatarEditor.renderColours(self: any)
	for key, pick in self.swatches do
		local slot, i = string.match(key, "^(.-)_(%d+)$")
		pick.Enabled = slot ~= nil and self.spec.colours[slot] == tonumber(i)
	end
end

function AvatarEditor.rebuildChips(self: any)
	for _, child in self.chipBar:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
	self.chips = {}
	local count = math.max(#self.slots, self.editing)
	for i = 1, count do
		local slot = self.slots[i]
		local b = tile(self.chipBar, "Slot_" .. i, function() self:openSlot(i) end,
			if LIGHT then (if i == self.editing then Ui.SUN else PANEL2) elseif i == self.editing then PANEL2 else INK)
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(44, 44)
		local thumb = frame(b, "Thumb")
		thumb.Size = UDim2.fromScale(1, 1)
		local canvas = Canvas2D.inFrame(thumb)
		local code = if i == self.editing then self:code() elseif slot then slot.code else self:code()
		KitPortrait.draw(canvas, code, "head", 44, 44)
		if i == self.editing then stroke(b, AMBER, 2) end
		if i == self.active then
			local dot = frame(b, "Worn", GOOD, 0)
			dot.Size, dot.Position = UDim2.fromOffset(8, 8), UDim2.fromOffset(34, 2)
			corner(dot, 4)
		end
		self.chips[i] = { button = b, canvas = canvas, code = code }
	end
	if count < (self.max or 8) then
		local add = button(self.chipBar, "SlotNew", "+", function() self:newSlot() end, Ui.BLUE)
		add.LayoutOrder = count + 1
		add.TextSize = Ui.px(18)
		add.Size = UDim2.fromOffset(44, 44)
	end
end

function AvatarEditor.refreshFooter(self: any)
	local slot = self.slots[self.editing]
	local saved = slot ~= nil and not self:dirty()
	self.saveButton.Text = if saved and self.editing == self.active then "WEARING" else "SAVE & WEAR"
	self.saveNewButton.Visible = #self.slots < (self.max or 8)
	self.deleteButton.Visible = slot ~= nil and #self.slots > 1
	local m = self.message
	if m then
		self.status.Text, self.status.TextColor3 = m.text, m.colour
	elseif not self.saving and self.note then
		self.status.Text, self.status.TextColor3 = self.note, AMBER
	else
		self.status.Text, self.status.TextColor3 = if self:dirty() then "Unsaved changes" else "", DIM
	end
end

function AvatarEditor.refresh(self: any)
	-- the chosen tab is gold, the chosen part and pose blue (with the kit's shine and lip)
	for id, b in self.groupButtons do
		Ui.paint(b, if id == self.group then AMBER else PANEL2, TEXT)
	end
	for id, b in self.catButtons or {} do
		Ui.paint(b, if id == self.category then AMBER else PANEL2, TEXT)
		b.Text = string.upper(AvatarKit.category(id).name) .. (if self.locks[id] then " *" else "")
	end
	for id, b in self.poseButtons do
		Ui.paint(b, if id == self.pose then AMBER else PANEL2, TEXT)
	end
	self.lockButton.Text = if self.locks[self.category] then "LOCKED" else "LOCK"
	Ui.paint(self.lockButton, if self.locks[self.category] then AMBER else PANEL2, TEXT)
	self.undoButton.AutoButtonColor, self.redoButton.AutoButtonColor = #self.undoStack > 0, #self.redoStack > 0
	self.undoButton.TextTransparency = if #self.undoStack > 0 then 0 else 0.6
	self.redoButton.TextTransparency = if #self.redoStack > 0 then 0 else 0.6
	if self.tiles then self:renderTiles() end
	self:renderColours()
	-- The chip you are editing shows the edit live.
	local chip = self.chips[self.editing]
	if chip and chip.code ~= self:code() then
		chip.code = self:code()
		KitPortrait.draw(chip.canvas, chip.code, "head", 44, 44)
	end
	self:refreshFooter()
end

-- The preview, every frame while open: the real fighter in the chosen pose.
function AvatarEditor.draw(self: any, clock: number)
	if not self.gui.Enabled then return end
	self.clock = clock
	local code = self:code()
	local weapon = self.weaponOf()
	local key = code .. "/" .. weapon
	if self.charKey ~= key then
		self.char = Loadout.build(code, weapon)
		self.charKey = key
	end
	local char = self.char
	local c = self.previewCanvas
	local px = self.stagePx or Vector2.new(300, 400)
	local face = self.zoom == "face"
	local ppu = if face then px.Y / 2.8 else px.Y / 7.6
	local camY = if face then char.height * 0.86 else char.height * 0.52
	Canvas2D.setTransform(c, ppu, 0, 0, -ppu, px.X / 2, px.Y / 2 + camY * ppu)
	-- A pedestal to stand on.
	Canvas2D.ellipse(c, 0, -0.1, 3.2, 0.5, PANEL2, 1)
	Canvas2D.rect(c, -3.2, -0.6, 6.4, 0.5, LINE, 1)
	local t = clock - (self.poseAt or 0)
	local st: any
	if self.pose == "attack" then
		local move = char.moves[char.signature]
		local total = (move.startup or 10) + (move.active or 4) + (move.recovery or 20)
		local f = math.floor(t * 60) % (total + 40)
		st = PosedFighter.posed(char, 0, if f < total then "attack" else "idle", f)
		st.moveId, st.moveFrame, st.startupEff = char.signature, math.min(f, total), move.startup or 10
	elseif self.pose == "run" then
		st = PosedFighter.posed(char, 0, "run", math.floor(t * 60))
		-- Movement's stride is driven by distance. Advance that distance on a treadmill;
		-- the draw below cancels the root travel so the runner stays on the pedestal.
		st.vx = char.runSpeed * self.facing
		st.x = t * st.vx
	elseif self.pose == "air" then
		local phase = (t % 1.2) / 1.2
		st = PosedFighter.posed(char, 0, "air", math.floor(t * 60))
		st.onGround, st.vy = false, 40 * (1 - phase * 2)
		st.y = 3.2 * math.sin(phase * math.pi)
	else
		st = PosedFighter.posed(char, 0, self.pose, math.floor(t * 60))
	end
	st.facing = self.facing
	-- Team colours belong to matches; the studio is not one.
	local teams = Fighter2D.teamColours
	Fighter2D.teamColours = nil
	Canvas2D.save(c)
	Canvas2D.translate(c, -st.x, 0)
	Fighter2D.draw(c, st, char, clock, 0)
	Canvas2D.restore(c)
	Fighter2D.teamColours = teams
	Canvas2D.finish(c, true)
end

return AvatarEditor
