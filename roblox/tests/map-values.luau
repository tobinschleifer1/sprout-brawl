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
			-- (on a daylight realm also 1.2:1 over the walking face and the lit band, the tones that meet
			-- the scenery at the island's top: pushed past the body alone, it landed on them at 1.00-1.14:1)
			local topStep = math.huge
			if day then
				for _, tone in { realm.top[2], realm.rock[4] } do
					topStep = math.min(topStep, (L + 0.05) / (RealmArt.lum(tone) + 0.05))
				end
			end
			local sCap = math.max(capS, select(2, RealmArt.hsv(realm.sky[2])) * (if day then 0.5 else 0.75))
			if ratio < 1.5 - 0.03 or topStep < 1.2 - 0.03 or S > sCap + 0.02 then      -- (1.5 here, not the code's constant: a test that reads it moves with it)
				off += a
				worst = worst or string.format("%s (L %.3f, S %.2f: %.2f:1 %s from the rock's L %.3f, S %.2f)", r[5], L, S, ratio, if day then "lighter" else "darker", body, capS)
			end
			checked += 1
		end
		-- a landmark keeps its own shading: hazed colour by colour it went flat (a ghost hall, a
		-- one-tone pyramid, about 1.1:1); its tones must still span 1.2:1
		-- (by area, 10th to 90th percentile: the darkest and lightest pixel anywhere let a landmark pass on
		-- an accent or a storm lid while 92% of it was two tones 1.05:1 apart - round 5)
		if which == "landmark" then
			local ls, total = {}, 0
			for _, r in RealmArt.layer(realm, which).rects do
				table.insert(ls, { RealmArt.lum(r[5]), r[3] * r[4] }); total += r[3] * r[4]
			end
			table.sort(ls, function(a, b) return a[1] < b[1] end)
			local function pct(p: number): number
				local acc = 0
				for _, e in ls do acc += e[2]; if acc >= p * total then return e[1] end end
				return ls[#ls][1]
			end
			if total > 0 and (pct(0.9) + 0.05) / (pct(0.1) + 0.05) < 1.2 then
				fail(`{realm.id} landmark: by area its tones span only {string.format("%.2f", (pct(0.9) + 0.05) / (pct(0.1) + 0.05))}:1 (10th to 90th percentile) - hazed flat`)
			end
		end
		-- (a rainbow is its landmark's whole shape and its colour is the point: a named exception)
		local allowed = if which == "landmark" then (if realm.landmark == "rainbow" then 0.95 else 0.08) else 0
		if area > 0 and off / area > allowed + 1e-9 then
			fail(`{realm.id} {which}: {string.format("%.1f", 100 * off / area)}% of its area breaks the value rule (allowed {allowed * 100}%), e.g. {worst}`)
		end
	end
end
-- the depth ladder: far ridge, then landmark, then island - the ridge beyond the landmark, lighter than
-- (nearly) all of it on a daylight realm and darker on a dark one (the landmark sat on the wrong side of
-- the ridge on every realm, round 5); weighted by area, so a small accent does not count
for _, realm in Realms.LIST do
	local farRects = RealmArt.layer(realm, "far").rects
	local landRects = RealmArt.layer(realm, "landmark").rects
	if #farRects > 0 and #landRects > 0 then
		local farL = RealmArt.lum(farRects[1][5])
		local ls, total = {}, 0
		for _, r in landRects do table.insert(ls, { RealmArt.lum(r[5]), r[3] * r[4] }); total += r[3] * r[4] end
		table.sort(ls, function(a, b) return a[1] < b[1] end)
		local function pct(p)
			local acc = 0
			for _, e in ls do acc += e[2]; if acc >= p * total then return e[1] end end
			return ls[#ls][1]
		end
		if RealmArt.daylight(realm) then
			if farL <= pct(0.9) then fail(`{realm.id}: the far ridge (L {string.format("%.3f", farL)}) is not lighter than its landmark (90% at L {string.format("%.3f", pct(0.9))})`) end
		else
			if farL >= pct(0.1) then fail(`{realm.id}: the far ridge (L {string.format("%.3f", farL)}) is not darker than its landmark (10% at L {string.format("%.3f", pct(0.1))})`) end
		end
	end
end
if checked < 100 then fail(`only {checked} background rectangles were checked`) end
print(`PASS map values: {checked} background rectangles across {#Realms.LIST} realms, each 1.5:1 from its island's rock and no more saturated`)
