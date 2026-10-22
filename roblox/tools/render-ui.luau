--!nocheck
-- Development tool, not a test: one of the game's screens built by its real module against
-- stand-in Instances (Recorder.gui), with anything it draws on the game canvas recorded - written as
-- JSON for tools/gui-svg.mjs, so a screen can be looked at without Studio.
--
--   lune run tools/render-ui <out.json> <plaza|studio|hud|results|records|notice|people|climb|locker|shop> [width] [height] [variant]
--     plaza   variant: "x,z" where you stand (beside a station shows its prompt; the default shows
--             the tip), or "stamps" to open the stamp panel
--     studio  variant: a tab - presets, body, face, hair, outfit, extras; or clothing (the tops, two owned)
--     hud     variant: "fight" (mid-fight, a full ultimate) or "countdown" (the combo card, "3")
--     results variant: "teams" for a team match (the winners share first); a GG has just been said
--     notice  variant: "error" for a refused match (with OK); otherwise the loading notice
--
-- Pictures drawn into a GUI frame (Canvas2D.inFrame: the studio's tiles and preview, the stamp
-- icons) are not placed - only the screen-wide canvas is - so those frames show empty.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Rbx = require("@lune/roblox")
local Loader = require("../tests/loader")
local Recorder = require("./recorder")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Input = Loader.load("Input")
local Products = Loader.load("Products")
local AvatarKit = Loader.load("AvatarKit")
local shapes = Recorder.install(Canvas)
-- BF_EXTREME=1: the largest values a player can have - 20-character names (Roblox's most), 999%
-- damage, a 999,999,999 balance - to find what overflows (the bug hunt, 2026-10-22)
local EXTREME = process.env.BF_EXTREME == "1"
local LONG = "xXDragonSlayer2009Xx"

local screen = process.args[2] or "plaza"
local W = tonumber(process.args[3] or "1280") or 1280
local H = tonumber(process.args[4] or "720") or 720
local variant = process.args[5]

local new, made = Recorder.gui(W, H)
local enumNames = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
Loader.gui = { Instance = { new = new }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = enumNames }
-- a style theme to draw in (Ui.THEMES), picked before any screen module loads and reads its fonts
Loader.loadFrom("src/client/", "Ui").useTheme(process.env.UI_THEME)
-- frames' own canvases draw nowhere (see above)
local frameCanvas = nil      -- a screen-wide frame's canvas (the podium's) is the screen's own
Canvas.inFrame = function()
	if frameCanvas then return frameCanvas end
	local f = Recorder.canvas(Canvas, 100, 100)
	f.pool, f.poolState = {}, {}
	return f
end

local codes = setmetatable({}, { __index = function(_, k) return k end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) },
	{ __index = function(_, k) return k end })
local function never() return false end
local services = setmetatable({ ReplicatedStorage = { Shared = shared } }, { __index = function()
	local stub = { GetFocusedTextBox = never, IsKeyDown = never, IsGamepadButtonDown = never }
	stub.InputBegan = { Connect = function() end }
	return stub
end })
local function load(name: string): any
	return luau.load(fs.readFile("src/client/" .. name .. ".luau"), { debugName = name, environment = {
		game = { GetService = function(_, s) return services[s] end },
		script = { Parent = codes },
		require = function(target)
			if target == "InputClient" then return { new = function() return {
				frame = Input.emptyFrame(), sample = function(self) return { self.frame } end, reset = function() end,
			} end } end
			if target == "PodiumView" then return {} end
			if type(target) == "string" and fs.isFile("src/client/" .. target .. ".luau") then return Loader.loadFrom("src/client/", target) end
			return Loader.load(target)
		end,
		Instance = { new = new }, Enum = enumNames, Color3 = Rbx.Color3, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Vector2 = Rbx.Vector2,
		Random = { new = function() return { NextInteger = function(_, a) return a end, NextNumber = function() return 0.5 end } end },
		typeof = function(v) return type(v) end,
	}, injectGlobals = true })()
end

