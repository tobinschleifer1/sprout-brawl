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
local StageThumb = require(script.Parent.StageThumb)
local Stages = require(Shared.Data.Stages)
local KIT: any = require(Shared.Data.AvatarKit)
local Hub2D = {}
Hub2D.__index = Hub2D
local INK = Color3.fromRGB(14, 20, 27)
local METAL = Color3.fromRGB(42, 53, 64)
local STEEL = Color3.fromRGB(97, 117, 125)
local AMBER = Color3.fromRGB(240, 177, 82)
local WHITE = Color3.fromRGB(231, 227, 209)
local READY = Color3.fromRGB(96, 200, 110)
local TEAM1 = Color3.fromRGB(62, 138, 46)
local TEAM2 = Color3.fromRGB(222, 98, 28)
local GLASS = Color3.fromRGB(24, 38, 54)
-- The wardrobe's two mannequins wear the ready-made characters in turn, a new pair every few
-- seconds: the station shows what the studio can make before anyone opens it.
local MANNEQUIN_SECONDS = 4

local function text(parent: Instance, name: string, value: string, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, value, Enum.Font.GothamBold, size
	t.TextColor3, t.BackgroundTransparency, t.TextWrapped = WHITE, 1, true
	t.Parent = parent
	return t
end
-- The map this room will fight on as far as anyone can tell yet: the host's pick, the leading
-- ballot when the room votes (ties to the earliest ballot), or nil for Random.
local function shownMap(room: any): any
	if not room then return nil end
	local id = room.stage
	if room.mapChoice == "random" then return nil end
	if room.mapChoice == "vote" then
		local count, best, bestN = {}, nil, 0
		for _, slot in room.slots or {} do
			if slot.vote then
				count[slot.vote] = (count[slot.vote] or 0) + 1
				if count[slot.vote] > bestN then best, bestN = slot.vote, count[slot.vote] end
			end
		end
		id = best or id
	end
	for _, stage in Stages.LIST do
		if stage.id == id then return stage end
	end
	return nil
end
Hub2D.shownMap = shownMap

function Hub2D.new(parent: Instance): any
	local self: any = setmetatable({ active = false, held = false, camX = 0, labels = {}, peers = {}, onInteract = nil }, Hub2D)
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
	-- The character studio, one click away anywhere on the concourse (the wardrobe station is the
	-- in-world way in). Not in a fight's preparation room: characters are made in the lobby.
	local character = Instance.new("TextButton")
	character.Name, character.Font, character.TextSize = "CharacterButton", Enum.Font.GothamBold, 15
	character.AnchorPoint = Vector2.new(1, 0)
	character.Position, character.Size = UDim2.new(1, -16, 0, 12), UDim2.fromOffset(150, 38)
	character.BackgroundColor3, character.BorderSizePixel = Color3.fromRGB(28, 60, 78), 0
	character.TextColor3, character.Text, character.Parent = Color3.fromRGB(127, 212, 255), "CHARACTER", gui
	local round = Instance.new("UICorner")
	round.CornerRadius, round.Parent = UDim.new(0, 8), character
	character.Activated:Connect(function()
		if self.active and not self.blocked and self.onCharacter then self.onCharacter() end
	end)
	self.characterButton = character
	self.mannequins = {}
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
	self.characterButton.Visible = nextRoom == nil
	self.gui:SetAttribute("Scene", self.model.data.id)
	self.gui:SetAttribute("RoomId", nextId)
	if nextRoom then
		local ready, humans, bots = 0, 0, 0
		for _, slot in nextRoom.slots do
			if slot.userId then humans += 1; if slot.ready then ready += 1 end end
			if slot.bot then bots += 1 end
		end
		local shown = shownMap(nextRoom)
		local map = if nextRoom.mapChoice == "random" then "Random map"
			elseif nextRoom.mapChoice == "vote" then (if shown then `Vote: {shown.name} leads` else "Vote for a map")
			else (if shown then shown.name else "Random map")
		local rules = if nextRoom.mode == "timed" then `Timed {(nextRoom.time or 180) // 60} min` else `{nextRoom.stocks or 3} lives`
		self.directions.Text = nextRoom.error or `{ready}/{humans} ready · {bots} CPUs · {map} · {rules} · walk to a station; exit left`
	else
		self.directions.Text = "1v1  ·  2v2  ·  3v3     —     walk to a gate to prepare your fight  ·  the wardrobe makes your character"
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


-- A thumbnail (StageThumb shapes, pixels y-down) fitted into a world-space rectangle.
local function boardThumb(c: any, shapes: { any }, x0: number, y0: number, w: number, h: number, K: number)
	Canvas.save(c)
	Canvas.translate(c, x0, y0 + h)
	Canvas.scale(c, 1 / K, -1 / K)
	for _, sh in shapes do
		Canvas.rect(c, sh[2], sh[3], sh[4], sh[5], Canvas.hex(sh[6], INK), sh[7])
	end
	Canvas.restore(c)
end

local function stationArt(c: any, s: any, active: boolean, room: any, weaponId: string?)
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
				if weapon.id == weaponId then
					-- your own weapon, framed, so the rack answers "what am I holding"
					local gx, gy = x - 6 + ((i - 1) % 4) * 4, 7 + math.floor((i - 1) / 4) * 2.6
					Canvas.rect(c, gx - 1.6, gy - 1.1, 3.4, 2.4, AMBER, 0.9)
					Canvas.rect(c, gx - 1.4, gy - 0.9, 3.0, 2.0, INK)
				end
				Canvas.save(c)
				Canvas.translate(c, x - 6 + ((i - 1) % 4) * 4, 7 + math.floor((i - 1) / 4) * 2.6)
				Canvas.scale(c, 0.45, 0.45)
				WeaponArt.draw(c, weapon.id, weapon.palette, { angle = 0.2, ox = 0, oy = 0, scale = 1, charge = 0 })
				Canvas.restore(c)
			end
		elseif s.kind == "Wardrobe" then
			-- A boutique bay: a back wall, a lit mirror in the middle (your reflection is drawn in
			-- it by Hub2D.drawWardrobe) and a pedestal either side for the mannequins.
			Canvas.rect(c, x - 8, 0, 16, 13, INK)
			Canvas.rect(c, x - 8.5, 13, 17, 0.8, METAL)
			Canvas.rect(c, x - 7, 12.3, 14, 0.3, color, 0.8)
			Canvas.rect(c, x - 7.5, 11, 15, 0.25, STEEL)
			for n = -3, 3 do
				Canvas.rect(c, x + n * 2 - 0.08, 10.2, 0.16, 0.8, STEEL)
			end
			Canvas.rect(c, x - 2.7, 0.5, 5.4, 9.2, color)
			Canvas.rect(c, x - 2.3, 0.9, 4.6, 8.4, GLASS)
			for _, side in { -1, 1 } do
				Canvas.rect(c, x + side * 5.5 - 1.7, 0, 3.4, 0.7, STEEL)
				Canvas.rect(c, x + side * 5.5 - 1.2, 0.7, 2.4, 0.2, color, 0.6)
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
		elseif s.kind == "Maps" then
			-- The map board shows the map: the pick, the leading ballot, or the Random die.
			Canvas.rect(c, x - 5.6, 5.3, 11.2, 7.6, INK)
			local stage = shownMap(room)
			local K = 10
			boardThumb(c, if stage then StageThumb.shapes(stage, 100, 64) else StageThumb.random(100, 64), x - 5, 5.7, 10, 6.4, K)
		elseif s.kind == "Players" then
			-- The ready rail: a light per place, green when ready, amber when waiting, dark when open.
			Canvas.rect(c, x - 6, 5.3, 12, 4, INK)
			local slots = if room then room.slots else {}
			local n = math.max(1, #slots)
			for i = 1, n do
				local slot = slots[i]
				local lx = x - 5 + (i - 0.5) * (10 / n)
				local lamp = if not slot or (not slot.userId and not slot.bot) then METAL
					elseif slot.ready or slot.bot then READY else AMBER
				Canvas.rect(c, lx - 0.6, 6.4, 1.2, 1.8, lamp)
				Canvas.rect(c, lx - 0.9, 8.4, 1.8, 0.3, if slot and slot.team == 1 then TEAM2 else TEAM1)
			end
		elseif s.kind == "Rules" then
			-- The rules board: a pip per life, or a clock face for a timed fight.
			Canvas.rect(c, x - 4, 5.3, 8, 6, INK)
			if room and room.mode == "timed" then
				Canvas.circle(c, x, 8.3, 2.2, color)
				Canvas.circle(c, x, 8.3, 1.8, INK)
				Canvas.rect(c, x - 0.15, 8.3, 0.3, 1.4, WHITE)
				Canvas.rect(c, x, 8.15, 1.1, 0.3, WHITE)
			else
				local lives = if room then room.stocks or 3 else 3
				for i = 1, lives do
					Canvas.rect(c, x - 3.4 + (i - 1) * 1.5, 7.6, 1.1, 1.1, color)
				end
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

-- The wardrobe's living parts, drawn over its structure: two mannequins in ready-made characters,
-- and your own character in the mirror, facing back at you and moving as you move.
function Hub2D.drawWardrobe(self: any, c: any, s: any, state: any, clock: number)
	local presets = KIT.presets
	local turn = math.floor(clock / MANNEQUIN_SECONDS)
	for k, side in { -1, 1 } do
		local code = presets[(turn * 2 + k) % #presets + 1].code
		local m = self.mannequins[k]
		if not m or m.code ~= code then
			-- Empty-handed: a mannequin displays clothes, and twelve swords in a boutique read as
			-- an armoury. The pose code already handles a character with no weapon.
			local char = table.clone(Loadout.build(code, "Sword"))
			char.weapon = nil
			m = { code = code, char = char, state = Snapshot.decode(Snapshot.encode(Lobby.new(char).fighter)) }
			self.mannequins[k] = m
		end
		local st = m.state
		st.x, st.y, st.facing, st.state, st.onGround, st.vx = s.x + side * 5.5, 0.9, -side, "idle", true, 0
		Fighter2D.draw(c, st, m.char, clock + k * 0.7, 0.9)
	end
	if self.char then
		local r = Snapshot.decode(Snapshot.encode(self.model.fighter))
		r.x, r.y, r.facing = s.x, 1.0 + math.max(0, state.y) * 0.3, -state.facing
		Fighter2D.draw(c, r, self.char, clock, 1.0)
	end
	-- The glass over the reflection: a tint and two sheen strokes.
	Canvas.rect(c, s.x - 2.3, 0.9, 4.6, 8.4, Canvas.hex(s.color, AMBER), 0.10)
	Canvas.rect(c, s.x - 1.6, 6.8, 0.25, 2.2, WHITE, 0.25)
	Canvas.rect(c, s.x - 1.1, 7.6, 0.2, 1.3, WHITE, 0.18)
end

function Hub2D.draw(self: any, c: any, dt: number)
	-- Team colours are a match's; the concourse and its rooms are not one.
	local teams = Fighter2D.teamColours
	Fighter2D.teamColours = nil
	self:drawScene(c, dt)
	Fighter2D.teamColours = teams
end

function Hub2D.drawScene(self: any, c: any, dt: number)
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
			stationArt(c, s, self.model:nearest() == s, self.room, self.char and self.char.weapon and self.char.weapon.id)
			if s.kind == "Wardrobe" then
				self:drawWardrobe(c, s, Snapshot.decode(Snapshot.encode(f)), os.clock())
			end
			-- Above the door's signal posts (they reach 14 + 2 + team size), not through them.
			local at = c:project(s.x, if s.kind == "Format" then 21 else 16.5)
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
