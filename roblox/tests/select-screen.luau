--!strict
-- The select screen (SelectScreen) and its stat bars (WeaponStats), with the real module running
-- against stand-in Instances: the buttons are pressed and what they send is checked.
--
--   * the bars come from the data: the heaviest hitter tops Damage and Defense, the fastest tops
--     Dexterity and Speed, and every bar is 3..9;
--   * the layout fits at 1280x720, 1920x1080, phones (812x375, 640x320), an ultrawide and short windows,
--     for 1v1, 2v2 and 3v3: nothing
--     off screen, no two portraits or cards overlap, team 0 on the left of team 1 with the VS
--     between, the pedestals under the roster;
--   * the vote pages fit too: a card per arena and Random, a card per rule set and "keep current",
--     all on screen, none overlapping, between the title and the strip of who has voted;
--   * two weapons (weapon drops): clicks fill the first hand then the second; one you hold is kept
--     and its partner chosen next; both are ringed and named with their hand, the card names both,
--     and the status says which hand is next;
--   * every control sends its action: a portrait its weapon, ADD BOT the chosen difficulty for its
--     slot, YES / NO the ballot, REMOVE a bot, READY, LEAVE; there is no START (the room starts
--     itself); HIDE and the ROOM button minimise and restore; a vote shows its card and hides ADD BOT;
--   * the room's phase picks the page: an arena card sends its vote, a rule card its rule; counts,
--     your gold ring, the who-has-voted chips, the countdown and the arena in the rules bar follow
--     the room; the map page draws each arena;
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
local Stages = Loader.load("Data/Stages")
local Rules = Loader.load("Data/Rules")
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
	props.FindFirstChild = function(_, name) for _, ch in props._children do if ch.Name == name and not ch.destroyed then return ch end end return nil end
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
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = new }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = enumNames }
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
local Ui = Loader.loadFrom("src/client/", "Ui")
for _, size in { { 1280, 720 }, { 1920, 1080 }, { 812, 375 }, { 667, 375 }, { 844, 390 }, { 2560, 1080 }, { 1280, 560 }, { 1280, 400 }, { 640, 320 } } do
	for _, n in { 2, 4, 6 } do
		local sw, sh = size[1], size[2]
		local slots = {}
		for i = 1, n do slots[i] = { team = (i - 1) % 2 } end
		local L = Screen.layout(sw, sh, slots)
		local where = `{sw}x{sh}, {n} slots`
		-- neighbouring portraits keep 8 px between their rings' outer edges (3 px rings, or 2 px compact),
		-- and with brackets, room for those too (2 px apart at 844 wide before)
		do
			local ring = if L.compact then 2 else 3
			local marks = if L.compact then 0 else Ui.BRACKET_OUT + Ui.BRACKET_INK - ring
			for k = 2, #L.roster do
				local a, b = L.roster[k - 1], L.roster[k]
				if a.y == b.y then
					local clear = (b.x - a.x) - L.cell - 2 * ring - math.max(0, marks)
					if clear < 8 - 0.01 then fail(`{where}: the {a.id} and {b.id} portraits are {clear} px apart`) end
				end
			end
		end
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
		-- the vote pages: every card (and an arena's name under it) inside the band between the
		-- title and the strip, none overlapping
		if #L.maps ~= #Stages.LIST + 1 or L.maps[#L.maps].id ~= "Random" then fail(`{where}: {#L.maps} arena cards, want every stage and Random`) end
		if #L.rules ~= #Rules.presets + 1 or L.rules[#L.rules].id ~= "current" then fail(`{where}: {#L.rules} rule cards, want every preset and keep current`) end
		for _, set in { { L.maps, L.nameH, "arena" }, { L.rules, 0, "rule" } } do
			local boxes = {}
			for _, m in set[1] do
				local box = { x = m.x, y = m.y, w = m.w, h = m.h + set[2] }
				if box.x < 0 or box.x + box.w > sw or box.y < L.voteTop or box.y + box.h > L.stripY then
					fail(`{where}: the {m.id} {set[3]} card is outside the vote band`)
				end
				if m.w < 40 or m.h < 24 then fail(`{where}: the {m.id} {set[3]} card is only {m.w}x{m.h}`) end
				for _, other in boxes do if overlap(box, other) then fail(`{where}: two {set[3]} cards overlap`) end end
				table.insert(boxes, box)
			end
		end
		if L.stripY + 28 * L.s > L.buttonsY then fail(`{where}: the voted strip runs into LEAVE / HIDE`) end
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
-- (every weapon unlocked for the screen's own behaviour; the locks are checked at the end)
screen:setLevel(50)
screen.onAction = function(a: any) table.insert(sent, a) end
local now = 0
screen.now = function() return now end
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
-- weapon drops: two weapons. The next click fills the second hand; one you already hold is kept,
-- and its partner is chosen next. Both are ringed and named with their hand; the card names both.
find("PickAxe").Activated:Fire()
if lastSent().action ~= "weapon2" or lastSent().value ~= "Axe" then fail("the second click did not choose the second weapon") end
do
	local r = room()
	r.slots[1].weapon, r.slots[1].weapon2 = "Hammer", "Axe"
	r.slots[2].weapon2 = "Pike"
	screen:update(r, 1)
	if not string.find(screen.status.Text, "weapon 1", 1, true) then fail(`after a pair the status says "{screen.status.Text}", not that weapon 1 is next`) end
	-- (tiles carry the short name: SelectScreen.SHORT)
	for _, c in { { "Hammer", "1 · HAMMER" }, { "Axe", "2 · AXE" } } do
		local cell = find("Pick" .. c[1])
		local ring
		for _, ch in cell._children do if ch.ClassName == "UIStroke" then ring = ch end end
		if not ring or ring.Thickness < 3 then fail(`your {c[1]} has no ring`) end
		-- (and the stepped brackets every chosen card wears)
		local marks = cell:FindFirstChild("Brackets")
		if not marks or marks.Visible ~= true then fail(`your {c[1]} wears no brackets`) end
		if find("Name" .. c[1]).Text ~= c[2] then fail(`the {c[1]} portrait is named "{find("Name" .. c[1]).Text}", not "{c[2]}"`) end
	end
	if find("NameSword").Text ~= "SWORD" then fail("a weapon you do not hold is named with a hand") end
	local swordMarks = find("PickSword"):FindFirstChild("Brackets")
	if swordMarks and swordMarks.Visible then fail("a weapon you do not hold wears the brackets") end
	if inCard(1, "Weapon").Text ~= "WAR HAMMER + BATTLE AXE" or inCard(2, "Weapon").Text ~= "WAR HAMMER + WARPIKE" then
		fail(`the cards say "{inCard(1, "Weapon").Text}" and "{inCard(2, "Weapon").Text}"`)
	end
	local pikeTags = 0
	for _, o in made do if o.Name == "Tag" and not o.destroyed and o.Text == "P2" then pikeTags += 1 end end
	if pikeTags ~= 2 then fail(`the rival's two weapons carry {pikeTags} tags`) end
	local before = #sent
	find("PickHammer").Activated:Fire()
	if #sent ~= before then fail("clicking a weapon you hold sent a change") end
	if not string.find(screen.status.Text, "weapon 2", 1, true) then fail("clicking your first weapon did not move on to its partner") end
	find("PickPike").Activated:Fire()
	if lastSent().action ~= "weapon2" or lastSent().value ~= "Pike" then fail("after keeping the hammer, the next pick was not its partner") end
	find("PickAxe").Activated:Fire()
	if #sent ~= before + 1 then fail("clicking your second weapon sent a change") end
	find("PickPike").Activated:Fire()
	if lastSent().action ~= "weapon" or lastSent().value ~= "Pike" then fail("after keeping the axe, the next pick was not the first hand") end
	screen.hand = 1
end
-- bots are always hard: there is no difficulty to choose
for _, d in { "easy", "normal", "hard" } do
	if inCard(3, "Difficulty" .. d) then fail("an open slot still offers a bot difficulty") end
end
-- ADD BOT waits out the room's BOT_WAIT, counting down, then opens
screen:update(room({ botWait = 7 }), 1)
local add = inCard(3, "AddBot")
if add.Active or not string.find(add.Text, "7", 1, true) then fail(`ADD BOT is open during the room's wait ({add.Text})`) end
screen:update(room({ botWait = 0 }), 1)
if not add.Active or not string.find(add.Text, "ADD BOT", 1, true) then fail(`ADD BOT did not open after the wait ({add.Text})`) end
inCard(3, "AddBot").Activated:Fire()
if lastSent().action ~= "bot" or lastSent().value ~= "hard" or lastSent().slot ~= 3 then fail(`ADD BOT sent {lastSent().action}/{tostring(lastSent().value)}/{tostring(lastSent().slot)}`) end
inCard(4, "RemoveBot").Activated:Fire()
if lastSent().action ~= "bot" or lastSent().value ~= false or lastSent().slot ~= 4 then fail("REMOVE BOT did not send a removal for the bot's slot") end
find("Ready").Activated:Fire()
if lastSent().action ~= "ready" then fail("READY did not send ready") end
if find("Start") or find("MapButton") or find("RulesButton") then fail("the screen still has a START, MAP or RULES button: the room votes and starts itself") end
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
-- the pick page while the room is full: its countdown to the map vote
local function page(name: string): boolean return visible(find("Page" .. name)) end
screen:update(room({ phaseLeft = 25 }), 1)
if not page("pick") or page("map") or page("rules") then fail("the pick phase did not show the pick page alone") end
if not string.find(screen.status.Text, "25s", 1, true) then fail(`the pick countdown says "{screen.status.Text}"`) end
if not string.find(find("Rules").Text, "MAP: VOTE", 1, true) then fail(`the rules bar says "{find("Rules").Text}" before the map vote`) end
-- the map vote: P2 and you on the Undertow, nobody else
local function voted(phase: string, field: string, mineV: string?, theirs: string?, left: number): any
	local r = room({ phase = phase, phaseLeft = left, stage = "Undertow" })
	r.slots[3] = { team = 0, bot = "easy", weapon = "Axe", avatar = "Classic", ready = true }
	r.slots[1][field], r.slots[2][field] = mineV, theirs
	return r
end
screen:update(voted("map", "vote", "Undertow", "Undertow", 11), 1)
if not page("map") or page("pick") or page("rules") then fail("the map phase did not show the map page alone") end
if not visible(find("Clock")) or find("Clock").Text ~= "11" then fail(`the map vote's clock says "{find("Clock").Text}"`) end
if find("VoteTitle").Text ~= "VOTE FOR THE ARENA" then fail("the map page has no title") end
local undertow = find("MapUndertow")
local count = undertow and undertow:FindFirstChild("Count")
if not count or not visible(count) or count.Text ~= "2" then fail(`the Undertow's count shows {count and count.Text}`) end
if visible(find("MapRandom"):FindFirstChild("Count")) then fail("an arena nobody voted for shows a count") end
local ring
for _, ch in undertow._children do if ch.ClassName == "UIStroke" then ring = ch end end
if not ring or ring.Thickness < 3 then fail("your arena has no ring") end
-- (gold is for you: a bracketed card's ring is not gold)
if math.abs(ring.Color.R - 1) < 0.01 and math.abs(ring.Color.G - 231 / 255) < 0.01 then fail("your bracketed arena still wears a gold ring") end
-- (and the brackets, which mark it instead of a thicker ring)
if not undertow:FindFirstChild("Brackets") or not undertow:FindFirstChild("Brackets").Visible then fail("your arena wears no brackets") end
if math.abs(find("MapNameUndertow").TextColor3.B - find("MapNameRandom").TextColor3.B) < 0.1 then fail("your arena's name is not picked out") end
-- the page just replaced another under the pointer: a click this soon is not a vote
local before = #sent
find("MapRandom").Activated:Fire()
if #sent ~= before then fail("a click the moment the map page appeared cast a vote") end
now += Screen.SETTLE
for _, id in { "Random", Stages.LIST[1].id } do
	find("Map" .. id).Activated:Fire()
	if lastSent().action ~= "vote" or lastSent().value ~= id or lastSent().id ~= 7 then fail(`the {id} arena card sent {lastSent().action}/{tostring(lastSent().value)}`) end
end
local function chip(i: number): any return find("Chip" .. i) end
if not chip(1) or not string.find(chip(1).Text, "✓", 1, true) or chip(3).Text ~= "CPU" or chip(5) then
	fail(`the voted strip reads {chip(1) and chip(1).Text} / {chip(3) and chip(3).Text}`)
end
screen:update(voted("map", "vote", nil, "Undertow", 10), 1)
if string.find(chip(1).Text, "✓", 1, true) or not string.find(chip(2).Text, "✓", 1, true) then fail("the strip does not follow who has voted") end
-- the map page draws each arena inside its own card: its sky and its platforms, in the card
local c = Recorder.canvas(Canvas, W, H)
table.clear(shapes)
screen.sinceDraw = nil
screen:draw(c, 1)
for _, m in screen.L.maps do
	if m.id ~= "Random" then
		local inside, colours = 0, {}
		for _, sh in shapes do
			if sh[1] == "p" then
				local ok = true
				for k = 2, 5 do
					local x, y = sh[k][1], sh[k][2]
					if x < m.x - 0.5 or x > m.x + m.w + 0.5 or y < m.y - 0.5 or y > m.y + m.h + 0.5 then ok = false end
				end
				if ok then inside += 1; colours[sh[6]] = true end
			end
		end
		local n = 0
		for _ in colours do n += 1 end
		if inside < 20 or n < 6 then fail(`the {m.id} card has {inside} shapes in {n} colours drawn inside it - its arena is not drawn`) end
	end
end
-- the rules vote: the arena is settled, so the bar names it
screen:update(voted("rules", "ruleVote", "chaos", nil, 9), 1)
if not page("rules") or page("map") or page("pick") then fail("the rules phase did not show the rules page alone") end
-- (the Undertow, by its realm's name, as on its card)
if not string.find(find("Rules").Text, "MAP: VIKING HARBOR", 1, true) then fail(`the rules bar says "{find("Rules").Text}" after the map vote`) end
if find("Clock").Text ~= "9" then fail(`the rules vote's clock says "{find("Clock").Text}"`) end
before = #sent
find("Rulechaos").Activated:Fire()
if #sent ~= before then fail("a click the moment the rules page replaced the map page cast a vote") end
now += Screen.SETTLE
for _, preset in Rules.presets do
	local card = find("Rule" .. preset.id)
	local n = if preset.id == "chaos" then "VOTES · 1" else ""
	if card:FindFirstChild("Count").Text ~= n then fail(`the {preset.id} card counts "{card:FindFirstChild("Count").Text}"`) end
	local how = card:FindFirstChild("Fact1").Text
	if (preset.rules.mode == "timed") ~= (string.find(how, "TIMED", 1, true) ~= nil) then fail(`the {preset.id} card says "{how}"`) end
	card.Activated:Fire()
	if lastSent().action ~= "rule" or lastSent().value ~= preset.id then fail(`the {preset.id} card sent {lastSent().action}/{tostring(lastSent().value)}`) end
end
find("Rulecurrent").Activated:Fire()
if lastSent().action ~= "rule" or lastSent().value ~= "current" then fail("KEEP CURRENT did not send current") end
screen:update(room(), 1)
-- HIDE and back
find("Hide").Activated:Fire()
if screen.open or not visible(find("Reopen")) or visible(find("Root")) then fail("HIDE did not minimise to the ROOM button") end
find("Reopen").Activated:Fire()
if not screen.open or not visible(find("Root")) then fail("the ROOM button did not bring the screen back") end
find("Leave").Activated:Fire()
if lastSent().action ~= "leave" then fail("LEAVE did not send leave") end
-- the scene draws, and the roster's portraits are made once
table.clear(shapes)
screen.sinceDraw = nil
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
-- built at the gui's size, then drawn on a screen of another size (the gui's size was stale when
-- it opened): the next draw lays it out for the screen it is drawn on
do
	local big = Recorder.canvas(Canvas, 1514, 806)
	screen:draw(big, 1)
	if screen.L.W ~= 1514 or screen.L.H ~= 806 then fail(`drawn on 1514x806, the screen is laid out for {screen.L.W}x{screen.L.H}`) end
	local card = find("Card1")
	local p = screen.L.pedestals[1]
	if math.abs(card.Position.X.Offset - p.x) > 1 then fail("the cards were not rebuilt for the new size") end
	screen:draw(c, 1)
	if screen.L.W ~= W then fail("drawn back at the first size, the layout stayed at the other") end
end
-- a fight starts (playing), then comes back (setup): the screen comes back with it
screen:hide()
screen:update(room({ state = "playing" }), 1)
if screen.open then fail("a room that went to its fight opened the screen") end
screen:update(room({ state = "setup" }), 1)
if not screen.open then fail("the room back from its fight did not bring the screen back") end
screen:update({ left = true }, 1)
if screen.open or screen.gui.Enabled then fail("leaving did not close the screen") end

-- NEW OPPONENTS: leaves the room for the queue in one press (Rooms.requeue), clear of LEAVE and READY
do
	screen:update(room({ id = 9 }), 1)
	find("Requeue").Activated:Fire()
	if lastSent().action ~= "requeue" then fail("NEW OPPONENTS did not ask to requeue") end
	local rq, rd = find("Requeue"), find("Ready")
	if rq.Position.X.Offset < rd.Position.X.Offset + rd.Size.X.Offset + 8 then fail("NEW OPPONENTS crowds READY") end
	if rq.Position.X.Offset + rq.Size.X.Offset > screen.L.W then fail("NEW OPPONENTS runs off the screen") end
end
-- levels (Progression): at level 1 only the six starters can be picked. A locked portrait is veiled
-- and named by its level, and clicking it says so instead of sending anything.
do
	screen:setLevel(1)
	screen:update(room({ id = 8 }), 1)
	local before = #sent
	find("PickHammer").Activated:Fire()
	if #sent ~= before then fail("a locked weapon was sent to the server") end
	if not string.find(find("Status").Text, "level 5", 1, true) then fail(`clicking a locked weapon did not say its level: {find("Status").Text}`) end
	if not find("NameHammer") or find("NameHammer").Text ~= "LV 5" then fail("a locked weapon is not named by its unlock level") end
	if not find("PickHammer"):FindFirstChild("Locked").Visible then fail("a locked weapon's portrait is not veiled") end
	if find("PickScythe"):FindFirstChild("Locked").Visible then fail("a starter is veiled at level 1") end
	find("PickScythe").Activated:Fire()
	if #sent ~= before + 1 or lastSent().value ~= "Scythe" then fail("a starter could not be picked at level 1") end
	screen:setLevel(5)
	if find("PickHammer"):FindFirstChild("Locked").Visible then fail("level 5 left the War Hammer locked") end
	find("PickHammer").Activated:Fire()
	if lastSent().value ~= "Hammer" then fail("the War Hammer could not be picked at level 5") end
end
-- a free-for-all stands everyone in a row with no VS, each in their own colour; Ranked votes on the
-- competitive maps only
do
	local slots = { { team = 0 }, { team = 1 }, { team = 2 }, { team = 3 } }
	local L = Screen.layout(1280, 720, slots)
	if not L.ffa or L.vsX then fail("a free-for-all was laid out as two teams") end
	for k = 2, #L.pedestals do
		if L.pedestals[k].slot ~= k or math.abs(L.pedestals[k].x - L.pedestals[k - 1].x - L.pedestals[1].cardW - 14) > 1 then
			fail("a free-for-all's pedestals are not evenly spaced in slot order")
		end
	end
	if Screen.teamColour(2, true) == Screen.teamColour(0, true) then fail("free-for-all fighters share a colour") end
	if Screen.layout(1280, 720, { { team = 0 }, { team = 1 } }).ffa then fail("a 1v1 was taken for a free-for-all") end
	local ranked = Screen.layout(1280, 720, { { team = 0 }, { team = 1 } }, "ranked")
	local all = Screen.layout(1280, 720, { { team = 0 }, { team = 1 } }, "all")
	if #ranked.maps >= #all.maps then fail("Ranked's map vote offers every map") end
	for _, m in ranked.maps do
		if m.id ~= "Random" and not Stages.BY_ID[m.id].ranked then fail(`Ranked offers {m.id}, not a competitive map`) end
	end
	local first, last = ranked.maps[1], ranked.maps[#ranked.maps]
	if math.abs((first.x + last.x + last.w) / 2 - 640) > 2 then fail("Ranked's map cards are not centred") end
	if #ranked.maps > 5 or first.y ~= last.y then fail("Ranked's map cards are not one row") end
end

print("  levels lock the weapons above yours (veiled, named by level, explained, never sent); free-for-alls stand in a row; Ranked votes the competitive maps")
print("PASS select screen: bars from the data; the layout fits 1280x720, 1920x1080, 812x375, 2560x1080, 1280x560, 1280x400 and 640x320 for 1v1/2v2/3v3 with the teams either side of the VS")
print("  every control sends its action (portrait, ADD BOT at a difficulty, YES/NO, REMOVE, READY, LEAVE; no START), HIDE and ROOM, votes take their card, cards show their weapon's bars, picks carry tags, rematches reopen, the roster is drawn once")
print("  the vote pages fit at every size; the phase picks the page; arena and rule cards send their votes, with counts, your ring, the voted strip, the clock and the arena in the bar")
