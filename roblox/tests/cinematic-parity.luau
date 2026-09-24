--!strict
-- UltCinematic.luau gives the same ultimate cutscene as web/src/render2d/ultCinematic.js on every
-- half-frame from -2 to 40: the timing (dim, zoom, banner slide and alpha, invincibility glow),
-- the camera punch, the gold glow shapes and the banner layout on three screen sizes.
--
-- Then the properties the parity cannot vouch for, because both builds could agree on them wrongly:
-- the beat ends inside the freeze, the glow covers exactly the invincible frames, the zoom peaks at
-- ZOOM, and the banner is centred and fully opaque while it holds.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local U = Loader.loadFrom("src/client/", "UltCinematic")
local T = serde.decode("json", fs.readFile("tests/cinematic-fixture.json"))

local checked = 0
local function same(where: string, want: string, have: any)
	local ok = if type(have) == "number" then math.abs((tonumber(want) :: number) - have) <= 1e-9 else want == tostring(have)
	assert(ok, `{where}: JS {want}, Luau {tostring(have)}`)
	checked += 1
end

for _, r in T.rows do
	local e = tonumber(r.e) :: number
	local c = U.at(e)
	for i, v in { c.active, c.dim, c.zoom, c.slide, c.band, c.glow } do
		same(`frame {e} timing {i}`, r.c[i], v)
	end
	same(`frame {e} over`, r.over, U.over(e))
	local p = U.punch(3.5, 11, 5.2, -8.25, 6.5, c.zoom)
	for i, v in { p.x, p.y, p.ppu } do
		same(`frame {e} punch {i}`, r.p[i], v)
	end
	local glow = U.glowShapes(c, -8.25, 4, 5.4)
	assert(#glow == #r.glow, `frame {e}: {#r.glow} glow shapes in JS, {#glow} in Luau`)
	for i, sh in glow do
		for j = 1, 7 do
			same(`frame {e} glow {i}.{j}`, r.glow[i][j], sh[j])
		end
	end
	for s, want in r.banners do
		local screen = T.screens[s]
		local B = U.bannerLayout(c, screen[1], screen[2])
		assert((want == nil) == (B == nil), `frame {e} screen {s}: banner presence differs`)
		if B then
			local got = { B.cx, B.cy, B.w, B.h, B.rot, B.alpha, B.stripe, B.portrait.x, B.portrait.y, B.portrait.size,
				B.weapon.x, B.weapon.y, B.weapon.size, B.text.x, B.text.y, B.text.size }
			for i, v in got do
				same(`frame {e} screen {s} banner {i}`, want[i], v)
			end
		end
	end
end
print(`replayed {checked} cutscene values across {#T.rows} frames`)

-- Properties, asserted directly.
local F, INV = U.FREEZE, U.INVINCIBLE
assert(not U.at(F).active and U.at(F - 1).active, "the cutscene must end exactly when the freeze does")
assert(not U.at(-1).active, "nothing before activation")
-- A client drawing behind its snapshots sees the event before the frame it names. The record must
-- survive those negative frames, or the cutscene is dropped before it starts.
for e = -12, F - 1 do
	assert(not U.over(e), `frame {e}: the cutscene was declared over before it had played`)
end
assert(U.over(F) and U.over(F + 30), "the cutscene is over once the freeze is")
for e = 0, F + 4 do
	assert(U.at(e).glow == (e < INV), `frame {e}: the gold must show exactly while the caster is invincible`)
end
local peak = 0
for e = 0, F - 1 do peak = math.max(peak, U.at(e).zoom) end
assert(math.abs(peak - U.ZOOM) < 1e-9, `zoom peaks at {peak}, not {U.ZOOM}`)
assert(math.abs(U.at(4).dim - U.DIM) < 1e-9, "the scene is fully dimmed by frame 4")
local B = assert(U.bannerLayout(U.at(10), 1280, 720))
assert(B.cx == 640 and B.alpha == 1, "the banner holds centred and opaque")
assert(U.bannerLayout(U.at(0), 1280, 720) == nil, "frame 0 has no banner yet (alpha 0)")
local enter, leave = assert(U.bannerLayout(U.at(1), 1280, 720)), assert(U.bannerLayout(U.at(F - 3), 1280, 720))
assert(enter.cx < 0 and leave.cx > 1280 * 0.5, "the banner enters from the left and leaves to the right")
assert(B.portrait.x < B.weapon.x and B.weapon.x < B.text.x, "caster, then weapon, then name, left to right")
local full = U.punch(0, 0, 5, 10, 4, U.ZOOM)
assert(full.x == 10 and full.y == 4 and full.ppu == 5 * U.ZOOM, "at full zoom the camera is on the caster")
local none = U.punch(0, 0, 5, 10, 4, 1)
assert(none.x == 0 and none.y == 0 and none.ppu == 5, "at zoom 1 the camera is untouched")
print("UltCinematic.luau matches web/src/render2d/ultCinematic.js, and the beat holds its properties.")
