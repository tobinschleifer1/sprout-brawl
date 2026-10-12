--!strict
-- Cached Roblox-only cuts of the player's art. One extra torso sprite; no joint-cap sprites,
-- no animation-dependent pictures. The replay-held composer and generated kit are untouched.
local Compose = require(script.Parent.AvatarCompose)
local AvatarKit = require(game:GetService("ReplicatedStorage").Shared.AvatarKit)
local PARTS = AvatarKit.KIT.parts
local PostureArt = {}
PostureArt.parts = table.clone(PARTS) :: { [string]: any }
-- Waist at row 11. The chest continues four rows BELOW its pivot, hiding the abdomen's top edge.
PostureArt.parts.chest = { w = 16, h = 15, ox = 8, oy = 11, span = 11 }
PostureArt.parts.abdomen = { w = 16, h = 7, ox = 8, oy = 7, span = 7 }

local function cut(g: Compose.Grid, top: number, height: number): Compose.Grid
	local cells = {}
	for y = 0, height - 1 do
		for x = 0, g.w - 1 do cells[y * g.w + x + 1] = g.cells[(y + top) * g.w + x + 1] end
	end
	return { w = g.w, h = height, cells = cells }
end

-- Bevel the last row of the upper segment and first row of the lower one. Cutting the existing
-- rectangles preserves their side outlines without adding a dark stripe across the joint.
local function bevel(rects: { Compose.Rect }, w: number, h: number, top: boolean): { Compose.Rect }
	local out = {}
	local edge = if top then 0 else h - 1
	for _, rect in rects do
		if rect[1] >= 1 and rect[1] + rect[3] <= w - 1 then
			table.insert(out, rect)
			continue
		end
		for _, band in { { 0, edge, 0 }, { edge, edge + 1, 1 }, { edge + 1, h, 0 } } do
			local x0, x1 = math.max(rect[1], band[3]), math.min(rect[1] + rect[3], w - band[3])
			local y0, y1 = math.max(rect[2], band[1]), math.min(rect[2] + rect[4], band[2])
			if x1 > x0 and y1 > y0 then table.insert(out, { x0, y0, x1 - x0, y1 - y0, rect[5], rect[6] }) end
		end
	end
	return out
end

local CUTS: { [string]: { number } } = { chest = { 0, 15 }, abdomen = { 11, 7 } }
local CACHE: { [string]: any } = {}
function PostureArt.sprites(code: string): any
	if CACHE[code] then return CACHE[code] end
	local art: { [string]: any } = table.clone(Compose.sprites(code))
	local grid = Compose.compose(AvatarKit.decode(code) or AvatarKit.sanitize(nil)).torso
	for name, spec in CUTS do
		local top, height = spec[1], spec[2]
		local g = cut(grid, top, height)
		art[name] = { full = Compose.piece(grid, top, top + height), half = Compose.piece(Compose.halve(g)) }
	end
	for _, id in Compose.SEGMENTS do
		local P = PARTS[id]
		local full = bevel(art[id].full, P.w, P.h, id == "forearm" or id == "shin")
		art[id] = { full = full, farFull = Compose.shadeRects(full) }
	end
	CACHE[code] = art
	return art
end
return PostureArt
