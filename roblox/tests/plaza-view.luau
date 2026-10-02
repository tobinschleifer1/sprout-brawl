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
	drawnWeapons[id] = true
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
	return obj
end
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
local PLAZA = Loader.load("Data/Plaza")
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
for _, st in PLAZA.market.stations do if st.kind == "Members" then board = st end end
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

-- 4. Depth: a player behind a cabinet is drawn before it, one in front after it.
do
	local cab = PLAZA.cabinets[1]
	local order: { string } = {}
	-- Cabinet 1 by where it is drawn: every cabinet shares one sprite, and the back row (drawn
	-- first) stands at the same x.
	local D = PLAZA.depth
	Canvas.sprite = function(c: any, key: string, _list: any, x0: number, y1: number, ...: any)
		if key == "prop|cab" and math.abs(x0 - (cab.x - 4)) < 1e-6 and math.abs(y1 - (cab.z * D + 7)) < 1e-6 then
			table.insert(order, "cab")
		end
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
		hub:setPeers({ { userId = 2, name = "Guest", avatar = guest, weapon = "Sword", x = cab.x, z = z, y = 0, facing = 1 } }, 1)
		hub.peers[2].z, hub.peers[2].x = z, cab.x
		stand({ x = cab.x - 8, z = 9 })
		hub.camX = cab.x
		hub:draw(canvas(1280, 720), 1/60)
		local firstCab, firstGuest = nil, nil
		for i, what in order do
			if what == "cab" and not firstCab and i then firstCab = i end
			if what == "person:" .. guest and not firstGuest then firstGuest = i end
		end
		return { tostring(firstCab), tostring(firstGuest) }
	end
	local behind = drawWith(cab.z + 1.5)
	assert(tonumber(behind[2]) and tonumber(behind[1]) and tonumber(behind[2]) < tonumber(behind[1]), "a player behind cabinet 1 must be drawn before it")
	local infront = drawWith(cab.z - 1.5)
	assert(tonumber(infront[2]) > tonumber(infront[1]), "a player in front of cabinet 1 must be drawn after it")
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

-- 5b. Overheads: a stamp over the stamper, a bubble over the speaker, nothing over anyone else.
do
	local over = { [1] = { kind = "stamp", id = "gg" }, [2] = { kind = "say", text = "GG!" } }
	hub.social = { overhead = function(_, id) local o = over[id]; if o then return o, 0.5, 2.6 end return nil end }
	hub.localId = 1
	hub:setPeers({ { userId = 2, name = "Talker", avatar = KIT.presets[4].code, weapon = "Sword", x = 3, z = 8, y = 0, facing = 1 },
		{ userId = 3, name = "Quiet", avatar = KIT.presets[6].code, weapon = "Sword", x = -3, z = 8, y = 0, facing = 1 } }, 1)
	for _, peer in hub.peers do peer.x, peer.z = peer.target.x, peer.target.z end
	stand({ x = 0, z = 8 })
	hub.camX = 0
	local stampAt: any = nil
	Canvas.sprite = function(c: any, key: string, _list: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number, ...: any)
		if key == "ovh|gg" then stampAt = { x = x0 + cols * pw / 2, y = y1 } end
		primitive(c, x0, y1)
	end
	hub:draw(canvas(1280, 720), 1/60)
	assert(stampAt and math.abs(stampAt.x - 0) < 0.01 and stampAt.y > 8 * PLAZA.depth + 5, "your stamp over your own head")
	local bubble = hub.pool["bub2"]
	assert(bubble and bubble.Visible and bubble.Text == "GG!", "the speaker's bubble shows what they said")
	assert(not hub.pool["bub3"] or not hub.pool["bub3"].Visible, "no bubble over someone who said nothing")
	hub.social, hub.localId = nil, nil
	hub:setPeers({}, 1)
	Canvas.sprite = function(c: any, key: string, _list: any, ...: any)
		table.insert(sprites, key)
		primitive(c, ...)
	end
end

