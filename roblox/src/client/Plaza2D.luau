--!strict
-- The lobby: the Skyhold Bazaar, a market on floating islands walked beat-'em-up style (Plaza.luau
-- is the walking, Data/Plaza the map), and the private lounges fights are prepared in. In Roblox it
-- is drawn as a realm (Realms.LOBBY) to match the arenas; the web's Neon Row data is its map.
--
-- Drawing, back to front: the realm's sky; every plaza (the island it stands on hanging below its
-- front edge, its paving, its low back wall) and the plank bridges between; then every prop
-- and person SORTED BY DEPTH, so a player walking behind a cabinet is hidden by it and one walking
-- in front covers it; then the front railings. A point at depth z is lifted z * DEPTH on screen,
-- which is the whole of the perspective: characters keep their side-on art and are never scaled.
--
-- Props are pixel art built once (PlazaArt) and drawn as sprites; people are drawn by Fighter2D,
-- exactly as they fight. Labels (station names, stall signs, name tags) are TextLabels projected
-- from world points, pooled and hidden when unused.

local Shared = game:GetService("ReplicatedStorage").Shared
local UIS = game:GetService("UserInputService")
local Plaza = require(Shared.Plaza)
local Loadout = require(Shared.Loadout)
local Input = require(Shared.Input)
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Stages = require(Shared.Data.Stages)
local KIT: any = require(Shared.Data.AvatarKit)
local InputClient = require(script.Parent.InputClient)
local Canvas = require(script.Parent.Canvas2D)
local Fighter2D = require(script.Parent.Fighter2D)
local WeaponArt = require(script.Parent.Weapons2D)
local StageThumb = require(script.Parent.StageThumb)
local Realms = require(Shared.Realms)
local PlazaArt = require(script.Parent.PlazaArt)
local RealmArt = require(script.Parent.RealmArt)
local PosedFighter = require(script.Parent.PosedFighter)
local Ui = require(script.Parent.Ui)

local PLAZA: any = Plaza.DATA
local D = PLAZA.depth :: number
local A = PlazaArt.C

local Plaza2D = {}
Plaza2D.__index = Plaza2D

local INK = Color3.fromRGB(15, 18, 24)
local WHITE = Color3.fromRGB(230, 225, 214)
local AMBER = Color3.fromRGB(232, 162, 74)
local CYAN = Color3.fromRGB(127, 168, 184)
local PINK = Color3.fromRGB(200, 100, 60)
local METAL = Color3.fromRGB(38, 43, 53)
local STEEL = Color3.fromRGB(110, 119, 136)
local FENCE = Color3.fromHex(A.woodDk)
local FENCE_HI = Color3.fromHex(A.woodHi)
local READY = Color3.fromRGB(127, 190, 110)
local TEAM1 = Color3.fromRGB(62, 138, 46)
local TEAM2 = Color3.fromRGB(222, 98, 28)
local MANNEQUIN_SECONDS = 4

-- Where things stand in the market, beyond the stations themselves. Depths behind the floor's back
-- edge (18) stand on the parapet line, drawn over the roof and under everyone walking on it.
local STALLS = {
	{ x = -62, sign = "RAMEN", goods = "bowls", a = A.lantern, b = A.paper, vendor = "samurai" },
	{ x = -28, sign = "MASKS", goods = "masks", a = A.pink, b = A.white, vendor = "ninja" },
	{ x = 28, sign = "SKEWERS", goods = "skewers", a = A.amber, b = A.woodDk, vendor = "cowboy" },
	{ x = 62, sign = "GADGETS", goods = "gadgets", a = A.cyan, b = A.slate, vendor = "robot" },
}
local STALL_Z = 18.8
Plaza2D.STALLS = STALLS

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
Plaza2D.shownMap = shownMap

-- The top row, below Roblox's top bar (its menu and chat buttons sit at the top left). Placed again
-- whenever that bar's height changes: it is still 0 when the client starts and builds this HUD,
-- which in a playtest left the title under Roblox's buttons.
function Plaza2D.placeTop(self: any, inset: number)
	if self.inset == inset then return end
	self.inset = inset
	self.title.Position = UDim2.fromOffset(18, inset + 6)
	self.directions.Position = UDim2.fromOffset(18, inset + 38)
end

-- The bottom row's right end: the CHARACTER button, and LobbySocial's button bar to its left
-- (LobbySocial.RIGHT_GAP leaves the button its room). The controls row stays clear of the lot.
Plaza2D.CHARACTER_W = 168
Plaza2D.SOCIAL_BAR_W = 4 * 124 - 8 + 8 + Plaza2D.CHARACTER_W

