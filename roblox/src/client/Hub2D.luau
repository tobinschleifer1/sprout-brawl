--!strict
-- A playable 2D concourse, rendered by the same canvas and fighter art as the match.
-- World-space door signs are not clickable menu substitutes: interaction requires proximity.
local Shared = game:GetService("ReplicatedStorage").Shared
local UIS = game:GetService("UserInputService")
local HUB = require(Shared.Data.Hub)
local Lobby = require(Shared.Lobby)
local Loadout = require(Shared.Loadout)
local Snapshot = require(Shared.Snapshot)
local Input = require(Shared.Input)
local Config = require(Shared.Config)
local InputClient = require(script.Parent.InputClient)
local Canvas = require(script.Parent.Canvas2D)
local Backdrop = require(script.Parent.BackdropArt)
local Fighter2D = require(script.Parent.Fighter2D)
local Weapons = require(Shared.Data.Weapons)
local WeaponArt = require(script.Parent.Weapons2D)
local Hub2D = {}
Hub2D.__index = Hub2D
local INK = Color3.fromRGB(14, 20, 27)
local METAL = Color3.fromRGB(42, 53, 64)
local STEEL = Color3.fromRGB(97, 117, 125)
local AMBER = Color3.fromRGB(240, 177, 82)
local WHITE = Color3.fromRGB(231, 227, 209)

local function text(parent: Instance, name: string, value: string, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, value, Enum.Font.GothamBold, size
	t.TextColor3, t.BackgroundTransparency, t.TextWrapped = WHITE, 1, true
	t.Parent = parent
	return t
end
function Hub2D.new(parent: Instance): any
	local self = setmetatable({ active = false, held = false, camX = 0, labels = {}, peers = {}, onInteract = nil }, Hub2D)
	self.input = InputClient.new()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "BlockfallHub", false, true
	gui.DisplayOrder, gui.Enabled, gui.Parent = 12, false, parent
	self.gui = gui
	local title = text(gui, "Title", "THE IRON CONCOURSE", 22)
	title.Position, title.Size = UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 30)
	title.TextColor3 = AMBER
	self.title = title
	local directions = text(gui, "Directions", "1v1  ·  2v2  ·  3v3     —     walk to a portal to choose map, weapons and players", 12)
	directions.Position, directions.Size = UDim2.fromOffset(16, 44), UDim2.new(1, -32, 0, 32)
	self.directions = directions
	self:setSceneLabels(HUB)
	local controls = text(gui, "Movement", "WASD / arrows: move   •   Space / A: jump   •   E / X: interact", 13)
	controls.Position, controls.Size = UDim2.new(0, 12, 1, -40), UDim2.new(1, -24, 0, 32)
	local prompt = Instance.new("TextButton")
	prompt.Name, prompt.Font, prompt.TextSize = "Interact", Enum.Font.GothamBold, 16
	prompt.AnchorPoint = Vector2.new(0.5, 1)
	prompt.Position, prompt.Size = UDim2.new(0.5, 0, 1, -48), UDim2.new(1, -32, 0, 44)
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize, cap.Parent = Vector2.new(540, 44), prompt
	prompt.BackgroundColor3, prompt.BackgroundTransparency, prompt.BorderSizePixel = INK, 0.12, 0
	prompt.TextColor3, prompt.TextWrapped, prompt.Parent = AMBER, true, gui
	prompt.Activated:Connect(function() self:interact() end)
	self.prompt = prompt
	return self
end
function Hub2D.setSceneLabels(self: any, scene: any)
	for _, tag in self.labels do tag:Destroy() end
	self.labels = {}
	for _, station in scene.stations do
		local value = station.name .. (if station.landmark then "\n" .. station.landmark else "")
		local tag = text(self.gui, station.id, value, 15)
		tag.TextColor3 = Canvas.hex(station.color, AMBER)
		self.labels[station.id] = tag
	end
	self.title.Text = string.upper(scene.name)
