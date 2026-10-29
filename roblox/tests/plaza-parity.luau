--!strict
-- Plaza.luau against web/src/engine/plaza.js: every frame of twelve walks through the market and
-- the three lounges - position, speed, hop, facing, state, the station on offer and the district -
-- with warps and scene changes mid-walk. Exact: the arithmetic is the same operations in the same
-- order, so the doubles match to the bit.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Plaza = Loader.load("Plaza")
local T = serde.decode("json", fs.readFile("tests/plaza-fixture.json"))
local DATA = Plaza.WEB          -- (the web's market: the Roblox lobby's has no arcade or gates)
local byId: { [string]: any } = { [DATA.market.id] = DATA.market }
for _, r in DATA.rooms do byId[r.id] = r end

local checked = 0
for n, case in T.cases do
	local scene = assert(case.inline or byId[case.scene], case.scene)
	local w = Plaza.new(scene)
	if case.at then w:setScene(scene, case.at) end
	for i, f in case.frames do
		if string.sub(f.event, 1, 5) == "warp:" then assert(w:warp(string.sub(f.event, 6)), "warp failed") end
		if f.event == "scene" then w:setScene(scene) end
		w:step(f.input)
		for k, field in T.fields do
			local want, got = f.values[k], w.p[field]
			local ok = if type(got) == "number" then got == tonumber(want) else got == want
			assert(ok, `walk {n} ({case.scene}) frame {i}: {field} JS {want}, Luau {tostring(got)}`)
			checked += 1
		end
		local near, d = w:nearest(), w:district()
		assert((if near then near.id else "") == f.near, `walk {n} frame {i}: station {f.near} vs {near and near.id}`)
		assert((if d then d.id else "") == f.district, `walk {n} frame {i}: district`)
		checked += 2
	end
end
print(`plaza: {checked} values across {#T.cases} walks (and edge and tie scripts) match web/src/engine/plaza.js exactly`)
