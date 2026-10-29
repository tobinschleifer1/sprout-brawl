--!nocheck
-- Levels, weapon unlocks, the Ranked ladder and PLAY's free-for-alls (Roblox only; the owner's
-- design, 2026-10-30): Progression's rules as numbers, then the same rules through the real server
-- modules - Economy paying XP, rank points and the tier rewards into a saved record, and Rooms
-- locking weapons and Ranked by level and building free-for-all and Ranked rooms.
local Loader = require("./loader")
local Progression = Loader.load("Progression")
local Weapons = Loader.load("Weapons")
local Inventory = Loader.load("Inventory")
local Stages = Loader.load("Data/Stages")
local Mint = Loader.loadFrom("src/server/", "Mint")
local Economy = Loader.loadFrom("src/server/", "Economy")
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local Rooms = Loader.loadFrom("src/server/", "Rooms")
local DropBanner = Loader.loadFrom("src/client/", "DropBanner")
Rooms.BOT_WAIT = 0

local function fail(msg: string) error(msg, 2) end

-- 1. The weapons: the first six made are everyone's, the rest unlock from level 3 to level 15, and
-- every weapon in the game has a level (a new one fails here until it is given one).
do
	local want = { "Sword", "Scythe", "Blasters", "Grimoire", "Axe", "Pike" }
	if #Progression.STARTERS ~= 6 then fail("there are not six starter weapons") end
	for i, id in want do
		if Progression.STARTERS[i] ~= id then fail(`starter {i} is {Progression.STARTERS[i]}, not {id}`) end
		if Weapons.LIST[i].id ~= id then fail(`the roster's weapon {i} is {Weapons.LIST[i].id}: the starters are not the first six made`) end
		if not Progression.unlocked(1, id) then fail(`{id} is locked at level 1`) end
	end
	local seen, last = {}, 0
	for _, w in Weapons.LIST do
		local listed = table.find(Progression.STARTERS, w.id) ~= nil
		for _, u in Progression.UNLOCKS do if u.weapon == w.id then listed = true end end
		if not listed then fail(`{w.id} has no unlock level`) end
	end
	for _, u in Progression.UNLOCKS do
		if not Weapons.BY_ID[u.weapon] then fail(`{u.weapon} unlocks but is not a weapon`) end
		if seen[u.weapon] then fail(`{u.weapon} unlocks twice`) end
		seen[u.weapon] = true
		if u.level <= last then fail("the unlocks are not in rising order of level") end
		last = u.level
		if Progression.unlocked(u.level - 1, u.weapon) then fail(`{u.weapon} is open at level {u.level - 1}`) end
		if not Progression.unlocked(u.level, u.weapon) then fail(`{u.weapon} is locked at its own level`) end
	end
	if Progression.UNLOCKS[1].level ~= 3 then fail("the first unlock is not at level 3") end
	if last ~= 15 then fail("the last unlock is not at level 15") end
	if Progression.unlockLevel("NotYetMade") ~= 15 then fail("a weapon nobody gave a level is not the last unlock's") end
	local between = Progression.unlocksBetween(2, 5)
	if #between ~= 2 or between[1] ~= "Gauntlets" or between[2] ~= "Hammer" then fail("level 2 to 5 did not unlock the Gauntlets and the War Hammer") end
end

-- 2. The pace ("quick"): level 3 within three matches, Ranked (level 10) and level 15 about
-- thirty matches in, winning half of them against people.
do
	if Progression.level(0) ~= 1 then fail("a new player is not level 1") end
	local function matchesTo(level: number, won: boolean, cpu: boolean): number
		local xp, n = 0, 0
		while Progression.level(xp) < level do
			n += 1
			xp += Progression.xpFor(won and n % 2 == 0, cpu)
		end
		return n
	end
	if matchesTo(3, false, true) > 4 then fail(`level 3 took {matchesTo(3, false, true)} lost matches against bots`) end
	if matchesTo(3, true, false) > 3 then fail("level 3 took more than three matches") end
	local to15 = matchesTo(15, true, false)
	if to15 < 22 or to15 > 34 then fail(`level 15 took {to15} matches, not about thirty`) end
	local to10 = matchesTo(10, true, false)
	if to10 >= to15 or to10 < 10 then fail(`Ranked opened after {to10} matches`) end
	if Progression.RANKED_LEVEL ~= 10 then fail("Ranked does not open at level 10") end
	local level, into, need = Progression.level(Progression.need(1) + 7)
	if level ~= 2 or into ~= 7 or need ~= Progression.need(2) then fail("the XP into a level is wrong") end
	if select(3, Progression.level(1e9)) ~= 0 or Progression.level(1e9) ~= Progression.MAX_LEVEL then fail("XP past the top level is not MAX") end
	if Progression.xpFor(true, false) <= Progression.xpFor(false, false) then fail("a win pays no more XP than a loss") end
	if Progression.xpFor(false, true) >= Progression.xpFor(false, false) then fail("a match against bots pays as much XP") end
