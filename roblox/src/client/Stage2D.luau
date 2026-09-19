--!strict
-- The stage, drawn. A port of `_stage` in web/src/render2d/renderer2d.js.
--
-- Every number here is the JavaScript's number. The solids get a body that runs off the bottom of
-- the screen, a bright cap and a lip on each grabbable corner, because where the ledge is is
-- information the player needs and a flat slab of one colour makes it guesswork. The shelves are
-- drawn thinner and lighter so they read as pass-through at a glance.
--
-- Not ported yet: `drawSurface`, the per-theme material pass that sits between the body and the
-- cap. It is texture, not information, and everything below reads correctly without it.

local Canvas2D = require(script.Parent.Canvas2D)

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local Stage2D = {}

function Stage2D.draw(c: any, stage: any)
	local p = stage.data.palette or {}
	local ground = Canvas2D.hex(p.ground, Color3.fromRGB(107, 74, 44))
	local groundTop = Canvas2D.hex(p.groundTop, Color3.fromRGB(95, 191, 75))
	local shelf = Canvas2D.hex(p.platform, Color3.fromRGB(184, 137, 74))
	local accent = Canvas2D.hex(p.accent, Color3.fromRGB(62, 143, 53))

	for _, sp in stage.solids do
		-- The main island runs 60 studs deep so it leaves the bottom of the screen at every zoom;
		-- anything else is only as deep as it actually is.
		local depth = if sp == stage.main then 60 else math.max(sp.thickness or 6, 6)
		local w = sp.x2 - sp.x1
		Canvas2D.rect(c, sp.x1, sp.top - depth, w, depth, ground)
		Canvas2D.rect(c, sp.x1, sp.top - depth, w, math.min(depth, 1.2), BLACK, 0.16)
		Canvas2D.rect(c, sp.x1, sp.top - 1.2, w, 1.2, groundTop)
		Canvas2D.rect(c, sp.x1, sp.top - 1.5, w, 0.3, BLACK, 0.22)
		Canvas2D.rect(c, sp.x1, sp.top - 0.35, w, 0.35, WHITE, 0.22)
		if sp.ledges ~= false then
			Canvas2D.rect(c, sp.x1, sp.top - 2.0, 0.7, 2.0, accent)
			Canvas2D.rect(c, sp.x2 - 0.7, sp.top - 2.0, 0.7, 2.0, accent)
		end
	end

	for _, pl in stage.platforms do
		if not pl.solid then
			local th = pl.thickness or 1
			local w = pl.x2 - pl.x1
			Canvas2D.rect(c, pl.x1, pl.top - th, w, th, shelf)
			Canvas2D.rect(c, pl.x1, pl.top - 0.4, w, 0.4, groundTop)
			Canvas2D.rect(c, pl.x1, pl.top - 0.15, w, 0.15, WHITE, 0.24)
			Canvas2D.rect(c, pl.x1, pl.top - th, w, 0.3, BLACK, 0.30)
			Canvas2D.rect(c, pl.x1, pl.top - th, 0.35, th, BLACK, 0.30)
			Canvas2D.rect(c, pl.x2 - 0.35, pl.top - th, 0.35, th, BLACK, 0.30)
			if pl.sinking then
				-- Hatching along the underside: the only warning a player gets that this one sags.
				local x = pl.x1 + 1
				while x < pl.x2 - 1 do
					Canvas2D.rect(c, x, pl.top - th - 0.5, 1.2, 0.4, BLACK, 0.28)
					x += 3
				end
			end
		end
	end
end

-- The sky behind everything. `_sky` in the JavaScript is a vertical gradient through the stage's
-- skyStops; a single Frame with a UIGradient is the same picture with one instance.
function Stage2D.sky(c: any, stage: any)
	local p = stage.data.palette or {}
	local vp = Canvas2D.viewport(c)
	Canvas2D.screen(c)
	Canvas2D.rect(c, 0, 0, vp.X, vp.Y, Canvas2D.hex(p.sky, Color3.fromRGB(201, 211, 224)))
end

return Stage2D