local playerGui = new("PlayerGui")
local KIT = Loader.load("Data/AvatarKit")
local c = Recorder.canvas(Canvas, W, H)
c.pool, c.poolState = {}, {}          -- (for a module that calls Canvas2D.finish itself)

if screen == "plaza" then
	local Plaza2D = load("Plaza2D")
	local Social = load("LobbySocial")
	local social = Social.new(playerGui, { localId = 1, clock = function() return 0 end, send = function() end })
	social:setEnabled(true)
	if variant == "stamps" then social:toggle("Stamps") end
	local hub = Plaza2D.new(playerGui)
	hub.social = social          -- as the client wires them (init.client.luau)
	local cfg = Loader.load("MatchConfig").default()
	for _, p in KIT.presets do if p.id == "knight" then cfg.slots[1].avatarId = p.code end end
	hub:show(cfg)
	-- "x,z": where you stand (beside a station shows its prompt)
	local x, z = 0, 8
	if variant and string.find(variant, ",") then
		local a, b = string.match(variant, "^([%-%d%.]+),([%-%d%.]+)$")
		x, z = tonumber(a) or 0, tonumber(b) or 8
	end
	hub.model:setScene(hub.model.data, { x = x, z = z })
	hub.camX = x
	for _ = 1, 20 do table.clear(shapes); hub:step(1 / 60, false); hub:draw(c, 1 / 60) end
elseif screen == "studio" then
	local Editor = load("AvatarEditor")
	local ed = Editor.new(playerGui, { send = function() end, weapon = function() return "Sword" end })
	ed.gui.AbsoluteSize = Rbx.Vector2.new(W, H)
	ed:open()
	ed:layout(Rbx.Vector2.new(W, H))
	if variant == "clothing" then
		-- the tops, two pieces owned and the rest in the Shop
		ed:setView({ slots = { { name = "Fighter 1", code = AvatarKit.defaultCode() } }, active = 1, max = 8, saving = true, unlocked = {},
			pieces = { "neon_circuit_bomber", "candy_sugarstripe_tee" } })
		ed:selectCategory("top")
		ed:pick("top", "neon_circuit_bomber")
	elseif variant then ed:selectGroup(variant) end
	table.clear(shapes)
	-- a backdrop where the plaza would be
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
elseif screen == "hud" then
	local Hud = load("Hud")
	local Loadout = Loader.load("Loadout")
	local hud = Hud.new(playerGui)
	local roster, chars = {}, {}
	local names = if EXTREME then { LONG, "BigBrawlerBob_12345", "CPU", "TheUltimateAlly_777" } else { "etondes", "Rival", "CPU", "Ally" }
	local weapons = { "Scythe", "Sword", "Hammer", "Daggers" }
	for i = 1, 4 do
		roster[i] = { index = i - 1, team = (i - 1) % 2, name = names[i], weapon = weapons[i] }
		chars[i] = Loadout.build("Classic", weapons[i])
	end
	hud:bind(roster, chars, 0, true)
	local countdown = variant == "countdown"
	local states = {}
	for i = 1, 4 do
		states[i] = { index = i - 1, percent = if EXTREME then 999 else ({ 0, 47, 112, 168 })[i], stocks = if EXTREME then 9 else ({ 3, 2, 3, 1 })[i], alive = true,
			ultCharge = ({ 20, 9, 4, 0 })[i], state = if i == 1 then "idle" else "run", onGround = true, x = 0, y = 0 }
	end
	if countdown then for _, st in states do st.percent, st.ultCharge = 0, 0 end end
	local snap = { state = if countdown then "countdown" else "fight", countdown = 150, time = 16 }
	-- a dusk sky where the arena would be
	c:screen()
	for b = 0, 11 do
		local k = b / 11
		Canvas.rect(c, 0, b * H / 12, W, H / 12 + 1, Rbx.Color3.new(0.12 + 0.2 * k, 0.1 + 0.12 * k, 0.3 + 0.2 * k), 1)
	end
	hud:update(states, snap, nil, chars, { fighters = roster, timed = true, timeLimit = 180 })
