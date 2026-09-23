--!strict
-- Roblox draws each weapon as exactly the rectangles web/src/data/weaponArt.js compiled for it.
--
-- data-parity already proves Data/Art.luau holds the same numbers as the JavaScript. This proves
-- the renderer DRAWS them: every rectangle, in order, with its geometry and alpha untouched, and
-- nothing else - so the web's weapon and Roblox's weapon are the same picture, not two drawings
-- that happen to be generated from one file.
local Loader = require("./loader")
local Weapons = Loader.load("Data/Weapons")
local Art = Loader.load("Data/Art")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")

local FRAME_BUDGET = 80
local drawn: { any } = {}
Canvas.rect = function(_c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	table.insert(drawn, { x, y, w, h, colour, alpha })
end
local function canvas(): any
	return { m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }
end
local POSE = { angle = 0, ox = 0, oy = 0, scale = 1, charge = 0, hide = false }

local checked, total = 0, 0
for _, w in Weapons.LIST do
	local rects = Art.sprites[w.id]
	assert(rects, `{w.id} has no art`)
	assert(#rects <= FRAME_BUDGET, `{w.id} costs {#rects} Frames, over the budget of {FRAME_BUDGET}`)
	table.clear(drawn)
	local c = canvas()
	Weapons2D.draw(c, w.id, w.palette, POSE)
	assert(#c.stack == 0, `{w.id}: transform stack left unbalanced`)
	assert(#drawn == #rects, `{w.id}: drew {#drawn} rectangles, the art has {#rects}`)
	for i, r in rects do
		local d = drawn[i]
		for k = 1, 4 do
			assert(d[k] == r[k], `{w.id} rectangle {i} field {k}: drew {d[k]}, art says {r[k]}`)
		end
		local want = tonumber(string.sub(r[5], 2), 16) :: number
		local got = d[5]
		assert(got and got.R, `{w.id} rectangle {i}: no colour`)
		local packed = math.round(got.R * 255) * 65536 + math.round(got.G * 255) * 256 + math.round(got.B * 255)
		assert(packed == want, `{w.id} rectangle {i}: drew colour {string.format("#%06X", packed)}, art says {r[5]}`)
		assert(d[6] == r[6], `{w.id} rectangle {i}: alpha {d[6]}, art says {r[6]}`)
		checked += 1
	end
	total += #rects
end

-- A hidden weapon and an unknown one draw nothing at all.
table.clear(drawn)
Weapons2D.draw(canvas(), "Axe", {}, { angle = 0, ox = 0, oy = 0, scale = 1, charge = 0, hide = true })
Weapons2D.draw(canvas(), "NoSuchWeapon", {}, POSE)
assert(#drawn == 0, "a hidden or unknown weapon must draw nothing")

print(`checked {checked} weapon rectangles across {#Weapons.LIST} weapons ({total // #Weapons.LIST} a weapon, budget {FRAME_BUDGET})`)
print("Weapons2D draws exactly the art web/src/data/weaponArt.js compiled.")
