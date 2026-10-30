--!strict
-- Earning things, on the server (Roblox only; docs/briefs/crates-and-monetisation-plan.md, phase 3):
-- the drop meter, crates and keys, the guarantee counters, crafting with Sparks and salvaging copies.
--
-- Everything is decided here from the player's saved record (AvatarStore `inventory`, cleaned by
-- Inventory.sanitize); the client only asks. Rolls come from Loot, so what the odds screen shows is
-- what happens. Every new copy gets its serial from the Mint BEFORE anything is spent: if a serial
-- cannot be reserved, nothing is consumed and the player is told to try again.
--
-- A match counts after QUALIFY_SECONDS of this fighter's participation outside Training and
-- some damage dealt or taken. A rolling hourly cap bounds rewards, including against bots.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Inventory = require(Shared.Inventory)
local Loot = require(Shared.Loot)
local Progression = require(Shared.Progression)
local Economy = {}
Economy.__index = Economy

Economy.QUALIFY_SECONDS, Economy.HOURLY_CAP = 45, 12
-- A match with CPU fighters in it counts this much toward the drop meter (the owner: "a quarter less").
Economy.CPU_STEP = 0.75
-- The first win of each UTC day pays these Sparks; VIP doubles it. VIP adds VIP_SPARKS to Spark drops.
Economy.FIRST_WIN, Economy.VIP_SPARKS = 25, 0.10

-- opts: { store = AvatarStore, mint = Mint, rand = () -> number, time = () -> number (os.time),
--   paidAllowed = (userId) -> boolean (PolicyService), vip = (userId) -> boolean (the VIP pass),
--   studio = true in a Studio playtest (Economy.studioBoost) }
function Economy.new(opts: any): any
	return setmetatable({ store = opts.store, mint = opts.mint, rand = opts.rand or math.random, time = opts.time or os.time,
		paidAllowed = opts.paidAllowed, vip = opts.vip or function() return false end, studio = opts.studio == true,
		boosts = {} }, Economy)
end

-- Studio only: a playtest reaches Ranked in a few matches instead of about sixteen (Studio records
-- are session-only, so every playtest starts at level 1). A player's first counted match of the
-- session draws 3-6; each counted match then pays at least the XP still short of RANKED_LEVEL shared
-- over the matches left, so Ranked opens on the drawn match. Returns that least XP (0 when done).
Economy.BOOST_MIN, Economy.BOOST_MAX = 3, 6
function Economy.studioBoost(self: any, userId: number?, xp: number): number
	if not self.studio or not userId then return 0 end
	local b = self.boosts[userId]
	if not b then
		b = { left = Economy.BOOST_MIN + math.floor(self.rand() * (Economy.BOOST_MAX - Economy.BOOST_MIN + 1)) }
		self.boosts[userId] = b
	end
	local short = Progression.xpTo(Progression.RANKED_LEVEL) - xp
	if b.left <= 0 or short <= 0 then return 0 end
	local least = math.ceil(short / b.left)
	b.left -= 1
	return least
end
local function isVip(self: any, userId: number?): boolean
	if not userId then return false end
	local ok, v = pcall(self.vip, userId)
	return ok and v == true
end
-- Did this row win? The top row of a free-for-all, or anyone on the winning team.
function Economy.won(results: any, row: any): boolean
	if type(results) ~= "table" or type(row) ~= "table" then return false end
	if results.winnerTeam ~= nil then return row.team == results.winnerTeam end
	local first = results.rows and results.rows[1]
	return first ~= nil and first.index == row.index
end

function Economy.inventory(self: any, userId: number): any
	local rec = self.store:load(userId)
	rec.inventory = rec.inventory or Inventory.sanitize(nil)
	return rec.inventory
end

-- A new copy of `id` for the player, serial first. Returns the uid and instance, or nil.
function Economy._grant(self: any, inv: any, id: string, paid: boolean, src: string): (string?, any)
	local n = 0
	for _ in inv.items do n += 1 end
	if n >= Inventory.MAX_OWNED or inv.seq >= Inventory.MAX_INTEGER then return nil, "your locker is full" end
	local serial = self.mint:serial(id)
	if not serial then return nil, "the vault is busy: try again in a moment" end
	local uid = Inventory.add(inv, id, serial, paid, src, self.time())
	if not uid then return nil, "your locker is full" end
	return uid, inv.items[uid]
end

