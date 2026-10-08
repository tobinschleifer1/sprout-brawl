--!strict
-- DropShapes.luau draws the same weapon drop as web/src/render2d/dropShapes.js - every shape and
-- the lying weapon's sprite, falling and landed, fresh and thrown, from long-lived to about to go.
-- Then what parity cannot vouch for: the column of light only while it falls, the blink only in
-- its last FADE frames, a thrown weapon's drop shows that weapon and a fresh one the cache.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local DropShapes = Loader.loadFrom("src/client/", "DropShapes")
local T = serde.decode("json", fs.readFile("tests/drop-fixture.json"))

local checked = 0
for n, c in T.cases do
	local d = { x = -3.75, y = 14.25, onGround = c.onGround, life = c.life, look = c.look }
	local got, sprite = DropShapes.shapes(d, c.frame)
	assert(#got == #c.shapes, `case {n}: {#got} shapes, JS {#c.shapes}`)
	for i, sh in got do
		for j, v in sh do
			local want = c.shapes[i][j]
			local ok = if type(v) == "number" then math.abs(v - (tonumber(want) :: number)) < 1e-9 else v == want
			assert(ok, `case {n} shape {i}.{j}: JS {want}, Luau {tostring(v)}`)
			checked += 1
		end
	end
	assert((sprite == nil) == (c.sprite == nil), `case {n}: sprite {sprite ~= nil}, JS {c.sprite ~= nil}`)
	if sprite then
		assert(sprite.id == c.sprite.id and math.abs(sprite.x - tonumber(c.sprite.x)) < 1e-9
			and math.abs(sprite.y - tonumber(c.sprite.y)) < 1e-9 and math.abs(sprite.angle - tonumber(c.sprite.angle)) < 1e-9
			and math.abs(sprite.alpha - tonumber(c.sprite.alpha)) < 1e-9,
			`case {n}: the lying weapon differs`)
		checked += 5
	end
end
print(`drops: {checked} values across {#T.cases} cases match the web`)

-- Properties.
local function tall(list: { any }): number
	local n = 0
	for _, sh in list do if sh[1] == "r" and sh[5] == DropShapes.BEAM then n += 1 end end
	return n
end
local falling = DropShapes.shapes({ x = 0, y = 10, onGround = false, life = 840 }, 3)
local landed = DropShapes.shapes({ x = 0, y = 0, onGround = true, life = 840 }, 3)
assert(tall(falling) > 0 and tall(landed) == 0, "the column of light shows while it falls, and not once it lands")
local function alphaAt(life: number, frame: number): number
	local s = DropShapes.shapes({ x = 0, y = 0, onGround = true, life = life }, frame)
	return s[2][7]                     -- the cache body
end
assert(alphaAt(500, 0) == alphaAt(500, 8), "a long-lived drop does not blink")
assert(alphaAt(DropShapes.FADE - 1, 0) ~= alphaAt(DropShapes.FADE - 1, 8), "a drop about to go blinks")
local _, sprite = DropShapes.shapes({ x = 0, y = 0, onGround = true, life = 500, look = "Hammer" }, 0)
local cache, none = DropShapes.shapes({ x = 0, y = 0, onGround = true, life = 500 }, 0)
assert(sprite and sprite.id == "Hammer", "a thrown hammer lies there as a hammer")
assert(none == nil and #cache >= 6, "a fresh drop is the cache")
print("drop properties: the beam while falling, the blink before it goes, the thrown weapon shown, the cache for a fresh one")