end

-- 3. The ladder: six tiers, points up on a win, down a little on a loss, never below a tier reached.
do
	local names = {}
	for _, t in Progression.TIERS do table.insert(names, t.name) end
	if table.concat(names, " ") ~= "BRONZE SILVER GOLD PLATINUM DIAMOND CHAMPION" then fail("the tiers are " .. table.concat(names, " ")) end
	for i = 2, #Progression.TIERS do
		local t = Progression.TIERS[i]
		if t.at <= Progression.TIERS[i - 1].at then fail("the tiers do not rise") end
		if not t.reward or (t.reward.keys or 0) < 1 or (t.reward.sparks or 0) < 1 then fail(`{t.name} pays no keys or Sparks`) end
		if (t.reward.keys or 0) < (Progression.TIERS[i - 1].reward and Progression.TIERS[i - 1].reward.keys or 0) then fail(`{t.name} pays fewer keys than the tier under it`) end
		if Progression.tier(t.at) ~= i or Progression.tier(t.at - 1) ~= i - 1 then fail(`{t.name} begins at the wrong points`) end
	end
	if Progression.rankAfter(0, 1, true, false) ~= Progression.RANK_WIN then fail("a win did not add RANK_WIN") end
	if Progression.rankAfter(50, 1, false, false) ~= 50 - Progression.RANK_LOSS then fail("a loss did not take RANK_LOSS") end
	if Progression.rankAfter(0, 1, false, false) ~= 0 then fail("rank points went below zero") end
	if Progression.rankAfter(105, 2, false, false) ~= 100 then fail("a loss dropped a player out of a tier they had reached") end
	if Progression.rankAfter(0, 1, true, true) >= Progression.RANK_WIN then fail("a win against bots counted in full") end
end

-- 4. The saved record: progress cleaned like every other balance.
do
	local inv = Inventory.sanitize({ progress = { xp = -5, points = 1 / 0, best = 99, wins = "lots" } })
	local p = inv.progress
	if p.xp ~= 0 or p.points ~= 0 or p.best ~= #Progression.TIERS or p.wins ~= 0 then fail("a bad progress record survived") end
	if Inventory.sanitize(nil).progress.best ~= 1 then fail("a new record's best tier is not Bronze") end
	local kept = Inventory.sanitize({ progress = { xp = 1234, points = 260, best = 3, wins = 4 } }).progress
	if kept.xp ~= 1234 or kept.points ~= 260 or kept.best ~= 3 or kept.wins ~= 4 then fail("a good progress record was not kept") end
end

-- 5. Economy: a counted match pays XP; a ranked one rank points, the tier rewards once, Sparks for
-- a win and a key every few wins; nothing for a match that did not count.
local function records() return AvatarStore.new(nil, function() return 1 end, { sessionOnly = true }) end
local row = { index = 0, team = 0, damage = 20, taken = 10, fightFrames = 3600 }
local function results(won: boolean, ranked: boolean, cpu: boolean?): any
	return { mode = "StockTeams", winnerTeam = if won then 0 else 1, rows = { row }, ranked = ranked, cpu = cpu == true }