-- ------------------------------------------------------------------ construction ----
function Plaza2D.new(parent: Instance): any
	local self: any = setmetatable({ active = false, held = false, camX = 0, peers = {}, pool = {}, used = {},
		mannequins = {}, vendors = {}, onInteract = nil, onCharacter = nil, blocked = false, bannerAt = -10 }, Plaza2D)
	self.input = InputClient.new()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "BlockfallHub", false, true
	gui.DisplayOrder, gui.Enabled, gui.Parent = 12, false, parent
	self.gui = gui
	-- The HUD is the shared cartoon kit (Ui): outlined display words, bevelled buttons, key caps.
	local title = Ui.text(gui, string.upper(Realms.LOBBY.name), 26, Ui.GOLD, Ui.DISPLAY)
	title.Name = "Title"
	title.Size = UDim2.new(1, -220, 0, 32)
	title.TextXAlignment = Enum.TextXAlignment.Left
	self.title = title
	local directions = Ui.text(gui, "", 13, Ui.WHITE)
	directions.Name = "Directions"
	directions.Size = UDim2.new(1, -220, 0, 20)
	directions.TextXAlignment = Enum.TextXAlignment.Left
	self.directions = directions
	-- The district you walked into, large, for a moment.
	local banner = Ui.text(gui, "", 44, Ui.CYAN, Ui.DISPLAY)
	banner.Name = "District"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position, banner.Size = UDim2.new(0.5, 0, 0, 70), UDim2.fromOffset(700, 52)
	banner.TextTransparency = 1
	self.banner = banner
	self.bannerOutline = Ui.outline(banner, 4)
	self.bannerOutline.Transparency = 1
	-- How to move, as key caps along the bottom.
	-- (centred in the room the social bar leaves at the bottom right; hidden where it does not fit)
	local controls, controlsW = Ui.hintRow(gui, "Movement", { { "A D", "WALK" }, { "W S", "STEP IN / OUT" }, { "SPACE", "HOP" }, { "E", "USE" } }, 24)
	controls.Position, controls.Size = UDim2.new(0, 16, 1, -39), UDim2.new(1, -Plaza2D.SOCIAL_BAR_W - 48, 0, 26)
	self.controls, self.controlsW = controls, controlsW
	-- What you can do here: a card with the E key on it beside a station, or a tip when there is
	-- nothing in reach (the cap hides, the words soften).
	local prompt = Ui.make("TextButton", gui, { Name = "Interact", Font = Ui.DISPLAY, TextSize = 22, TextColor3 = Ui.GOLD,
		BackgroundColor3 = Ui.PANEL, BackgroundTransparency = 0.04, BorderSizePixel = 0, AutoButtonColor = false, TextWrapped = true })
	prompt.AnchorPoint = Vector2.new(0.5, 1)
	prompt.Position, prompt.Size = UDim2.new(0.5, 0, 1, -62), UDim2.new(1, -32, 0, 50)
	Ui.make("UISizeConstraint", prompt, { MaxSize = Vector2.new(596, 50) })
	Ui.corner(prompt, 12)
	self.promptEdge = Ui.stroke(prompt, Ui.INK, 3)
	self.promptOutline = Ui.outline(prompt, 2)
	self.promptPad = Ui.make("UIPadding", prompt, { PaddingLeft = UDim.new(0, 64), PaddingRight = UDim.new(0, 16) })
	local key = Ui.keycap(prompt, "E", 20)
	key.Position, key.Size = UDim2.new(0, 12, 0.5, -18), UDim2.fromOffset(36, 34)
	self.promptKey = key
	prompt.Activated:Connect(function() self:interact() end)
	self.prompt = prompt
	local character = Ui.button(gui, "CHARACTER", Ui.BLUE, function()
		if self.active and not self.blocked and self.onCharacter then self.onCharacter() end
	end)
	character.Name = "CharacterButton"
	-- At the bottom right, in the row with the social buttons. Not the top right: Roblox's player list
	-- hangs there under its top bar, and in a playtest the button could not be clicked through it.
	character.AnchorPoint = Vector2.new(1, 1)
	character.Position, character.Size = UDim2.new(1, -16, 1, -10), UDim2.fromOffset(Plaza2D.CHARACTER_W, 42)
	self.characterButton = character
	-- Alone at a cabinet: take on the CPU (also C).
	local cpu = Ui.keyButton(gui, "C", "VS CPU", Ui.PURPLE, function()
		if self.active and not self.blocked and self.onCabinet then self.onCabinet({ action = "cpu" }) end
	end, 42)
	cpu.Name, cpu.Visible = "CpuButton", false
	cpu.AnchorPoint = Vector2.new(0.5, 1)
	cpu.Position, cpu.Size = UDim2.new(0.5, 0, 1, -126), UDim2.fromOffset(190, 42)
	self.cpuButton = cpu
	self.cabinets = {}
	self.labelLayer = gui
	self:placeTop(Ui.topInset())
	return self
end

-- ------------------------------------------------------------------ labels ----
-- World labels are pooled by id: `label` claims one for this frame, `endLabels` hides the rest.
function Plaza2D.label(self: any, id: string, value: string, size: number, colour: Color3): TextLabel
	local t = self.pool[id]
	if not t then
		t = text(self.labelLayer, "Label_" .. id, value, size)
		t.TextStrokeTransparency = 0.55
		self.pool[id] = t
	end
	t.Text, t.TextColor3, t.Visible = value, colour, true
	self.used[id] = true
	return t
end

function Plaza2D.placeLabel(self: any, c: any, id: string, value: string, x: number, y: number, size: number, colour: Color3, width: number?)
	local at = c:project(x, y)
	local t = self:label(id, value, size, colour)
	local w = width or 260
	t.TextSize = size
	t.Position, t.Size = UDim2.fromOffset(at.X - w / 2, at.Y - size * 1.2), UDim2.fromOffset(w, size * 2.4)
	return t
end

-- A speech bubble: a pooled label styled once, sized to its text.
function Plaza2D.bubble(self: any, c: any, id: string, value: string, x: number, y: number, alpha: number)
	local t = self:label(id, value, 14, INK)
	self.styled = self.styled or {}
	if not self.styled[id] then
		self.styled[id] = true
		t.BackgroundColor3 = Color3.fromRGB(246, 242, 232)
		t.TextStrokeTransparency = 1
		local r = Instance.new("UICorner")
		r.CornerRadius, r.Parent = UDim.new(0, 8), t
	end
	local at = c:project(x, y)
	local w = #value * 8 + 26
	t.Position, t.Size = UDim2.fromOffset(at.X - w / 2, at.Y - 30), UDim2.fromOffset(w, 28)
	t.BackgroundTransparency = 1 - 0.95 * alpha
	t.TextTransparency = 1 - alpha
end

