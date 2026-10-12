--!strict
-- The four bars on a fighter's pedestal in the select screen - Damage, Defense, Dexterity, Speed -
-- out of 10, read off the weapon data rather than typed in, so they cannot disagree with how the
-- weapon actually plays:
--   Damage     the average damage of its lights and signatures
--   Defense    its weight (heavier is harder to launch)
--   Dexterity  how fast its lights start (fewer startup frames is higher)
--   Speed      its run speed
-- Each is scaled across the roster to 3..9, so the bars compare weapons with each other and no
-- weapon is empty or maxed on anything. Pure; tests/select-screen.luau checks it.
local Shared = game:GetService("ReplicatedStorage").Shared
local Weapons = require(Shared.Weapons)
local Loadout = require(Shared.Loadout)

local WeaponStats = {}
WeaponStats.KEYS = { "damage", "defense", "dexterity", "speed" }
WeaponStats.LOW, WeaponStats.HIGH = 3, 9

local LIGHTS = { "LightNeutral1", "LightNeutral2", "LightNeutral3", "LightSide1", "LightSide2", "LightUp", "LightDown" }
local HITS = { "LightNeutral1", "LightNeutral2", "LightNeutral3", "LightSide1", "LightSide2", "LightUp", "LightDown",
	"SigSide", "SigDown", "SigNeutral" }

local function mean(moves: any, ids: { string }, field: string): number
	local sum, n = 0, 0
	for _, id in ids do
		local m = moves[id]
		if m and m[field] then sum += m[field]; n += 1 end
	end
	return if n > 0 then sum / n else 0
end

-- The raw measures for one weapon (on the Classic body, so only the weapon differs).
function WeaponStats.raw(weaponId: string): any
	local c = Loadout.build("Classic", weaponId)
	return {
		damage = mean(c.moves, HITS, "damage"),
		defense = c.weight,
		dexterity = -mean(c.moves, LIGHTS, "startup"),     -- negative: fewer frames scores higher
		speed = c.runSpeed,
	}
end

local cache: { [string]: any }? = nil
-- Every weapon's bars, { [weaponId] = { damage, defense, dexterity, speed } }, computed once.
function WeaponStats.all(): { [string]: any }
	if cache then return cache end
	local raw, lo, hi = {}, {}, {}
	for _, w in Weapons.LIST do
		local r = WeaponStats.raw(w.id)
		raw[w.id] = r
		for _, k in WeaponStats.KEYS do
			lo[k] = math.min(lo[k] or math.huge, r[k])
			hi[k] = math.max(hi[k] or -math.huge, r[k])
		end
	end
	local out = {}
	for id, r in raw do
		local bars = {}
		for _, k in WeaponStats.KEYS do
			local span = hi[k] - lo[k]
			local t = if span > 0 then (r[k] - lo[k]) / span else 0.5
			bars[k] = math.floor(WeaponStats.LOW + (WeaponStats.HIGH - WeaponStats.LOW) * t + 0.5)
		end
		out[id] = bars
	end
	cache = out
	return out
end

function WeaponStats.of(weaponId: string): any
	return WeaponStats.all()[weaponId]
end

return WeaponStats
