--!strict
-- What a player owns and wears (Roblox only; docs/briefs/crates-and-monetisation-plan.md).
--
-- Two shapes:
--   the INVENTORY, saved in the player's record (AvatarStore):
--     items     every owned copy as an INSTANCE, by uid: { i = item id, s = serial, p = paid for with
--               Robux (trading obeys IsPaidItemTradingAllowed), t = when obtained (os.time), src =
--               how: "drop", "crate", "craft", "shop", "grant" }
--     owned     an index rebuilt from `items` on every read (not trusted from storage): id -> true
--     equipped  one item per slot, and a weapon skin per weapon
--     sparks, crates { scrap, forge }, keys { forge = { earned, paid } }, pity { scrap, forge }
--               (openings since the last guaranteed-tier item), meter (qualifying matches until the
--               next drop), earn { hour, count } (qualifying matches counted this hour), seq (the
--               next uid)
--   the LOADOUT, what a fighter carries into a match: only what is equipped, as plain ids.
-- Both are rebuilt through the catalogue whenever they are read - a record came from a DataStore,
-- a loadout from the network - so anything unknown, unowned or misplaced is dropped. Pure.
local Cosmetics = require(script.Parent.Cosmetics)
local Inventory = {}

Inventory.VERSION = 2
-- The slots a loadout carries, by item type. Weapon skins are per weapon (`skins`).
Inventory.SLOTS = {
	hit_effect = "hit", ko_effect = "ko", swing_trail = "trail", step_trail = "steps",
	spawn_effect = "spawn", shield_skin = "shield", title = "title",
} :: { [string]: string }
local TYPE_OF: { [string]: string } = {}
for t, slot in Inventory.SLOTS do TYPE_OF[slot] = t end
Inventory.MAX_OWNED = 2000
Inventory.MAX_COUNT = 1000000          -- any balance (Sparks, crates, keys) is clamped to this
Inventory.CRATES = { "scrap", "forge" }
Inventory.SOURCES = { drop = true, crate = true, craft = true, shop = true, grant = true, migrated = true }

export type Loadout = { skins: { [string]: string }, [string]: any }
export type Instance = { i: string, s: number, p: boolean, t: number, src: string }

local function item(id: any, wantType: string?): any
	if type(id) ~= "string" or #id > 64 then return nil end
	local it = Cosmetics.get(id)
	if not it or (wantType and it.type ~= wantType) then return nil end
	return it
end
local function count(v: any): number
	if type(v) ~= "number" or v ~= v then return 0 end
	return math.clamp(math.floor(v), 0, Inventory.MAX_COUNT)
end

-- A loadout as it may arrive: every entry checked against the catalogue and its slot.
function Inventory.cleanLoadout(raw: any): Loadout
	local src = if type(raw) == "table" then raw else {}
	local out: Loadout = { skins = {} }
	if type(src.skins) == "table" then
		for weapon, id in src.skins do
			local it = item(id, "weapon_skin")
			if it and it.weapon == weapon then out.skins[weapon] = id end
		end
	end
	for slot, t in TYPE_OF do
		if item(src[slot], t) then out[slot] = src[slot] end
	end
	return out
end

local function reindex(inv: any)
	local owned: { [string]: boolean } = {}
	for _, inst in inv.items do owned[inst.i] = true end
	inv.owned = owned
end