-- What someone just stamped or said, over their head (LobbySocial keeps who and since when).
function Plaza2D.drawOverhead(self: any, c: any, userId: number, x: number, headY: number)
	local social = self.social
	if not social then return end
	local o, age, life = social:overhead(userId)
	if not o then return end
	local fade = math.clamp((life - age) / 0.4, 0, 1)
	if o.kind == "stamp" then
		local stamp
		for _, st in PLAZA.stamps do if st.id == o.id then stamp = st end end
		if not stamp then return end
		local prop = PlazaArt.stamp(stamp)
		-- A pop: overshoot, settle, and a slow bob while it is up.
		local pop = if age < 0.18 then 0.5 + age / 0.18 * 0.75 elseif age < 0.32 then 1.25 - (age - 0.18) / 0.14 * 0.25 else 1
		local k = 0.17 * pop
		local y = headY + 0.8 + math.sin(age * 5) * 0.12
		Canvas.sprite(c, "ovh|" .. o.id, prop.rects, x - prop.w * k / 2, y + prop.h * k, k, k, prop.w, prop.h, fade)
	else
		self:bubble(c, "bub" .. userId, o.text, x, headY + 2.6, fade)
	end
end

function Plaza2D.endLabels(self: any)
	for id, t in self.pool do
		if not self.used[id] then t.Visible = false end
	end
	table.clear(self.used)
end

-- ------------------------------------------------------------------ state ----
function Plaza2D.configure(self: any, cfg: any)
	local sl = cfg.slots[1]
	local key = sl.avatarId .. "/" .. sl.weaponId
	if key == self.loadout then return end
	self.char = Loadout.build(sl.avatarId, sl.weaponId)
	self.loadout = key
	if not self.model then self.model = Plaza.new(PLAZA.market) end
end

function Plaza2D.show(self: any, cfg: any)
	self:configure(cfg)
	self.active, self.gui.Enabled, self.blocked = true, true, false
	self.input:reset()
	self:setRoom(nil)
	self.held = true                                  -- a held key must be released first
end

function Plaza2D.hide(self: any)
	self.active, self.gui.Enabled = false, false
end

function Plaza2D.setRoom(self: any, room: any)
	local nextRoom = if room and not room.left then room else nil
	local oldId = if self.room then self.room.id else 0
	local nextId = if nextRoom then nextRoom.id else 0
	self.room = nextRoom
	if oldId ~= nextId then
		if oldId == 0 then self.returnAt = { x = self.model.p.x, z = self.model.p.z } end
		local scene = if nextRoom then PLAZA.rooms[nextRoom.format] else PLAZA.market
		self.model:setScene(scene, if nextId == 0 then self.returnAt else nil)
		self.camX = self.model.p.x
		self:setPeers({}, 0)
		self.input:reset()
		self.held = true
		self.district = nil
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
			elseif nextRoom.mapChoice == "vote" then (if shown then `Vote: {Realms.name(shown)} leads` else "Vote for a map")
			else (if shown then Realms.name(shown) else "Random map")
		local rules = if nextRoom.mode == "timed" then `Timed {(nextRoom.time or 180) // 60} min` else `{nextRoom.stocks or 3} lives`
		self.title.Text = string.upper(Realms.place("lounge", self.model.data.name))
		self.directions.Text = nextRoom.error or `{ready}/{humans} ready · {bots} CPUs · {map} · {rules} · the stairs on the left go back down`
	else
		self.title.Text = string.upper(Realms.LOBBY.name)
		self.directions.Text = "Arcade cabinets for 1v1  ·  fighters' gates for 2v2 and 3v3  ·  the tailor's terrace makes your character"
	end
end

function Plaza2D.setPeers(self: any, entries: any, localId: number)
	local present = {}
	local area = if self.room then self.room.id else 0
	for _, entry in entries do
		if entry.userId ~= localId and (entry.area or 0) == area then
			local key = entry.avatar .. "/" .. entry.weapon
			local peer = self.peers[entry.userId]
			if not peer then
				peer = { x = entry.x, z = entry.z or 8, y = entry.y or 0, name = entry.name }
				self.peers[entry.userId] = peer
			end
			if peer.key ~= key then
				peer.char = Loadout.build(entry.avatar, entry.weapon)
				peer.key = key
			end
			peer.target, present[entry.userId] = entry, true
		end
	end
	for id in self.peers do
		if not present[id] then self.peers[id] = nil end
	end
end

-- The arcade as the server last described it (Cabinets.views), and which seat, if any, is yours.
function Plaza2D.setCabinets(self: any, views: any, localId: number)
	if type(views) ~= "table" then return end
	local byNumber = {}
	local mine = nil
	for _, v in views do
		byNumber[v.number] = v
		for side, seat in v.seats or {} do
			if seat.userId == localId then mine = `Cab{v.number}{side}` end
		end
	end
	self.cabinets = byNumber
	self.seatId = mine
end

function Plaza2D.seatStation(self: any): any
	if not self.seatId or self.room then return nil end
	for _, st in PLAZA.market.stations do
		if st.id == self.seatId then return st end
	end
	return nil
end

-- What using a cabinet seat means right now: get up from yours, watch a fight, or sit down.
function Plaza2D.cabinetIntent(self: any, st: any): any
	local view = self.cabinets[st.cabinet]
	if self.seatId then
		return if self.seatId == st.id then { action = "stand" } else nil
	end
	if view and view.state == "playing" then return { action = "watch", cabinet = st.cabinet } end
	local side = if st.side < 0 then "A" else "B"
	if view and view.seats and view.seats[side] then return nil end
	return { action = "sit", cabinet = st.cabinet, side = side }
end

function Plaza2D.interact(self: any)
	if not self.active or self.blocked or UIS:GetFocusedTextBox() then return end
	local seat = self:seatStation()
	local station = seat or self.model:nearest()
	if station and station.kind == "Cabinet" then
		local intent = self:cabinetIntent(station)
		if intent and self.onCabinet then self.onCabinet(intent) end
		return
	end
	if station and self.onInteract then self.onInteract(station) end
end

function Plaza2D.warp(self: any, id: string): boolean
	return self.model:warp(id)
end

