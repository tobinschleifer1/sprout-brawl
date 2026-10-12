--!strict
-- Every weapon in the Roblox build: the generated roster (Data/Weapons.luau, from the web) followed
-- by the Roblox-only ones (RobloxWeapons.luau). The game reads weapons from here; tests that hold
-- the generated data to the web read Data/Weapons directly, which this never changes - it copies.
local Generated = require(script.Parent.Data.Weapons)
local RobloxWeapons = require(script.Parent.RobloxWeapons)
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

-- The art, merged the same way (Weapons2D draws from this).
local function merged(a: { [string]: any }, b: { [string]: any }): { [string]: any }
	local out = table.clone(a)
	for k, v in b do out[k] = v end
	return out
end
local ART = { sprites = merged(GeneratedArt.sprites, RobloxArt.sprites), awakened = merged(GeneratedArt.awakened, RobloxArt.awakened) }

return { LIST = LIST, BY_ID = BY_ID, DEFAULT_ID = Generated.DEFAULT_ID, FISTS = Generated.FISTS, ROBLOX_ONLY = ROBLOX_ONLY, ART = ART }