end
do
	local t = 0
	local econ = Economy.new({ store = records(), mint = Mint.new(nil, function() return t end, true), rand = function() return 0.5 end,
		time = function() return t end })
	local out = econ:matchFinished(1, results(true, false), row)
	if not out.progress or out.progress.xp ~= Progression.xpFor(true, false) then fail("a won match did not pay its XP") end
	if out.progress.rank then fail("a match that was not ranked moved the rank") end
	local inv = econ:inventory(1)
	if inv.progress.xp ~= Progression.xpFor(true, false) or inv.progress.points ~= 0 then fail("the XP was not saved, or a casual match moved rank points") end
	-- to level 3: the Gauntlets unlock, and say so
	local unlocked = nil
	for _ = 1, 5 do
		t += 3600
		local o = econ:matchFinished(1, results(true, false), row)
		if #o.progress.unlocked > 0 and not unlocked then unlocked = o.progress end
	end
	if not unlocked or unlocked.unlocked[1] ~= "Gauntlets" or unlocked.level < 3 then fail("reaching level 3 did not unlock the Gauntlets") end
	if econ:level(1) < 3 then fail("Economy.level does not read the saved XP") end
	local view = econ:view(1).progress
	if view.level ~= econ:level(1) or view.need ~= Progression.need(view.level) then fail("the view's level is not the record's") end
	-- a match that did not count pays nothing
	local before = inv.progress.xp
	econ:matchFinished(1, { mode = "Training", frames = 9999, rows = {} }, row)
	if inv.progress.xp ~= before then fail("a Training match paid XP") end
	-- the hourly cap stops XP with the drops (a fresh hour: the matches above are all older)
	t += 3600
	for _ = 1, Economy.HOURLY_CAP + 2 do econ:matchFinished(1, results(true, false), row) end
	if inv.progress.xp ~= before + Economy.HOURLY_CAP * Progression.xpFor(true, false) then fail("XP was paid past the hourly cap") end
end
do
	local t = 0
	local econ = Economy.new({ store = records(), mint = Mint.new(nil, function() return t end, true), rand = function() return 0.5 end,
		time = function() return t end })
	local inv = econ:inventory(1)
	local keys, sparks = inv.keys.forge.earned, inv.sparks
	-- four ranked wins: 100 points, Silver
	local outs = {}
	for i = 1, 4 do
		t += 3600
		outs[i] = econ:matchFinished(1, results(true, true), row)
	end
	local r = outs[4].progress.rank
	if not r or r.points ~= 4 * Progression.RANK_WIN or r.tier ~= 2 then fail("four ranked wins did not reach Silver") end
	if not r.promoted or r.promoted[1] ~= 2 then fail("reaching Silver was not a promotion") end
	if outs[3].progress.rank.promoted then fail("a promotion before Silver was reached") end
	if not outs[3].progress.rank.key or outs[2].progress.rank.key then fail("the boost key did not come on the third ranked win") end
	local silver = Progression.TIERS[2].reward
	local wantKeys = keys + silver.keys + 1
	local wantSparks = sparks + silver.sparks + 4 * Progression.RANKED_SPARKS
	if inv.keys.forge.earned ~= wantKeys then fail(`ranked paid {inv.keys.forge.earned - keys} keys, not {wantKeys - keys}`) end
	-- (a first win of the day, and a Sparks drop, pay Sparks too: counted from what each match said)
	for _, o in outs do
		wantSparks += (o.firstWin or 0) + (if o.drop and o.drop.kind == "sparks" then o.drop.amount else 0)
	end
	if inv.sparks ~= wantSparks then fail(`ranked paid {inv.sparks - sparks} Sparks, not {wantSparks - sparks}`) end
	-- a loss: points down, never below Silver, and Silver never pays twice
	local paid = inv.sparks
	for _ = 1, 3 do t += 3600; econ:matchFinished(1, results(false, true), row) end
	if inv.progress.points ~= 100 then fail(`three losses left {inv.progress.points} points: below the Silver a player reached`) end
	t += 3600
	local again = econ:matchFinished(1, results(true, true), row)
	if again.progress.rank.promoted then fail("Silver paid twice") end
	if inv.sparks ~= paid + Progression.RANKED_SPARKS + (again.firstWin or 0) + (if again.drop and again.drop.kind == "sparks" then again.drop.amount else 0) then fail("a win back to Silver paid its reward again") end
	-- a big jump pays every tier passed, crates too
	inv.progress.points = 240
	local crates = inv.crates.scrap
	t += 3600
	local gold = econ:matchFinished(1, results(true, true), row).progress.rank
	if gold.tier ~= 3 or #gold.promoted ~= 1 or inv.crates.scrap ~= crates + 1 then fail("reaching Gold did not pay its crate") end
	-- ranked moves the drop meter further
	local m = Economy.new({ store = records(), mint = Mint.new(nil, function() return t end, true), rand = function() return 0.99 end, time = function() return t end })
	local a = m:matchFinished(1, results(false, false), row).left
	local b = m:matchFinished(2, results(false, true), row).left
	if math.abs((a - b) - Progression.RANKED_METER) > 1e-9 then fail("a ranked match did not move the drop meter further") end