elseif screen == "results" then
	local View = load("PodiumView")
	local Loadout = Loader.load("Loadout")
	local chars, rows = {}, {}
	local looks = { "knight", "ninja", "samurai", "robot" }
	for i, id in looks do
		local code = "Classic"
		for _, p in KIT.presets do if p.id == id then code = p.code end end
		chars[i] = Loadout.build(code, ({ "Sword", "Scythe", "Hammer", "Daggers" })[i])
	end
	for i, idx in { 0, 2, 1, 3 } do
		table.insert(rows, { index = idx, name = (if EXTREME then { LONG, "BigBrawlerBob_12345", "TheUltimateAlly_777", "CPU" } else { "etondes", "Rival", "Ally", "CPU" })[idx + 1], team = idx % 2,
			score = 5 - i, kos = 4 - i, falls = i, sds = 0, damage = 120 * (5 - i), taken = 80 * i })
	end
	frameCanvas = c
	local view = View.new(new("ScreenGui"), { rows = rows, winnerTeam = 0, teams = variant == "teams" }, chars, Rbx.Vector2.new(W, H), nil)
	frameCanvas = nil
	-- gui-svg paints the canvas under every Frame, but in Roblox the podium's canvas is a child of
	-- its backdrop and draws over it: see through the backdrop so the picture matches
	view.root.BackgroundTransparency = 1
	view.gg.Activated:Fire()
	table.clear(shapes)
	view:draw(1)
