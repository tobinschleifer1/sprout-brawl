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
local Economy = {}
Economy.__index = Economy

Economy.QUALIFY_SECONDS, Economy.HOURLY_CAP = 45, 12

-- opts: { store = AvatarStore, mint = Mint, rand = () -> number, time = () -> number (os.time) }
function Economy.new(opts: any): any
	return setmetatable({ store = opts.store, mint = opts.mint, rand = opts.rand or math.random, time = opts.time or os.time, paidAllowed = opts.paidAllowed }, Economy)
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
function Economy._matchFinished(self: any, inv: any, results: any, row: any): any
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
	inv.meter = (inv.meter or Loot.nextMeter(self.rand)) - 1
	local out: any = { counted = true }
	if inv.meter <= 0 then
		out.drop = self:_dropInto(inv, Loot.rollDrop(self.rand))
		inv.meter = Loot.nextMeter(self.rand)
	end
	out.left = inv.meter
	return out
end

-- Apply a drop; returns what it was.
function Economy._dropInto(self: any, inv: any, d: any): any
	if d.kind == "crate" then
		inv.crates[d.crate] = math.min(Inventory.MAX_COUNT, inv.crates[d.crate] + 1)
		return { kind = "crate", crate = d.crate }
	elseif d.kind == "sparks" then
		inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + d.amount)
		return { kind = "sparks", amount = d.amount }
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
	if paid then
		local ok, allowed = pcall(function() return self.paidAllowed and self.paidAllowed(userId) end)
		if not ok or allowed ~= true then return false, "paid keys are unavailable for this player" end
		if expectedPity ~= inv.pity[crateId] then return false, "odds changed; refresh Odds & Details before opening" end
	end
	local id, rarity, nextPity = Loot.roll(crateId, inv.pity[crateId], self.rand)
	local uid, why = self:_grant(inv, id, paid, "crate")
	if not uid then return false, why end
	-- only now is anything spent
	inv.crates[crateId] -= 1
	if crate.key then
		local k = inv.keys[crate.key]
		if paid then k.paid -= 1 else k.earned -= 1 end
	end
	inv.pity[crateId] = nextPity
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
	local guarantees = {}
	for id, crate in Loot.CRATES do guarantees[id] = crate.guarantee.at - inv.pity[id] end
	return { sparks = inv.sparks, crates = table.clone(inv.crates), keys = { forge = inv.keys.forge.earned + inv.keys.forge.paid },
		meter = inv.meter, guarantees = guarantees, items = items }
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
	local ok, result = self.store:inventoryTransaction(userId, function(inv) return true, self:_matchFinished(inv, results, row) end)
	return if ok then result else { counted = false, error = result }
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