function Plaza2D.step(self: any, dt: number, blocked: boolean)
	if not self.active then return end
	self.blocked = blocked
	for _, frame in self.input:sample(dt, Config.FRAME) do
		self.model:step(if blocked then Input.emptyFrame() else frame)
	end
	-- Seated, you stay at the machine, facing it: put back at the seat after every step, which also
	-- undoes any walking or hop the frames just made.
	local seat = self:seatStation()
	if seat then
		local p = self.model.p
		if p.x ~= seat.x or p.z ~= seat.z then self.model:setScene(self.model.data, { x = seat.x, z = seat.z }) end
		p.facing = seat.facing
	end
	local view = seat and self.cabinets[seat.cabinet]
	local alone = view ~= nil and view.state == "open" and not (view.seats.A and view.seats.B)
	self.cpuButton.Visible = alone and not blocked
	local cDown = alone and not UIS:GetFocusedTextBox() and UIS:IsKeyDown(Enum.KeyCode.C)
	if cDown and not self.cHeld and not blocked and self.onCabinet then self.onCabinet({ action = "cpu" }) end
	self.cHeld = cDown
	local down = not UIS:GetFocusedTextBox() and (UIS:IsKeyDown(Enum.KeyCode.E)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX))
	if down and not self.held then self:interact() end
	self.held = down
end

-- ------------------------------------------------------------------ drawing: the ground ----
-- Under each roof of the bazaar, the floating island it stands on: the same RealmArt body the arenas
-- use, hanging from the roof's front edge. Built once.
local function underside(c: any, r: any, i: number)
	local body = RealmArt.island(Realms.LOBBY, r.x2 - r.x1, 6, 20 + i)
	RealmArt.draw(c, body, r.x1, r.z1 * D, 1 / RealmArt.BODY_PPU)
end

function Plaza2D.drawGround(self: any, c: any, scene: any, left: number, right: number)
	for i, r in scene.floor do
		if r.x2 < left or r.x1 > right then continue end
		local bridge = r.bridge == true
		local y1, y2 = r.z1 * D, r.z2 * D
		if bridge then
			-- Planks across the sky between two islands, with a rope rail either side.
			Canvas.rect(c, r.x1, y1, r.x2 - r.x1, y2 - y1, Canvas.hex(A.woodDk, INK))
			for x = r.x1 + 0.2, r.x2 - 0.6, 1.1 do
				Canvas.rect(c, x, y1 + 0.05, 0.9, y2 - y1 - 0.1, Canvas.hex(A.wood, INK))
			end
			Canvas.rect(c, r.x1, y2 + 1.1, r.x2 - r.x1, 0.12, Canvas.hex(A.paper, WHITE), 0.6)
			Canvas.rect(c, r.x1, y1 - 0.4, r.x2 - r.x1, 0.3, Canvas.hex(A.woodDk, INK))
		else
			underside(c, r, i)
			-- the paving, as one sprite: a plaza of flagstones is hundreds of joints
			local paving = RealmArt.paving(Realms.LOBBY, r.x2 - r.x1, y2 - y1, i)
			RealmArt.draw(c, paving, r.x1, y1, 1 / RealmArt.BODY_PPU)
			Canvas.rect(c, r.x1, y1 - 0.2, r.x2 - r.x1, 0.35, Canvas.hex(Realms.LOBBY.top[2], INK))  -- the grass lip
			Canvas.rect(c, r.x1, y2, r.x2 - r.x1, 1.4, Canvas.hex(A.slate, INK))                     -- the low wall
			Canvas.rect(c, r.x1, y2 + 1.4, r.x2 - r.x1, 0.3, Canvas.hex(A.slateHi, INK))
		end
	end
end

-- The rail along each roof's front edge, drawn over everyone: the nearest thing to the viewer.
function Plaza2D.drawRails(self: any, c: any, scene: any, left: number, right: number)
	for _, r in scene.floor do
		if r.bridge or r.x2 < left or r.x1 > right then continue end
		local y = r.z1 * D - 0.2
		-- a timber fence: a rail on posts
		Canvas.rect(c, r.x1, y + 1.2, r.x2 - r.x1, 0.26, FENCE)
		Canvas.rect(c, r.x1, y + 1.2, r.x2 - r.x1, 0.08, FENCE_HI)
		for x = math.ceil(r.x1 / 4) * 4, r.x2, 4 do
			Canvas.rect(c, x - 0.12, y, 0.24, 1.6, FENCE)
		end
	end
end

-- ------------------------------------------------------------------ drawing: people ----
-- Presentation-only distance on the plaza floor, keyed by actor rather than loadout: two people
-- wearing the same kit must not advance each other's stride. The mirror reads the same actor.
local strides: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function stride(actor: any, char: any): number
	local prev = strides[actor]
	if not prev then
		prev = { x = actor.x, z = actor.z, distance = 0 }
		strides[actor] = prev
	end
	local dx, dz = actor.x - prev.x, actor.z - prev.z
	local distance = math.sqrt(dx * dx + dz * dz)
	-- A warp starts afresh, instead of inserting a roof's worth of steps into the next pose.
	prev.distance = if distance > char.height * 2 then 0 else prev.distance + distance
	prev.x, prev.z = actor.x, actor.z
	return prev.distance
end
local function posed(char: any, state: string, sf: number, x: number, z: number, y: number, facing: number, vx: number, actor: any?): any
	local st = PosedFighter.posed(char, 0, state, sf)
	st.x, st.y, st.facing, st.vx = x, y + z * D, facing, vx
	st.onGround = y <= 0.01
	if actor then
		st.strideDistance = stride(actor, char)
		if actor.vx ~= nil and actor.vz ~= nil then
			st.vx = facing * math.sqrt(actor.vx * actor.vx + actor.vz * actor.vz)
		end
	end
	return st
end

function Plaza2D.drawPerson(self: any, c: any, char: any, st: any, z: number, clock: number)
	Fighter2D.draw(c, st, char, clock, z * D)
end