-- Whether a finished match counts for this player: `row` is their MatchService results row.
function Economy.qualifies(results: any, row: any): boolean
	if type(results) ~= "table" or type(row) ~= "table" then return false end
	if results.mode == "Training" then return false end
	local frames = row.fightFrames
	if type(frames) ~= "number" or frames ~= frames or frames == math.huge or frames < Economy.QUALIFY_SECONDS * 60 then return false end
	return (row.damage or 0) > 0 or (row.taken or 0) > 0
end

-- A match ended. Returns what the player is told: { counted, left, capped?, drop? }.
function Economy._matchFinished(self: any, inv: any, results: any, row: any, userId: number?): any
	if not Economy.qualifies(results, row) then return { counted = false, left = inv.meter } end
	local now = self.time()
	local hour = math.floor(now / 3600)
	local times = inv.earn.times
	-- Old records only know an hour bucket. Conservatively place their matches at that hour's
	-- end once, so a boundary/rejoin cannot erase matches whose exact timestamps were not saved.
	if not times then
		times = {}
		for _ = 1, math.min(Economy.HOURLY_CAP, inv.earn.count) do table.insert(times, inv.earn.hour * 3600 + 3599) end
		inv.earn.times = times
	end
	for i = #times, 1, -1 do if times[i] <= now - 3600 then table.remove(times, i) end end
	if inv.earn.hour ~= hour then inv.earn.hour, inv.earn.count = hour, 0 end
	if #times >= Economy.HOURLY_CAP then return { counted = false, capped = true, left = inv.meter } end
	table.insert(times, now)
	inv.earn.count += 1
	local vip = isVip(self, userId)
	local ranked = results.ranked == true
	inv.meter = (inv.meter or Loot.nextMeter(self.rand)) - (if results.cpu then Economy.CPU_STEP else 1)
		- (if ranked then Progression.RANKED_METER else 0)
	local out: any = { counted = true, cpu = results.cpu == true }
	if inv.meter <= 0 then
		out.drop = self:_dropInto(inv, Loot.rollDrop(self.rand), vip)
		-- what is left of a quarter step carries into the next meter
		inv.meter = Loot.nextMeter(self.rand) + inv.meter
	end
	-- the first win of the day
	local day = math.floor(now / 86400)
	if Economy.won(results, row) and inv.firstWin ~= day then
		inv.firstWin = day
		local bonus = Economy.FIRST_WIN * (if vip then 2 else 1)
		inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + bonus)
		out.firstWin = bonus
	end
	out.progress = Economy._progress(inv, Economy.won(results, row), results.cpu == true, ranked,
		self:studioBoost(userId, inv.progress.xp))
	out.left = inv.meter
	return out
end

-- Levels and the Ranked ladder (Progression), for a match that counted. Returns what changed.
function Economy._progress(inv: any, won: boolean, cpu: boolean, ranked: boolean, least: number?): any
	local p = inv.progress
	local before = Progression.level(p.xp)
	local gained = math.max(Progression.xpFor(won, cpu), least or 0)
	p.xp = math.min(Inventory.MAX_COUNT, p.xp + gained)
	local level, into, need = Progression.level(p.xp)
	local out: any = { xp = gained, level = level, into = into, need = need, from = before,
		unlocked = Progression.unlocksBetween(before, level) }
	if not ranked then return out end
	local points = Progression.rankAfter(p.points, p.best, won, cpu)
	local tier = Progression.tier(points)
	local rank: any = { delta = points - p.points, points = points, tier = tier }
	p.points = points
	-- each tier reached for the first time pays its reward once, in order (a jump of two pays both)
	if tier > p.best then
		rank.promoted = {}
		for t = p.best + 1, tier do
			local r = Progression.TIERS[t].reward
			if r then
				inv.keys.forge.earned = math.min(Inventory.MAX_COUNT, inv.keys.forge.earned + (r.keys or 0))
				inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + (r.sparks or 0))
				if r.crate then inv.crates[r.crate] = math.min(Inventory.MAX_COUNT, inv.crates[r.crate] + (r.crates or 1)) end
			end
			table.insert(rank.promoted, t)
		end
		p.best = tier
	end
	-- the ranked boost: Sparks for a win, and a Forge Key every KEY_EVERY wins
	if won then
		inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + Progression.RANKED_SPARKS)
		rank.sparks = Progression.RANKED_SPARKS
		p.wins = math.min(Inventory.MAX_COUNT, p.wins + 1)
		if p.wins % Progression.KEY_EVERY == 0 then
			inv.keys.forge.earned = math.min(Inventory.MAX_COUNT, inv.keys.forge.earned + 1)
			rank.key = true
		end
	end
	out.rank = rank
	return out
