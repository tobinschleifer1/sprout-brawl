--!strict
-- One small, cached trailing piece at full detail. The neck's scarf/mantle takes priority over
-- a coat hem, then long rear hair. Other hair still follows the lagging head. At match LOD the
-- original welded pictures are used, with no extra sprite or composition work.
local Kit = require(game:GetService("ReplicatedStorage").Shared.AvatarKit)
local Compose = require(script.Parent.AvatarCompose)
local Expressions = require(script.Parent.Expressions)
local Secondary = { CACHE_MAX = 64 }
local cache: { [string]: any } = {}
local order: { string } = {}

local function option(spec: any, category: string): any
	for _, cat in Kit.KIT.categories do
		if cat.id == category then
			for _, opt in cat.options do if opt.id == spec.parts[category] then return opt end end
		end
	end
	return nil
end

function Secondary.art(code: string): any
	if cache[code] then return cache[code] end
	local spec = Kit.decode(code) or Kit.sanitize(nil)
	local category, kind, anchor = "hair", "hair", "head"
	local neck, top = spec.parts.neck, spec.parts.top
	if neck == "summitMantle" or neck == "scarf" then
		category, kind, anchor = "neck", neck, "chest"
	elseif top == "trench" or top == "robe" then
		category, kind, anchor = "top", "coat", "pelvis"
	end
	local chosen = option(spec, category)
	local layers, tail, changed = {}, {}, {}
	local roles = Compose.resolveRoles(spec)
	local _, trim = Compose.layersOf(spec)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, layer in chosen.layers do
		local copy = table.clone(layer)
		copy.rows = {}
		for row, text in layer.rows do
			local chars = {}
			for col = 1, #text do
				local glyph = string.sub(text, col, col)
				local x, y = layer.x + col - 1, layer.y + row - 1
				local take = (kind == "hair" and layer.part == "head" and layer.z == 10 and layer.y >= 8 and y >= trim)
					or (kind == "scarf" and layer.part == "torso" and y >= 3 and x < 5)
					or (kind == "summitMantle" and ((layer.part == "torso" and y >= 2 and x < 3) or layer.part == "pelvis"))
					or (kind == "coat" and layer.part == "pelvis" and y >= 3 and x < 4)
				if take and glyph ~= "." then
					changed[layer.part] = true
					-- The mantle continues into the pelvis at the same cell pitch. Its half-cell
					-- overlap is rounded into the neck's one continuous strip, hidden under the waist.
					if kind == "summitMantle" and layer.part == "pelvis" then x = math.min(x, 3) + 1; y += 16 end
					-- Rear hair is a silhouette in the player's shadow colour. Tiny alternating
					-- highlights cost rectangles without reading at this size.
					table.insert(tail, { x = x, y = y, cell = if kind == "hair" then roles.H else roles[glyph] })
					minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y)
					glyph = "."
				end
				table.insert(chars, glyph)
			end
			copy.rows[row] = table.concat(chars)
		end
		table.insert(layers, copy)
	end
	local art: any = { kind = kind, anchor = anchor, full = nil, replacements = {}, heads = {} }
	if #tail > 0 then
		local w, h = maxX - minX + 3, maxY - minY + 3
		local grid: Compose.Grid = { w = w, h = h, cells = {} }
		for _, pixel in tail do grid.cells[(pixel.y - minY + 1) * w + pixel.x - minX + 2] = pixel.cell end
		art.full, art.w, art.h = Compose.piece(grid), w, h
		art.x, art.y = minX + 1, minY
		art.spec, art.override, art.category = spec, { [category] = layers }, category
		local body = Compose.compose(spec, art.override)
		if changed.head then art.replacements.head = Compose.piece(body.head) end
		if changed.torso then
			art.replacements.chest = Compose.piece(body.torso, 0, 15)
			art.replacements.abdomen = Compose.piece(body.torso, 11, 18)
		end
		if changed.pelvis then art.replacements.pelvis = Compose.piece(body.pelvis) end
	end
	cache[code] = art
	table.insert(order, code)
	if #order > Secondary.CACHE_MAX then cache[table.remove(order, 1) :: string] = nil end
	return art
end

-- Expressions can change the eyes, not put the detached ponytail back on the head. These heads
-- are cut once per held expression, never per movement frame. The trailing picture stays identical.
function Secondary.head(art: any, expression: string): any
	if not art.heads[expression] then
		local spec, override = Expressions.specFor(art.spec, expression)
		local cuts: { [string]: { any } } = override or {}
		cuts[art.category] = art.override[art.category]
		art.heads[expression] = Compose.piece(Compose.compose(spec, cuts).head)
	end
	return art.heads[expression]
end

function Secondary.cacheSize(): number return #order end

-- A tiny damped follower, keyed like Expressions by loadout/fighter. Repeated draws of one frame
-- cannot advance it; a seek or new match resets it. Weak loadout keys do not keep old matches alive.
local follows: { [any]: { [number]: any } } = setmetatable({} :: any, { __mode = "k" })
function Secondary.pose(art: any, p: any, ch: any, s: any, char: any): any
	local pw, ph = char.radius * 1.15 / 12, char.height * 0.02
	local x, y, rot, sx, sy, dx, dy
	if art.anchor == "head" then
		ph = pw
		x, y, rot, sx, sy = p.headX, p.headY, p.headRot, ch.sx, ch.sy
		dx, dy = (art.x - 9) * pw, (15.2 - art.y) * ph
	elseif art.anchor == "pelvis" then
		x, y, rot, sx, sy = p.hipX, p.hipY, p.hipRot, 1, 1
		dx, dy = (art.x - 7) * pw, (2.5 - art.y) * ph
	else
		x, y, rot, sx, sy = p.waistX, p.waistY, p.chestRot, p.chestSX, p.chestSY
		dx, dy = (art.x - 8) * pw, (11 - art.y) * ph
	end
	local cs, sn = math.cos(rot), math.sin(rot)
	x += dx * sx * cs - dy * sy * sn
	y += dx * sx * sn + dy * sy * cs
	local fc, index = s.frameCount, s.index
	local wind = -0.62 * math.clamp(s.vx * s.facing / char.runSpeed, -1, 1)
		+ 0.10 * math.clamp(s.vy / 50, -1, 1)
	local target = math.clamp(rot + wind + 0.045 * math.sin(fc * 0.28 + index), -1.1, 1.1)
	local per = follows[char]
	if not per then per = {}; follows[char] = per end
	local old = per[index]
	if not old or old.art ~= art or fc < old.at or fc > old.at + 30 then
		old = { at = fc, art = art, angle = rot + (target - rot) * (1 - math.exp(-math.max(0, s.stateFrame - 2) / 5)) }
		per[index] = old
	elseif fc > old.at then
		old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))
		old.at = fc
	end
	return { x = x, y = y, rot = old.angle, sx = sx, sy = sy, pw = pw, ph = ph }
end

return Secondary