local function vendorChar(self: any, id: string): any
	local v = self.vendors[id]
	if not v then
		for _, p in KIT.presets do
			if p.id == id then
				v = table.clone(Loadout.build(p.code, "Sword"))
				v.weapon = nil                             -- vendors sell; they do not fight
			end
		end
		self.vendors[id] = v
	end
	return v
end

-- ------------------------------------------------------------------ drawing: the market ----
function Plaza2D.marketItems(self: any, c: any, add: (number, () -> ()) -> (), clock: number)
	local model = self.model
	-- The billboard over the square: the game's name, and who is on the rooftop tonight.
	add(24, function()
		local bb = PlazaArt.get("billboard", PlazaArt.billboard)
		-- 0.7 scale: the screen is 23 studs across, 10 tall, standing over the stalls.
		local k, base = 0.7, 24 * D
		PlazaArt.draw(c, "billboard", bb, 0, base, k)
		local sx0, sy0, sw, sh = -16.5 * k, base + 7.5 * k, 33 * k, 10.25 * k
		local pulse = 0.55 + 0.25 * math.sin(clock * 2.2)
		Canvas.rect(c, sx0, sy0, sw, sh, AMBER, 0.03 + pulse * 0.03)
		for i = 0, 7 do
			Canvas.rect(c, sx0, sy0 + ((clock * 2 + i * 1.3) % sh), sw, 0.1, CYAN, 0.05)
		end
		self:placeLabel(c, "billboard", "BLOCKFALL", 0, sy0 + sh * 0.66, 40, AMBER, 520)
		local n = 1
		for _ in self.peers do n += 1 end
		self:placeLabel(c, "billboard2", `{n} ON THE ROOF TONIGHT  ·  ARCADE OPEN`, 0, sy0 + sh * 0.25, 14, CYAN, 520)
	end)
	add(22, function()
		local wt = PlazaArt.get("tower", PlazaArt.waterTower)
		PlazaArt.draw(c, "tower", wt, 76, 22 * D)
		local lights = PlazaArt.get("lights", function() return PlazaArt.stringLights(640) end)
		PlazaArt.draw(c, "lights", lights, -42, 18.6 * D)
		PlazaArt.draw(c, "lights", lights, 42, 18.6 * D)
	end)
	for _, st in STALLS do
		local back = PlazaArt.get("stallB" .. st.sign, function() return PlazaArt.stallBack(st.a, st.b) end)
		local front = PlazaArt.get("stallF" .. st.sign, function() return PlazaArt.stallFront(st.goods) end)
		add(STALL_Z + 0.2, function()
			PlazaArt.draw(c, "stallB" .. st.sign, back, st.x, STALL_Z * D)
			self:placeLabel(c, "stall" .. st.sign, st.sign, st.x, STALL_Z * D + 10, 15, Canvas.hex(st.a, AMBER), 160)
		end)
		add(STALL_Z + 0.1, function()
			local vc = vendorChar(self, st.vendor)
			if vc then
				local s = posed(vc, "idle", math.floor(clock * 60), st.x + 1.5, STALL_Z, 0, -1, 0)
				self:drawPerson(c, vc, s, STALL_Z, clock)
			end
		end)
		add(STALL_Z, function() PlazaArt.draw(c, "stallF" .. st.sign, front, st.x, STALL_Z * D) end)
	end
	add(18.5, function()
		local ac = PlazaArt.get("ac", PlazaArt.acUnit)
		PlazaArt.draw(c, "ac", ac, -80, 18.5 * D)
		PlazaArt.draw(c, "ac", ac, 12, 18.5 * D)
	end)
	add(14, function()
		local k = PlazaArt.get("kiosk", PlazaArt.kiosk)
		PlazaArt.draw(c, "kiosk", k, 0, 12 * D)
		-- The hologram: a turning diamond of light over the projector.
		local turn = math.sin(clock * 1.6)
		local cy = 12 * D + 10.5
		for i = 0, 5 do
			local w = (3 - math.abs(i - 2.5) * 1.05) * math.abs(turn) + 0.3
			Canvas.rect(c, -w, cy - 2.8 + i * 1.1, w * 2, 1, CYAN, 0.28)
		end
		Canvas.rect(c, -0.12, 12 * D + 6.2, 0.24, 7, CYAN, 0.18)
	end)
	-- Tailor's roof: the boutique, its mannequins, and you in its mirror.
	local wardrobe
	for _, s in model.data.stations do if s.kind == "Wardrobe" then wardrobe = s end end
	if wardrobe then
		add(17.4, function()
			local shop = PlazaArt.get("boutique", PlazaArt.boutique)
			PlazaArt.draw(c, "boutique", shop, wardrobe.x, 17.4 * D)
			self:drawWardrobe(c, wardrobe, clock)
		end)
	end
	add(16.6, function()
		local pl = PlazaArt.get("plant", PlazaArt.plant)
		PlazaArt.draw(c, "plant", pl, -144, 16.6 * D)
		PlazaArt.draw(c, "plant", pl, -100, 16.6 * D)
	end)
	add(20.4, function()
		PlazaArt.draw(c, "plant", PlazaArt.get("plant", PlazaArt.plant), 99, 20.4 * D)
		PlazaArt.draw(c, "plant", PlazaArt.get("plant", PlazaArt.plant), 181, 20.4 * D)
	end)
	-- The notice board and the roof map.
	for _, s in model.data.stations do
		if s.kind == "Members" then
			add(s.z + 1, function()
				PlazaArt.draw(c, "board", PlazaArt.get("board", PlazaArt.noticeBoard), s.x, (s.z + 1) * D)
			end)
		elseif s.kind == "Warp" then
			add(s.z + 1, function()
				PlazaArt.draw(c, "mapsign", PlazaArt.get("mapsign", PlazaArt.mapSign), s.x, (s.z + 1) * D)
			end)
		elseif s.kind == "Parkour" then
			add(s.z + 1.6, function()
				PlazaArt.draw(c, "climbgate", PlazaArt.get("climbgate", PlazaArt.climbGate), s.x, (s.z + 1.6) * D)
				self:placeLabel(c, "climb", s.name .. "\n" .. s.landmark, s.x, (s.z + 1.6) * D + 20.5, 16, AMBER, 300)
			end)
		elseif s.kind == "Records" then
			add(s.z + 1, function()
				PlazaArt.draw(c, "records", PlazaArt.get("records", PlazaArt.recordBoard), s.x, (s.z + 1) * D)
				self:placeLabel(c, "records", s.name, s.x, (s.z + 1) * D + 11.8, 13, AMBER, 200)
				if self.recordsLine then
					self:placeLabel(c, "recordsTop", self.recordsLine, s.x, (s.z + 1) * D + 10.4, 11, WHITE, 240)
				end
			end)
		elseif s.kind == "Format" then
			add(s.z + 1.8, function()
				local colour = if s.teamSize == 1 then A.amber elseif s.teamSize == 2 then A.cyan else A.pink
				PlazaArt.draw(c, "lift" .. s.id, PlazaArt.get("lift" .. s.id, function() return PlazaArt.lift(colour) end), s.x, (s.z + 1.8) * D)
			end)
		end
	end
	-- The arcade: its canopy, and the cabinets, each pair with its stools and number.
	add(20.5, function()
		local canopy = PlazaArt.get("canopy", function() return PlazaArt.canopy(88 * 8) end)
		PlazaArt.draw(c, "canopy", canopy, 140, 20.5 * D)
		local flick = if math.floor(clock * 7) % 23 == 0 then 0.35 else 1
		self:placeLabel(c, "arcade", "THE ARCADE", 140, 20.5 * D + 16.2, 30, if flick < 1 then CYAN:Lerp(INK, 0.5) else CYAN, 400)
	end)
	for _, cab in PLAZA.cabinets do
		add(cab.z, function()
			PlazaArt.draw(c, "cab", PlazaArt.get("cab", PlazaArt.cabinetPair), cab.x, cab.z * D)
			local flick = 0.7 + 0.3 * math.sin(clock * 9 + cab.number)
			Canvas.rect(c, cab.x - 2.2, cab.z * D + 3.3, 0.3, 2, CYAN, 0.25 * flick)
			Canvas.rect(c, cab.x + 1.9, cab.z * D + 3.3, 0.3, 2, PINK, 0.25 * flick)
			self:placeLabel(c, "cab" .. cab.number, string.format("%02d", cab.number), cab.x, cab.z * D + 8.4, 18, AMBER, 60)
			-- What the cabinet is doing: a countdown, a fight (and who is watching), the streak.
			local view = self.cabinets[cab.number]
			if view then
				if view.state == "countdown" and view.startsIn then
					self:placeLabel(c, "cabT" .. cab.number, `READY · {math.ceil(view.startsIn)}`, cab.x, cab.z * D + 10.2, 16, CYAN, 160)
				elseif view.state == "playing" then
					local watchers = if (view.watchers or 0) > 0 then ` · {view.watchers} watching` else ""
					self:placeLabel(c, "cabT" .. cab.number, (if view.cpu then "VS CPU" else "IN PLAY") .. watchers, cab.x, cab.z * D + 10.2, 14, PINK, 200)
					Canvas.rect(c, cab.x - 3.2, cab.z * D + 3.2, 6.4, 2.4, PINK, 0.08 + 0.06 * math.sin(clock * 12))
				end
				if view.streak and view.streak.wins > 0 then
					local s2 = if view.streak.wins == 1 then "1 WIN" else `{view.streak.wins} WINS`
					self:placeLabel(c, "cabS" .. cab.number, `{s2}\n{view.streak.name}`, cab.x, cab.z * D + 12.2, 15, AMBER, 200)
				end
			end
		end)
		for _, side in { -1, 1 } do
			add(cab.z - 0.05, function()
				PlazaArt.draw(c, "stool", PlazaArt.get("stool", PlazaArt.stool), cab.x + side * 5, cab.z * D)
			end)
		end
	end
