--!strict
-- What a player owns and wears (Roblox only; docs/briefs/crates-and-monetisation-plan.md, phase 2).
--
-- Two shapes:
--   the INVENTORY, saved in the player's record (AvatarStore): `owned` item ids and `equipped`, one
--     item per slot, and a weapon skin per weapon;
--   the LOADOUT, what a fighter carries into a match and every client draws: only what is equipped,
--     as plain ids ({ skins = { Sword = "sword_frostbite" }, hit = ..., ko = ..., trail = ... }).
-- Both are rebuilt through the catalogue whenever they are read - a record came from a DataStore,
-- a loadout from the network - so an unknown id, a skin on the wrong weapon or an item in the wrong
-- slot is dropped, never drawn. Pure; the server decides ownership (`Inventory.equip`).
local Cosmetics = require(script.Parent.Cosmetics)
local Inventory = {}

-- The slots a loadout carries, by item type. Weapon skins are per weapon (`skins`).
Inventory.SLOTS = {
	hit_effect = "hit", ko_effect = "ko", swing_trail = "trail", step_trail = "steps",
	spawn_effect = "spawn", shield_skin = "shield", title = "title",
} :: { [string]: string }
local TYPE_OF: { [string]: string } = {}
for t, slot in Inventory.SLOTS do TYPE_OF[slot] = t end
Inventory.MAX_OWNED = 2000

export type Loadout = { skins: { [string]: string }, [string]: any }

local function item(id: any, wantType: string?): any
	if type(id) ~= "string" or #id > 64 then return nil end
	local it = Cosmetics.get(id)
	if not it or (wantType and it.type ~= wantType) then return nil end
	return it
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

-- An inventory as it may be stored: owned ids that exist, equipped only from what is owned.
function Inventory.sanitize(raw: any): any
	local src = if type(raw) == "table" then raw else {}
	local owned: { [string]: boolean } = {}
	local n = 0
	if type(src.owned) == "table" then
		for id, v in src.owned do
			if v == true and item(id) and n < Inventory.MAX_OWNED then owned[id] = true; n += 1 end
		end
	end
	local equipped = Inventory.cleanLoadout(src.equipped)
	for weapon, id in equipped.skins do
		if not owned[id] then equipped.skins[weapon] = nil end
	end
	for slot in TYPE_OF do
		if equipped[slot] and not owned[equipped[slot]] then equipped[slot] = nil end
	end
	return { owned = owned, equipped = equipped }
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