-- 5c. The arcade: a seat's use depends on the cabinet; seated, you stay put, facing the machine.
do
	local intents: { any } = {}
	hub.onCabinet = function(intent) table.insert(intents, intent) end
	local seatA, seatB
	for _, st in PLAZA.market.stations do
		if st.id == "Cab3A" then seatA = st end
		if st.id == "Cab3B" then seatB = st end
	end
	local function views(state: string, seats: any, extra: any?): any
		local list = {}
		for _, cab in PLAZA.cabinets do
			local v = { number = cab.number, state = "open", seats = {}, watchers = 0 }
			if cab.number == 3 then
				v.state, v.seats = state, seats
				for k, val in extra or {} do v[k] = val end
			end
			table.insert(list, v)
		end
		return list
	end
	local labelsSeen: { [string]: string } = {}
	local function frame()
		hub:draw(canvas(1280, 720), 1/60)
		for id, t in hub.pool do if t.Visible then labelsSeen[id] = t.Text end end
	end
	-- Open cabinet: sit at the seat you stand by.
	hub:setCabinets(views("open", {}), 1)
	stand(seatA)
	hub:interact()
	assert(intents[#intents].action == "sit" and intents[#intents].cabinet == 3 and intents[#intents].side == "A", "an empty seat is sat at")
	-- Taken: nothing to do there; the prompt says so.
	hub:setCabinets(views("open", { A = { userId = 7, name = "Rin" } }), 1)
	local n = #intents
	hub:interact()
	frame()
	assert(#intents == n and string.find(hub.prompt.Text, "TAKEN"), "a taken seat cannot be sat in, and says so")
	-- A fight on: watch it, and the cabinet says who is watching.
	hub:setCabinets(views("playing", { A = { userId = 7, name = "Rin" }, B = { userId = 8, name = "Kai" } }, { watchers = 2 }), 1)
	stand(seatB)
	hub:interact()
	frame()
	assert(intents[#intents].action == "watch" and intents[#intents].cabinet == 3, "a busy cabinet is watched")
	assert(labelsSeen["cabT3"] == "IN PLAY · 2 watching", `the cabinet says it is in play, got {labelsSeen["cabT3"]}`)
	-- Countdown and streak on the cabinet.
	hub:setCabinets(views("countdown", { A = { userId = 7, name = "Rin" }, B = { userId = 8, name = "Kai" } }, { startsIn = 2.4, streak = { userId = 7, name = "Rin", wins = 3 } }), 1)
	frame()
	assert(labelsSeen["cabT3"] == "READY · 3" and labelsSeen["cabS3"] == "3 WINS\nRin", "the countdown and the champion's streak show on the cabinet")
	-- Seated: locked to the seat, facing the machine, walking moves nothing; E gets up; alone, C plays the CPU.
	hub:setCabinets(views("open", { A = { userId = 1, name = "Me" } }), 1)
	stand({ x = 0, z = 8 })
	hub.input.frame.x = 1
	for _ = 1, 20 do hub:step(1/60, false) end
	hub.input.frame.x = 0
	assert(hub.model.p.x == seatA.x and hub.model.p.z == seatA.z and hub.model.p.facing == seatA.facing, "a seated player stays at the seat, facing the cabinet")
	assert(hub.cpuButton.Visible, "alone at a cabinet, the CPU button shows")
	hub:interact()
	assert(intents[#intents].action == "stand", "E at your seat gets up")
	cDown = true
	hub:step(1/60, false)
	hub:step(1/60, false)
	cDown = false
	assert(intents[#intents].action == "cpu" and intents[#intents - 1].action == "stand", "C once plays the CPU, once")
	hub:setCabinets(views("countdown", { A = { userId = 1, name = "Me" }, B = { userId = 8, name = "Kai" } }), 1)
	hub:step(1/60, false)
	assert(not hub.cpuButton.Visible, "no CPU once someone sits across")
	hub:setCabinets(views("open", {}), 1)
	hub:step(1/60, false)
	hub.onCabinet = nil
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
	for _, d in PLAZA.market.districts do assert(seen[d.name], `no banner for {d.name}`) end
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
		if key == "232,162,74" and math.abs(w - 3.4) < 1e-6 and math.abs(h - 2.4) < 1e-6 then frames += 1 end
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
	for _, w in Loader.load("Data/Weapons").LIST do assert(drawnWeapons[w.id], "the rack shows every weapon: " .. w.id) end
	for _, st in PLAZA.rooms.Doubles.stations do
		stand(st)
		hub:draw(canvas(1280, 720), 1/60)
		assert(hub.gui.attributes.NearbyStation == st.id, `lounge station {st.id} not offered where it stands`)
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
print(`PASS lobby view: walking in depth, stations offered where they stand, modal/chat guards, {visits} finite bounded draws (peak {peak} primitives), depth order, wardrobe, CHARACTER button, district banners, lounges show the room`)
