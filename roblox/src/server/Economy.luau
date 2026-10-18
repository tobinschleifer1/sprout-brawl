--!strict
-- Earning things, on the server (Roblox only; docs/briefs/crates-and-monetisation-plan.md, phase 3):
-- the drop meter, crates and keys, the guarantee counters, crafting with Sparks and salvaging copies.
--
-- Everything is decided here from the player's saved record (AvatarStore `inventory`, cleaned by
-- Inventory.sanitize); the client only asks. Rolls come from Loot, so what the odds screen shows is
-- what happens. Every new copy gets its serial from the Mint BEFORE anything is spent: if a serial
-- cannot be reserved, nothing is consumed and the player is told to try again.
--
-- A match counts toward the drop meter when it ran at least QUALIFY_SECONDS, was not Training, and
-- the player dealt or took damage; at most HOURLY_CAP count an hour, so idle rooms do not farm.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Inventory = require(Shared.Inventory)
local Loot = require(Shared.Loot)
local Economy = {}
Economy.__index = Economy

Economy.QUALIFY_SECONDS, Economy.HOURLY_CAP = 45, 12

-- opts: { store = AvatarStore, mint = Mint, rand = () -> number, time = () -> number (os.time) }
function Economy.new(opts: any): any
	return setmetatable({ store = opts.store, mint = opts.mint, rand = opts.rand or math.random, time = opts.time or os.time }, Economy)
end

function Economy.inventory(self: any, userId: number): any
	local rec = self.store:load(userId)
	rec.inventory = rec.inventory or Inventory.sanitize(nil)
	return rec.inventory
end

local function dirty(self: any, userId: number)
	self.store.dirty[userId] = self.store.dirty[userId] or self.store.clock()
end

-- A new copy of `id` for the player, serial first. Returns the uid and instance, or nil.
function Economy.grant(self: any, userId: number, id: string, paid: boolean, src: string): (string?, any)
	local inv = self:inventory(userId)
	local serial = self.mint:serial(id)
	if not serial then return nil, "the vault is busy: try again in a moment" end
	local uid = Inventory.add(inv, id, serial, paid, src, self.time())
	if not uid then return nil, "your locker is full" end
	dirty(self, userId)
	return uid, inv.items[uid]
end

-- Whether a finished match counts for this player: `row` is their MatchService results row.
function Economy.qualifies(results: any, row: any): boolean
	if type(results) ~= "table" or type(row) ~= "table" then return false end
	if results.mode == "Training" then return false end
	if (results.frames or 0) < Economy.QUALIFY_SECONDS * 60 then return false end
	return (row.damage or 0) > 0 or (row.taken or 0) > 0
end

-- A match ended. Returns what the player is told: { counted, left, capped?, drop? }.
function Economy.matchFinished(self: any, userId: number, results: any, row: any): any
	local inv = self:inventory(userId)
	if not Economy.qualifies(results, row) then return { counted = false, left = inv.meter } end
	local hour = math.floor(self.time() / 3600)
	if inv.earn.hour ~= hour then inv.earn.hour, inv.earn.count = hour, 0 end
	if inv.earn.count >= Economy.HOURLY_CAP then return { counted = false, capped = true, left = inv.meter } end
	inv.earn.count += 1
	inv.meter = (inv.meter or Loot.nextMeter(self.rand)) - 1
	local out: any = { counted = true }
	if inv.meter <= 0 then
		out.drop = self:_drop(userId, Loot.rollDrop(self.rand))
		inv.meter = Loot.nextMeter(self.rand)
	end
	out.left = inv.meter
	dirty(self, userId)
	return out
end

-- Apply a drop; returns what it was.
function Economy._drop(self: any, userId: number, d: any): any
	local inv = self:inventory(userId)
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
	local uid = self:grant(userId, id, false, "drop")
	if not uid then
		-- the vault could not be reached: the drop is a crate instead, never lost
		inv.crates[d.crate] = math.min(Inventory.MAX_COUNT, inv.crates[d.crate] + 1)
		return { kind = "crate", crate = d.crate }
	end
	return { kind = "item", id = id, rarity = rarity, uid = uid, serial = inv.items[uid].s }
end

-- Open a crate. Forge Crates take a Forge Key, an earned one first (so the item stays tradeable
-- for everyone); an item from a paid key is paid. Returns ok and the result or why not.
function Economy.open(self: any, userId: number, crateId: any): (boolean, any)
	local crate = type(crateId) == "string" and Loot.CRATES[crateId]
	if not crate then return false, "no such crate" end
	local inv = self:inventory(userId)
	if inv.crates[crateId] < 1 then return false, "you have no " .. crate.name end
	local paid = false
	if crate.key then
		local k = inv.keys[crate.key]
		if k.earned < 1 and k.paid < 1 then return false, "you need a Forge Key" end
		paid = k.earned < 1
	end
	local id, rarity, nextPity = Loot.roll(crateId, inv.pity[crateId], self.rand)
	local uid, why = self:grant(userId, id, paid, "crate")
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
function Economy.craft(self: any, userId: number, id: any): (boolean, any)
	local cost = type(id) == "string" and Loot.craftCost(id)
	if not cost then return false, "that cannot be crafted" end
	local inv = self:inventory(userId)
	if inv.sparks < cost then return false, `you need {cost} Sparks` end
	local uid, why = self:grant(userId, id, false, "craft")
	if not uid then return false, why end
	inv.sparks -= cost
	return true, { id = id, uid = uid, serial = inv.items[uid].s, cost = cost }
end

-- Salvage a copy for Sparks: it leaves the game (the Mint counts it destroyed).
function Economy.salvage(self: any, userId: number, uid: any): (boolean, any)
	local inv = self:inventory(userId)
	if type(uid) ~= "string" or not inv.items[uid] then return false, "no such item" end
	local inst = Inventory.remove(inv, uid) :: any
	local item = Cosmetics.get(inst.i)
	local sparks = Loot.dupe((item :: any).rarity)
	inv.sparks = math.min(Inventory.MAX_COUNT, inv.sparks + sparks)
	self.mint:destroy(inst.i)
	dirty(self, userId)
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

-- A request from the client: { action = "open", crate } / { action = "craft", id } / { action =
-- "salvage", uid }. Returns ok and the result or why not; saves on success.
function Economy.apply(self: any, userId: number, msg: any): (boolean, any)
	if type(msg) ~= "table" then return false, "bad request" end
	local ok, res
	if msg.action == "open" then ok, res = self:open(userId, msg.crate)
	elseif msg.action == "craft" then ok, res = self:craft(userId, msg.id)
	elseif msg.action == "salvage" then return self:salvage(userId, msg.uid)
	else return false, "bad request" end
	if ok then dirty(self, userId) end
	return ok, res
end

return Economy
