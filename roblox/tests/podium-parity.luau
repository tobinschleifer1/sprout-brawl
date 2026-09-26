--!strict
-- Podium.luau lays out the results podium exactly as web/src/render2d/podium.js does, for 1 to 8
-- fighters on four screen sizes, and agrees on places, stat values and ordinals. Then the
-- properties a parity test cannot vouch for: finishing order left to right, each place standing no
-- higher than the one before, and nothing drawn outside the screen.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local P = Loader.loadFrom("src/client/", "Podium")
local T = serde.decode("json", fs.readFile("tests/podium-fixture.json"))

local checked = 0
for _, L in T.layouts do
	local slots = P.layout(L.n, L.W, L.H)
	assert(#slots == #L.slots, `{L.n}@{L.W}x{L.H}: {#slots} slots, JS has {#L.slots}`)
	for i, want in L.slots do
		local s = slots[i]
		local got = { s.cx, s.top, s.colW, s.figureH, s.pillar.x, s.pillar.y, s.pillar.w, s.pillar.h,
			s.cap.x, s.cap.y, s.cap.w, s.cap.h, s.card.x, s.card.y, s.card.w, s.card.h, s.rowH }
		for j, v in got do
			assert(math.abs(v - (tonumber(want[j]) :: number)) < 1e-9, `{L.n}@{L.W}x{L.H} slot {i} field {j}: JS {want[j]}, Luau {v}`)
			checked += 1
		end
		-- properties
		if i > 1 then
			assert(s.cx > slots[i - 1].cx, "places run left to right")
			assert(s.top >= slots[i - 1].top, "no place stands above the one that beat it")
		end
		assert(s.pillar.x >= 0 and s.pillar.x + s.pillar.w <= L.W + 1e-9, "pillar inside the screen")
		assert(s.card.x >= 0 and s.card.x + s.card.w <= L.W + 1e-9, "card inside the screen")
		assert(s.card.y + s.card.h <= L.H + 1e-9, "card above the bottom edge")
		assert(s.top - s.figureH >= 0, "the fighter's head is on screen")
	end
end

local function same(a: { any }, b: { any }, what: string)
	assert(#a == #b, what)
	for i = 1, #a do assert(a[i] == b[i], `{what} [{i}]: JS {b[i]}, Luau {a[i]}`) end
end
same(P.places({ { team = 1 }, { team = 1 }, { team = 0 }, { team = 0 } }, true), T.places.teams, "team places")
same(P.places({ { team = 0 }, { team = 1 }, { team = 2 }, { team = 3 } }, false), T.places.ffa, "ffa places")
same(P.places({ { team = 0 }, { team = 1 }, { team = 2 }, { team = 3 } }, true), T.places.ffaTeamsFlag, "ffa places with teams on")
assert(T.places.teams[2] == 1 and T.places.teams[3] == 2, "a winning team shares first place")
local row = { score = 3, kos = 4, falls = 1, sds = 0, damage = 184.5, taken = 91.49 }
for i, want in T.stats do
	assert(P.STATS[i][1] == want[1] and P.STATS[i][2] == want[2], `stat {i} label/field`)
	assert(tostring(P.statValue(row, want[2])) == want[3], `stat {want[1]}: JS {want[3]}, Luau {P.statValue(row, want[2])}`)
end
for _, c in T.titles do
	assert(P.title(c.rows, c.teams) == c.want, `title {c.k}: JS {c.want}, Luau {P.title(c.rows, c.teams)}`)
end
assert(T.titles[1].want == "Ana wins", "a 1v1 run as teams names the winner, not a team")
assert(T.titles[2].want == "Green team wins", "a real team win names the team")
for _, o in T.ordinals do
	assert(P.ordinal(o[1]) == o[2], `ordinal {o[1]}: JS {o[2]}, Luau {P.ordinal(o[1])}`)
end
print(`podium: {checked} layout values across {#T.layouts} layouts, places, stats and ordinals match the web`)
