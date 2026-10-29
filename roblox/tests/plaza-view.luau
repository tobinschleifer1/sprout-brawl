--!strict
-- The real Plaza2D controller and drawing, with input, Instances and drawing primitives mocked.
-- Proves walking and proximity, input edges, modal and chat guards, bounded and finite drawing at
-- three screen sizes, depth order, the stations showing the room, the wardrobe and the CHARACTER
-- button - not how it looks (tools/render-hub.luau is for looking).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Input = Loader.load("Input")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local WeaponArt = Loader.loadFrom("src/client/", "Weapons2D")
local drawWeapon = WeaponArt.draw
local drawnWeapons = {}
WeaponArt.draw = function(c, id, ...)
	-- where it was drawn, keeping the smallest draw of each: the rack's icons are under half size,
	-- the weapons fighters hold nearby are full size
	local size = math.abs(c.m.a) + math.abs(c.m.b)
	local was = drawnWeapons[id]
	if not was or size < was[3] then drawnWeapons[id] = { c.m.e, c.m.f, size } end
	return drawWeapon(c, id, ...)
end
local codes = setmetatable({}, { __index = function(_, key) return key end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, key) return key end })
local eDown, focused, cDown = false, false, false
local function instance(): any
	local obj: any = { attributes = {}, Visible = true, TextTransparency = 0 }
	obj.Destroy = function() obj.destroyed = true end
	obj.Activated = { Connect = function(_, fn) obj.activate = fn end }
	obj.SetAttribute = function(_, key, value) obj.attributes[key] = value end
	obj.GetChildren = function() return {} end          -- (Ui.paintCard walks a card's children)
	return obj
end
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
local Plaza2D = luau.load(fs.readFile("src/client/Plaza2D.luau"), { environment = {
	game = { GetService = function(_, name)
		if name == "ReplicatedStorage" then return { Shared = shared } end
		return { GetFocusedTextBox = function() return focused end,
			IsKeyDown = function(_, key) return (eDown and key == "E") or (cDown and key == "C") end,
			IsGamepadButtonDown = function() return false end }
	end },
	script = { Parent = codes },
	require = function(name)
		if name == "InputClient" then return { new = function() return {
			frame = Input.emptyFrame(), sample = function(self) return { self.frame } end, reset = function() end,
		} end } end
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2, UDim = Rbx.UDim,
	Enum = setmetatable({}, { __index = function() return codes end }), Instance = { new = instance },
}, injectGlobals = true })()
local PLAZA = Loader.load("Plaza").DATA      -- (the Roblox lobby: no arcade or gates)
local KIT = Loader.load("Data/AvatarKit")
local cfg = Loader.load("MatchConfig").default()
-- You arrive in a kit character no preset matches, so the mirror can be told from the mannequins.
do
	local code = KIT.presets[2].code
	cfg.slots[1].avatarId = string.sub(code, 1, -2) .. (if string.sub(code, -1) == "1" then "2" else "1")
end
local hub = Plaza2D.new({})
hub:show(cfg)
local opened: { any } = {}
hub.onInteract = function(st) table.insert(opened, st) end

-- 0. Nobody in the lobby blinks: a posed character is fully opaque on every frame. (A fresh Fighter
--    carries spawn invincibility, drawn as a 10Hz blink; the lobby poses a fresh one each frame.)
do
	local Posed = Loader.loadFrom("src/client/", "PosedFighter")
	local Channels = Loader.loadFrom("src/client/", "Channels")
	local char = Loader.load("Loadout").build(KIT.presets[2].code, "Sword")
	for _, state in { "idle", "run", "air", "victory" } do
		for sf = 0, 30 do
			local ch = Channels.For(Posed.posed(char, 0, state, sf), char, nil, sf / 60)
			assert(ch.visible and ch.opacity == 1, `{state} frame {sf}: opacity {ch.opacity} - the lobby would flicker`)
		end
	end
end

-- 1. Walking: arrows move you along the street and into the depth; nothing happens at spawn.
hub:step(1/60, false)
hub:interact()
assert(#opened == 0, "spawn is not a station")
hub.input.frame.x = 1
for _ = 1, 40 do hub:step(1/60, false) end
assert(hub.model.p.x > 5, "walking right must move you along the street")
hub.input.frame.x, hub.input.frame.y = 0, 1
local z0 = hub.model.p.z
for _ = 1, 30 do hub:step(1/60, false) end
assert(hub.model.p.z > z0 + 2, "up must walk into the depth of the roof")
hub.input.frame.y = 0

-- 2. Interaction: a held E opens once; a panel blocks it; typing in chat never uses a station.
local function stand(st: any)
	hub.model:setScene(hub.model.data, { x = st.x, z = st.z })
end
local board
for _, st in PLAZA.market.stations do if st.kind == "Warp" then board = st end end
stand(board)
eDown = true
hub:step(1/60, false)
hub:step(1/60, false)
hub:step(1/60, false)
assert(#opened == 1 and opened[1] == board, "holding E must use the station once")
hub:step(1/60, true)
hub:interact()
assert(#opened == 1, "an open panel blocks the lobby")
eDown, focused = false, true
hub:step(1/60, false)
eDown = true
hub:step(1/60, false)
assert(#opened == 1, "typing E in chat must not use a station")
eDown, focused = false, false

-- 3. Drawing: finite, bounded, back to front, at every station and three screen sizes.
local sprites: { string } = {}
local function primitive(c: any, ...: any)
	for _, value in { ... } do
		if type(value) == "number" then assert(value == value and math.abs(value) < math.huge, "finite lobby geometry") end
	end
	c.used += 1
end
Canvas.rect, Canvas.circle, Canvas.ellipse = primitive, primitive, primitive
Canvas.sprite = function(c: any, key: string, _list: any, ...: any)
	table.insert(sprites, key)
	primitive(c, ...)
end
local function canvas(w: number, h: number): any
	return setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
		gui = { AbsoluteSize = { X = w, Y = h } }, finish = function(self) self.drawn = self.used; self.used = 0 end }, { __index = Canvas })
end
-- The lobby has depth as well as X. A distance-driven fight gait fed only X freezes both legs
-- while walking north/south; the mirror's fixed X used to freeze its stride on every walk.
do
	local Draw = Loader.loadFrom("src/client/", "Fighter2D")
	local Channels = Loader.loadFrom("src/client/", "Channels")
	local Posture = Loader.loadFrom("src/client/", "Posture")
	local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
	local realDraw = Draw.draw
	local poses = {}
	Draw.draw = function(c, st, char, t, top)
		local ch = Channels.For(st, char, nil, t)
		local p = Posture.For(ch, st, char, WeaponPose.For(st, char, nil, t), nil, t)
		poses[char] = { x = st.x, foot = p.legs[1].pose.ex, bob = p.bob, speed = math.abs(st.vx) }
		return realDraw(c, st, char, t, top)
	end
	local c = canvas(1280, 720)
	local function changed(before, after, why)
		assert(before and after and math.abs(after.foot - before.foot) > 0.01, why .. " feet did not stride")
		assert(before.bob ~= nil and after.bob ~= nil, why .. " run is not grounded")
		assert(math.abs(after.bob - before.bob) > 1e-5, why .. " bounce did not follow stride")
	end
	hub.model:setScene(PLAZA.market, { x = 10, z = 4 })
	hub.input.frame.x, hub.input.frame.y = 0, 1
	hub:step(1/60, false); hub:draw(c, 1/60)
	local before = poses[hub.char]
	for _ = 1, 12 do hub:step(1/60, false); hub:draw(c, 1/60) end
	local after = poses[hub.char]
	assert(after.x == before.x and hub.model.p.z > 4.5 and after.speed > 0.5, "depth walk lost its pose speed")
	changed(before, after, "depth walk")

	local wardrobe
	for _, st in PLAZA.market.stations do if st.kind == "Wardrobe" then wardrobe = st end end
	hub:drawWardrobe(c, wardrobe, 0)
	-- (the reflection is your character unarmed: its sword reached out past the glass)
	local mirror = hub.mirrorChar and hub.mirrorChar.char
	assert(mirror and mirror.weapon == nil and hub.char.weapon ~= nil, "the reflection in the mirror is armed")
	before = poses[mirror]
	for _ = 1, 12 do hub:step(1/60, false); hub:drawWardrobe(c, wardrobe, 0) end
	after = poses[mirror]
	assert(after.x == before.x, "mirror left its fixed display position")
	changed(before, after, "mirror")
	hub.input.frame.y = 0

	-- Remote peers use their interpolated depth travel, not a wall clock or their fixed X.
	hub:setPeers({ { userId = 42, name = "Walker", avatar = "Noir", weapon = "Sword", x = 10, z = 4, y = 0, facing = 1, moving = true } }, 1)
	local peer = hub.peers[42]
	peer.x, peer.z, peer.y = 10, 4, 0
	hub:draw(c, 1/60)
	before = poses[peer.char]
	peer.target.z = 8
	for _ = 1, 4 do hub:draw(c, 1/60) end
	after = poses[peer.char]
	assert(after.x == before.x, "peer test must walk only in depth")
	changed(before, after, "peer depth walk")
	Draw.draw = realDraw
	hub:setPeers({}, 1)
end
local peak, visits = 0, 0
for _, size in { { 390, 844 }, { 1280, 720 }, { 1920, 1080 } } do
	for _, st in PLAZA.market.stations do
		stand(st)
		hub.camX = st.x
		local c = canvas(size[1], size[2])
		hub:draw(c, 1/60)
		assert(c.drawn > 20 and c.drawn < 900, `{st.id} at {size[1]}x{size[2]}: {c.drawn} primitives`)
		assert(#c.stack == 0, "the lobby leaves no transforms behind for the arena renderer")
		assert(hub.gui.attributes.NearbyStation == st.id, `{st.id}: the prompt should name the station you stand at`)
		peak = math.max(peak, c.drawn)
		visits += 1
	end
end

-- 4. Depth: a player behind the square's kiosk is drawn before it, one in front after it.
do
	local order: { string } = {}
	local KIOSK_Z = 14          -- (Plaza2D.marketItems stands the kiosk at this depth)
	Canvas.sprite = function(c: any, key: string, _list: any, x0: number, y1: number, ...: any)
		if key == "prop|kiosk" then table.insert(order, "kiosk") end
		if string.sub(key, 1, 2) == "k1" then table.insert(order, "person:" .. string.match(key, "^(k1%w+)")) end
		primitive(c, x0, y1, ...)
	end
	-- A code no preset has: the tailor's mannequins cycle through the presets on the clock, and a
	-- mannequin wearing the guest's code (drawn at the back) made this order check flaky.
	local guest = string.sub(KIT.presets[5].code, 1, -2) .. (if string.sub(KIT.presets[5].code, -1) == "3" then "4" else "3")
	for _, preset in KIT.presets do assert(preset.code ~= guest, "the guest must not wear a preset") end
	assert(Loader.load("AvatarKit").canonical(guest) == guest, "and must wear a real character")
	local function drawWith(z: number): { string }
		table.clear(order)
		hub:setPeers({ { userId = 2, name = "Guest", avatar = guest, weapon = "Sword", x = 0, z = z, y = 0, facing = 1 } }, 1)
		hub.peers[2].z, hub.peers[2].x = z, 0
		stand({ x = -8, z = 9 })
		hub.camX = 0
		hub:draw(canvas(1280, 720), 1/60)
		local first, firstGuest = nil, nil
		for i, what in order do
			if what == "kiosk" and not first then first = i end
			if what == "person:" .. guest and not firstGuest then firstGuest = i end
		end
		return { tostring(first), tostring(firstGuest) }
	end
	local behind = drawWith(KIOSK_Z + 1.5)
	assert(tonumber(behind[2]) and tonumber(behind[1]) and tonumber(behind[2]) < tonumber(behind[1]), "a player behind the kiosk must be drawn before it")
	local infront = drawWith(KIOSK_Z - 1.5)
	assert(tonumber(infront[2]) > tonumber(infront[1]), "a player in front of the kiosk must be drawn after it")
	-- a name tag is outlined in ink at 2 px, as the signs' words (TextStroke is 1 px; at a 0.55 stroke a
	-- name over the sky was grey on grey)
	local tag = hub.pool["name2"]
	local stroke = hub.tagStrokes and hub.tagStrokes[2]
	assert(tag and tag.Visible and type(stroke) == "table" and stroke.Thickness >= 2, "the guest's name tag is not outlined")
	hub:setPeers({}, 1)
	Canvas.sprite = function(c: any, key: string, _list: any, ...: any)
		table.insert(sprites, key)
		primitive(c, ...)
	end
end

-- 5. The wardrobe: mannequins in ready-made characters that change, you in the mirror.
do
	local wardrobe
	for _, st in PLAZA.market.stations do if st.kind == "Wardrobe" then wardrobe = st end end
	local presetCodes = {}
	for _, p in KIT.presets do presetCodes[p.code] = true end
	local function wornAt(clock: number): { [string]: number }
		table.clear(sprites)
		hub:drawWardrobe(canvas(1280, 720), wardrobe, clock)
		local seen = {}
		for _, key in sprites do
			local code = string.match(key, "^(k1%w+)|")
			if code then seen[code] = (seen[code] or 0) + 1 end
		end
		return seen
	end
	local a, b = wornAt(0), wornAt(4.01)
	local mannequins, changed = 0, false
	for code, n in a do
		if presetCodes[code] then mannequins += n // 7 end
		if not b[code] then changed = true end
	end
	assert((a[cfg.slots[1].avatarId] or 0) >= 7, "your character is in the wardrobe's mirror")
	assert(mannequins >= 2 and changed, "two mannequins in ready-made characters, changing over time")
end

-- 6. The CHARACTER button: in the market, not in a lounge, not while a panel is open.
do
	local studio = 0
	hub.onCharacter = function() studio += 1 end
	hub.characterButton.activate()
	assert(studio == 1, "the CHARACTER button opens the studio")
	hub:step(1/60, true)
	hub.characterButton.activate()
	assert(studio == 1, "a panel over the lobby blocks the CHARACTER button")
	hub:step(1/60, false)
	hub:setRoom({ id = 77, format = "Duel", stage = "FoundryFloor", slots = { { userId = 1 } } })
	assert(hub.characterButton.Visible == false, "a lounge hides the CHARACTER button")
	hub:setRoom({ left = true })
	assert(hub.characterButton.Visible == true, "back on Neon Row, the button returns")
end

-- 7. The district banner names where you walked in.
do
	local seen = {}
	for _, w in PLAZA.market.warps do
		hub.model:warp(w.id)
		hub:draw(canvas(1280, 720), 1/60)
		seen[hub.banner.Text] = true
		assert(hub.gui.attributes.District == w.id, `warped to {w.id}, in district {hub.gui.attributes.District}`)
	end
	-- in the Skyhold Bazaar's own names (Realms.PLACES), one per district, never the web's
	local RealmsMod = Loader.load("Realms")
	for _, d in PLAZA.market.districts do
		local name = string.upper(RealmsMod.place(d.id, d.name))
		assert(name ~= d.name, `{d.id} has no bazaar name`)
		assert(seen[name], `no banner for {name}`)
	end
end

-- 8. The lounges: every station reachable and drawn with the room's state on it.
local returnAt
do
	hub.model:warp("arcade")
	returnAt = hub.model.p.x
	local Stages = Loader.load("Data/Stages")
	local byId = {}
	for _, st in Stages.LIST do byId[st.id] = st end
	local room = { id = 9, format = "Doubles", stage = "FoundryFloor", mapChoice = "vote", mode = "stock", stocks = 4,
		slots = { { userId = 1, team = 0, ready = false, vote = "Undertow" }, { userId = 2, team = 1, ready = true, vote = "Saltflat" },
			{ team = 0 }, { team = 1, bot = "easy" } } }
	assert(Plaza2D.shownMap(room).id == "Undertow", "a tied vote shows the earliest ballot")
	hub:setRoom(room)
	assert(hub.model.data.id == "LoungeDoubles", "a room puts you on its lounge roof")
	local colours = {}
	local frames = 0
	local recorder = function(c, _x, _y, w, h, colour, ...)
		local key = string.format("%d,%d,%d", math.floor(colour.R * 255 + 0.5), math.floor(colour.G * 255 + 0.5), math.floor(colour.B * 255 + 0.5))
		colours[key] = (colours[key] or 0) + 1
		-- the amber frame round your weapon: its width follows the rack's columns, its height does not
		if key == "232,162,74" and w > 1 and w < 4 and math.abs(h - 2.4) < 1e-6 then frames += 1 end
		c.used += 1
	end
	local function drawAt(st: any): { [string]: number }
		colours = {}
		drawnWeapons = {}
		Canvas.rect = recorder
		stand(st)
		hub.camX = st.x
		hub:draw(canvas(1280, 720), 1/60)
		Canvas.rect = primitive
		return colours
	end
	local stations = {}
	for _, st in PLAZA.rooms.Doubles.stations do stations[st.id] = st end
	local function rgb(hex: string): string
		local c = Rbx.Color3.fromHex(hex)
		return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	local seen = drawAt(stations.Maps)
	-- in its realm's colours (Realms.dress): Roblox draws every stage in its realm
	local Realms = Loader.load("Realms")
	assert(seen[rgb(Realms.dress(byId.Undertow).palette.skyStops[1][2])], "the map board shows the leading map's sky")
	assert(not seen[rgb(Realms.dress(byId.FoundryFloor).palette.skyStops[1][2])], "the map board shows a map that is not leading")
	seen = drawAt(stations.Players)
	assert((seen["127,190,110"] or 0) == 2, `two green lamps (the ready player and the bot), got {seen["127,190,110"] or 0}`)
	room.slots[1].ready = true
	hub:setRoom(room)
	seen = drawAt(stations.Players)
	assert((seen["127,190,110"] or 0) == 3, "readying lights your lamp")
	frames = 0
	drawAt(stations.Weapons)
	assert(frames == 1, `exactly one weapon framed on the rack, got {frames}`)
	-- every weapon in the game (the merged roster, Roblox-only ones too), in the rack's three rows:
	-- a fixed four a row once hung the 13th and 14th below the panel
	local rows: { [number]: boolean } = {}
	local nrows = 0
	for _, w in Loader.load("Weapons").LIST do
		local at = drawnWeapons[w.id]
		assert(at, "the rack shows every weapon: " .. w.id)
		local key = math.floor(at[2] + 0.5)
		if not rows[key] then rows[key] = true; nrows += 1 end
	end
	assert(nrows <= 3, `the rack's weapons spill onto {nrows} rows, the panel holds three`)
	for _, st in PLAZA.rooms.Doubles.stations do
		stand(st)
		hub:draw(canvas(1280, 720), 1/60)
		assert(hub.gui.attributes.NearbyStation == st.id, `lounge station {st.id} not offered where it stands`)
	end
	-- each station's name on a sign in the UI's kit, in its own colour (bare amber words floated over
	-- the roof in round 0), and its desk a kit box: an ink outline round a face
	for _, st in PLAZA.rooms.Doubles.stations do
		if st.kind == "Exit" then continue end
		stand(st)
		hub.camX = st.x
		hub:draw(canvas(1280, 720), 1/60)
		local sg = hub.signs and hub.signs["st" .. st.id]
		assert(sg and sg.card.Visible, `the {st.id} station has no sign`)
		assert(sg.card.BackgroundColor3 == Plaza2D.STATION_COLOURS[st.kind], `the {st.id} sign is not in its station's colour`)
		assert(sg.text.Text == st.name, `the {st.id} sign reads {sg.text.Text}`)
		local bare = hub.pool["st" .. st.id]
		assert(not bare or bare.Visible == false, `the {st.id} station's name still floats as bare words`)
	end
	do
		local rects: { any } = {}
		Canvas.rect = function(c, x, y, w, h, colour, ...)
			table.insert(rects, { x, y, w, h, colour })
			c.used += 1
		end
		local st = stations.Rules
		Plaza2D.stationArt(canvas(1280, 720), st, false, room, nil)
		Canvas.rect = primitive
		local o = Plaza2D.KIT_INK
		local outlined = false
		for _, r in rects do
			if math.abs(r[1] - (st.x - 6 - o)) < 1e-6 and math.abs(r[2] + o) < 1e-6 and math.abs(r[3] - (12 + 2 * o)) < 1e-6
				and r[5] == Rbx.Color3.fromRGB(15, 18, 24) then outlined = true end
		end
		assert(o > 0 and outlined, "the station's desk has no ink outline round it")
	end
	hub:setPeers({ { userId = 2, area = 0, name = "Outsider", avatar = "Classic", weapon = "Sword", x = 0, z = 8, facing = 1 } }, 1)
	assert(not hub.peers[2], "people on Neon Row must not appear in a lounge")
end
hub:setRoom({ left = true })
assert(hub.model.data.id == "NeonRow" and hub.model.p.x == returnAt, "leaving a lounge returns you where you went up")

-- 9. Hidden, the lobby neither moves nor interacts.
hub:hide()
local x = hub.model.p.x
hub.input.frame.x = 1
hub:step(1/60, false)
hub:interact()
assert(hub.model.p.x == x, "a hidden lobby cannot move during a match")
-- The prompt: beside a station, the E key and the action in gold; away from one, a tip and no key.
-- The controls row shows where it fits beside the social bar.
do
	local wasActive, wasBlocked = hub.active, hub.blocked
	hub.active, hub.blocked = true, false
	local tried = false
	for _, st in PLAZA.market.stations do
		if st.kind == "Warp" then
			tried = true
			stand(st)
			hub.gui.AbsoluteSize = { X = 1280, Y = 720 }
			hub:draw(canvas(1280, 720), 1/60)
			assert(hub.promptKey.Visible and string.find(hub.prompt.Text, "USE", 1, true) and not string.find(hub.prompt.Text, "[E", 1, true),
				`beside {st.id} the prompt reads {hub.prompt.Text}`)
			-- (it stands in the key hints' row at the bottom left, under the walking band: above the
			-- buttons' row it covered the band's front 45 px, where a crowd's front row stands)
			assert(not hub.controls.Visible, "the controls row shows under the action card on a wide screen")
			local p = hub.prompt
			local top = p.Position.Y.Scale * 720 + p.Position.Y.Offset - p.AnchorPoint.Y * p.Size.Y.Offset
			local c = canvas(1280, 720)
			hub:draw(c, 1/60)
			local front = math.huge
			for _, r in hub.model.data.floor do if st.x >= r.x1 and st.x <= r.x2 then front = math.min(front, r.z1 * PLAZA.depth) end end
			local band = c:project(st.x, front).Y
			assert(top >= band, `on a wide screen the action card's top ({top}) is over the walking band (front edge {band})`)
			local right = p.Position.X.Scale * 1280 + p.Position.X.Offset - p.AnchorPoint.X * p.Size.X.Offset + p.Size.X.Offset
			assert(right <= 1280 - Plaza2D.SOCIAL_BAR_W - 16, `the action card reaches x {right}, into the buttons' row`)
			-- away from a station: no card, and the key hints are back
			hub.model:setScene(hub.model.data, { x = st.x - 9, z = 3 })
			hub:draw(canvas(1280, 720), 1/60)
			assert(not hub.prompt.Visible and hub.controls.Visible, "away from a station a card shows, or the key hints do not")
			break
		end
	end
	assert(tried, "no station to stand beside for the action card")
	hub.model:setScene(hub.model.data, { x = 0, z = 8 })
	hub.camX = 0
	hub.gui.AbsoluteSize = { X = 812, Y = 375 }
	local narrow = canvas(812, 375)
	hub:draw(narrow, 1/60)
	-- each stall's name, now a kit sign over its awning, stays within its stall's width on a phone
	do
		local Ui = Loader.loadFrom("src/client/", "Ui")
		local signs = 0
		for _, st in Plaza2D.STALLS do
			local sg = hub.signs and hub.signs["stall" .. st.sign]
			-- (the two stalls either side of the square, on a phone's screen from it: a sign wider
			-- than its stall may be hidden at the edge, so its width is checked whether shown or not)
			if sg and math.abs(st.x) <= 30 then
				local y = 18.8 * PLAZA.depth + 10.4
				local span = math.abs(narrow:project(st.x + 6, y).X - narrow:project(st.x - 6, y).X)
				assert(sg.card.Size.X.Offset <= span, `{st.sign}'s sign is {sg.card.Size.X.Offset} px wide over a {span} px stall`)
				assert(sg.card.BackgroundColor3 == Rbx.Color3.fromHex(st.a), `{st.sign}'s sign is not in its awning's colour`)
				signs += 1
			end
		end
		assert(signs > 0, "no stall sign was checked")
		-- world lettering lives in a layer under the HUD (the billboard's drew over the prompt card)
		local labels = 0
		for _, t in hub.pool do
			assert(t.Parent == hub.labelLayer and hub.labelLayer ~= hub.gui, `the world label {t.Name} paints over the HUD`)
			labels += 1
		end
		assert(labels > 0, "no world labels were checked")
	end
	-- (no tip on a phone either: it covered a stall and the back of the walking band)
	assert(not hub.prompt.Visible, `away from a station a card shows on a phone: {hub.prompt.Text}`)
	assert(not hub.controls.Visible, "the controls row showed where it runs into the social bar")
	-- beside a station, the action card, placed as below
	do
		local boardSt
		for _, st in PLAZA.market.stations do if st.kind == "Warp" then boardSt = st end end
		stand(boardSt)
		hub:draw(narrow, 1/60)
	end
	-- (a narrow screen: the prompt at the bottom left, above the dock, its right edge short of the
	-- screen's middle where your fighter stands; under the title card it covered the billboard)
	do
		local p = hub.prompt
		assert(p.Visible, "no prompt on a narrow screen")
		local right = p.Position.X.Scale * 812 + p.Position.X.Offset - p.AnchorPoint.X * p.Size.X.Offset + p.Size.X.Offset
		local bottom = p.Position.Y.Scale * 375 + p.Position.Y.Offset + (1 - p.AnchorPoint.Y) * p.Size.Y.Offset
		assert(right <= 812 / 2 - Plaza2D.FIGHTER_CLEAR, `on a narrow screen the prompt reaches x {right}, over your fighter`)
		assert(bottom <= 375 - 10 - Plaza2D.ICON - 14 + 0.01 and p.Position.Y.Scale == 1, `on a narrow screen the prompt's foot is at {bottom}, not above the dock`)
	end
	hub.active, hub.blocked = wasActive, wasBlocked
end
-- The top row sits below Roblox's top bar, and follows it when the bar's height arrives late (it is
-- 0 when the client starts): placed at 58 it moves down, and the next frame (here, no bar) back up.
do
	hub:placeTop(58)
	assert(hub.title.Position.Y.Offset == 70 and hub.directions.Position.Y.Offset == 102 and hub.plate.Position.Y.Offset == 64,
		`under a 58 px bar the top row is at {hub.title.Position.Y.Offset}`)
	-- and the CHARACTER button is not up there at all: Roblox's player list hangs from the top right
	assert(hub.characterButton.Position.Y.Scale == 1 and hub.characterButton.AnchorPoint.Y == 1, "the CHARACTER button is not in the bottom row")
	hub:draw(canvas(1280, 720), 1/60)
	assert(hub.title.Position.Y.Offset == 12, "the top row did not follow the bar's height on the next frame")
end
-- 11. Round 2 of the lobby's review: every station named on a sign, each sign the same gap over what it
--     names and clear of the title card, the tip goes on every screen, a lounge in view whole, and the
--     roofs' ends inked.
do
	hub.gui.AbsoluteSize = { X = 1280, Y = 720 }
	local function plateBottom(): number
		return hub.plate.Position.Y.Offset + hub.plate.Size.Y.Offset
	end
	-- every market station that is a place to go has its name up, and no sign meets the title card
	for _, st in PLAZA.market.stations do
		if st.kind == "Cabinet" then continue end
		-- (from the front of the roof: the camera rides lowest there, so the signs stand highest)
		hub.model:setScene(hub.model.data, { x = st.x, z = 2 })
		hub.camX = st.x
		hub:draw(canvas(1280, 720), 1/60)
		-- (long after walking in: while the district's title is up, a sign under it steps aside)
		hub.bannerAt = -1e9
		hub:draw(canvas(1280, 720), 1/60)
		if st.kind == "Members" or st.kind == "Warp" or st.kind == "Format" then
			local sg = hub.signs and hub.signs["st" .. st.id]
			assert(sg and sg.card.Visible, `the market's {st.id} has no sign`)
		end
		local px1 = hub.plate.Position.X.Offset
		local px2 = px1 + hub.plate.Size.X.Offset
		for id, sg in hub.signs or {} do
			local x1 = sg.card.Position.X.Offset
			local x2 = x1 + sg.card.Size.X.Offset
			-- (only a sign under the card: one off the screen's side is nowhere near it)
			if sg.card.Visible and x2 > px1 and x1 < px2 and x1 < 1280 and x2 > 0 then
				assert(sg.card.Position.Y.Offset >= plateBottom() + 2, `at {st.id} the {id} sign (top {sg.card.Position.Y.Offset}) meets the title card (bottom {plateBottom()})`)
			end
		end
	end
	-- in a lounge: each station's sign the same gap over its own top, and the whole room in view
	hub.model:warp("arcade")
	hub:setRoom({ id = 12, format = "Triples", stage = "FoundryFloor", slots = { { userId = 1, team = 0 } } })
	local real = Plaza2D.placeSign
	local ys: { [string]: number } = {}
	Plaza2D.placeSign = function(self, c, id, value, x, y, ...)
		ys[id] = y
		return real(self, c, id, value, x, y, ...)
	end
	local gaps: { number } = {}
	for _, st in hub.model.data.stations do
		if st.kind == "Exit" then continue end
		stand(st)
		hub.camX = st.x
		hub:draw(canvas(1280, 720), 1/60)
		local top = Plaza2D.stationArt(canvas(1280, 720), st, false, hub.room, nil)
		table.insert(gaps, ys["st" .. st.id] - ((st.z + 1) * PLAZA.depth + top * Plaza2D.STATION_SCALE))
	end
	Plaza2D.placeSign = real
	for _, g in gaps do
		assert(math.abs(g - gaps[1]) < 1e-6, `the lounge's signs hang at different gaps over their stations ({g} and {gaps[1]})`)
	end
	do
		local c = canvas(1280, 720)
		hub:draw(c, 1/60)
		local b = hub.model.data.bounds
		local l, r = c:project(b.x1, 0).X, c:project(b.x2, 0).X
		-- (the camera eases toward its target: settle it first)
		for _ = 1, 200 do hub:draw(c, 1/60) end
		-- every station whole on screen, stairs to ready rail, and the room no smaller than that needs
		-- (fitted to the island's whole width its people stood a third smaller than the market's)
		for _, st in hub.model.data.stations do
			-- (its art's half width: the stairs' doorway 3.6 studs, a desk 6, the rack's screen 8 - each
			-- at the scale the lounge draws its stations)
			local reach = if st.kind == "Exit" then 3.9
				else (if st.kind == "Weapons" then 8.5 else 6.5) * Plaza2D.STATION_SCALE
			local sl, sr = c:project(st.x - reach, 0).X, c:project(st.x + reach, 0).X
			assert(sl >= -1 and sr <= 1281, `the lounge's {st.id} runs off the screen ({sl} to {sr} of 1280)`)
		end
		local scale = math.abs(c:project(1, 0).X - c:project(0, 0).X)
		assert(scale > 1280 / (b.x2 - b.x1) + 0.5, `the lounge is drawn at {scale} px a stud, the island's whole width`)
		local _ = l + r
	end
	assert(hub.district ~= "lounge", "a lounge's district banner repeats the title card's name")
	-- the wall rises to within 60 px of the title card (at 15 studs it started under the stations' signs,
	-- leaving the sky over them as it was), its windows sit between the stations, not behind them, and
	-- the couches stand on its pale plaster, not its deep wainscot
	do
		local c = canvas(1280, 720)
		for _ = 1, 200 do hub:draw(c, 1/60) end
		local wallTop = c:project(0, Plaza2D.WALL_Z * PLAZA.depth + Plaza2D.WALL_H).Y
		local cardBottom = hub.plate.Position.Y.Offset + hub.plate.Size.Y.Offset
		assert(wallTop - cardBottom <= 60, `{wallTop - cardBottom} px of empty sky between the title card and the lounge's wall`)
		local sky = Rbx.Color3.fromHex(Loader.load("Realms").LOBBY.sky[2])
		local windows: { { number } } = {}
		local was = Canvas.sprite
		Canvas.sprite = function(cc: any, key: string, list: any, x0: number, y1: number, pw: number, ...: any)
			if string.find(key, "^prop|wall") then
				for _, r in list do
					if Rbx.Color3.fromHex(r[5]) == sky then table.insert(windows, { x0 + r[1] * pw, x0 + (r[1] + r[3]) * pw }) end
				end
			end
			return was(cc, key, list, x0, y1, pw, ...)
		end
		hub:draw(c, 1/60)
		Canvas.sprite = was
		assert(#windows >= 3, "the lounge's wall has no windows")
		for _, st in hub.model.data.stations do
			-- (the art's own reach, outline and all: the rack's screen frame 8.5 + ink, a desk 6 + ink)
			local half = if st.kind == "Exit" then 3.9 else ((if st.kind == "Weapons" then 8.5 else 6) + 0.3) * Plaza2D.STATION_SCALE
			for _, w in windows do
				-- (half a stud of plaster at least between: one stood 3 px from the weapon rack)
				assert(w[2] <= st.x - half - 0.5 or w[1] >= st.x + half + 0.5, `a window ({w[1]} to {w[2]}) stands behind or against the {st.id} station`)
			end
		end
		-- (less than half of a couch against the wainscot)
		local couchBase = 17.8 * PLAZA.depth
		local couchTop = couchBase + 22 * Loader.loadFrom("src/client/", "PlazaArt").CELL
		local wainscotTop = Plaza2D.WALL_Z * PLAZA.depth + Plaza2D.WAINSCOT
		assert(wainscotTop < (couchBase + couchTop) / 2, "the couches stand on the wall's deep wainscot")
		-- what does stand against the skirting keeps its ink outline: 2:1 or better (1.47:1 on deep indigo)
		local Art = Loader.loadFrom("src/client/", "PlazaArt")
		local Ui = Loader.loadFrom("src/client/", "Ui")
		-- (every colour in the wall's bottom rows, where the couches and desks stand: its fill's dark showed
		-- under the skirting at 1.47:1)
		do
			local low, h = 3, 196
			local art = Art.loungeWall(400, h, { 100 }, "#6FB5F2", low, "#BFE3FA")
			-- (painted in order, so only what shows is checked: the wall's fill lies under everything)
			local footTop = art.h - (low + 3)
			local cell: { [number]: string } = {}
			for _, r in art.rects do
				if (r[6] or 1) >= 1 then
					for y = math.max(r[2], footTop), math.min(r[2] + r[4], art.h) - 1 do
						for x = r[1], r[1] + r[3] - 1 do cell[y * 1000 + x] = r[5] end
					end
				end
			end
			for key, hex in cell do
				local x = key % 1000
				if hex ~= Art.C.ink and x > 1 and x < art.w - 2 then
					local ratio = Ui.contrast(Rbx.Color3.fromHex(Art.C.ink), Rbx.Color3.fromHex(hex))
					assert(ratio >= 3, `an ink outline reads at {ratio}:1 on the wall's skirting ({hex})`)
				end
			end
		end
		-- and the plaster is in courses, not one flat colour (53% of the band behind the stations)
		local wallArt = Art.loungeWall(400, 196, { 100 }, "#6FB5F2", 3, "#BFE3FA")
		-- (the window's view: an island across most of the pane, not a speck)
		local widest = 0
		for _, r in wallArt.rects do if r[5] == Art.C.green then widest = math.max(widest, r[3]) end end
		assert(widest >= 37 * 0.6, `the window's island is {widest} cells across a 37-cell pane`)
		local courses = 0
		for _, r in wallArt.rects do if r[5] == Art.C.plasterDk then courses += 1 end end
		assert(courses >= 10, `the lounge's plaster has {courses} course lines`)
	end
	-- the lounge is a room: its back wall stands behind the stations (its upper fifth was empty sky)
	do
		local keys: { [string]: boolean } = {}
		local was = Canvas.sprite
		Canvas.sprite = function(c: any, key: string, ...: any)
			keys[key] = true
			return was(c, key, ...)
		end
		hub:draw(canvas(1280, 720), 1/60)
		Canvas.sprite = was
		local wall = false
		for k in keys do if string.find(k, "^prop|wall") then wall = true end end
		assert(wall, "the lounge has no back wall")
	end
	-- framed on its stations: the floor under its front edge an eighth of the screen or less (framed
	-- as the market, a quarter was empty floor and island)
	do
		local c = canvas(1280, 720)
		for _ = 1, 200 do hub:draw(c, 1/60) end
		local front = math.huge
		for _, r in hub.model.data.floor do front = math.min(front, r.z1 * PLAZA.depth) end
		local railY = c:project(0, front).Y
		assert(railY >= 720 * 0.86, `the lounge's front edge is at y {railY}: the rest of the screen is empty floor`)
	end
	hub:setRoom({ left = true })
	-- on a wide screen there is no tip card over the roof at all (it cut the legs off people at the
	-- front): the title card's directions say where things are; the card is only ever an action
	hub.model:setScene(hub.model.data, { x = 0, z = 8 })
	hub.camX = 0
	hub:draw(canvas(1280, 720), 1/60)
	assert(not hub.prompt.Visible, "a tip card shows over the roof on a wide screen")
	assert(string.find(hub.directions.Text, "East", 1, true) and string.find(hub.directions.Text, "West", 1, true),
		`the title card does not say which way things are: {hub.directions.Text}`)
	local board
	for _, st in PLAZA.market.stations do if st.kind == "Warp" then board = st end end
	stand(board)
	hub:draw(canvas(1280, 720), 1/60)
	assert(hub.prompt.Visible and hub.promptKey.Visible, "beside a station on a wide screen the action card does not show")
	-- each roof's ends are inked: an ink rect hard against each end of every roof in view
	do
		local inked: { [number]: boolean } = {}
		Canvas.rect = function(c, x, _y, w, _h, colour, ...)
			if colour == Rbx.Color3.fromRGB(15, 18, 24) then inked[math.floor((x + w) * 1000 + 0.5)] = true; inked[math.floor(x * 1000 + 0.5)] = true end
			c.used += 1
		end
		local scene = hub.model.data
		hub:drawGround(canvas(1280, 720), scene, -1e9, 1e9)
		Canvas.rect = primitive
		local roofs = 0
		for _, r in scene.floor do
			if r.bridge then continue end
			assert(inked[math.floor(r.x1 * 1000 + 0.5)] and inked[math.floor(r.x2 * 1000 + 0.5)], `the roof from {r.x1} to {r.x2} has an end with no ink`)
			roofs += 1
		end
		assert(roofs > 0, "no roofs checked")
	end
end

-- 12. Round 3: signs clear of the district title while it shows, pale signs lettered in ink, a
--     cabinet's state on kit tags.
do
	hub.gui.AbsoluteSize = { X = 1280, Y = 720 }
	local Ui = Loader.loadFrom("src/client/", "Ui")
	for _, w in PLAZA.market.warps do
		hub.model:warp(w.id)
		hub.district = nil          -- walked in just now: the title is up
		hub.model:setScene(hub.model.data, { x = hub.model.p.x, z = 2 })
		hub.camX = hub.model.p.x
		hub:draw(canvas(1280, 720), 1/60)
		assert(hub.banner.TextTransparency < 1, `no district title at {w.id}`)
		local tw = Ui.textWidth(hub.banner.Text, 40, Ui.DISPLAY)
		local bx1, bx2 = 640 - tw / 2 - 12, 640 + tw / 2 + 12
		local bottom = hub.banner.Position.Y.Offset + hub.banner.Size.Y.Offset
		for id, sg in hub.signs or {} do
			local x1 = sg.card.Position.X.Offset
			local x2 = x1 + sg.card.Size.X.Offset
			if sg.card.Visible and x2 > bx1 and x1 < bx2 then
				assert(sg.card.Position.Y.Offset >= bottom + 16, `at {w.id} the {id} sign (top {sg.card.Position.Y.Offset}) meets the district title (bottom {bottom})`)
			end
		end
		-- and the station you walked in for keeps its sign up under the title, clear of it
		if w.id == "tailor" then
			assert(hub.signs.wardrobe and hub.signs.wardrobe.card.Visible, "the wardrobe's sign is hidden under the district title")
		end
	end
	-- a pale face is lettered in ink, a deep one in white (white on the gold lift measured 1.17:1; the
	-- skewer stall's yellow is the pale one now)
	hub.model:setScene(hub.model.data, { x = 28, z = 8 })
	hub.camX = 28
	hub:draw(canvas(1280, 720), 1/60)
	local checked = 0
	for id, sg in hub.signs do
		local white = Ui.contrast(Ui.WHITE, sg.face)
		if white < 2 then
			assert(sg.text.TextColor3 == Ui.INK, `the {id} sign is white on a face it measures {white}:1 against`)
			checked += 1
		elseif white > 3 then
			assert(sg.text.TextColor3 == Ui.WHITE, `the {id} sign is ink on a deep face`)
		end
	end
	assert(checked > 0, "no pale sign checked")
	-- and an ink word has no halo: the olive outline closed its counters (the UI's yellows have none)
	for id, sg in hub.signs do
		if sg.pale then assert(sg.outline.Enabled == false, `the {id} sign's ink words carry a halo`) end
	end
	-- in a crowd no two name tags' words meet (nine sat on two baselines and read as one line)
	do
		local list = {}
		for i = 1, 12 do
			local p = KIT.presets[(i * 3) % #KIT.presets + 1]
			-- (shoulder to shoulder in two rows, so untreated their tags would collide)
			table.insert(list, { userId = 100 + i, name = p.name, avatar = p.code, weapon = "Sword",
				x = -9 + ((i - 1) % 6) * 3, z = if i <= 6 then 6 else 6.4, y = 0, facing = 1 })
		end
		hub:setPeers(list, 1)
		for _, peer in hub.peers do peer.x, peer.z = peer.target.x, peer.target.z end
		hub.model:setScene(hub.model.data, { x = 0, z = 8 })
		hub.camX = 0
		hub:draw(canvas(1280, 720), 1/60)
		local boxes = {}
		for id, t in hub.pool do
			if string.sub(id, 1, 4) == "name" and t.Visible then
				local w = Ui.textWidth(t.Text, 12)
				local cx, cy = t.Position.X.Offset + t.Size.X.Offset / 2, t.Position.Y.Offset + t.Size.Y.Offset / 2
				table.insert(boxes, { cx - w / 2, cy - 8, cx + w / 2, cy + 8, t.Text })
			end
		end
		assert(#boxes >= 10, `only {#boxes} tags in the crowd`)
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				local a, b = boxes[i], boxes[j]
				assert(not (a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]), `the name tags overlap: {a[5]} and {b[5]}`)
			end
		end
		hub:setPeers({}, 1)
	end
	-- a sign mostly off the screen's side is hidden, one on it is not
	do
		hub.gui.AbsoluteSize = { X = 812, Y = 375 }
		local seen = 0
		for x = -60, 60, 6 do
			hub.model:setScene(hub.model.data, { x = x, z = 8 })
			hub.camX = x
			hub:draw(canvas(812, 375), 1/60)
			for id, sg in hub.signs do
				local c = sg.card
				local x1, w = c.Position.X.Offset, c.Size.X.Offset
				-- (the whole card on the screen, or none of it: a marquee 62% on read "5" for 05, and with
				-- its pad allowed off NOTICE BOARD lost its frame)
				if c.Visible then
					assert(x1 >= 0 and x1 + w <= 812, `the {id} sign's card runs off the screen ({x1} to {x1 + w} of 812)`)
					seen += 1
				end
			end
		end
		assert(seen > 0, "no signs on the phone")
		-- and no two cards meet anywhere along it (NOTICE BOARD's, slid on, met MASKS')
		for x = -60, 60, 3 do
			hub.model:setScene(hub.model.data, { x = x, z = 8 })
			hub.camX = x
			hub:draw(canvas(812, 375), 1/60)
			local cards = {}
			for id, sg in hub.signs do if sg.card.Visible then table.insert(cards, { id, sg.card }) end end
			for i = 1, #cards do
				for j = i + 1, #cards do
					local a, b = cards[i][2], cards[j][2]
					-- (each card's 3 px stroke is drawn outside it: two cards closer than 6 px touch)
					local ax, ay, bx, by = a.Position.X.Offset, a.Position.Y.Offset, b.Position.X.Offset, b.Position.Y.Offset
					local g = 6
					assert(not (ax < bx + b.Size.X.Offset + g and bx < ax + a.Size.X.Offset + g and ay < by + b.Size.Y.Offset + g and by < ay + a.Size.Y.Offset + g),
						`at x {x} on the phone the {cards[i][1]} and {cards[j][1]} signs meet`)
				end
			end
			-- nor meets the title card (risen over an awning, NOTICE BOARD's did)
			local cardBottom = hub.plate.Position.Y.Offset + hub.plate.Size.Y.Offset
			local cardRight = hub.plate.Position.X.Offset + hub.plate.Size.X.Offset
			for id, sg in hub.signs do
				local c = sg.card
				if c.Visible and c.Position.X.Offset < cardRight + 6 then
					assert(c.Position.Y.Offset >= cardBottom + 6, `at x {x} on the phone the {id} sign meets the title card`)
				end
			end
			-- nor does a station's sign, slid on, cover a stall's awning (NOTICE BOARD's hid 18 px of MASKS')
			local c375 = canvas(812, 375)
			hub:draw(c375, 1/60)
			for _, st in Plaza2D.STALLS do
				local l, r = c375:project(st.x - 6, 0).X, c375:project(st.x + 6, 0).X
				local top, bottom = c375:project(0, 18.8 * PLAZA.depth + 10).Y, c375:project(0, 18.8 * PLAZA.depth + 7.4).Y
				for id, sg in hub.signs do
					local c = sg.card
					-- (a sign slid along from over its own station - one standing over its own, in front of a stall
					-- behind it, is drawn as the depth has it)
					local slid = sg.anchorX and math.abs(c.Position.X.Offset + c.Size.X.Offset / 2 - sg.anchorX) > 2
					if c.Visible and slid and string.sub(id, 1, 5) ~= "stall" then
						local cx, cy = c.Position.X.Offset, c.Position.Y.Offset
						assert(not (cx < r and l < cx + c.Size.X.Offset and cy < bottom and top < cy + c.Size.Y.Offset),
							`at x {x} on the phone the {id} sign lies over the {st.sign} stall's awning`)
					end
				end
			end
		end
		-- a station still on the screen keeps its name: its card slides on rather than going (NOTICE
		-- BOARD's went whole)
		local named = 0
		for x = -60, 60, 3 do
			hub.model:setScene(hub.model.data, { x = x, z = 8 })
			hub.camX = x
			hub:draw(canvas(812, 375), 1/60)
			-- (every station's sign, standing on the screen by 30 px: one at its very edge, with no room, may go)
			for _, id in { "stBoard", "stMap" } do
				local sg = hub.signs[id]
				if sg and sg.anchorX and sg.anchorX > 30 and sg.anchorX < 812 - 30 then
					assert(sg.card.Visible, `the {id} station stands on the screen (x {sg.anchorX}) with no name`)
					named += 1
				end
			end
		end
		assert(named > 0, "the notice board never stood on the phone's screen")
		-- and on the phone the walking band's front clears the buttons' row (they sat on its front 32 px)
		hub.model:setScene(hub.model.data, { x = 0, z = 8 })
		hub.camX = 0
		local c = canvas(812, 375)
		for _ = 1, 3 do hub:draw(c, 1/60) end
		local front = math.huge
		for _, r in hub.model.data.floor do if r.x1 <= 0 and r.x2 >= 0 then front = math.min(front, r.z1 * PLAZA.depth) end end
		local edge = c:project(0, front).Y
		assert(edge <= 375 - 10 - Plaza2D.ICON, `on a phone the walking band runs to y {edge}, under the buttons (from {375 - 10 - Plaza2D.ICON})`)
		-- and the billboard's BLOCKFALL clear of the title card (framed lower, it went under the card)
		local bb = hub.pool["billboard"]
		assert(bb and bb.Visible, "no BLOCKFALL on the phone's billboard")
		local wordsTop = bb.Position.Y.Offset + bb.Size.Y.Offset / 2 - bb.TextSize / 2
		local cardBottom = hub.plate.Position.Y.Offset + hub.plate.Size.Y.Offset
		assert(wordsTop >= cardBottom, `on a phone BLOCKFALL's top (y {wordsTop}) is under the title card (to y {cardBottom})`)
		hub.gui.AbsoluteSize = { X = 1280, Y = 720 }
	end
	-- the floor is a mid-tone stone white names read on at 2:1 or better (pale flagstones were the
	-- biggest light mass on screen, white on them 1.4:1)
	do
		local RealmArt = Loader.loadFrom("src/client/", "RealmArt")
		-- (every stone tone, by a wide roof's area: the grass lip along its back aside)
		local lobby = Loader.load("Realms").LOBBY
		local art = RealmArt.paving(lobby, 80, 12, 1)
		local stone, light = 0, 0
		for _, r in art.rects do
			if r[5] ~= lobby.top[2] and r[5] ~= lobby.top[3] then
				stone += r[3] * r[4]
				if Ui.contrast(Ui.WHITE, Rbx.Color3.fromHex(r[5])) < 2 then light += r[3] * r[4] end
			end
		end
		assert(stone > 0 and light / stone < 0.05, `{math.floor(light / stone * 100)}% of the paving is a stone white names read under 2:1 on`)
	end
end

-- 13. Your reflection in the tailor's mirror reads as one: glass over it at 0.3 or more (at 0.1 the
--     knight in the mirror read as a second player in the doorway)
do
	local glass = 0
	Canvas.rect = function(c, _x, _y, w, h, _colour, alpha)
		if math.abs(w - 4.8) < 1e-6 and math.abs(h - 8.7) < 1e-6 then glass = math.max(glass, alpha or 1) end
		c.used += 1
	end
	local wardrobe
	for _, st in PLAZA.market.stations do if st.kind == "Wardrobe" then wardrobe = st end end
	hub:drawWardrobe(canvas(1280, 720), wardrobe, 0)
	Canvas.rect = primitive
	assert(glass >= 0.3, `the mirror's glass is {glass} over your reflection`)
end

-- 14. The billboard at the screen's edge keeps the game's name, shrunk into the visible part of its
--     screen (hidden whole, the board was a blank panel 175 px wide)
do
	local Ui = Loader.loadFrom("src/client/", "Ui")
	hub.gui.AbsoluteSize = { X = 1280, Y = 720 }
	local kept = 0
	for x = -60, -30, 2 do
		hub.model:setScene(hub.model.data, { x = x, z = 15 })
		hub.camX = x
		hub:draw(canvas(1280, 720), 1/60)
		local span = hub.billboardSpan
		local t = hub.pool["billboard"]
		if span and span[1] < 1280 - 80 and span[2] > 1280 then
			assert(t and t.Visible, `the billboard stands half on the screen (x {span[1]}) with no name on it`)
			local w = Ui.textWidth(t.Text, t.TextSize / Ui.SCALE, t.Font)
			local cx = t.Position.X.Offset + t.Size.X.Offset / 2
			assert(cx - w / 2 >= 0 and cx + w / 2 <= 1280, `the billboard's name runs off the screen ({cx - w / 2} to {cx + w / 2})`)
			kept += 1
		end
	end
	assert(kept > 0, "the billboard never stood half on the screen")
end

-- 10. Every outlined prop has an ink line round its silhouette, but not under its base: bare, the
--     props were flat colour on the pale paving with no edge, beside fighters drawn in ink.
do
	local Art = Loader.loadFrom("src/client/", "PlazaArt")
	local inkHex = Art.C.ink
	local checked = 0
	for _, name in { "billboard", "kiosk", "waterTower", "acUnit", "mapSign", "boutique", "recordBoard", "plant" } do
		local prop = Art[name]()
		local solid, ink = {}, {}
		for _, r in prop.rects do
			for y = r[2], r[2] + r[4] - 1 do
				for x = r[1], r[1] + r[3] - 1 do
					if r[5] == inkHex and r[6] >= 1 then ink[y * 4096 + x] = true end
					if (r[6] or 1) >= 0.8 and r[5] ~= inkHex then solid[y * 4096 + x] = true end
				end
			end
		end
		local missing = 0
		for key in solid do
			local x, y = key % 4096, key // 4096
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, -1 }, { 0, 1 } } do
				local nx, ny = x + d[1], y + d[2]
				local nk = ny * 4096 + nx
				if ny < prop.h and not solid[nk] and not ink[nk] then missing += 1 end
			end
		end
		assert(missing == 0, `{name}: {missing} silhouette edges with no ink`)
		checked += 1
	end
	assert(checked >= 8, "no props checked")
end

print(`PASS lobby view: walking in depth, stations offered where they stand, modal/chat guards, {visits} finite bounded draws (peak {peak} primitives), depth order, wardrobe, CHARACTER button, district banners, lounges show the room`)
