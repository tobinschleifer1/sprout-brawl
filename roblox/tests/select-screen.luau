--!strict
-- The select screen (SelectScreen) and its stat bars (WeaponStats), with the real module running
-- against stand-in Instances: the buttons are pressed and what they send is checked.
--
--   * the bars come from the data: the heaviest hitter tops Damage and Defense, the fastest tops
--     Dexterity and Speed, and every bar is 3..9;
--   * the layout fits at 1280x720, 1920x1080 and a phone's 812x375, for 1v1, 2v2 and 3v3: nothing
--     off screen, no two portraits or cards overlap, team 0 on the left of team 1 with the VS
--     between, the pedestals under the roster;
--   * every control sends its action: a portrait its weapon, ADD BOT the chosen difficulty for its
--     slot, YES / NO the ballot, REMOVE a bot, READY, LEAVE, START only for a host who can start;
--     HIDE and the ROOM button minimise and restore; a vote shows its card and hides ADD BOT;
--   * each card's bars are that weapon's, and every pick carries its player's tag;
--   * a new room and a room back from a fight open the screen; leaving closes it;
--   * the scene draws, and the roster's still portraits are made once, not every frame.
--
--     lune run tests/select-screen
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local WeaponStats = Loader.loadFrom("src/client/", "WeaponStats")
local Weapons = Loader.load("Data/Weapons")
local Recorder = require("../tools/recorder")
local shapes = Recorder.install(Canvas)

local function fail(msg: string): never
	error(msg, 0)
end

-- ------------------------------------------------------------------ the stat bars ----
do
	local all = WeaponStats.all()
	for id, bars in all do
		for _, k in WeaponStats.KEYS do
			if bars[k] < WeaponStats.LOW or bars[k] > WeaponStats.HIGH then fail(`{id} {k} = {bars[k]}`) end
		end
	end
	if all.Hammer.damage ~= WeaponStats.HIGH or all.Hammer.defense ~= WeaponStats.HIGH then fail("the hammer does not top damage and defense") end
	if all.Daggers.dexterity ~= WeaponStats.HIGH or all.Daggers.speed ~= WeaponStats.HIGH then fail("the daggers do not top dexterity and speed") end
	if all.Daggers.damage ~= WeaponStats.LOW or all.Hammer.speed ~= WeaponStats.LOW then fail("the daggers' damage or the hammer's speed is not the lowest") end
	if WeaponStats.all() ~= all then fail("the bars are recomputed on every call") end
end

-- ------------------------------------------------------------------ stand-in Instances ----
local W, H = 1280, 720
local made = {}
local function signal(): any
	local fns = {}
	return { Connect = function(_, fn) table.insert(fns, fn) end, Fire = function(_, ...) for _, fn in fns do fn(...) end end }
end
local function new(class: string): any
	local props: any = { ClassName = class, Visible = true, Activated = signal(), Name = class, _children = {} }
	local self: any
	props.Destroy = function()
		props.destroyed = true
		for _, ch in table.clone(props._children) do ch:Destroy() end
	end
	self = setmetatable({}, { __index = props, __newindex = function(_, k, v)
		props[k] = v
		if k == "Parent" and v then table.insert(v._children, self) end
	end })
	if class == "ScreenGui" then props.AbsoluteSize = Rbx.Vector2.new(W, H); props.Enabled = true end
	table.insert(made, self)
	return self
end
local names = setmetatable({}, { __index = function(_, k) return k end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) },
	{ __index = function(_, k) return k end })
local function resolve(name: string): any
	if string.sub(name, 1, 5) == "Data/" then return Loader.load(name) end
	if fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
	return Loader.load(name)
end
local enumNames = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
local Screen = luau.load(fs.readFile("src/client/SelectScreen.luau"), { debugName = "SelectScreen", environment = {
	game = { GetService = function() return { Shared = shared } end },
	script = { Parent = names }, require = resolve,
	Instance = { new = new }, Enum = enumNames,
	Color3 = Rbx.Color3, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Vector2 = Rbx.Vector2,
}, injectGlobals = true })()