end
function Hub2D.setRoom(self: any, room: any)
	local nextRoom = if room and not room.left then room else nil
	local oldId = if self.room then self.room.id else 0
	local nextId = if nextRoom then nextRoom.id else 0
	self.room = nextRoom
	if oldId ~= nextId then
		if oldId == 0 then self.returnX = self.model.fighter.x end
		local scene = if nextRoom then HUB.rooms[nextRoom.format] else HUB
		self.model:setScene(scene)
		if nextId == 0 and self.returnX then self.model.fighter.x = self.returnX end
		self.camX = self.model.fighter.x
		self:setSceneLabels(scene)
		self:setPeers({}, 0)
		self.input:reset()
		self.held = true
	end
	self.gui:SetAttribute("Scene", self.model.data.id)
	self.gui:SetAttribute("RoomId", nextId)
	if nextRoom then
		local ready, humans, bots = 0, 0, 0
		for _, slot in nextRoom.slots do
			if slot.userId then humans += 1; if slot.ready then ready += 1 end end
			if slot.bot then bots += 1 end
		end
		self.directions.Text = nextRoom.error or `{ready}/{humans} players ready · {bots} CPUs · Map: {nextRoom.stage} · Walk to a station; exit left`
	else
		self.directions.Text = "1v1  ·  2v2  ·  3v3     —     walk to a gate to prepare your fight"
	end
end
function Hub2D.configure(self: any, cfg: any)
	local sl = cfg.slots[1]
	local key = sl.avatarId .. "/" .. sl.weaponId
	if key == self.loadout then return end
	self.char = Loadout.build(sl.avatarId, sl.weaponId)
	if self.model then self.model:setLoadout(self.char) else self.model = Lobby.new(self.char) end
	self.loadout = key
end
function Hub2D.show(self: any, cfg: any)
	self:configure(cfg)
	self.active, self.gui.Enabled, self.blocked = true, true, false
	self.input:reset()
	self:setRoom(nil)
	-- A held interaction key must be released before another station opens.
	self.held = true
end
function Hub2D.hide(self: any)
	self.active, self.gui.Enabled = false, false
end
function Hub2D.setPeers(self: any, entries: any, localId: number)
	local present = {}
	for _, entry in entries do
		if entry.userId ~= localId and (entry.area or 0) == (if self.room then self.room.id else 0) then
			local key = entry.avatar .. "/" .. entry.weapon
			local peer = self.peers[entry.userId]
			if not peer then
				peer = { x = entry.x, y = entry.y, tag = text(self.gui, "Player_" .. entry.userId, entry.name, 12) }
				self.peers[entry.userId] = peer
			end
			if peer.key ~= key then
				peer.char = Loadout.build(entry.avatar, entry.weapon)
				peer.state = Snapshot.decode(Snapshot.encode(Lobby.new(peer.char).fighter))
				peer.key = key
			end
			peer.target, present[entry.userId] = entry, true
		end
	end
	for id, peer in self.peers do
		if not present[id] then peer.tag:Destroy(); self.peers[id] = nil end
	end
end
function Hub2D.interact(self: any)
	if not self.active or self.blocked or UIS:GetFocusedTextBox() then return end
	local station = self.model:nearest()
	if station and self.onInteract then self.onInteract(station) end
end
function Hub2D.step(self: any, dt: number, blocked: boolean)
	if not self.active then return end
	self.blocked = blocked
	for _, frame in self.input:sample(dt, Config.FRAME) do
		self.model:step(if blocked then Input.emptyFrame() else frame)
	end
	local down = not UIS:GetFocusedTextBox() and (UIS:IsKeyDown(Enum.KeyCode.E)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX))
	if down and not self.held then self:interact() end
	self.held = down
end