elseif screen == "records" then
	local Records = load("ClimbRecords")
	local r = Records.new(playerGui, { localId = 2, now = function() return 1000 end })
	local names = if EXTREME then { LONG, "BigBrawlerBob_12345", "TheUltimateAlly_777", "cy", "dee", "eve", "fox" } else { "ada", "etondes", "bo", "cy", "dee", "eve", "fox" }
	local speed, levels = {}, {}
	for i, n in names do
		table.insert(speed, { rank = i, userId = i, name = n, frames = 60 * (55 + i * 9) })
		table.insert(levels, { rank = i, userId = i, name = n, best = math.max(0, 7 - i), summits = math.max(0, 4 - i) })
	end
	r:set({ speed = speed, levels = levels, nextAt = 1000 + 3600 })
	r:setMine({ best = 5, summits = 1, bestFrames = 60 * 73 })
	r:open()
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
elseif screen == "notice" then
	local Panel = load("RoomPanel")
	local panel = Panel.new(playerGui)
	if variant == "error" then panel:show("That match could not be run: the arena failed to load.") else panel:waiting("Loading arena and fighters…") end
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
elseif screen == "people" then
	local Social = load("LobbySocial")
	local social = Social.new(playerGui, { localId = 1, clock = function() return 0 end, send = function() end })
	social:setEnabled(true)
	social:toggle("People")
	social:setMembers({ { userId = 1, name = if EXTREME then LONG else "etondes", where = "Skyhold Bazaar", place = "market", x = 0 },
		{ userId = 2, name = "Rival", where = "In a fight · 2v2", place = "fight" },
		{ userId = 3, name = "ada", where = "Skyhold Bazaar", place = "market", x = 40 },
		{ userId = 4, name = "bo", where = "Room · 3v3", place = "room" } })
	-- (through the game's own handler, so the log shows the colours the game picks)
	social:onEvent({ userId = 3, name = "ada", kind = "say", index = 1 })
	social:onEvent({ userId = social.localId, kind = "stamp", id = "gg" })
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
elseif screen == "climb" then
	local View = load("ParkourView")
	local code = "Classic"
	for _, p in KIT.presets do if p.id == "knight" then code = p.code end end
	local v = View.new(playerGui, { input = { sample = function() return {} end, reset = function() end }, send = function() end,
		skip = function() end, price = function() return 7 end, records = function() end, restart = function() end })
	v:start(code, 1)
	for _ = 1, 10 do table.clear(shapes); v:step(1 / 60); v:draw(c, 1 / 60) end
elseif screen == "locker" then
	-- variant: locker (default), crates, workshop, odds, opening
	local L = load("LockerScreen")
	local s = L.new(playerGui, { sendLocker = function() end, sendEconomy = function() end, now = os.clock, rand = function() return 0.4 end })
	s:open()
	s:setLocker({ owned = { "sword_starforged", "hit_sakura", "ko_dragonsbreath", "trail_ember", "daggers_neontwins", "pike_eventide", "frost_snowline_beanie", "neon_circuit_bomber" },
		wearing = { skins = { Sword = "sword_starforged" }, hit = "hit_sakura" } })
	local econ = { sparks = if EXTREME then 999999999 else 2340, crates = { scrap = if EXTREME then 999 else 3, forge = 1 }, keys = { forge = if EXTREME then 999 else 2 }, meter = 2, guarantees = { scrap = 18, forge = 33 },
		items = { { uid = "u1", id = "sword_starforged", serial = 57, copies = 1240 }, { uid = "u2", id = "hit_sakura", serial = 312, copies = 8800 },
			{ uid = "u3", id = "ko_dragonsbreath", serial = 4, copies = 96 }, { uid = "u4", id = "trail_ember", serial = 1021, copies = 9100 },
			{ uid = "u5", id = "daggers_neontwins", serial = 77, copies = 5400 }, { uid = "u6", id = "daggers_neontwins", serial = 901, copies = 5400 },
			{ uid = "u7", id = "pike_eventide", serial = 2, copies = 31 }, { uid = "u9", id = "frost_snowline_beanie", serial = 140, copies = 2210 },
			{ uid = "u10", id = "neon_circuit_bomber", serial = 18, copies = 940 } } }
	s:setEconomy(econ)
	if variant == "crates" or variant == "odds" or variant == "opening" then s:show("crates") end
	if variant == "workshop" then s:show("workshop") end
	if variant == "odds" then s:showOdds("forge", false) end
	if variant == "opening" then
		s:openCrate("forge")
		local v = table.clone(econ)
		v.event = { done = "open", result = { id = "pike_eventide", rarity = "Mythic", uid = "u8", serial = 32, copies = 32 } }
		s:setEconomy(v)
	end
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
elseif screen == "shop" then
	-- variant: shop (default), odds, restricted
	local S = load("ShopScreen")
	local s = S.new(playerGui, { send = function() end, prompt = function() end })
	s:open()
	local restricted = variant == "restricted"
	local keys = {}
	if not restricted then
		for _, b in Products.KEYS do table.insert(keys, { bundle = b.bundle, count = b.count, price = b.price }) end
	end
	local passes = {}
	for _, p in Products.PASSES do
		table.insert(passes, { id = p.id, name = p.name, price = p.price, owned = p.id == "wardrobe", available = p.available, perks = p.perks })
	end
	-- the clothing packs as the server builds them, two pieces owned
	local Inventory = Loader.load("Inventory")
	local inv = Inventory.sanitize(nil)
	inv.owned.candy_sugarstripe_tee, inv.owned.neon_circuit_bomber = true, true
	local clothing = Loader.loadFrom("src/server/", "Shop").clothing(inv)
	s:setEconomy({ sparks = if EXTREME then 999999999 else 2340, keys = { forge = if EXTREME then 999 else 2 }, shop = { restricted = restricted, resetsIn = 26000, keys = keys, passes = passes, clothing = clothing,
		featured = { { id = "hammer_cobblestone", price = 29, owned = false }, { id = "sword_frostbite", price = 49, owned = true },
			{ id = "daggers_venomfang", price = 99, owned = false, credit = true }, { id = "sword_starforged", price = 199, owned = false } } } })
	if variant == "odds" then s:showOdds(false) end
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
else
	error("unknown screen " .. screen)
end

local nodes = Recorder.nodes(made, W, H)
fs.writeFile(process.args[1], serde.encode("json", { w = W, h = H, shapes = shapes, nodes = nodes }))
print(`{screen} at {W}x{H}: {#shapes} canvas shapes, {#nodes} GUI nodes`)
