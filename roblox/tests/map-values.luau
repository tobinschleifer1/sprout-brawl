-- The maps' value order (the maps' round 2): everything behind the fight - the far ridge and the
-- landmark - is hazed toward the realm's mid sky and never lighter or more saturated than the island's
-- rock body, so the
-- island is the brightest solid thing in the fight. Round 1's haze went toward the pale horizon and
-- made daylight landmarks lighter: the hall's roof at L 0.57 over rock at 0.11.
local Loader = require("./loader")
local RealmArt = Loader.loadFrom("src/client/", "RealmArt")
local Realms = Loader.load("Realms")

local function fail(msg: string): never error(msg, 0) end
local checked = 0
for _, realm in Realms.LIST do
	local body = RealmArt.lum(realm.rock[3])
	local _, capS = RealmArt.hsv(realm.rock[3])
	local day = RealmArt.daylight(realm)
	for _, which in { "far", "landmark" } do
		-- a landmark may keep a few emissive accents in their own colour (RealmArt.accent: lava, a
		-- forge's glow, gold, the rainbow) - up to 8% of its area; the far ridge none
		local area, off, worst = 0, 0, nil
		for _, r in RealmArt.layer(realm, which).rects do
			local a = r[3] * r[4]
			area += a
			local L = RealmArt.lum(r[5])
			local ratio = if day then (L + 0.05) / (body + 0.05) else (body + 0.05) / (L + 0.05)
			local _, S = RealmArt.hsv(r[5])
			if ratio < 1.5 - 0.03 or S > capS + 0.02 then      -- (1.5 here, not the code's constant: a test that reads it moves with it)
				off += a
				worst = worst or string.format("%s (L %.3f, S %.2f: %.2f:1 %s from the rock's L %.3f, S %.2f)", r[5], L, S, ratio, if day then "lighter" else "darker", body, capS)
			end
			checked += 1
		end
		local allowed = if which == "landmark" then 0.08 else 0
		if area > 0 and off / area > allowed + 1e-9 then
			fail(`{realm.id} {which}: {string.format("%.1f", 100 * off / area)}% of its area breaks the value rule (allowed {allowed * 100}%), e.g. {worst}`)
		end
	end
end
if checked < 100 then fail(`only {checked} background rectangles were checked`) end
print(`PASS map values: {checked} background rectangles across {#Realms.LIST} realms, each 1.5:1 from its island's rock and no more saturated`)
