--!strict
-- Shield.luau draws the same energy shell as web/src/render2d/shield.js - every shape, at six
-- strengths, six frames and three impact states - and its integer hash agrees to the bit. Then
-- what parity cannot vouch for: the rim loses segments as the shield weakens, the shell flickers
-- only when low, a fresh hit flares white where it landed and not opposite, and an empty shield
-- draws nothing.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Shield = Loader.loadFrom("src/client/", "Shield")
local T = serde.decode("json", fs.readFile("tests/shield-fixture.json"))

local checked = 0
for _, h in T.hashes do
	assert(math.abs(Shield.hash(h[1], h[2]) - (tonumber(h[3]) :: number)) < 1e-15, `hash({h[1]}, {h[2]})`)
	checked += 1
end
for n, c in T.cases do
	local hit = if c.hit then { k = tonumber(c.hit.k), x = tonumber(c.hit.x), y = tonumber(c.hit.y) } else nil
	local got = Shield.shapes(2.25, 4.5, 5.2, tonumber(c.hp) :: number, c.frame, hit)
	assert(#got == #c.shapes, `case {n} (hp {c.hp}, frame {c.frame}): {#got} shapes, JS {#c.shapes}`)
	for i, sh in got do
		for j, v in sh do
			local want = c.shapes[i][j]
			local ok = if type(v) == "number" then math.abs(v - (tonumber(want) :: number)) < 1e-9 else v == want
			assert(ok, `case {n} shape {i}.{j}: JS {want}, Luau {tostring(v)}`)
			checked += 1
		end
	end
end
print(`shield: {checked} values across {#T.cases} cases match the web`)

-- Properties.
local function rim(list: { any }): number
	local n = 0
	for _, sh in list do if sh[1] == "l" and sh[6] == 0.6 then n += 1 end end
	return n
end
local full, weak = 0, 0
for frame = 0, 600, 6 do
	full += rim(Shield.shapes(0, 0, 5, 1, frame, nil))
	weak += rim(Shield.shapes(0, 0, 5, 0.1, frame, nil))
end
assert(full == Shield.RIM * 101, "a full shield has an unbroken rim")
assert(weak < full * 0.7, `a weak shield breaks up: {weak} rim segments against {full}`)
local function fillAlpha(hp: number, frame: number): number
	return Shield.shapes(0, 0, 5, hp, frame, nil)[1][7]
end
assert(fillAlpha(0.5, 0) == fillAlpha(0.5, 3), "a healthy shield holds steady")
assert(fillAlpha(0.2, 0) ~= fillAlpha(0.2, 3), "a low shield flickers")
-- a hit on the right flares the right side of the rim white, and not the left
local hit = Shield.shapes(0, 0, 5, 1, 0, { k = 1, x = 10, y = 0 })
local right, left = 0, 0
for _, sh in hit do
	if sh[1] == "l" and sh[7] == "#FFFFFF" then
		if (sh[2] + sh[4]) / 2 > 0 then right += 1 else left += 1 end
	end
end
assert(right > 0 and left == 0, `the flare is where the hit landed (right {right}, left {left})`)
assert(#Shield.shapes(0, 0, 5, 0, 0, nil) == 0, "an empty shield draws nothing")
print("shield: the rim breaks up as it weakens, flickers when low, flares where struck")
