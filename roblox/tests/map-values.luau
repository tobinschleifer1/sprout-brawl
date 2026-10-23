-- The maps' value order (the maps' round 2): everything behind the fight - the far ridge and the
-- landmark - is hazed to the realm's mid sky and never lighter than the island's lit rock, so the
-- island is the brightest solid thing in the fight. Round 1's haze went toward the pale horizon and
-- made daylight landmarks lighter: the hall's roof at L 0.57 over rock at 0.11.
local Loader = require("./loader")
local RealmArt = Loader.loadFrom("src/client/", "RealmArt")
local Realms = Loader.load("Realms")

local function fail(msg: string): never error(msg, 0) end
local checked = 0
for _, realm in Realms.LIST do
	local cap = RealmArt.lum(realm.rock[4])
	for _, which in { "far", "landmark" } do
		for _, r in RealmArt.layer(realm, which).rects do
			local L = RealmArt.lum(r[5])
			if L > cap + 0.005 then
				fail(`{realm.id} {which}: {r[5]} (L {string.format("%.3f", L)}) is lighter than the island's lit rock (L {string.format("%.3f", cap)})`)
			end
			checked += 1
		end
	end
end
if checked < 100 then fail(`only {checked} background rectangles were checked`) end
print(`PASS map values: {checked} background rectangles across {#Realms.LIST} realms, none lighter than their island's lit rock`)
