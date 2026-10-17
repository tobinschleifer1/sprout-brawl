--!strict
-- Roblox-only: what a Rocket Boots kick throws out (Kicks). Two pixel pictures, each built once and
-- drawn as ONE sprite, so a kick costs two Frames on the lowest devices and never rebuilds them:
--
--   BLAST   the shock cone ahead of the boot, in the boots' glow: it runs from the foot to the far
--           side of the move's hitbox, so the reach of a kick is something you can see
--   PLUME   the exhaust out of the heel, in fire, pushing the kick; a fuel-burning move's ignition
--           frames throw it twice the size
--
-- Both are drawn along the kick's own direction, in the fighter's posture frame, with the boot.
local Canvas2D = require(script.Parent.Canvas2D)
local KickFx = {}

-- Grids: the picture points along +x from its left edge's middle row. '.' is empty; letters are
-- looked up below with an alpha, so the cone fades toward its tip.
local BLAST = {
	"WWC.............",
	"WWWCCC..........",
	"WWWWCCCCbbb.....",
	"WWWWWCCCCCCbbbbb",
	"WWWWCCCCbbb.....",
	"WWWCCC..........",
	"WWC.............",
}
local PLUME = {
	"YYo.......",
	"YYYoor....",
	"YYYYoorrr.",
	"YYYoor....",
	"YYo.......",
}
-- (Few shades on purpose: every run of one is a Frame on the lowest devices.)
local INK: { [string]: { any } } = {
	W = { "#FFFFFF", 0.95 }, c = { "#B8F6FF", 0.85 }, C = { "#62E8FF", 0.6 }, b = { "#62E8FF", 0.3 },
	Y = { "#FFF4C8", 1 }, o = { "#FFB93F", 0.95 }, r = { "#F2621B", 0.8 },
}
local function compile(rows: { string }): { any }
	local out = {}
	for y, row in rows do
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			local run = x
			while run + 1 <= #row and string.sub(row, run + 1, run + 1) == ch do run += 1 end
			local ink = INK[ch]
			if ink then table.insert(out, { x - 1, y - 1, run - x + 1, 1, ink[1], ink[2] }) end
			x = run + 1
		end
	end
	return out
end
KickFx.BLAST = { rects = compile(BLAST), cols = #BLAST[1], rows = #BLAST }
KickFx.PLUME = { rects = compile(PLUME), cols = #PLUME[1], rows = #PLUME }
-- the cone's thickness and the exhaust's length and thickness, studs
KickFx.BLAST_WIDTH, KickFx.PLUME_LENGTH, KickFx.PLUME_WIDTH = 1.0, 0.9, 0.55
-- how far the exhaust turns off the line of the leg, radians (toward the sole)
KickFx.HEEL_TURN = 1.0

local function stamp(c: any, key: string, art: any, x: number, y: number, angle: number, length: number, width: number)
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	Canvas2D.rotate(c, angle)
	Canvas2D.sprite(c, key, art.rects, 0, width / 2, length / art.cols, width / art.rows, art.cols, art.rows)
	Canvas2D.restore(c)
end

-- One striking leg's effects, from its foot (x, y) along the unit direction (ux, uy): the cone out
-- `reach` studs ahead, the exhaust behind. `ignite` doubles the exhaust.
function KickFx.draw(c: any, x: number, y: number, ux: number, uy: number, reach: number, ignite: boolean)
	local angle = math.atan2(uy, ux)
	local k = if ignite then 2 else 1
	-- out of the heel: back along the leg and turned down off it, clear of the shin
	stamp(c, "kickfx|plume", KickFx.PLUME, x, y, angle + math.pi - KickFx.HEEL_TURN, KickFx.PLUME_LENGTH * k, KickFx.PLUME_WIDTH * k)
	if reach > 0.05 then
		stamp(c, "kickfx|blast", KickFx.BLAST, x, y, angle, reach, KickFx.BLAST_WIDTH)
	end
end

return KickFx
