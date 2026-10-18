--!strict
-- A cosmetic's picture on a tile (Roblox only; the Locker, the Workshop and the crate reel): drawn
-- through the game's own renderers, so a tile shows the item as it looks in a fight.
--   weapon skins   the skinned weapon, laid flat (Weapons2D)
--   effects        one frame of the effect's own drawing, in its ramp (FxArt)
--   trails         the trail's colours as a striped arc
--   titles         the title's words
-- Sizes are passed in, never read from the frame: a frame's AbsoluteSize lags a layout by a frame.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Loot = require(Shared.Loot)
local CosmeticArt = require(Shared.CosmeticArt)
local Canvas2D = require(script.Parent.Canvas2D)
local Weapons2D = require(script.Parent.Weapons2D)
local FxArt = require(script.Parent.FxArt)
local ItemArt = {}

-- The drawing each effect's tile shows: a kind, a flipbook frame and a ramp. A recolouring hit
-- effect shows the plain pop in its ramp.
ItemArt.FX = {
	hit_comicpow = { "star", 1, "gold" }, hit_supernova = { "star", 1, "gold" }, hit_eventhorizon = { "cyclone", 1, "void" },
	ko_balloonpop = { "pop", 2, "#FF6A8A" }, ko_ghostrise = { "pillar", 2, "#DDE6FF" }, ko_firework = { "burst", 2, "red" },
	ko_pixelshatter = { "xslash", 1, "#E8ECF2" }, ko_meteor = { "comet", 1, "fire" }, ko_blackhole = { "cyclone", 2, "void" },
	ko_dragonsbreath = { "burst", 2, "fire" },
	spawn_confetti = { "burst", 1, "gold" }, spawn_portal = { "ring", 2, "void" }, spawn_droppod = { "comet", 1, "wind" },
	spawn_lightning = { "bolt", 1, "volt" },
	shield_hex = { "ring", 3, "#7FD4FF" }, shield_crystal = { "ring", 3, "#CFEFFF" }, shield_runes = { "ring", 3, "gold" },
	steps_leaves = { "pop", 3, "#5FD068" }, steps_sparkle = { "spark", 1, "#FFF4C8" }, steps_flame = { "pop", 2, "fire" },
} :: { [string]: { any } }

-- What a tile draws for `id`: "weapon", "fx", "trail", "title" or "crate"; and its parameters.
function ItemArt.plan(id: string): (string, any)
	if CosmeticArt.props and CosmeticArt.props[id] then return "crate", id end
	local it = Cosmetics.get(id)
	if not it then return "none", nil end
	if it.type == "weapon_skin" then return "weapon", `{it.weapon}@{id}` end
	if it.type == "swing_trail" then return "trail", Weapons2D.TRAILS[id] or { "#FFFFFF" } end
	if it.type == "title" then return "title", it.name end
	local fx: { any } = ItemArt.FX[id] or { "pop", 2 :: any, it.ramp or (Loot.RARITY[it.rarity] or Loot.RARITY.Common).colour }
	return "fx", fx
end

local function fitRects(c: any, rects: { any }, w: number, h: number, pad: number)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, r in rects do
		x0, y0 = math.min(x0, r[1]), math.min(y0, r[2])
		x1, y1 = math.max(x1, r[1] + r[3]), math.max(y1, r[2] + r[4])
	end
	-- whole multiples of 8 px a stud, so every art pixel is whole screen pixels
	local ppu = math.max(8, math.floor(math.min((w - pad * 2) / (x1 - x0), (h - pad * 2) / (y1 - y0)) / 8) * 8)
	Canvas2D.setTransform(c, ppu, 0, 0, ppu, w / 2 - (x0 + x1) / 2 * ppu, h / 2 - (y0 + y1) / 2 * ppu)
	for _, r in rects do
		Canvas2D.rect(c, r[1], r[2], r[3], r[4], Canvas2D.hex(r[5], Color3.new(1, 0, 1)), r[6] or 1)
	end
end

-- Draw `id` on a tile canvas `w` x `h` pixels.
function ItemArt.draw(c: any, id: string, w: number, h: number)
	local kind, arg = ItemArt.plan(id)
	if kind == "weapon" then
		local cx, cy, ppu = Weapons2D.fit(arg, w, h, 6)
		Canvas2D.setTransform(c, ppu, 0, 0, -ppu, w / 2 - cx * ppu, h / 2 + cy * ppu)
		Weapons2D.draw(c, arg, Weapons2D.skinPalette(string.match(arg, "@(.+)$")) or {}, { angle = 0, ox = 0, oy = 0, scale = 1, charge = 0 })
	elseif kind == "crate" then
		fitRects(c, CosmeticArt.props[arg], w, h, 6)
	elseif kind == "fx" then
		-- effects are drawn y-up, as in a fight
		Canvas2D.setTransform(c, 1, 0, 0, -1, 0, h)
		local art = FxArt.get(arg[1], arg[2], arg[3], nil, 1)
		FxArt.draw(c, art, w / 2, h / 2, FxArt.sized(art, math.min(w, h) * 0.85))
	elseif kind == "trail" then
		Canvas2D.screen(c)
		local n = 12
		for i = 0, n - 1 do
			local u = i / (n - 1)
			local a = math.pi * (1.1 - 0.9 * u)
			local rad = math.min(w, h) * 0.36
			local col = Canvas2D.hex(arg[i % #arg + 1], Color3.new(1, 1, 1))
			local s = 4 + 6 * u
			Canvas2D.rect(c, w / 2 + math.cos(a) * rad - s / 2, h * 0.62 - math.sin(a) * rad - s / 2, s, s, col, 0.4 + 0.6 * u)
		end
	end
	Canvas2D.finish(c, true)
end

return ItemArt
