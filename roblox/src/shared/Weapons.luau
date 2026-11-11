--!strict
-- Every weapon in the Roblox build: the generated roster (Data/Weapons.luau, from the web) followed
-- by the Roblox-only ones (RobloxWeapons.luau), each with the Roblox-only tuning applied
-- (WeaponTuning.luau). The game reads weapons from here; tests that hold the generated data to the
-- web read Data/Weapons directly, which this never changes - it copies. The roster before tuning is
-- kept too (UNTUNED_LIST, UNTUNED_BY_ID): the replays build their fighters from it.
local Generated = require(script.Parent.Data.Weapons)
local RobloxWeapons = require(script.Parent.RobloxWeapons)
local WeaponTuning = require(script.Parent.WeaponTuning)
local GeneratedArt = require(script.Parent.Data.Art)
local RobloxArt = require(script.Parent.RobloxArt)

local LIST = table.clone(Generated.LIST)
local BY_ID = table.clone(Generated.BY_ID)
local ROBLOX_ONLY: { [string]: boolean } = {}
for _, w in RobloxWeapons.LIST do
	table.insert(LIST, w)
	BY_ID[w.id] = w
	ROBLOX_ONLY[w.id] = true
end
local UNTUNED_LIST, UNTUNED_BY_ID = table.clone(LIST), table.clone(BY_ID)
for i, w in LIST do
	local patch = WeaponTuning.FOR[w.id]
	if patch then
		local tuned = WeaponTuning.apply(w, patch)
		LIST[i], BY_ID[w.id] = tuned, tuned
	end
end
for id in WeaponTuning.FOR do
	if not UNTUNED_BY_ID[id] then error(`weapon tuning: no weapon {id}`) end
end

-- The art, merged the same way (Weapons2D draws from this).
local function merged(a: { [string]: any }, b: { [string]: any }): { [string]: any }
	local out = table.clone(a)
	for k, v in b do out[k] = v end
	return out
end
local ART = { sprites = merged(GeneratedArt.sprites, RobloxArt.sprites), awakened = merged(GeneratedArt.awakened, RobloxArt.awakened),
	-- one of a pair, for weapons held one in each hand (client DualWield); keyed by weapon id
	single = RobloxArt.single, singleAwakened = RobloxArt.singleAwakened }

return { LIST = LIST, BY_ID = BY_ID, DEFAULT_ID = Generated.DEFAULT_ID, FISTS = Generated.FISTS, ROBLOX_ONLY = ROBLOX_ONLY, ART = ART,
	UNTUNED_LIST = UNTUNED_LIST, UNTUNED_BY_ID = UNTUNED_BY_ID }
