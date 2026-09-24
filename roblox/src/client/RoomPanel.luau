--!strict
-- Only opened from a world portal. All choices are server-confirmed room edits.
local Shared = game:GetService("ReplicatedStorage").Shared
local Weapons = require(Shared.Data.Weapons)
local Avatars = require(Shared.Data.Avatars)
local Stages = require(Shared.Data.Stages)
local Canvas = require(script.Parent.Canvas2D)
local Art = require(script.Parent.Weapons2D)
local RoomPanel = {}
RoomPanel.__index = RoomPanel

local INK, STEEL, GOLD, WHITE = Color3.fromRGB(16,21,28), Color3.fromRGB(44,57,66), Color3.fromRGB(235,173,80), Color3.fromRGB(233,230,218)
-- A stage's layout as a small diagram, drawn from the same stage data the engine collides against:
-- solid ground with its lit cap and grabbable ledges, drop-through shelves, and a moving shelf's
-- travel. The map board shows this beside each name, because a map is chosen by its shape.
local function stageExtent(stage: any): (number, number, number, number)
	local x0, x1, y0, y1 = stage.main.x1, stage.main.x2, stage.main.y - stage.main.thickness, stage.main.y
	for _, p in stage.platforms do
		local mx = if p.moving and p.moving.x then p.moving.x else nil
		local lo = if mx then math.min(mx.from, mx.to) else p.x
		local hi = if mx then math.max(mx.from, mx.to) else p.x
		x0, x1 = math.min(x0, lo - p.w / 2), math.max(x1, hi + p.w / 2)
		local my = if p.moving and p.moving.y then p.moving.y else nil
		y1 = math.max(y1, if my then math.max(my.from, my.to) else p.y)
		y0 = math.min(y0, p.y - (p.thickness or (if p.solid then 5 else 1)))
	end
	return x0 - 4, x1 + 4, y0 - 2, y1 + 6
end
function RoomPanel.drawStage(c: any, stage: any, w: number, h: number)
	local x0, x1, y0, y1 = stageExtent(stage)
	local ppu = math.min(w / (x1 - x0), h / (y1 - y0))
	c:world((x0 + x1) / 2, (y0 + y1) / 2, ppu, 0, 0)
	local pal = stage.palette or {}
	local ground = Canvas.hex(pal.ground, Color3.fromRGB(62, 68, 80))
	local top = Canvas.hex(pal.groundTop, Color3.fromRGB(138, 148, 166))
	local shelf = Canvas.hex(pal.platform, Color3.fromRGB(110, 119, 136))
	local accent = Canvas.hex(pal.accent, GOLD)
	Canvas.rect(c, x0, y0, x1 - x0, y1 - y0, INK)
	local function solid(a: number, b: number, topY: number, thick: number, ledges: any)
		Canvas.rect(c, a, topY - thick, b - a, thick, ground)
		Canvas.rect(c, a, topY - 1, b - a, 1, top)
		if ledges ~= false then
			Canvas.rect(c, a, topY - 2, 0.9, 2, accent)
			Canvas.rect(c, b - 0.9, topY - 2, 0.9, 2, accent)
		end
	end
	local m = stage.main
	solid(m.x1, m.x2, m.y, m.thickness, m.ledges)
	for _, p in stage.platforms do
		if p.solid then
			solid(p.x - p.w / 2, p.x + p.w / 2, p.y, p.thickness or 5, p.ledges)
		else
			local mx = if p.moving and p.moving.x then p.moving.x else nil
			if mx then   -- the shelf's whole travel, faint, so the board says "this one moves"
				local lo, hi = math.min(mx.from, mx.to), math.max(mx.from, mx.to)
				Canvas.rect(c, lo - p.w / 2, p.y - 0.4, hi - lo + p.w, 0.4, shelf, 0.35)
			end
			Canvas.rect(c, p.x - p.w / 2, p.y - (p.thickness or 1), p.w, p.thickness or 1, shelf)
		end
	end
