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
local sprites = 0
Canvas.rect = function(_c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	table.insert(drawn, { x, y, w, h, colour, alpha })
end
-- The weapon is drawn as one sprite (one Frame moved per frame): expanded back into the rectangles
-- it holds, in the weapon's own frame, it must be exactly the art - same order, geometry, colour and
-- alpha - so the check below is the same check it was when every rectangle was a separate Frame.
Canvas.sprite = function(_c: any, _key: string, rects: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number, alpha: number?)
	sprites += 1
	for _, r in rects do
		assert(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= cols and r[2] + r[4] <= rows, "a cell lies outside the sprite")
	end
	Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, h, hex, a)
		table.insert(drawn, { x, y, w, h, Canvas.hex(hex, nil :: any), a * (alpha or 1) })
	end)
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
	sprites = 0
	local c = canvas()
	Weapons2D.draw(c, w.id, w.palette, POSE)
	assert(#c.stack == 0, `{w.id}: transform stack left unbalanced`)
	assert(sprites == 1, `{w.id}: drawn as {sprites} sprites, not one`)
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

-- Framing a weapon in a UI tile (the room panel's catalogue): the whole weapon fits, it is centred,
-- and the scale is a whole multiple of 8 px/stud so every art pixel is a whole number of screen pixels.
local framed = 0
for _, w in Weapons.LIST do
	local b = assert(Weapons2D.bounds(w.id))
	-- The bounds contain every rectangle, and are tight: each edge is touched by some rectangle.
	local touch = { false, false, false, false }
	for _, r in Art.sprites[w.id] do
		assert(r[1] >= b[1] - 1e-9 and r[2] >= b[2] - 1e-9 and r[1] + r[3] <= b[3] + 1e-9 and r[2] + r[4] <= b[4] + 1e-9,
			`{w.id}: a rectangle lies outside its bounds`)
		touch[1] = touch[1] or math.abs(r[1] - b[1]) < 1e-9
		touch[2] = touch[2] or math.abs(r[2] - b[2]) < 1e-9
		touch[3] = touch[3] or math.abs(r[1] + r[3] - b[3]) < 1e-9
		touch[4] = touch[4] or math.abs(r[2] + r[4] - b[4]) < 1e-9
	end
	assert(touch[1] and touch[2] and touch[3] and touch[4], `{w.id}: bounds are not tight`)
	for _, size in { { 150, 76 }, { 200, 76 }, { 217, 76 }, { 120, 60 }, { 300, 100 } } do
		local tw, th = size[1], size[2]
		local cx, cy, ppu = Weapons2D.fit(w.id, tw, th)
		assert(ppu % 8 == 0 and ppu >= 8, `{w.id}: scale {ppu} is not a multiple of 8 px/stud`)
		assert(math.abs(cx - (b[1] + b[3]) / 2) < 1e-9 and math.abs(cy - (b[2] + b[4]) / 2) < 1e-9, `{w.id}: not centred`)
		local raw = math.min((tw - 8) / (b[3] - b[1]), (th - 8) / (b[4] - b[2]))
		if raw >= 8 then
			assert((b[3] - b[1]) * ppu <= tw - 8 + 1e-6 and (b[4] - b[2]) * ppu <= th - 8 + 1e-6,
				`{w.id} overflows a {tw}x{th} tile at {ppu} px/stud`)
		end
		framed += 1
	end
end
assert(Weapons2D.bounds("NoSuchWeapon") == nil)
print(`framed {framed} weapon tiles pixel-exact and uncut`)
print(`checked {checked} weapon rectangles across {#Weapons.LIST} weapons ({total // #Weapons.LIST} a weapon, budget {FRAME_BUDGET})`)
print("Weapons2D draws exactly the art web/src/data/weaponArt.js compiled.")
