--!strict
-- The same authored pixel tiles and weapon fittings as web/src/render2d/art2d.js.
-- The sky gradient uses 24 flat strips; every silhouette and fitting is an exact rectangle.
local Canvas2D = require(script.Parent.Canvas2D)
local Art = require(game:GetService("ReplicatedStorage").Shared.Data.Art)
local WHITE = Color3.new(1, 1, 1)
local BackdropArt = {}

function BackdropArt.sky(c: any, stageId: string, camX: number): boolean
	local art = Art.scenes[stageId]
	if not art then return false end
	local vp = Canvas2D.viewport(c)
	if vp.Y <= 0 then return false end
	Canvas2D.screen(c)
	for i = 0, 23 do
		local at = (i + 0.5) / 24 * (#art.sky - 1)
		local index = math.min(#art.sky - 1, math.floor(at) + 1)
		local a = Canvas2D.hex(art.sky[index], WHITE)
		local b = Canvas2D.hex(art.sky[index + 1], WHITE)
		local k = at - (index - 1)
		local colour = Color3.new(a.R + (b.R - a.R) * k, a.G + (b.G - a.G) * k, a.B + (b.B - a.B) * k)
		Canvas2D.rect(c, 0, i * vp.Y / 24, vp.X, vp.Y / 24 + 1, colour)
	end
	Canvas2D.save(c)
	local scale = vp.Y / 270
	Canvas2D.scale(c, scale, scale)
	local width = vp.X / scale
	local sx, sy, radius = art.sun[1], art.sun[2], art.sun[3]
	local sunX = sx / 480 * width - camX * 0.03
	local light = Canvas2D.hex(art.light, WHITE)
	Canvas2D.rect(c, sunX - radius, sy - radius * 0.6, radius * 2, radius * 1.2, light, 0.65)
	Canvas2D.rect(c, sunX - radius * 0.6, sy - radius, radius * 1.2, radius * 0.4, light, 0.65)
	Canvas2D.rect(c, sunX - radius * 0.6, sy + radius * 0.6, radius * 1.2, radius * 0.4, light, 0.65)
	for i = 0, 17 do
		Canvas2D.rect(c, ((i * 97 + 31) % 480) / 480 * width, 12 + (i * 29) % 83, 1, 1, light, 0.12 + (i % 3) * 0.08)
	end
	for _, layer in art.layers do
		local shift = -camX * layer.parallax
		local tile = math.floor(-shift / 480) * 480 + shift
		while tile < width do
			for _, r in layer.rectangles do
				if tile + r[1] + r[3] <= 0 or tile + r[1] >= width then continue end
				Canvas2D.rect(c, tile + r[1], r[2], r[3], r[4], Canvas2D.hex(r[5], WHITE), r[6])
			end
			tile += 480
		end
	end
	Canvas2D.restore(c)
	return true
end

function BackdropArt.weapon(c: any, weaponId: string, palette: any)
	for _, r in Art.weapons[weaponId] or {} do
		Canvas2D.rect(c, r[1], r[2], r[3], r[4], Canvas2D.hex(palette[r[5]] or palette.accent, WHITE), r[6])
	end
end

return BackdropArt
