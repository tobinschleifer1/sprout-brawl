--!strict
-- A fighter's body. The rig half of `_fighter` in web/src/render2d/renderer2d.js.
--
-- NEUTRAL POSE ONLY, for now. In the web build every limb angle, the bob, the lean, the squash and
-- the smear come out of render2d/channels.js, which is 746 lines and reads far more fighter state
-- than a snapshot currently carries. Porting it is the next step. What this draws is the same
-- skeleton at rest, from the same proportions, so the canvas, the camera and the stage can be
-- confirmed against something recognisable before the animation goes on top of it.
--
-- Proportions are the JavaScript's, and they are load-bearing: HIP, SHO and HEAD are where the
-- weapon welds and every hitbox visual will hang off.

local Canvas2D = require(script.Parent.Canvas2D)

local BLACK = Color3.new(0, 0, 0)

local Fighter2D = {}

function Fighter2D.draw(c: any, s: any, char: any, platformTop: number?)
	if not s.alive or s.state == "ko" then
		return
	end
	local h, r = char.height, char.radius
	local pal = char.palette or {}
	local primary = Canvas2D.hex(pal.primary, Color3.fromRGB(210, 212, 220))
	local secondary = Canvas2D.hex(pal.secondary, Color3.fromRGB(150, 155, 170))
	local tertiary = Canvas2D.hex(pal.tertiary, Color3.fromRGB(96, 102, 120))

	Canvas2D.save(c)
	Canvas2D.translate(c, s.x, s.y)
	-- One drawing, both facings. Everything below is drawn facing +X and mirrored here, which is
	-- why a weapon that looked right for months can turn out to have been mirrored the whole time.
	Canvas2D.scale(c, s.facing, 1)

	-- Respawn invincibility has to be legible or it reads as the game ignoring hits.
	if s.invincible > 0 then
		c.alpha = 0.45 + 0.25 * math.sin(os.clock() * 24)
	end

	-- Ground shadow, tied to how far above the platform the fighter is, so height off the stage is
	-- readable without looking away from the fighter.
	if platformTop then
		local d = math.clamp(1 - (s.y - platformTop) / 14, 0.25, 1)
		Canvas2D.ellipse(c, 0, platformTop - s.y + 0.1, r * 1.25 * d, 0.45 * d, BLACK, c.alpha * 0.22)
	end

	local HIP, SHO = h * 0.34, h * 0.70
	local lw, ll = r * 0.42, HIP

	-- Legs. The far one first, and in the darker palette entry, which is where the depth in this
	-- art style comes from - there is no lighting to do it.
	Canvas2D.rect(c, -r * 0.30 - lw / 2, 0, lw, ll, tertiary, 0.74)
	Canvas2D.rect(c, r * 0.30 - lw / 2, 0, lw, ll, tertiary)

	-- Back arm, then torso, then front arm: the torso has to hide the far shoulder.
	local aw, al = r * 0.34, SHO - HIP
	Canvas2D.rect(c, -aw / 2, HIP + al * 0.1, aw, al * 0.9, secondary, 0.74)
	Canvas2D.rect(c, -r * 0.82, HIP, r * 1.64, SHO - HIP, primary)
	Canvas2D.rect(c, r * 0.22, HIP + al * 0.1, aw, al * 0.9, secondary)

	-- The head is a plain box here. avatar2d.js owns its real shape, face and headgear, and that is
	-- the whole of what a player-made character gets to choose - it lands in the next step.
	local hs = h * 0.24
	Canvas2D.rect(c, -hs / 2, SHO, hs, hs, primary)

	c.alpha = 1
	Canvas2D.restore(c)
end

return Fighter2D