end

-- 6. Rooms: free-for-alls of 3, 4 and 6, each fighter their own team; Ranked locked below level 10,
-- one set of rules, competitive maps, no rules vote; weapons locked by level.
local function player(id: number): any return { UserId = id, DisplayName = `P{id}`, Name = `P{id}` } end
do
	for _, case in { { "FFA3", 3 }, { "FFA4", 4 }, { "FFA6", 6 } } do
		local m = Rooms.new()
		local list = {}
		for i = 1, case[2] - 1 do list[i] = player(i); m:queue(list[i], case[1]) end
		local room = m:get(1)
		if not room then fail(`{case[1]}: {case[2] - 1} queued opened no room`) end
		if #room.slots ~= case[2] then fail(`{case[1]} has {#room.slots} places`) end
		for i, slot in room.slots do if slot.team ~= i - 1 then fail(`{case[1]}: place {i} is on team {slot.team}`) end end
		local view = m:queueView(99)
		if view.queued then fail("an outsider is queued") end
		if not room.ffa or room.ranked then fail(`{case[1]} is not a free-for-all`) end
		local _, opts = m:roster(room, function() return 1 end)
		if opts.mode ~= "StockFFA" or opts.ranked then fail(`{case[1]} plays {opts.mode}`) end
		room.mode = "timed"
		if select(2, m:roster(room, function() return 1 end)).mode ~= "TimedFFA" then fail("a timed free-for-all is not TimedFFA") end
	end
	if Rooms.formAt(2) ~= 2 or Rooms.formAt(3) ~= 2 or Rooms.formAt(4) ~= 3 or Rooms.formAt(6) ~= 5 then fail("formAt is wrong") end
	local order = {}
	for _, f in Rooms.FORMATS do table.insert(order, f.id) end
	if table.concat(order, " ") ~= "Duel Doubles Triples FFA3 FFA4 FFA6 Ranked" then fail("PLAY's formats are " .. table.concat(order, " ")) end
end
do
	local m = Rooms.new()
	local levels = { [1] = 9, [2] = 10, [3] = 12 }
	local P1, P2, P3 = player(1), player(2), player(3)
	m.levelOf = function(id) return levels[id] or 1 end
	local changed, why = m:queue(P1, "Ranked")
	if changed or not why or not string.find(why, "level 10", 1, true) or m:queued(1) then fail("a level 9 player queued for Ranked") end
	if m:join(P1, "Ranked") then fail("a level 9 player joined Ranked directly") end
	m:queue(P2, "Ranked")
	m:queue(P3, "Ranked")
	local room = m:get(2)
	if not room or m:get(3) ~= room or not room.ranked then fail("two level 10+ players did not open a Ranked room") end
	if room.items ~= false or room.disasters ~= "off" or room.mapSet ~= "ranked" or room.stocks ~= 3 then fail("Ranked's rules are not its own") end
	local function edit(p, action, value)
		return m:edit(p, { id = room.id, revision = room.revision, action = action, value = value })
	end
	if edit(P2, "items", true) then fail("a host changed Ranked's rules") end
	-- weapons: the level 10 player cannot take the Daggers (11); the level 12 player can
	local ok, no = edit(P2, "weapon", "Daggers")
	if ok or not string.find(no or "", "level 11", 1, true) then fail(`a locked weapon was taken ({ok}, {no})`) end
	if not edit(P3, "weapon", "Daggers") then fail("an unlocked weapon was refused") end
	for _, p in { P2, P3 } do edit(p, "ready") end
	m:advance(room)
	if room.phase ~= "map" then fail("Ranked did not go to the map vote") end
	local casual = nil
	for _, st in Stages.LIST do if not st.ranked then casual = st.id end end
	if edit(P2, "vote", casual) then fail("Ranked took a vote for a map off the competitive rotation") end
	local fine = nil
	for _, st in Stages.LIST do if st.ranked then fine = st.id end end
	edit(P2, "vote", fine); edit(P3, "vote", fine)
	m:advance(room)
	if room.state ~= "playing" or room.stage ~= fine then fail("Ranked did not start the fight after the map vote") end
	local _, opts = m:roster(room)
	if not opts.ranked or opts.items ~= false or opts.mode ~= "StockTeams" then fail("Ranked's match is not ranked") end
	-- a random map in Ranked is a competitive one
	local r2 = Rooms.new()
	r2.levelOf = function() return 10 end
	local P5, P6 = player(5), player(6)
	r2:queue(P5, "Ranked"); r2:queue(P6, "Ranked")
	local room2 = r2:get(5)
	for _, p in { P5, P6 } do r2:edit(p, { id = room2.id, revision = room2.revision, action = "ready" }) end
	r2:advance(room2)
	r2.clock = function() return math.huge end
	for k = 1, #Stages.LIST do
		r2.rand = function(n) return ((k - 1) % n) + 1 end
		room2.phase, room2.state, room2.phaseEnds = "map", "setup", 0
		for _, slot in room2.slots do slot.vote = nil end
		r2:advance(room2)
		if not Stages.BY_ID[room2.stage].ranked then fail(`Ranked drew {room2.stage} at random`) end
	end
