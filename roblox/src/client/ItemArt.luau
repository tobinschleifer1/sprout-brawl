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
local Emotes = require(script.Parent.Emotes)
local Fighter2D = require(script.Parent.Fighter2D)
local PosedFighter = require(script.Parent.PosedFighter)
local Loadout = require(Shared.Loadout)
local KitPortrait = require(script.Parent.KitPortrait)
local AvatarKit = require(Shared.AvatarKit)
-- clothing worn on the head is shown on a head; the rest on the whole figure
local HEAD_WORN = { headwear = true, hair = true, eyewear = true }
local ItemArt = {}

-- The drawing each effect's tile shows: a kind, a flipbook frame and a ramp. A recolouring hit
-- effect shows the plain pop in its ramp.
ItemArt.FX = {
	hit_comicpow = { "star", 1, "gold" }, hit_supernova = { "star", 1, "gold" }, hit_eventhorizon = { "cyclone", 1, "void" },
	ko_balloonpop = { "pop", 2, "#FF6A8A" }, ko_ghostrise = { "pillar", 2, "#DDE6FF" }, ko_firework = { "burst", 2, "red" },
	ko_pixelshatter = { "xslash", 1, "#E8ECF2" }, ko_meteor = { "comet", 1, "fire" }, ko_blackhole = { "cyclone", 2, "void" },
	ko_dragonsbreath = { "burst", 2, "fire" },
	spawn_confetti = { "burst", 1, "gold" }, spawn_portal = { "ring", 2, "void" }, spawn_droppod = { "comet", 1, "wind" },
	spawn_lightning = { "bolt", 1, "volt" }, spawn_vipsparkle = { "star", 1, "gold" },
	shield_hex = { "ring", 3, "#7FD4FF" }, shield_crystal = { "ring", 3, "#CFEFFF" }, shield_runes = { "ring", 3, "gold" },
	steps_leaves = { "pop", 3, "#5FD068" }, steps_sparkle = { "spark", 1, "#FFF4C8" }, steps_flame = { "pop", 2, "fire" },
} :: { [string]: { any } }

-- What a tile draws for `id`: "weapon", "fx", "trail", "title", "crate" or "kit" (a clothing piece on
-- the default character: { code, view }); and its parameters.
function ItemArt.plan(id: string): (string, any)
	if CosmeticArt.props and CosmeticArt.props[id] then return "crate", id end
	local it = Cosmetics.get(id)
	if not it then return "none", nil end
	if it.type == "weapon_skin" then return "weapon", `{it.weapon}@{id}` end
	if it.type == "swing_trail" then return "trail", Weapons2D.TRAILS[id] or { "#FFFFFF" } end
	if it.type == "title" then return "title", it.name end
	if it.type == "emote" or it.type == "victory_pose" then return "pose", { id = id, victory = it.type == "victory_pose", frame = Emotes.KEY_FRAME } end
	if it.type == "clothing" and it.category then
		local spec = AvatarKit.sanitize(nil)
		spec.parts[it.category] = id
		return "kit", { AvatarKit.encode(spec), if HEAD_WORN[it.category] then "head" else "figure" }
	end
	local fx: { any } = ItemArt.FX[id] or { "pop", 2 :: any, it.ramp or (Loot.RARITY[it.rarity] or Loot.RARITY.Common).colour }
	return "fx", fx
end

-- A title's nameplate, in art pixels (x, y, w, h, colour; "c" is the rarity's colour): a plaque on two
-- posts with a ribbon's tails, and three lines of "lettering".
ItemArt.NAMEPLATE = {
	{ 0, 3, 3, 4, "#3A2A1E" }, { 25, 3, 3, 4, "#3A2A1E" },              -- the ribbon's tails, dark
	{ 1, 4, 2, 2, "c" }, { 25, 4, 2, 2, "c" },
	{ 3, 1, 22, 10, "#3A2A1E" },                                      -- the plaque's edge
	{ 4, 2, 20, 8, "c" },                                             -- its face
	{ 4, 8, 20, 2, "#FFFFFF", 0.35 },                                 -- the light along its top
	{ 7, 6, 14, 1, "#FFFFFF" }, { 9, 4, 10, 1, "#FFFFFF", 0.8 },      -- the lettering
} :: { { any } }

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
	if kind == "pose" then
		local char = table.clone(Loadout.build("Classic", "Sword"))
		char.cosmetics = { skins = {}, emoteNeutral = arg.id, pose = arg.id }
		local s = PosedFighter.posed(char, -1, if arg.victory then "victory" else "taunt", arg.frame)
		local ppu = math.min(w / 12, h / 8.5)
		Canvas2D.setTransform(c, ppu, 0, 0, -ppu, w * 0.48, h * 0.94)
		Fighter2D.draw(c, s, char, 0, nil)
	elseif kind == "weapon" then
		local cx, cy, ppu = Weapons2D.fit(arg, w, h, 6)
		Canvas2D.setTransform(c, ppu, 0, 0, -ppu, w / 2 - cx * ppu, h / 2 + cy * ppu)
		Weapons2D.draw(c, arg, Weapons2D.skinPalette(string.match(arg, "@(.+)$")) or {}, { angle = 0, ox = 0, oy = 0, scale = 1, charge = 0 })
	elseif kind == "kit" then
		KitPortrait.draw(c, arg[1], arg[2], w, h)
		return
	elseif kind == "crate" then
		fitRects(c, CosmeticArt.props[arg], w, h, 6)
	elseif kind == "fx" then
		-- effects are drawn y-up, as in a fight
		Canvas2D.setTransform(c, 1, 0, 0, -1, 0, h)
		local art = FxArt.get(arg[1], arg[2], arg[3], nil, 1)
		-- fitted by both sides around the art's own box, not by its width at its anchor: a tall pillar
		-- (Ghost Rise) drew 349 px past a 190 px tile, a cyclone 61 px, and the tiles do not clip
		local pw = math.min(w * 0.85 / art.cols, h * 0.85 / art.rows)
		FxArt.draw(c, art, w / 2 - (art.cols / 2 - art.ax) * pw, h / 2 - (art.ay - art.rows / 2) * pw, pw * art.ppu)
	elseif kind == "title" then
		-- a title is words; its tile shows a pixel nameplate in its rarity's colour (it drew nothing)
		local it = Cosmetics.get(id)
		local col = (Loot.RARITY[it and it.rarity or "Common"] or Loot.RARITY.Common).colour
		local rects = {}
		-- (fitRects works in studs, at whole multiples of 8 px a stud: the plate is in eighths)
		for _, r in ItemArt.NAMEPLATE do table.insert(rects, { r[1] / 8, r[2] / 8, r[3] / 8, r[4] / 8, if r[5] == "c" then col else r[5], r[6] }) end
		fitRects(c, rects, w, h, 8)
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