end

-- The player's level, from their saved XP.
function Economy.level(self: any, userId: number): number
	return (Progression.level(self:inventory(userId).progress.xp))
end
-- Their level and rank, as the client shows them.
function Economy.progressView(inv: any): any
	local p = inv.progress
	local level, into, need = Progression.level(p.xp)
	return { xp = p.xp, level = level, into = into, need = need, points = p.points, tier = Progression.tier(p.points),
		best = p.best, wins = p.wins }
end

-- Apply a drop; returns what it was.
function Economy._dropInto(self: any, inv: any, d: any, vip: boolean?): any
	if d.kind == "crate" then
		inv.crates[d.crate] = math.min(Inventory.MAX_COUNT, inv.crates[d.crate] + 1)
		return { kind = "crate", crate = d.crate }
	elseif d.kind == "sparks" then
		local amount = math.floor(d.amount * (if vip then 1 + Economy.VIP_SPARKS else 1))
		inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + amount)
		return { kind = "sparks", amount = amount }
	elseif d.kind == "key" then
		inv.keys.forge.earned = math.min(Inventory.MAX_COUNT, inv.keys.forge.earned + 1)
		return { kind = "key", key = d.key }
	end
	-- a cosmetic straight from the crate's pool, at its listed odds (the guarantee is not touched)
	local id, rarity = Loot.roll(d.crate, 0, self.rand)
	local uid = self:_grant(inv, id, false, "drop")
	if not uid then
		-- the vault could not be reached: the drop is a crate instead, never lost
		inv.crates[d.crate] = math.min(Inventory.MAX_COUNT, inv.crates[d.crate] + 1)
		return { kind = "crate", crate = d.crate }
	end
	return { kind = "item", id = id, rarity = rarity, uid = uid, serial = inv.items[uid].s }
end

-- Open a crate. Forge Crates take a Forge Key, an earned one first (so the item stays tradeable
-- for everyone); an item from a paid key is paid. Returns ok and the result or why not.
function Economy._open(self: any, inv: any, crateId: any, expectedPity: any, userId: number): (boolean, any)
	local crate = type(crateId) == "string" and #crateId <= 64 and Loot.CRATES[crateId]
	if not crate then return false, "no such crate" end
	if inv.crates[crateId] < 1 then return false, "you have no " .. crate.name end
	local paid = false
	if crate.key then
		local k = inv.keys[crate.key]
		if k.earned < 1 and k.paid < 1 then return false, "you need a Forge Key" end
		paid = k.earned < 1
	end
	-- the guarantee count that applies: paid keys progress their own, never the earned one
	local track = if paid then inv.paidPity else inv.pity
	if paid then
		local ok, allowed = pcall(function() return self.paidAllowed and self.paidAllowed(userId) end)
		if not ok or allowed ~= true then return false, "paid keys are unavailable for this player" end
		if expectedPity ~= track[crateId] then return false, "odds changed; refresh Odds & Details before opening" end
	end
	local id, rarity, nextPity = Loot.roll(crateId, track[crateId], self.rand)
	local uid, why = self:_grant(inv, id, paid, "crate")
	if not uid then return false, why end
	-- only now is anything spent
	inv.crates[crateId] -= 1
	if crate.key then
		local k = inv.keys[crate.key]
		if paid then k.paid -= 1 else k.earned -= 1 end
	end
	track[crateId] = nextPity
	return true, { id = id, rarity = rarity, uid = uid, serial = inv.items[uid].s, paid = paid, copies = self.mint:copies(id) }
end

-- Craft an item of a released series with Sparks.
function Economy._craft(self: any, inv: any, id: any): (boolean, any)
	local cost = type(id) == "string" and #id <= 64 and Loot.craftCost(id)
	if not cost then return false, "that cannot be crafted" end
	if inv.sparks < cost then return false, `you need {cost} Sparks` end
	local uid, why = self:_grant(inv, id, false, "craft")
	if not uid then return false, why end
	inv.sparks -= cost
	return true, { id = id, uid = uid, serial = inv.items[uid].s, cost = cost }
end

