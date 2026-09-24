--!strict
-- What UltBanner.paint puts on screen, read back through the same arithmetic Canvas2D.rect uses to
-- place a Frame. cinematic-parity proves the LAYOUT matches the web; this proves the painter
-- honours it: the band is centred on the layout point, tilted by its angle and as wide as it says;
-- the caster's feet land on the portrait point at the portrait's size; the weapon is drawn whole;
-- and the canvas is left as it was found, so the HUD drawn after it is not tilted or faded.
local Loader = require("./loader")
local Art = Loader.load("Data/Art")
local U = Loader.loadFrom("src/client/", "UltCinematic")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local UltBanner = Loader.loadFrom("src/client/", "UltBanner")

local rects: { any } = {}
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	local m = c.m
	local cx, cy = x + w / 2, y + h / 2
	table.insert(rects, {
		x = m.a * cx + m.c * cy + m.e, y = m.b * cx + m.d * cy + m.f,
		w = math.sqrt((m.a * w) ^ 2 + (m.b * w) ^ 2), rot = math.atan2(m.b * w, m.a * w),
		alpha = (alpha or 1) * c.alpha,
	})
end
local drawnFighter: any = nil
Fighter2D.draw = function(c: any, st: any, char: any, _t: number, _top: number?)
	local m = c.m
	drawnFighter = { fx = m.a * st.x + m.e, fy = m.d * st.y + m.f,
		head = m.d * (st.y + char.height) + m.f, alpha = c.alpha }
end

local function canvas(): any
	return { m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }
end
local near = function(a: number, b: number): boolean return math.abs(a - b) < 1e-6 end

local checked = 0
for _, screen in { { 1280, 720 }, { 812, 375 }, { 400, 420 } } do
	for e = 1, U.FREEZE - 1 do
		local B = U.bannerLayout(U.at(e), screen[1], screen[2])
		if B then
			table.clear(rects)
			drawnFighter = nil
			local c = canvas()
			local st = { x = -12.5, y = 3.25 }
			UltBanner.paint(c, B, "#B77DFF", "Scythe", st, { height = 5.4 }, 0)
			local where = `{screen[1]}x{screen[2]} frame {e}`
			-- the band: the two backing rectangles are centred on the layout point, tilted and sized by it
			for i = 1, 2 do
				local r = rects[i]
				assert(near(r.x, B.cx) and near(r.y, B.cy), `{where}: band {i} centred at {r.x},{r.y}, layout says {B.cx},{B.cy}`)
				assert(near(r.rot, B.rot), `{where}: band {i} tilted {r.rot}, layout says {B.rot}`)
				assert(near(r.w, B.w), `{where}: band {i} is {r.w} wide, layout says {B.w}`)
				assert(near(r.alpha, B.alpha), `{where}: band {i} alpha {r.alpha}, layout says {B.alpha}`)
			end
			-- the caster: feet on the portrait point, as tall as the portrait, faded with the band
			local f = assert(drawnFighter, `{where}: the caster was not drawn`)
			assert(near(f.fx, B.portrait.x) and near(f.fy, B.portrait.y), `{where}: feet at {f.fx},{f.fy}, portrait at {B.portrait.x},{B.portrait.y}`)
			assert(near(f.fy - f.head, B.portrait.size), `{where}: caster {f.fy - f.head}px tall, portrait {B.portrait.size}`)
			assert(near(f.alpha, B.alpha), `{where}: caster drawn at alpha {f.alpha}, band at {B.alpha}`)
			-- the weapon, whole
			assert(#rects == 3 + #Art.sprites.Scythe, `{where}: {#rects - 3} weapon rectangles, the art has {#Art.sprites.Scythe}`)
			-- and the canvas handed back untouched
			assert(#c.stack == 0 and #c.alphaStack == 0, `{where}: transform or alpha stack left unbalanced`)
			assert(c.alpha == 1, `{where}: canvas alpha left at {c.alpha}`)
			checked += 1
		end
	end
end
assert(checked > 40, `only {checked} banner frames painted`)
print(`painted the ultimate banner on {checked} frames across 3 screens; band, caster and weapon where the layout puts them`)
