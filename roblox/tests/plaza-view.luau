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
	before = poses[hub.char]
	for _ = 1, 12 do hub:step(1/60, false); hub:drawWardrobe(c, wardrobe, 0) end
	after = poses[hub.char]
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

-- 4. Depth: a player behind a cabinet is drawn before it, one in front after it.
do
	local cab = PLAZA.cabinets[1]
	local order: { string } = {}
	-- Cabinet 1 by where it is drawn: every cabinet shares one sprite, and the back row (drawn
	-- first) stands at the same x.
	local D = PLAZA.depth
	-- (where PlazaArt.draw puts the pair's top-left, from its own size: outlined, it grew a cell)
	local pair = Loader.loadFrom("src/client/", "PlazaArt").cabinetPair()
	local cell = 1 / 8
	Canvas.sprite = function(c: any, key: string, _list: any, x0: number, y1: number, ...: any)
		if key == "prop|cab" and math.abs(x0 - (cab.x - pair.w * cell / 2)) < 1e-6 and math.abs(y1 - (cab.z * D + pair.h * cell)) < 1e-6 then
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
	-- a name tag is outlined in ink at 2 px, as the signs' words (TextStroke is 1 px; at a 0.55 stroke a
	-- name over the sky was grey on grey)
	local tag = hub.pool["name2"]
	local stroke = hub.tagStrokes and hub.tagStrokes[2]
	assert(tag and tag.Visible and type(stroke) == "table" and stroke.Thickness >= 2, "the guest's name tag is not outlined")
	-- the back row of cabinets in its dark shades (the same art at the same x read as one locker)
	do
		local keys: { [string]: boolean } = {}
		local was = Canvas.sprite
		Canvas.sprite = function(c: any, key: string, ...: any)
			keys[key] = true
			return was(c, key, ...)
		end
		hub:draw(canvas(1280, 720), 1/60)
		Canvas.sprite = was
		assert(keys["prop|cab"] and keys["prop|cabFar"], "the arcade's two rows of cabinets are drawn alike")
	end
	-- each cabinet's number sits on its own marquee (rows 44-54 of the pair's 56), not over it, where the
	-- front row's numbers landed on the back row's cabinets
	do
		local real = Plaza2D.placeSign
		local at: { [string]: number } = {}
		Plaza2D.placeSign = function(self, c, id, value, x, y, ...)
			at[id] = y
			return real(self, c, id, value, x, y, ...)
		end
		hub:draw(canvas(1280, 720), 1/60)
		Plaza2D.placeSign = real
		local y = at["cab" .. cab.number]
		assert(y, "cabinet 1 has no number sign")
		local rel = (y - cab.z * D) / cell
		assert(rel >= 44 and rel <= 55, `cabinet 1's number is at row {rel} of its art, not on its marquee`)
	end
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
		hub.camX = hub.model.p.x          -- (the camera on you: off the screen, a sign is hidden)
		hub:draw(canvas(1280, 720), 1/60)
		for id, t in hub.pool do if t.Visible then labelsSeen[id] = t.Text end end
		-- (and the kit signs', by their own id: a cabinet's state is on tags now)
		for id, sg in hub.signs or {} do if sg.card.Visible then labelsSeen[id] = sg.text.Text end end
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
	assert(labelsSeen["cabT3"] == "READY · 3" and labelsSeen["cabS3"] == "3 WINS  Rin", "the countdown and the champion's streak show on the cabinet")
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
	for _, st in PLAZA.market.stations do
		if st.kind == "Format" then
			stand(st)
			hub.gui.AbsoluteSize = { X = 1280, Y = 720 }
			hub:draw(canvas(1280, 720), 1/60)
			assert(hub.promptKey.Visible and string.find(hub.prompt.Text, "ENTER", 1, true) and not string.find(hub.prompt.Text, "[E", 1, true),
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
		for _, st in PLAZA.market.stations do if st.kind == "Members" then boardSt = st end end
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
	for _, st in PLAZA.market.stations do if st.kind == "Members" then board = st end end
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
				assert(sg.card.Position.Y.Offset >= bottom + 4, `at {w.id} the {id} sign (top {sg.card.Position.Y.Offset}) meets the district title (bottom {bottom})`)
			end
		end
	end
	-- a pale face is lettered in ink, a deep one in white (white on the gold lift measured 1.17:1)
	for _, st in PLAZA.market.stations do
		if st.kind == "Format" then
			hub.model:setScene(hub.model.data, { x = st.x, z = 8 })
			hub.camX = st.x
			hub:draw(canvas(1280, 720), 1/60)
		end
	end
	local checked = 0
	for id, sg in hub.signs do
		local white = Ui.contrast(Ui.WHITE, sg.face)
		if white < 1.5 then
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
	-- the arcade's back row drawn smaller than the front (as well as darker), and its canopy low over
	-- the machines, not a band of empty sky above them
	do
		local Art = Loader.loadFrom("src/client/", "PlazaArt")
		local scales: { [string]: number } = {}
		local was = Canvas.sprite
		Canvas.sprite = function(c: any, key: string, list: any, x0: number, y1: number, pw: number, ...: any)
			scales[key] = pw
			return was(c, key, list, x0, y1, pw, ...)
		end
		hub.model:warp("arcade")
		hub:draw(canvas(1280, 720), 1/60)
		Canvas.sprite = was
		assert(scales["prop|cabFar"] and scales["prop|cab"] and scales["prop|cabFar"] < scales["prop|cab"] * 0.95,
			"the arcade's back row is no smaller than the front")
		assert(scales["prop|marquee"], "no marquee board over the arcade's canopy: a quarter of the screen of empty sky")
		local D = PLAZA.depth
		local beam = 20.5 * D + (Plaza2D.CANOPY_H - 14) * Art.CELL
		local backTop = 0
		for _, cab in PLAZA.cabinets do backTop = math.max(backTop, cab.z * D + 56 * Art.CELL * (if cab.z > Plaza2D.CAB_BACK then Plaza2D.CAB_FAR_SCALE else 1)) end
		assert(beam - backTop <= 2, `{beam - backTop} studs of empty sky between the arcade's canopy and its cabinets`)
	end
	-- a cabinet counting down shows it on a kit tag, not bare words
	hub.model:warp("arcade")
	hub.camX = hub.model.p.x
	hub:setCabinets({ { number = 1, state = "countdown", startsIn = 3, seats = {} } }, 1)
	hub:draw(canvas(1280, 720), 1/60)
	local tagSign = hub.signs and hub.signs.cabT1
	assert(tagSign and tagSign.card.Visible and string.find(tagSign.text.Text, "READY", 1, true), "cabinet 1's countdown is not on a tag")
	local bare = hub.pool["cabT1"]
	assert(not bare or bare.Visible == false, "cabinet 1's countdown is bare words")
	hub:setCabinets({}, 1)
	-- a name tag over a cabinet's number hides the number (Corsair's sat on 06's, one baseline)
	do
		local cab
		for _, cb in PLAZA.cabinets do if cb.number == 6 then cab = cb end end
		hub:setPeers({ { userId = 9, name = "Corsair", avatar = "Classic", weapon = "Sword", x = cab.x, z = cab.z - 4.5, y = 0, facing = 1 } }, 1)
		hub.peers[9].x, hub.peers[9].z = cab.x, cab.z - 4.5
		hub.model:setScene(hub.model.data, { x = cab.x, z = 3 })
		hub.camX = cab.x
		local c = canvas(1280, 720)
		hub:draw(c, 1/60)
		local tag, num = hub.pool["name9"], hub.signs["cab6"]
		assert(tag and tag.Visible, "the guest's name tag is not up")
		assert(num.card.Visible, "cabinet 06 lost its number under a name tag")
		-- the tag's words (20 px about its centre) clear of the number's card
		local tcy = tag.Position.Y.Offset + tag.Size.Y.Offset / 2
		local n1, n2 = num.card.Position.Y.Offset, num.card.Position.Y.Offset + num.card.Size.Y.Offset
		assert(tcy + 10 <= n1 or tcy - 10 >= n2, "a name tag is drawn over cabinet 06's number")
		-- (and where the guest stands, the tag would have met it: its own place is on the number)
		local peer = hub.peers[9]
		local natural = c:project(peer.x, peer.z * PLAZA.depth + peer.char.height + 1.6).Y
		assert(natural + 10 > n1 and natural - 10 < n2, "the test's guest does not stand where a tag meets 06's number")
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
				-- (all of its words on the screen, or none: a marquee 62% on read "5" for 05)
				local pad = Plaza2D.SIGN_PAD
				if c.Visible then
					assert(x1 + pad >= 0 and x1 + w - pad <= 812, `the {id} sign's words run off the screen ({x1 + pad} to {x1 + w - pad} of 812)`)
					seen += 1
				end
			end
		end
		assert(seen > 0, "no signs on the phone")
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
	-- each lift shows how many a side it takes, so the three are not the same grey doors
	do
		local Art = Loader.loadFrom("src/client/", "PlazaArt")
		local function sig(prop: any): string
			local parts = {}
			for _, r in prop.rects do table.insert(parts, table.concat({ r[1], r[2], r[3], r[4] }, ",")) end
			return table.concat(parts, ";")
		end
		local a, b, c = sig(Art.lift("#FFFFFF", 1)), sig(Art.lift("#FFFFFF", 2)), sig(Art.lift("#FFFFFF", 3))
		assert(a ~= b and b ~= c and a ~= c, "the three lifts' doors are drawn alike")
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

-- 10. Every outlined prop has an ink line round its silhouette, but not under its base: bare, the
--     props were flat colour on the pale paving with no edge, beside fighters drawn in ink.
do
	local Art = Loader.loadFrom("src/client/", "PlazaArt")
	local inkHex = Art.C.ink
	local checked = 0
	for _, name in { "billboard", "kiosk", "waterTower", "acUnit", "noticeBoard", "mapSign", "cabinetPair", "stool",
		"boutique", "recordBoard", "plant" } do
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
	assert(checked >= 10, "no props checked")
end

print(`PASS lobby view: walking in depth, stations offered where they stand, modal/chat guards, {visits} finite bounded draws (peak {peak} primitives), depth order, wardrobe, CHARACTER button, district banners, lounges show the room`)
