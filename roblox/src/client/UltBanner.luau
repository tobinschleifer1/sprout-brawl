--!strict
-- Paints a UltCinematic.bannerLayout in screen pixels: the band, then the caster standing on it
-- through the same Fighter2D the match uses, then their weapon - as renderer2d.js _ultBanner does.
-- The name is text, and text lives in the HUD (Hud.ultBanner), a separate ScreenGui in the same
-- pixel space. tests/ult-banner.luau checks what this puts on screen.
local Canvas2D = require(script.Parent.Canvas2D)
local Fighter2D = require(script.Parent.Fighter2D)
local Weapons2D = require(script.Parent.Weapons2D)

local UltBanner = {}

local INK = Color3.fromRGB(11, 14, 20)
local WHITE = Color3.new(1, 1, 1)

function UltBanner.paint(c: any, B: any, colour: string?, weapon: string?, st: any, char: any, t: number)
	Canvas2D.screen(c)
	Canvas2D.save(c)
	Canvas2D.translate(c, B.cx, B.cy)
	Canvas2D.rotate(c, B.rot)
	Canvas2D.rect(c, -B.w / 2, -B.h / 2 - B.stripe, B.w, B.h + B.stripe * 2, INK, B.alpha)
	Canvas2D.rect(c, -B.w / 2, -B.h / 2, B.w, B.h, Canvas2D.hex(colour, WHITE), B.alpha)
	Canvas2D.rect(c, -B.w / 2, -B.h / 2, B.w, B.stripe * 0.6, WHITE, B.alpha * 0.35)
	Canvas2D.restore(c)
	-- The caster with their feet on the band: their world position maps to the portrait point.
	local ppu = B.portrait.size / char.height
	Canvas2D.save(c)
	c.alpha = B.alpha
	Canvas2D.setTransform(c, ppu, 0, 0, -ppu, B.portrait.x - st.x * ppu, B.portrait.y + st.y * ppu)
	Fighter2D.draw(c, st, char, t, nil)
	if weapon then
		local s = B.weapon.size / 4
		Canvas2D.setTransform(c, s, 0, 0, -s, B.weapon.x, B.weapon.y)
		Canvas2D.rotate(c, -B.rot + 0.6)
		Weapons2D.drawSprite(c, weapon, 1)
	end
	Canvas2D.restore(c)
end

return UltBanner