local function stationArt(c: any, s: any, active: boolean)
	local color = Canvas.hex(s.color, AMBER)
	local x = s.x
	Canvas.rect(c, x - 7, 0, 14, 0.5, color, 0.6)
	if s.kind == "Format" then
		-- Stepped doorway, heavy jambs, inset glow and a small outline of the actual arena.
		Canvas.rect(c, x - 6, 0, 12, 13, METAL)
		Canvas.rect(c, x - 4.5, 0, 9, 12, INK)
		Canvas.rect(c, x - 5.8, 0, 0.6, 12, color)
		Canvas.rect(c, x + 5.2, 0, 0.6, 12, color)
		Canvas.rect(c, x - 4, 12, 8, 1.2, color)
		Canvas.rect(c, x - 2.5, 13.2, 5, 0.5, color)
		-- Different machinery silhouettes, not three recoloured copies of one gate.
		for n = 1, s.teamSize do
			local bx = x + (n - (s.teamSize + 1) / 2) * 3
			Canvas.rect(c, bx - 0.7, 14, 1.4, 2 + s.teamSize, STEEL)
			Canvas.rect(c, bx - 0.35, 14.5, 0.7, 0.8, color)
		end
		Canvas.rect(c, x - 4, 1, 8, 10, color, if active then 0.22 else 0.08)
		for n = 1, s.teamSize do
			for _, side in {-1, 1} do
				Canvas.rect(c, x + side * 2 - 0.4, 3 + n * 2, 0.8, 1.4, color)
				Canvas.rect(c, x + side * 2 - 0.5, 4.5 + n * 2, 1, 0.8, WHITE)
			end
		end
	else
		Canvas.rect(c, x - 6, 0, 12, 5, METAL)
		Canvas.rect(c, x - 6.5, 4.5, 13, 0.8, STEEL)
		Canvas.rect(c, x - 5, 0.8, 10, 0.4, color)
		if s.kind == "Weapons" then
			Canvas.rect(c, x - 8, 5.3, 16, 9, INK)
			for i, weapon in Weapons.LIST do
				Canvas.save(c)
				Canvas.translate(c, x - 6 + ((i - 1) % 4) * 4, 7 + math.floor((i - 1) / 4) * 2.6)
				Canvas.scale(c, 0.45, 0.45)
				WeaponArt.draw(c, weapon.id, weapon.palette, { angle = 0.2, ox = 0, oy = 0, scale = 1, charge = 0 })
				Canvas.restore(c)
			end
		elseif s.kind == "Exit" then
			Canvas.rect(c, x - 4, 0, 8, 12, INK)
			Canvas.rect(c, x - 4.5, 0, 0.5, 13, color)
			Canvas.rect(c, x + 4, 0, 0.5, 13, color)
		elseif s.kind == "Looks" then
			for n = -1, 1 do
				Canvas.rect(c, x + n * 3 - 1.2, 5.3, 2.4, 7, STEEL)
				Canvas.rect(c, x + n * 3 + 0.5, 8, 0.2, 1, color)
			end
		elseif s.kind == "Loadout" then
			Canvas.rect(c, x - 3, 5.3, 6, 1, INK)
			Canvas.rect(c, x - 1.5, 6.3, 3, 1, STEEL)
			Canvas.rect(c, x - 0.3, 7.3, 0.6, 5, WHITE)
			Canvas.rect(c, x - 1.5, 8, 3, 0.5, color)
		elseif s.kind == "Opponents" then
			for n = -1, 1 do
				Canvas.rect(c, x + n * 3 - 0.7, 5.3, 1.4, 2.5, color)
				Canvas.rect(c, x + n * 3 - 0.9, 8, 1.8, 1.8, color)
			end
		else
			Canvas.rect(c, x - 4, 5.3, 8, 6, INK)
			for n = 1, 4 do Canvas.rect(c, x - 3, 5.5 + n, 4 + n % 2, 0.3, color) end
		end
	end
	if active then
		Canvas.rect(c, x - 2, 0.6, 4, 0.3, WHITE)
		Canvas.rect(c, x - 1, 1, 2, 0.3, WHITE)
	end
end