-- An inventory as it may be stored. A version 1 record (an `owned` set, before instances) becomes
-- one instance per owned id, serial 0 (minted before serials existed), never paid for.
function Inventory.sanitize(raw: any): any
	local src = if type(raw) == "table" then raw else {}
	local items: { [string]: Instance } = {}
	local n = 0
	local seq = count(src.seq)
	if type(src.items) == "table" then
		for uid, inst in src.items do
			if n >= Inventory.MAX_OWNED then break end
			if type(uid) == "string" and #uid <= 16 and type(inst) == "table" and item(inst.i) then
				items[uid] = { i = inst.i, s = count(inst.s), p = inst.p == true, t = count(inst.t),
					src = if type(inst.src) == "string" and Inventory.SOURCES[inst.src] then inst.src else "grant" }
				n += 1
				local num = tonumber(string.match(uid, "^u(%d+)$"))
				if num and num >= seq then seq = num + 1 end
			end
		end
	elseif type(src.owned) == "table" then
		for id, v in src.owned do
			if v == true and item(id) and n < Inventory.MAX_OWNED then
				items["u" .. seq] = { i = id, s = 0, p = false, t = 0, src = "migrated" }
				seq += 1; n += 1
			end
		end
	end
	local function pair(t: any, keys: { string }): { [string]: number }
		local out = {}
		local from = if type(t) == "table" then t else {}
		for _, k in keys do out[k] = count(from[k]) end
		return out
	end
	local keySrc = if type(src.keys) == "table" and type(src.keys.forge) == "table" then src.keys.forge else {}
	local inv: any = {
		v = Inventory.VERSION, items = items, seq = seq, owned = {},
		sparks = count(src.sparks),
		crates = pair(src.crates, Inventory.CRATES),
		keys = { forge = { earned = count(keySrc.earned), paid = count(keySrc.paid) } },
		pity = pair(src.pity, Inventory.CRATES),
		meter = if type(src.meter) == "number" and src.meter >= 1 and src.meter <= 5 then math.floor(src.meter) else nil,
		earn = { hour = count(type(src.earn) == "table" and src.earn.hour), count = count(type(src.earn) == "table" and src.earn.count) },
	}
	reindex(inv)
	local equipped = Inventory.cleanLoadout(src.equipped)
	for weapon, id in equipped.skins do
		if not inv.owned[id] then equipped.skins[weapon] = nil end
	end
	for slot in TYPE_OF do
		if equipped[slot] and not inv.owned[equipped[slot]] then equipped[slot] = nil end
	end
	inv.equipped = equipped
	return inv
end

function Inventory.owns(inv: any, id: string): boolean
	return inv.owned[id] == true
end

-- How many copies of `id` the player has.
function Inventory.copies(inv: any, id: string): number
	local n = 0
	for _, inst in inv.items do if inst.i == id then n += 1 end end
	return n
end

-- Add an owned copy; returns its uid, or nil when the inventory is full.
function Inventory.add(inv: any, id: string, serial: number, paid: boolean, src: string, now: number): string?
	if not item(id) then return nil end
	local n = 0
	for _ in inv.items do n += 1 end
	if n >= Inventory.MAX_OWNED then return nil end
	local uid = "u" .. inv.seq
	inv.seq += 1
	inv.items[uid] = { i = id, s = serial, p = paid, t = now, src = src }
	inv.owned[id] = true
	return uid
end

-- Remove a copy; if it was the last one and it was worn, it comes off. Returns the instance.
function Inventory.remove(inv: any, uid: string): Instance?
	local inst = inv.items[uid]
	if not inst then return nil end
	inv.items[uid] = nil
	reindex(inv)
	if not inv.owned[inst.i] then
		for weapon, id in inv.equipped.skins do if id == inst.i then inv.equipped.skins[weapon] = nil end end
		for slot in TYPE_OF do if inv.equipped[slot] == inst.i then inv.equipped[slot] = nil end end
	end
	return inst
end

-- Wear an owned item (or take a slot off: `id` nil with `slot`/`weapon`). `owns(id)` says whether
-- the player owns it (the server's call: in Studio, everything). Returns ok and why not.
function Inventory.equip(inv: any, id: string?, owns: (string) -> boolean, slot: string?, weapon: string?): (boolean, string?)
	if id == nil then
		if weapon and type(weapon) == "string" then inv.equipped.skins[weapon] = nil; return true end
		if slot and TYPE_OF[slot] then inv.equipped[slot] = nil; return true end
		return false, "nothing to take off"
	end
	local it = item(id)
	if not it then return false, "no such item" end
	if not owns(id) then return false, "not owned" end
	if it.type == "weapon_skin" then
		inv.equipped.skins[it.weapon :: string] = id
		return true
	end
	local s = Inventory.SLOTS[it.type]
	if not s then return false, "cannot be worn" end
	inv.equipped[s] = id
	return true
end

-- What a fighter carries into a match: a copy of what is equipped.
function Inventory.loadout(inv: any): Loadout
	return Inventory.cleanLoadout(inv and inv.equipped)
end

return Inventory