end
do
	-- a level 1 player's remembered weapons are kept to the starters
	local m = Rooms.new()
	local p = player(8)
	m:profile(8).weapon, m:profile(8).weapon2 = "Chakram", "Whip"
	local room = m:join(p, "Duel")
	local slot = room.slots[1]
	if not Progression.unlocked(1, slot.weapon) or not Progression.unlocked(1, slot.weapon2) or slot.weapon == slot.weapon2 then
		fail(`a level 1 player brought {slot.weapon} and {slot.weapon2}`)
	end
	if m:edit(p, { id = room.id, revision = room.revision, action = "weapon2", value = "Hammer" }) then fail("a level 1 player took the War Hammer") end
	if not m:edit(p, { id = room.id, revision = room.revision, action = "weapon2", value = "Pike" }) then fail("a level 1 player could not take the Pike") end
end

-- 7. The line over the drop's: XP, a level, an unlock, Ranked opening, rank points and promotions.
do
	local text = DropBanner.progressText({ xp = 160, level = 5, from = 4, unlocked = { "Hammer" }, into = 0, need = 200 })
	if not string.find(text, "LEVEL 5", 1, true) or not string.find(text, "War Hammer", 1, true) then fail("a level up did not say the level and the unlock: " .. text) end
	local open = DropBanner.progressText({ xp = 100, level = 10, from = 9, unlocked = {} })
	if not string.find(open, "RANKED", 1, true) then fail("reaching level 10 did not say Ranked is open") end
	local plain = DropBanner.progressText({ xp = 100, level = 4, from = 4, unlocked = {} })
	if plain ~= "+100 XP" then fail("a plain match said " .. plain) end
	local promo, colour = DropBanner.progressText({ xp = 160, level = 12, from = 12, unlocked = {},
		rank = { delta = 25, points = 250, tier = 3, promoted = { 3 }, sparks = 15, key = true } })
	if not string.find(promo, "PROMOTED TO GOLD", 1, true) or not string.find(promo, "Forge Key", 1, true) or colour ~= Progression.TIERS[3].colour then
		fail("a promotion did not say so: " .. promo)
	end
	local loss = DropBanner.progressText({ xp = 100, level = 12, from = 12, unlocked = {}, rank = { delta = -10, points = 140, tier = 2 } })
	if not string.find(loss, "(-10)", 1, true) then fail("a ranked loss did not show its points: " .. loss) end
	if DropBanner.progressText(nil) ~= "" then fail("a match that did not count showed a progress line") end
end

print("PASS progression: the first six weapons for everyone, the rest from level 3 to 15; level 15 about thirty matches in; Ranked at level 10")
print("  six tiers, never dropping one reached, each paying keys and Sparks once; ranked wins pay Sparks and a key every three; ranked moves the drop meter further")
print("  free-for-alls of 3, 4 and 6 (own teams, FFA modes); Ranked's fixed rules and competitive maps, no rules vote; weapons and Ranked refused below their level")