function Hub2D.draw(self: any, c: any, dt: number)
	local f = self.model.fighter
	local scene = self.model.data
	local vp = c:viewport()
	local ppu = math.clamp(vp.Y / 60, 5, 16)
	local half = vp.X / ppu / 2
	local margin = math.min(half, (scene.main.x2 - scene.main.x1) / 2)
	local cameraTarget = math.clamp(f.x + f.facing * 5, scene.main.x1 + margin, scene.main.x2 - margin)
	self.camX += (cameraTarget - self.camX) * math.min(1, dt * 8)
	Backdrop.sky(c, "FoundryFloor", self.camX)
	c:world(self.camX, 14, ppu, 0, 0)
	local left, right = self.camX - half - 20, self.camX + half + 20
	-- Factory shell: repeated structural bays, pipes, low light and textured steel decking.
	for x = math.floor(left / 14) * 14, right, 14 do
		Canvas.rect(c, x, 0, 1.3, 37, INK, 0.75)
		Canvas.rect(c, x - 0.4, 0, 2.1, 1.2, STEEL)
		Canvas.rect(c, x, 30, 14, 0.6, METAL)
		Canvas.rect(c, x + 3, 29.2, 5, 0.3, AMBER, 0.4)
	end
	Canvas.rect(c, scene.main.x1, -9, scene.main.x2 - scene.main.x1, 9, METAL)
	Canvas.rect(c, scene.main.x1, -0.6, scene.main.x2 - scene.main.x1, 0.6, STEEL)
	for x = math.floor(left / 4) * 4, right, 4 do
		Canvas.rect(c, x, -5, 0.16, 4.2, INK)
		Canvas.rect(c, x + 0.7, -1.5, 0.25, 0.25, AMBER, 0.4)
	end
	for _, s in scene.stations do
		local tag = self.labels[s.id]
		local visible = s.x > left and s.x < right
		tag.Visible = visible
		if visible then
			stationArt(c, s, self.model:nearest() == s)
			local at = c:project(s.x, 15.5)
			tag.Position, tag.Size = UDim2.fromOffset(at.X - 12 * ppu, at.Y - 16), UDim2.fromOffset(24 * ppu, 36)
			tag.TextSize = math.clamp(ppu * 1.2, 11, 18)
		end
	end
	for _, p in scene.platforms do
		if p.x + p.w / 2 > left and p.x - p.w / 2 < right then
			Canvas.rect(c, p.x - p.w / 2, p.y - 0.5, p.w, 0.5, STEEL)
			Canvas.rect(c, p.x - p.w / 2, p.y - 1, p.w, 0.5, INK)
		end
	end
	local state = Snapshot.decode(Snapshot.encode(f))
	for _, peer in self.peers do
		local target = peer.target
		local blend = math.min(1, dt * 14)
		peer.x += (target.x - peer.x) * blend
		peer.y += (target.y - peer.y) * blend
		local st = peer.state
		st.x, st.y, st.facing = peer.x, peer.y, target.facing
		st.vx = if target.moving then target.facing * 20 else 0
		st.state = if peer.y > 0.1 then "air" else if target.moving then "run" else "idle"
		st.onGround = peer.y <= 0.1
		peer.tag.Visible = peer.x > left and peer.x < right
		if peer.tag.Visible then
			Fighter2D.draw(c, st, peer.char, os.clock(), 0)
			local at = c:project(peer.x, peer.y + peer.char.height + 2)
			peer.tag.Position, peer.tag.Size = UDim2.fromOffset(at.X - 70, at.Y - 14), UDim2.fromOffset(140, 26)
		end
	end
	Fighter2D.draw(c, state, self.char, os.clock(), 0)
	c:finish()
	local near = self.model:nearest()
	self.prompt.Text = if self.blocked then "Finish at the station, then return to the concourse."
		elseif near then `[E / X]  {if near.kind == "Format" or near.kind == "Exit" then "ENTER" else "USE"} {near.name}`
		else "Run to a door or station to choose your next fight."
	self.prompt.Active = not self.blocked and near ~= nil
	self.gui:SetAttribute("NearbyStation", if near then near.id else "")
	self.gui:SetAttribute("FighterX", f.x)
	self.gui:SetAttribute("FighterY", f.y)
end
return Hub2D