end

-- ------------------------------------------------------------------ drawing: the lounge ----
local function boardThumb(c: any, shapes: { any }, x0: number, y0: number, w: number, h: number, K: number)
	Canvas.save(c)
	Canvas.translate(c, x0, y0 + h)
	Canvas.scale(c, 1 / K, -1 / K)
	for _, sh in shapes do
		Canvas.rect(c, sh[2], sh[3], sh[4], sh[5], Canvas.hex(sh[6], INK), sh[7])
	end
	Canvas.restore(c)
end

-- How many columns the weapon rack needs to hold `n` weapons in three rows (at least four).
function Plaza2D.rackColumns(n: number): number
	return math.max(4, math.ceil(n / 3))
end

-- A preparation station, standing at its depth. The room's own state is drawn on it: the map
-- board the map, the ready rail a lamp per place, the rules board lives or a clock, the rack your
-- weapon.
local function stationArt(c: any, s: any, active: boolean, room: any, weaponId: string?)
	local x = s.x
	local colour = AMBER
	Canvas.rect(c, x - 6, 0, 12, 5, METAL)
	Canvas.rect(c, x - 6.5, 4.5, 13, 0.8, STEEL)
	Canvas.rect(c, x - 5, 0.8, 10, 0.4, colour)
	if s.kind == "Weapons" then
		Canvas.rect(c, x - 8, 5.3, 16, 9, INK)
		-- Three rows inside the rack's panel, as many columns as the roster needs, spread across
		-- its width: a fixed four a row put the 13th and 14th weapons below the panel.
		local cols = Plaza2D.rackColumns(#Weapons.LIST)
		local step = 12.8 / math.max(1, cols - 1)
		local art = math.min(0.45, step * 0.13)
		for i, weapon in Weapons.LIST do
			local gx, gy = x - 6.4 + ((i - 1) % cols) * step, 7 + math.floor((i - 1) / cols) * 2.6
			if weapon.id == weaponId then
				Canvas.rect(c, gx - step * 0.45, gy - 1.1, step * 0.9, 2.4, AMBER, 0.9)
				Canvas.rect(c, gx - step * 0.4, gy - 0.9, step * 0.8, 2.0, INK)
			end
			Canvas.save(c)
			Canvas.translate(c, gx, gy)
			Canvas.scale(c, art, art)
			WeaponArt.draw(c, weapon.id, weapon.palette, { angle = 0.2, ox = 0, oy = 0, scale = 1, charge = 0 })
			Canvas.restore(c)
		end
	elseif s.kind == "Maps" then
		Canvas.rect(c, x - 5.6, 5.3, 11.2, 7.6, INK)
		local stage = shownMap(room)
		boardThumb(c, if stage then StageThumb.shapes(Realms.dress(stage), 100, 64) else StageThumb.random(100, 64), x - 5, 5.7, 10, 6.4, 10)
	elseif s.kind == "Players" then
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
		Canvas.rect(c, x - 4, 5.3, 8, 6, INK)
		if room and room.mode == "timed" then
			Canvas.circle(c, x, 8.3, 2.2, colour)
			Canvas.circle(c, x, 8.3, 1.8, INK)
			Canvas.rect(c, x - 0.15, 8.3, 0.3, 1.4, WHITE)
			Canvas.rect(c, x, 8.15, 1.1, 0.3, WHITE)
		else
			local lives = if room then room.stocks or 3 else 3
			for i = 1, lives do
				Canvas.rect(c, x - 3.4 + (i - 1) * 1.5, 7.6, 1.1, 1.1, colour)
			end
		end
	end
	if active then
		Canvas.rect(c, x - 2, 0.6, 4, 0.3, WHITE)
		Canvas.rect(c, x - 1, 1, 2, 0.3, WHITE)
	end
end
Plaza2D.stationArt = stationArt

function Plaza2D.loungeItems(self: any, c: any, add: (number, () -> ()) -> (), clock: number)
	local near = self.model:nearest()
	add(18.4, function()
		local lights = PlazaArt.get("lights", function() return PlazaArt.stringLights(640) end)
		PlazaArt.draw(c, "lights", lights, 0, 18.4 * D)
		local pl = PlazaArt.get("plant", PlazaArt.plant)
		PlazaArt.draw(c, "plant", pl, -41, 18.4 * D)
		PlazaArt.draw(c, "plant", pl, 41, 18.4 * D)
	end)
	add(17.8, function()
		PlazaArt.draw(c, "couchP", PlazaArt.get("couchP", function() return PlazaArt.couch(A.pinkDk) end), -31, 17.8 * D)
		PlazaArt.draw(c, "couchC", PlazaArt.get("couchC", function() return PlazaArt.couch(A.cyanDk) end), 7, 17.8 * D)
	end)
	for _, s in self.model.data.stations do
		if s.kind == "Exit" then
			add(s.z + 8, function()
				-- The stairwell back down to Neon Row.
				local x, y = s.x, 16 * D
				Canvas.rect(c, x - 3, y + 1, 6, 12, INK)
				Canvas.rect(c, x - 3.4, y + 1, 0.4, 12.5, PINK)
				Canvas.rect(c, x + 3, y + 1, 0.4, 12.5, PINK)
				for i = 0, 5 do Canvas.rect(c, x - 2.6, y + 1.2 + i * 1.6, 5.2, 0.3, STEEL) end
				self:placeLabel(c, "st" .. s.id, s.name .. "\n" .. s.landmark, x, y + 15.5, 14, PINK, 220)
			end)
		else
			add(s.z + 1, function()
				-- At 0.7 scale about its base: the stations were drawn for the old hub's wider camera.
				Canvas.save(c)
				Canvas.translate(c, s.x, (s.z + 1) * D)
				Canvas.scale(c, 0.7, 0.7)
				Canvas.translate(c, -s.x, 0)
				stationArt(c, s, near == s, self.room, self.char and self.char.weapon and self.char.weapon.id)
				Canvas.restore(c)
				self:placeLabel(c, "st" .. s.id, s.name, s.x, (s.z + 1) * D + 11, 14, AMBER, 220)
			end)
		end
	end
end

-- ------------------------------------------------------------------ the wardrobe ----
function Plaza2D.drawWardrobe(self: any, c: any, s: any, clock: number)
	local presets = KIT.presets
	local turn = math.floor(clock / MANNEQUIN_SECONDS)
	local baseY = 17.4 * D
	for k, side in { -1, 1 } do
		local code = presets[(turn * 2 + k) % #presets + 1].code
		local m = self.mannequins[k]
		if not m or m.code ~= code then
			local char = table.clone(Loadout.build(code, "Sword"))
			char.weapon = nil
			m = { code = code, char = char }
			self.mannequins[k] = m
		end
		local st = posed(m.char, "idle", math.floor(clock * 60), s.x + side * 5.6, 17.4, 0.5, -side, 0)
		Fighter2D.draw(c, st, m.char, clock + k * 0.7, baseY + 0.5)
	end
	if self.char then
		local p = self.model.p
		local r = posed(self.char, p.state, p.sf, s.x, 17.4, 0.6 + math.max(0, p.y) * 0.3, -p.facing, p.vx, p)
		r.onGround = p.y <= 0.01
		Fighter2D.draw(c, r, self.char, clock, baseY + 0.6)
	end
	Canvas.rect(c, s.x - 2.4, baseY + 0.9, 4.8, 8.7, CYAN, 0.10)
	Canvas.rect(c, s.x - 1.6, baseY + 6.8, 0.25, 2.2, WHITE, 0.25)
	Canvas.rect(c, s.x - 1.1, baseY + 7.6, 0.2, 1.3, WHITE, 0.18)
	self:placeLabel(c, "wardrobe", s.name .. "\n" .. s.landmark, s.x, baseY + 16.2, 15, PINK, 300)
end

-- ------------------------------------------------------------------ the frame ----
function Plaza2D.draw(self: any, c: any, dt: number)
	-- Team colours are a match's; the lobby is not one.
	local teams = Fighter2D.teamColours
	Fighter2D.teamColours = nil
	self:drawScene(c, dt)
	Fighter2D.teamColours = teams
end

function Plaza2D.drawScene(self: any, c: any, dt: number)
	local model = self.model
	local p = model.p
	local scene = model.data
	local clock = os.clock()
	local vp = c:viewport()
	local ppu = math.clamp(vp.Y / 38, 6, 22)
	local half = vp.X / ppu / 2
	local b = scene.bounds
	local target = p.x + p.facing * 4
	if b.x2 - b.x1 > half * 2 then
		target = math.clamp(target, b.x1 + half, b.x2 - half)
	else
		target = (b.x1 + b.x2) / 2
	end
	self.camX += (target - self.camX) * math.min(1, dt * 6)
	RealmArt.sky(c, Realms.LOBBY, self.camX, clock)
	-- Framed on the plaza, not the island under it: the underside is a strip at the bottom.
	c:world(self.camX, 12.5 + p.z * D * 0.3, ppu, 0, 0)
	local left, right = self.camX - half - 12, self.camX + half + 12
	self:drawGround(c, scene, left, right)

	-- Everything that stands on the roof, sorted back to front by depth.
	local items: { any } = {}
	local seq = 0
	local function add(z: number, fn: () -> ())
		seq += 1
		table.insert(items, { z = z, seq = seq, fn = fn })
	end
	if scene.kind == "plaza" then self:marketItems(c, add, clock) else self:loungeItems(c, add, clock) end
	for id, peer in self.peers do
		local goal = peer.target
		local blend = math.min(1, dt * 14)
		peer.x += (goal.x - peer.x) * blend
		peer.z += ((goal.z or 8) - peer.z) * blend
		peer.y += ((goal.y or 0) - peer.y) * blend
		if peer.x > left and peer.x < right then
			add(peer.z, function()
				local state = if peer.y > 0.1 then "air" elseif goal.moving then "run" else "idle"
				local st = posed(peer.char, state, math.floor(clock * 60), peer.x, peer.z, peer.y, goal.facing or 1, if goal.moving then (goal.facing or 1) * 15 else 0, peer)
				self:drawPerson(c, peer.char, st, peer.z, clock)
				local head = peer.y + peer.z * D + peer.char.height
				self:placeLabel(c, "name" .. id, peer.name or "", peer.x, head + 1.6, 12, WHITE, 180)
				self:drawOverhead(c, id, peer.x, head + 1.4)
			end)
		end
	end
	if self.char then
		add(p.z, function()
			local st = posed(self.char, p.state, p.sf, p.x, p.z, p.y, p.facing, p.vx, p)
			self:drawPerson(c, self.char, st, p.z, clock)
			if self.localId then self:drawOverhead(c, self.localId, p.x, p.y + p.z * D + self.char.height + 0.2) end
		end)
	end
	table.sort(items, function(a, b2)
		if a.z ~= b2.z then return a.z > b2.z end
		return a.seq < b2.seq
	end)
	for _, it in items do it.fn() end
	self:drawRails(c, scene, left, right)

	-- The district you are in, announced as you enter it.
	local d = model:district()
	if d and d.id ~= self.district then
		self.district = d.id
		self.banner.Text = string.upper(Realms.place(d.id, d.name))
		self.bannerAt = clock
	end
	local age = clock - self.bannerAt
	self.banner.TextTransparency = if age < 2 then 0 elseif age < 3 then age - 2 else 1
	self.bannerOutline.Transparency = self.banner.TextTransparency

	local near = self:seatStation() or model:nearest()
	local cabinetWord = nil
	if near and near.kind == "Cabinet" then
		local intent = self:cabinetIntent(near)
		cabinetWord = if not intent then "TAKEN:" elseif intent.action == "stand" then "STAND UP FROM"
			elseif intent.action == "watch" then "WATCH" else "SIT AT"
		if intent and intent.action == "sit" then
			self:placeLabel(c, "seat", "SIT HERE", near.x, near.z * D + 7.2, 14, AMBER, 140)
		end
	end
	self:endLabels()
	c:finish()
	self:placeTop(Ui.topInset())
	local gw = self.gui.AbsoluteSize and self.gui.AbsoluteSize.X or 0
	self.controls.Visible = gw - Plaza2D.SOCIAL_BAR_W - 64 >= self.controlsW
	local action = not self.blocked and near ~= nil
	self.prompt.Text = if self.blocked then "Finish at the panel, then carry on."
		elseif near then `{if near.kind == "Format" or near.kind == "Exit" then "ENTER" elseif cabinetWord then cabinetWord else "USE"} {near.name}`
		else if self.room then "Walk to a station to set up the fight." else "Walk the roofs: the arcade and the climb are east, the tailor is west."
	self.prompt.Active = action
	-- an action (the E key, gold words, a gold rim) or a tip (soft words, no key)
	if self.promptAction ~= action then
		self.promptAction = action
		self.promptKey.Visible = action
		self.prompt.Font = if action then Ui.DISPLAY else Ui.LABEL
		self.prompt.TextSize = if action then 22 else 15
		self.prompt.TextColor3 = if action then Ui.GOLD else Ui.WHITE
		self.promptOutline.Enabled = action
		self.promptEdge.Color = if action then Ui.GOLD else Ui.INK
		self.promptPad.PaddingLeft = UDim.new(0, if action then 64 else 16)
	end
	self.gui:SetAttribute("NearbyStation", if near then near.id else "")
	self.gui:SetAttribute("FighterX", p.x)
	self.gui:SetAttribute("FighterZ", p.z)
	self.gui:SetAttribute("District", if d then d.id else "")
end

return Plaza2D
