--!strict
-- Only opened from a world portal. All choices are server-confirmed room edits.
local Shared = game:GetService("ReplicatedStorage").Shared
local Weapons = require(Shared.Data.Weapons)
local Stages = require(Shared.Data.Stages)
local Canvas = require(script.Parent.Canvas2D)
local Art = require(script.Parent.Weapons2D)
local StageThumb = require(script.Parent.StageThumb)
local Realms = require(Shared.Realms)
local Rules = require(game:GetService("ReplicatedStorage").Shared.Data.Rules)
local Ui = require(script.Parent.Ui)
local RoomPanel = {}
RoomPanel.__index = RoomPanel

-- the look is the shared cartoon kit's (Ui)
local INK, STEEL, GOLD, WHITE = Ui.INK, Ui.PANEL2, Ui.GOLD, Ui.WHITE
-- A stage's layout as a small diagram, drawn from the same stage data the engine collides against:
-- solid ground with its lit cap and grabbable ledges, drop-through shelves, and a moving shelf's
-- travel. The map board shows this beside each name, because a map is chosen by its shape.
-- A map-select thumbnail from the shape list both builds draw (StageThumb, held to
-- web/src/render2d/stageThumb.js), in the tile's own pixels.
function RoomPanel.drawThumb(c: any, shapes: { any })
	c:screen()
	for _, sh in shapes do
		Canvas.rect(c, sh[2], sh[3], sh[4], sh[5], Canvas.hex(sh[6], INK), sh[7])
	end