-- Salvage a copy for Sparks: it leaves the game (the Mint counts it destroyed).
function Economy._salvage(self: any, inv: any, uid: any): (boolean, any)
	if type(uid) ~= "string" or #uid > 17 or not inv.items[uid] then return false, "no such item" end
	if inv.items[uid].p then return false, "paid items cannot be salvaged into earned Sparks" end
	local inst = Inventory.remove(inv, uid) :: any
	local item = Cosmetics.get(inst.i)
	local sparks = Loot.dupe((item :: any).rarity)
	inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + sparks)
	return true, { id = inst.i, sparks = sparks }
end

-- What the client is shown.
function Economy.view(self: any, userId: number): any
	local inv = self:inventory(userId)
	local items = {}
	for uid, inst in inv.items do
		table.insert(items, { uid = uid, id = inst.i, serial = inst.s, paid = inst.p, copies = self.mint:copies(inst.i) })
	end
	table.sort(items, function(a, b) return a.uid < b.uid end)
	-- the countdown for the key the next opening will use (an earned one first)
	local guarantees = {}
	for id, crate in Loot.CRATES do
		local paidNext = crate.key ~= nil and inv.keys[crate.key].earned < 1 and inv.keys[crate.key].paid > 0
		guarantees[id] = crate.guarantee.at - (if paidNext then inv.paidPity[id] else inv.pity[id])
	end
	return { sparks = inv.sparks, crates = table.clone(inv.crates), keys = { forge = inv.keys.forge.earned + inv.keys.forge.paid },
		meter = inv.meter, guarantees = guarantees, items = items, progress = Economy.progressView(inv) }
end

-- All public mutations share the record transaction, including direct server grants and drops.
function Economy.grant(self: any, userId: number, id: string, paid: boolean, src: string): (string?, any)
	local ok, result = self.store:inventoryTransaction(userId, function(inv)
		local uid, why = self:_grant(inv, id, paid, src)
		return uid ~= nil, if uid then { uid = uid, item = why } else why
	end)
	if not ok then return nil, result end
	return result.uid, result.item
end
function Economy.open(self: any, userId: number, crateId: any, expectedPity: any): (boolean, any)
	return self.store:inventoryTransaction(userId, function(inv) return self:_open(inv, crateId, expectedPity, userId) end)
end
function Economy.craft(self: any, userId: number, id: any): (boolean, any)
	return self.store:inventoryTransaction(userId, function(inv) return self:_craft(inv, id) end)
end
function Economy.salvage(self: any, userId: number, uid: any): (boolean, any)
	local ok, result = self.store:inventoryTransaction(userId, function(inv) return self:_salvage(inv, uid) end)
	if ok then self.mint:destroy(result.id) end
	return ok, result
end
function Economy._drop(self: any, userId: number, d: any): any
	local ok, result = self.store:inventoryTransaction(userId, function(inv) return true, self:_dropInto(inv, d) end)
	return if ok then result else nil
end
function Economy.matchFinished(self: any, userId: number, results: any, row: any): any
	if not Economy.qualifies(results, row) then return { counted = false, left = self:inventory(userId).meter } end
	local ok, result = self.store:inventoryTransaction(userId, function(inv) return true, self:_matchFinished(inv, results, row, userId) end)
	return if ok then result else { counted = false, error = result }
end

-- A Robux purchase, applied once: `fn(inv)` runs in the record's transaction, and the purchase id is
-- remembered inside the same write, so a redelivered receipt finds it and grants nothing twice.
function Economy.purchase(self: any, userId: number, purchaseId: string, fn: (any) -> (boolean, any)): (boolean, any)
	return self.store:inventoryTransaction(userId, function(inv)
		if table.find(inv.receipts, purchaseId) then return true, { already = true } end
		local ok, res = fn(inv)
		if ok then
			table.insert(inv.receipts, purchaseId)
			while #inv.receipts > Inventory.RECEIPTS do table.remove(inv.receipts, 1) end
		end
		return ok, res
	end)
end

-- The remote supplies only a short catalogue id or an owned uid, never balances or roll results.
function Economy.apply(self: any, userId: number, msg: any): (boolean, any)
	if type(msg) ~= "table" then return false, "bad request" end
	if msg.action == "open" then return self:open(userId, msg.crate, msg.pity)
	elseif msg.action == "craft" then return self:craft(userId, msg.id)
	elseif msg.action == "salvage" then return self:salvage(userId, msg.uid)
	end
	return false, "bad request"
end

return Economy