-- ------------------------------------------------------------------ the layout ----
local function overlap(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
for _, size in { { 1280, 720 }, { 1920, 1080 }, { 812, 375 } } do
	for _, n in { 2, 4, 6 } do
		local sw, sh = size[1], size[2]
		local slots = {}
		for i = 1, n do slots[i] = { team = (i - 1) % 2 } end
		local L = Screen.layout(sw, sh, slots)
		local where = `{sw}x{sh}, {n} slots`
		local cells = {}
		for _, r in L.roster do
			local box = { x = r.x - L.cell / 2, y = r.y - L.cell / 2, w = L.cell, h = L.cell }
			if box.x < 0 or box.y < 0 or box.x + box.w > sw or box.y + box.h > sh then fail(`{where}: the {r.id} portrait is off screen`) end
			for _, other in cells do if overlap(box, other) then fail(`{where}: two portraits overlap`) end end
			table.insert(cells, box)
		end
		if #L.pedestals ~= n then fail(`{where}: {#L.pedestals} pedestals`) end
		local cards = {}
		local lastTeam0, firstTeam1 = -math.huge, math.huge
		for _, p in L.pedestals do
			local box = { x = p.x, y = p.cardY, w = p.cardW, h = p.cardH }
			if box.x < 0 or box.x + box.w > sw or box.y + box.h > sh then fail(`{where}: a card is off screen`) end
			for _, other in cards do if overlap(box, other) then fail(`{where}: two cards overlap`) end end
			table.insert(cards, box)
			if p.team == 0 then lastTeam0 = math.max(lastTeam0, p.x + p.cardW) else firstTeam1 = math.min(firstTeam1, p.x) end
			if p.plinthY - p.plinthH - p.fighterH < L.rosterBottom - 1 then fail(`{where}: a pedestal's fighter reaches into the roster`) end
			if p.fighterH < sh * 0.2 then fail(`{where}: the fighters are only {p.fighterH}px tall on a {sh}px screen`) end
		end
		if lastTeam0 >= firstTeam1 then fail(`{where}: team 0 is not left of team 1`) end
		if not L.vsX or L.vsX <= lastTeam0 or L.vsX >= firstTeam1 then fail(`{where}: the VS is not between the teams`) end
	end
end

-- ------------------------------------------------------------------ the controls ----
local function find(name: string): any
	for k = #made, 1, -1 do
		local o = made[k]
		if o.Name == name and not o.destroyed then return o end
	end
	return nil
end
-- `name` inside slot `slot`'s card
local function inCard(slot: number, name: string): any
	local card = find("Card" .. slot)
	local function walk(o: any): any
		for _, ch in o._children do
			if ch.Name == name and not ch.destroyed then return ch end
			local hit = walk(ch)
			if hit then return hit end
		end
		return nil
	end
	return card and walk(card)
end
local function visible(o: any): boolean
	local cur = o
	while cur do
		if cur.destroyed or cur.Visible == false or (cur.ClassName == "ScreenGui" and cur.Enabled == false) then return false end
		cur = cur.Parent
	end
	return true
end
local sent = {}
local screen = Screen.new(new("Folder"))
screen.onAction = function(a: any) table.insert(sent, a) end
local function lastSent(): any return sent[#sent] end
local function room(over: any?): any
	local r: any = { id = 7, host = 1, name = "2v2", state = "setup", revision = 4, stage = "FoundryFloor", stocks = 3,
		items = true, disasters = "off", mapChoice = "host", mode = "stock", time = 180, canStart = false, slots = {
			{ team = 0, userId = 1, name = "You", weapon = "Sword", avatar = "Classic", ready = false },
			{ team = 1, userId = 2, name = "Rival", weapon = "Hammer", avatar = "Classic", ready = true },
			{ team = 0 },
			{ team = 1, bot = "normal", weapon = "Daggers", avatar = "Classic", ready = true },
		} }
	for k, v in over or {} do r[k] = v end
	return r
end
screen:update(room(), 1)
if not screen.open or not screen.gui.Enabled then fail("joining a room did not open the screen") end
find("PickHammer").Activated:Fire()
if lastSent().action ~= "weapon" or lastSent().value ~= "Hammer" or lastSent().id ~= 7 or lastSent().revision ~= 4 then fail("a portrait did not send its weapon") end
inCard(3, "Difficultyhard").Activated:Fire()
inCard(3, "AddBot").Activated:Fire()
if lastSent().action ~= "bot" or lastSent().value ~= "hard" or lastSent().slot ~= 3 then fail(`ADD BOT sent {lastSent().action}/{tostring(lastSent().value)}/{tostring(lastSent().slot)}`) end
inCard(4, "RemoveBot").Activated:Fire()
if lastSent().action ~= "bot" or lastSent().value ~= false or lastSent().slot ~= 4 then fail("REMOVE BOT did not send a removal for the bot's slot") end
find("Ready").Activated:Fire()
if lastSent().action ~= "ready" then fail("READY did not send ready") end
screen:update(room({ host = 2 }), 1)
if visible(find("Start")) then fail("a host's START showed for someone who is not the host") end
-- a vote running on slot 3
screen:update(room({ botVote = { slot = 3, value = "hard", by = 2, yes = 1, no = 0, voters = 2, ballots = { ["2"] = true }, left = 6 } }), 1)
if not visible(inCard(3, "Vote")) or visible(inCard(3, "AddBot")) then fail("a running vote did not take over its card") end
inCard(3, "Yes").Activated:Fire()
if lastSent().action ~= "ballot" or lastSent().value ~= true then fail("YES did not send a yes") end
inCard(3, "No").Activated:Fire()
if lastSent().action ~= "ballot" or lastSent().value ~= false then fail("NO did not send a no") end
if visible(inCard(4, "RemoveBot")) then fail("REMOVE showed while another vote was running") end
-- each card's bars are its weapon's
local card2 = find("Card2")
local gold = 0
for _, ch in card2._children do
	if ch.ClassName == "Frame" and ch.Visible ~= false and ch.BackgroundColor3 and math.abs(ch.BackgroundColor3.R - 1) < 0.01 and ch.Name == "Frame" then gold += 1 end
end
local hb = WeaponStats.of("Hammer")
if gold ~= hb.damage + hb.defense + hb.dexterity + hb.speed then fail(`the hammer's card lights {gold} segments, its bars sum to {hb.damage + hb.defense + hb.dexterity + hb.speed}`) end
-- tags over the picks
local tags = {}
for _, o in made do if o.Name == "Tag" and not o.destroyed then tags[o.Text] = true end end
if not tags.YOU or not tags.P2 or not tags.CPU then fail("the roster is missing a player's tag") end
-- START: a host who can start sends it; one who cannot does not
screen:update(room({ host = 1, canStart = true }), 1)
local before = #sent
find("Start").Activated:Fire()
if #sent ~= before + 1 or lastSent().action ~= "start" then fail("a host who could start did not send START") end
screen:update(room({ host = 1, canStart = false }), 1)
before = #sent
find("Start").Activated:Fire()
if #sent ~= before then fail("START sent while the room could not start") end
-- HIDE and back
find("Hide").Activated:Fire()
if screen.open or not visible(find("Reopen")) or visible(find("Root")) then fail("HIDE did not minimise to the ROOM button") end
find("Reopen").Activated:Fire()
if not screen.open or not visible(find("Root")) then fail("the ROOM button did not bring the screen back") end
find("Leave").Activated:Fire()
if lastSent().action ~= "leave" then fail("LEAVE did not send leave") end
-- the scene draws, and the roster's portraits are made once
local c = Recorder.canvas(Canvas, W, H)
table.clear(shapes)
screen:draw(c, 1 / 60)
local first = #shapes
local snap = screen.fighters.roster1 and screen.fighters.roster1.snap
-- drawn at REDRAW_HZ: the next 60 Hz frame draws nothing (the canvas keeps the picture), the one
-- after redraws
table.clear(shapes)
screen:draw(c, 1 / 60)
if #shapes ~= 0 then fail(`the screen redrew at 60 Hz, not {Screen.REDRAW_HZ}`) end
screen:draw(c, 1 / 60)
if first < 200 or #shapes < 200 then fail(`the scene drew only {first} shapes`) end
if not snap or screen.fighters.roster1.snap ~= snap then fail("a still portrait was re-made on the next frame") end
-- a fight starts (playing), then comes back (setup): the screen comes back with it
screen:hide()
screen:update(room({ state = "playing" }), 1)
if screen.open then fail("a room that went to its fight opened the screen") end
screen:update(room({ state = "setup" }), 1)
if not screen.open then fail("the room back from its fight did not bring the screen back") end
screen:update({ left = true }, 1)
if screen.open or screen.gui.Enabled then fail("leaving did not close the screen") end

print("PASS select screen: bars from the data; the layout fits 1280x720, 1920x1080 and 812x375 for 1v1/2v2/3v3 with the teams either side of the VS")
print("  every control sends its action (portrait, ADD BOT at a difficulty, YES/NO, REMOVE, READY, START for a host who can, LEAVE), HIDE and ROOM, votes take their card, cards show their weapon's bars, picks carry tags, rematches reopen, the roster is drawn once")