end
local function label(parent: Instance, value: string, height: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency, t.TextColor3, t.Font = 1, WHITE, Ui.LABEL
	t.Text, t.TextSize, t.TextWrapped = value, Ui.px(12), true
	t.Size, t.Parent = UDim2.new(1, 0, 0, height), parent
	return t
end
-- The kit's bevelled button; a chosen one is gold.
local function button(parent: Instance, value: string, callback: () -> (), selected: boolean?): TextButton
	local b = Ui.button(parent, value, if selected then GOLD else STEEL, callback, { size = 12 })
	b.Name = value
	b.Size, b.TextWrapped = UDim2.new(1, 0, 0, 42), true
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
	panel.BackgroundColor3, panel.BackgroundTransparency, panel.Parent = Ui.PANEL, 0.02, gui
	Ui.corner(panel, 0)
	Ui.stroke(panel, INK, 3)
	Ui.rim(panel, Ui.PANEL2, 2, 0)
	self.panel = panel
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize, cap.Parent = Vector2.new(680, 680), panel
	self.title = label(panel, "MATCH ROOM", 44)
	self.title.Font, self.title.TextSize, self.title.TextColor3 = Ui.DISPLAY, Ui.px(20), GOLD
	Ui.outline(self.title, 3)
	self.status = label(panel, "", 44)
	self.status.Position = UDim2.fromOffset(0, 44)
	self.status.TextSize = Ui.px(11)
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
	self:buildNotice()
	return self
end
-- The notice: what the lobby has to say while a fight is fetched or refused, as a small card of its
-- own rather than the whole room panel - a band (blue while waiting, red for a problem), the
-- message, and OK for a problem.
function RoomPanel.buildNotice(self: any)
	local card, band, title = Ui.panel(self.gui, "Notice", Ui.BLUE, "", 34)
	card.AnchorPoint, card.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(1, -48, 0, 150)
	local cap = Ui.make("UISizeConstraint", card, { MaxSize = Vector2.new(460, 150) })
	card.Visible = false
	title.TextXAlignment = Enum.TextXAlignment.Center
	local message = Ui.text(card, "", 15, WHITE)
	message.Name = "Message"
	message.TextWrapped = true
	message.Position, message.Size = UDim2.fromOffset(16, 46), UDim2.new(1, -32, 0, 58)
	local ok = Ui.button(card, "BACK TO LOBBY", Ui.BLUE, function() self:hide() end)
	ok.Name = "Ok"
	ok.AnchorPoint, ok.Position, ok.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(180, 38)
	-- a wait has no OK, so its card is only as tall as its message, with a row of pixel blocks
	-- stepping along under it to say something is happening
	local dots = Ui.make("Frame", card, { Name = "Working", BackgroundTransparency = 1, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(5 * 14 - 4, 10) })
	for k = 1, 5 do
		local dot = Ui.make("Frame", dots, { Name = "Block" .. k, BackgroundColor3 = if k == 1 then Ui.GOLD else Ui.PANEL2, BorderSizePixel = 0,
			Position = UDim2.fromOffset((k - 1) * 14, 0), Size = UDim2.fromOffset(10, 10) })
		if not Ui.flat() then continue end
		Ui.make("UICorner", dot, { CornerRadius = UDim.new(0.5, 0) })      -- round dots in a smooth theme
	end
	self.notice = { card = card, band = band, title = title, message = message, ok = ok, cap = cap, dots = dots }
end
-- `waiting`: a fight is on its way (no button); otherwise a problem to acknowledge.
function RoomPanel.say(self: any, message: string, waiting: boolean)
	local n = self.notice
	n.title.Text = if waiting then "GET READY" else "MATCH DIDN'T START"
	Ui.paintBand(n.band, if waiting then Ui.BLUE else Ui.RED)
	n.message.Text = message
	n.ok.Visible = not waiting
	n.dots.Visible = waiting
	local h = if waiting then 130 else 166
	n.card.Size, n.cap.MaxSize = UDim2.new(1, -48, 0, h), Vector2.new(460, h)
	-- the lit block steps along while the wait lasts (one loop, stopped when the card goes)
	if waiting and not n.stepping and type(task) == "table" then
		n.stepping = true
		local k = 1
		local function step()
			if not (n.dots.Visible and n.card.Visible and self.gui.Enabled) then n.stepping = false; return end
			k = k % 5 + 1
			for _, b in n.dots:GetChildren() do b.BackgroundColor3 = if b.Name == "Block" .. k then Ui.GOLD else Ui.PANEL2 end
			task.delay(0.18, step)
		end
		task.delay(0.18, step)
	end
	n.card.Visible = true
	self.panel.Visible = false
	self.gui.Enabled = true
end
function RoomPanel.send(self: any, action: string, value: any?, slot: number?)
	if self.onAction then self.onAction({ action = action, value = value, slot = slot,
		id = self.room and self.room.id, revision = self.room and self.room.revision }) end
end
function RoomPanel.hide(self: any) self.gui.Enabled = false end
function RoomPanel.openStation(self: any, page: string)
	if not self.room or self.room.left or self.room.state ~= "setup" then return end
	if not table.find({ "Maps", "Weapons", "Rules", "Players" }, page) then return end
	self.page = page
	self:render()
	self.notice.card.Visible = false
	self.panel.Visible = true
	self.gui.Enabled = true
end
function RoomPanel.show(self: any, message: string?)
	self:say(message or "", false)
end
function RoomPanel.waiting(self: any, message: string) self:say(message, true) end
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
		-- After Brawlhalla's map select: a grid of thumbnails with Random first. How the map is
		-- chosen is the host's call - they pick, everyone votes, or it is random - and so is the set.
		local choice = room.mapChoice or "host"
		local set = room.mapSet or "all"
		local myVote = nil
		local votes: { [string]: number } = {}
		for _, slot in room.slots do
			if slot.userId == self.userId then myVote = slot.vote end
			if slot.vote then votes[slot.vote] = (votes[slot.vote] or 0) + 1 end
		end
		local function row(name: string, options: { { string } }, current: string, action: string)
			local bar = Instance.new("Frame")
			bar.Name, bar.BackgroundTransparency, bar.Size, bar.Parent = name, 1, UDim2.new(1, 0, 0, 36), self.body
			for i, opt in options do
				local b = button(bar, opt[2], function() if host then self:send(action, opt[1]) end end, current == opt[1])
				b.Name = `{name}_{opt[1]}`
				b.Position, b.Size = UDim2.new((i - 1) / #options, 2, 0, 0), UDim2.new(1 / #options, -4, 1, 0)
			end
		end
		row("MapChoice", { { "host", "Host picks" }, { "vote", "Everyone votes" }, { "random", "Random" } }, choice, "mapChoice")
		row("MapSet", { { "all", "All maps" }, { "ranked", "Ranked" } }, set, "mapSet")
		local hint = if choice == "vote" then "Tap a map to vote. One ballot is drawn when the fight starts."
			elseif choice == "random" then "A random map from the set is drawn when the fight starts."
			elseif host then "Tap the map to fight on." else "The host picks the map."
		label(self.body, hint, 24).Name = "MapHint"
		local grid = Instance.new("Frame")
		grid.Name, grid.BackgroundTransparency, grid.Size = "MapGrid", 1, UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize, grid.Parent = Enum.AutomaticSize.Y, self.body
		local gl = Instance.new("UIGridLayout")
		gl.CellSize, gl.CellPadding, gl.Parent = UDim2.fromOffset(150, 112), UDim2.fromOffset(6, 6), grid
		local tiles = { { id = "Random", name = "Random" } }
		for _, stage in Stages.LIST do
			if set ~= "ranked" or stage.ranked then table.insert(tiles, stage) end
		end
		for _, stage in tiles do
			local picked = if choice == "vote" then myVote == stage.id elseif choice == "host" then room.stage == stage.id else false
			local b = button(grid, "", function()
				if choice == "vote" then self:send("vote", stage.id)
				elseif choice == "host" and host then self:send("stage", stage.id) end
			end, picked)
			b.Name = "Stage_" .. stage.id
			local frame = Instance.new("Frame")
			frame.Name, frame.BackgroundTransparency, frame.ClipsDescendants = "StageImage", 1, true
			frame.Position, frame.Size, frame.Parent = UDim2.fromOffset(4, 4), UDim2.new(1, -8, 0, 76), b
			local name = label(b, (if picked then "✓ " else "") .. Realms.name(stage), 26)
			name.Name, name.Position = "MapName", UDim2.new(0, 0, 0, 82)
			if picked then name.TextColor3 = INK end
			if choice == "vote" and votes[stage.id] then
				local badge = label(b, `{votes[stage.id]} vote` .. (if votes[stage.id] == 1 then "" else "s"), 18)
				badge.Name, badge.Position, badge.Size = "Votes", UDim2.fromOffset(6, 6), UDim2.fromOffset(64, 18)
				badge.BackgroundTransparency, badge.BackgroundColor3, badge.TextSize = 0.1, INK, Ui.px(10)
			end
			table.insert(self.previews, { canvas = Canvas.inFrame(frame), stage = if stage.id ~= "Random" then stage else nil,
				random = stage.id == "Random", frame = frame })
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
	elseif self.page == "Rules" then
		-- The battle builder, after Brawlhalla's custom room: a preset sets everything at once, then
		-- each rule can still be changed on its own (which stops the preset matching).
		local function row(name: string, options: { { any } }, current: any, action: string)
			local bar = Instance.new("Frame")
			bar.Name, bar.BackgroundTransparency, bar.Size, bar.Parent = name, 1, UDim2.new(1, 0, 0, 40), self.body
			for i, opt in options do
				local b = button(bar, opt[2], function() if host then self:send(action, opt[1]) end end, current == opt[1])
				b.Name = `{name}_{opt[1]}`
				b.Position, b.Size = UDim2.new((i - 1) / #options, 2, 0, 0), UDim2.new(1 / #options, -4, 1, 0)
			end
		end
		label(self.body, "Presets", 22)
		local presets = {}
		for _, p in Rules.presets do table.insert(presets, { p.id, p.name }) end
		row("Preset", presets, room.preset, "preset")
		local on = nil
		for _, p in Rules.presets do if p.id == room.preset then on = p end end
		label(self.body, if on then on.hint else "Custom rules", 22).Name = "PresetHint"
		label(self.body, "Mode", 22)
		local modes = {}
		for _, m in Rules.modes do table.insert(modes, { m.id, m.name }) end
		row("Mode", modes, room.mode or "stock", "mode")
		if room.mode == "timed" then
			local times = {}
			for _, t in Rules.times do table.insert(times, { t, `{t // 60}:00` }) end
			row("Time", times, room.time, "time")
		else
			local lives = {}
			for _, n in Rules.stocks do table.insert(lives, { n, `{n} {if n == 1 then "life" else "lives"}` }) end
			row("Lives", lives, room.stocks, "stocks")
		end
		label(self.body, "Equal teams · bots OFF unless explicitly added below", 28)
		button(self.body, "Items: " .. (if room.items then "ON" else "OFF"), function() if host then self:send("items", not room.items) end end)
		-- Natural disasters. Off by default; "this map's own" runs the stage's signature disaster (if
		-- it has one), chaos adds the ones that work anywhere. Host-only like every shared rule.
		label(self.body, "Natural disasters", 28)
		for _, opt in { { "off", "Disasters: OFF" }, { "stage", "Disasters: THIS MAP'S OWN" }, { "chaos", "Disasters: CHAOS" } } do
			local b = button(self.body, opt[2], function() if host then self:send("disasters", opt[1]) end end, room.disasters == opt[1])
			b.Name = "Disasters_" .. opt[1]
		end
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
				RoomPanel.drawThumb(c, StageThumb.shapes(Realms.dress(preview.stage), size.X, size.Y))
			elseif preview.random then
				RoomPanel.drawThumb(c, StageThumb.random(size.X, size.Y))
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