end
local function label(parent: Instance, value: string, height: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency, t.TextColor3, t.Font = 1, WHITE, Enum.Font.GothamBold
	t.Text, t.TextSize, t.TextWrapped = value, 14, true
	t.Size, t.Parent = UDim2.new(1, 0, 0, height), parent
	return t
end
local function button(parent: Instance, value: string, callback: () -> (), selected: boolean?): TextButton
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.Font, b.TextSize = value, value, Enum.Font.GothamBold, 14
	b.Size, b.TextWrapped = UDim2.new(1, 0, 0, 42), true
	b.BackgroundColor3, b.TextColor3, b.BorderSizePixel = if selected then GOLD else STEEL, if selected then INK else WHITE, 0
	b.Parent = parent
	b.Activated:Connect(callback)
	return b
end
function RoomPanel.new(parent: Instance): any
	local self: any = setmetatable({ page = "Players", previews = {}, cfg = { slots = { { avatarId = "Classic", weaponId = "Sword" } } } }, RoomPanel)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "BlockfallRoom", false, true, 20
	gui.Enabled, gui.Parent = false, parent
	self.gui = gui
	local panel = Instance.new("Frame")
	panel.Name, panel.AnchorPoint = "Room", Vector2.new(0.5, 0.5)
	panel.Position, panel.Size = UDim2.fromScale(0.5, 0.5), UDim2.new(1, -24, 1, -96)
	panel.BackgroundColor3, panel.BackgroundTransparency, panel.Parent = INK, 0.08, gui
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize, cap.Parent = Vector2.new(680, 680), panel
	self.title = label(panel, "MATCH ROOM", 44)
	self.status = label(panel, "", 44)
	self.status.Position = UDim2.fromOffset(0, 44)
	self.status.TextSize = 12
	local body = Instance.new("ScrollingFrame")
	body.Name, body.BackgroundTransparency, body.BorderSizePixel = "Choices", 1, 0
	body.Position, body.Size = UDim2.fromOffset(12,92), UDim2.new(1,-24,1,-158)
	body.ScrollBarThickness, body.AutomaticCanvasSize, body.CanvasSize = 5, Enum.AutomaticSize.Y, UDim2.fromOffset(0,0)
	body.Parent, self.body = panel, body
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency, footer.Position, footer.Size, footer.Parent = 1, UDim2.new(0,12,1,-54), UDim2.new(1,-24,0,42), panel
	button(footer, "Back to room", function() self:hide() end).Size = UDim2.new(1/3,-4,1,0)
	self.ready = button(footer, "Ready", function() self:send("ready") end)
	self.ready.Position, self.ready.Size = UDim2.new(1/3,0,0,0), UDim2.new(1/3,-4,1,0)
	self.start = button(footer, "Start fight", function()
		if self.room and self.room.host == self.userId and self.room.canStart then self:send("start") end
	end)
	self.start.Position, self.start.Size = UDim2.new(2/3,0,0,0), UDim2.new(1/3,-4,1,0)
	return self
end
function RoomPanel.send(self: any, action: string, value: any?, slot: number?)
	if self.onAction then self.onAction({ action = action, value = value, slot = slot,
		id = self.room and self.room.id, revision = self.room and self.room.revision }) end
end
function RoomPanel.hide(self: any) self.gui.Enabled = false end
function RoomPanel.openStation(self: any, page: string)
	if not self.room or self.room.left or self.room.state ~= "setup" then return end
	if not table.find({ "Maps", "Weapons", "Looks", "Rules", "Players" }, page) then return end
	self.page = page
	self:render()
	self.gui.Enabled = true
end
function RoomPanel.show(self: any, message: string?)
	self.gui.Enabled = true
	self.status.Text = message or ""
end
function RoomPanel.waiting(self: any, message: string) self:show(message) end
function RoomPanel.update(self: any, room: any, userId: number)
	local entering = not self.room or self.room.left or self.room.id ~= room.id
	self.room, self.userId = room, userId
	if room.left then self:hide(); return end
	for _, slot in room.slots do
		if slot.userId == userId then self.cfg.slots[1] = { weaponId = slot.weapon, avatarId = slot.avatar } end
	end
	self:render()
	-- Room updates must not summon a modal over a walking player.
	if entering then self:hide() end
end
function RoomPanel.render(self: any)
	local room = self.room
	if not room or room.left then return end
	self.body:ClearAllChildren()
	self.previews = {}
	local layout = Instance.new("UIListLayout")
	layout.Padding, layout.Parent = UDim.new(0,6), self.body
	local host = room.host == self.userId
	self.title.Text = `{room.name}  ·  {self.page}  ·  ROOM {room.id}`
	self.ready.Visible, self.start.Visible = self.page == "Players", self.page == "Players"
	self.status.Text = room.error or (if room.state == "playing" then "Loading arena…" else
		(if host then "You host this room. " else "Host chooses map, bots and rules. ") .. "Both teams must be full; every player must ready.")
	self.ready.Text = "Ready"
	for _, slot in room.slots do if slot.userId == self.userId and slot.ready then self.ready.Text = "Unready" end end
	self.start.Text = if host then (if room.canStart then "Start fight" else "Waiting for team") else "Host starts"
	self.start.BackgroundColor3 = if host and room.canStart then GOLD else STEEL
	if self.page == "Maps" then
		for _, stage in Stages.LIST do
			local selected = room.stage == stage.id
			local b = button(self.body, "", function() if host then self:send("stage", stage.id) end end, selected)
			b.Name, b.Size = "Stage_" .. stage.id, UDim2.new(1, 0, 0, 72)
			local name = label(b, (if selected then "✓ " else "") .. stage.name .. "\n" .. (stage.archetype or ""), 68)
			name.Position, name.Size = UDim2.new(0.42, 0, 0, 0), UDim2.new(0.58, -8, 1, 0)
			if selected then name.TextColor3 = INK end
			local frame = Instance.new("Frame")
			frame.Name, frame.BackgroundTransparency, frame.ClipsDescendants = "StageImage", 1, true
			frame.Position, frame.Size, frame.Parent = UDim2.fromOffset(4, 4), UDim2.new(0.42, -8, 1, -8), b
			table.insert(self.previews, { canvas = Canvas.inFrame(frame), stage = stage, frame = frame })
		end
	elseif self.page == "Weapons" then
		for _, weapon in Weapons.LIST do
			local selected = self.cfg.slots[1].weaponId == weapon.id
			local b = button(self.body, "", function() self:send("weapon", weapon.id) end, selected)
			b.Name, b.Size = "Weapon_" .. weapon.id, UDim2.new(1,0,0,80)
			local name = label(b, (if selected then "✓ EQUIPPED  ·  " else "") .. weapon.name .. "\n" .. (weapon.archetype or ""), 76)
			name.Position, name.Size = UDim2.new(0.32,0,0,0), UDim2.new(0.68,-8,1,0)
			if selected then name.TextColor3 = INK end
			local frame = Instance.new("Frame")
			frame.Name, frame.BackgroundTransparency, frame.ClipsDescendants = "WeaponImage", 1, true
			frame.Size, frame.Parent = UDim2.new(0.32,0,1,0), b
			table.insert(self.previews, { canvas = Canvas.inFrame(frame), weapon = weapon, frame = frame })
		end
	elseif self.page == "Looks" then
		for _, avatar in Avatars.LIST do
			button(self.body, avatar.name, function() self:send("avatar", avatar.id) end, self.cfg.slots[1].avatarId == avatar.id)
		end
	elseif self.page == "Rules" then
		label(self.body, "Equal teams · stock battle · bots OFF unless explicitly added below", 52)
		for n = 1, 5 do button(self.body, `{n} stocks`, function() if host then self:send("stocks", n) end end, room.stocks == n) end
		button(self.body, "Items: " .. (if room.items then "ON" else "OFF"), function() if host then self:send("items", not room.items) end end)
		for i, slot in room.slots do
			if not slot.userId then
				local nextLevel = if not slot.bot then "easy" else if slot.bot == "easy" then "normal" else if slot.bot == "normal" then "hard" else false
				label(self.body, `TEAM {slot.team + 1} · PLACE {i}`, 28)
				button(self.body, (if slot.bot then `CPU: {slot.bot} — change / turn off` else "Bots OFF — add optional CPU"),
					function() if host then self:send("bot", nextLevel, i) end end)
			end
		end
	else
		for i, slot in room.slots do
			label(self.body, `TEAM {slot.team + 1}  ·  {slot.name}` .. (if slot.ready then "  ✓ READY" else "")
				.. (if slot.weapon and slot.userId then `  ·  {slot.weapon}` else ""), 40)
		end
	end
end
function RoomPanel.drawPreviews(self: any)
	if not self.gui.Enabled then return end
	for _, preview in self.previews do
		local size = preview.frame.AbsoluteSize
		if size.X > 0 and size.Y > 0 and (preview.width ~= size.X or preview.height ~= size.Y) then
			preview.width, preview.height = size.X, size.Y
			local c = preview.canvas
			c:clear()
			if preview.stage then
				RoomPanel.drawStage(c, preview.stage, size.X, size.Y)
			else
				-- Flat, fitted to the weapon's own extent at a pixel-exact scale. See Weapons2D.fit.
				local cx, cy, ppu = Art.fit(preview.weapon.id, size.X, size.Y)
				c:world(cx, cy, ppu, 0, 0)
				Art.draw(c, preview.weapon.id, preview.weapon.palette, { angle = 0, ox = 0, oy = 0, scale = 1, charge = 0 })
			end
			c:finish()
		end
	end
end
return RoomPanel
