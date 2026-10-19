--!strict
-- Kit character -> cells -> rectangles: a line-for-line port of web/src/render2d/avatarCompose.js,
-- replayed against it by tests/kit-parity.luau.
--
-- compose(spec) stacks every chosen option's layers onto the five puppet pieces (head, torso, arm,
-- leg, pelvis) and resolves each cell to a colour; piece(grid) outlines it and cuts it into as few
-- rectangles as possible, because every rectangle is a Frame. halve(grid) is the half-resolution
-- copy the renderer switches to when a cell would be smaller than a screen pixel; see the note at
-- the top of the JavaScript for why eyes and mouths carry extra weight in it.
--
-- Cells are indexed from 0 in the grid arithmetic (y * w + x) and stored at index + 1, so the
-- numbers in this file are the JavaScript's numbers.

local AvatarKit = require(game:GetService("ReplicatedStorage").Shared.AvatarKit)
local KIT: any = AvatarKit.KIT

local AvatarCompose = {}

AvatarCompose.PIECES = { "head", "torso", "arm", "leg", "pelvis" }
-- The jointed limbs, cut from the composed arm and leg (KIT.parts `of` and `r0`); full detail only.
AvatarCompose.SEGMENTS = { "upperarm", "forearm", "thigh", "shin" }
AvatarCompose.OUTLINE = KIT.outline :: string
AvatarCompose.OUTLINE_ALPHA = 0.85
AvatarCompose.SHADE_DARK = 0.72
AvatarCompose.FAR_SHADE = 0.74

export type Cell = { hex: string, weight: number }
export type Grid = { w: number, h: number, cells: { [number]: Cell } }  -- sparse: nil is transparent
export type Rect = { any }                                               -- { col, row, w, h, hex, alpha }

-- ------------------------------------------------------------------ colour ----
local function rgb(hex: string): (number, number, number)
	return tonumber(string.sub(hex, 2, 3), 16) :: number, tonumber(string.sub(hex, 4, 5), 16) :: number,
		tonumber(string.sub(hex, 6, 7), 16) :: number
end
local function round(v: number): number
	return math.floor(v + 0.5)   -- JavaScript's Math.round; every value here is non-negative
end
local function toHex(r: number, g: number, b: number): string
	return string.format("#%02X%02X%02X", r, g, b)
end

function AvatarCompose.darken(hex: string, k: number): string
	local r, g, b = rgb(hex)
	return toHex(round(r * k), round(g * k), round(b * k))
end
function AvatarCompose.lighten(hex: string): string
	local r, g, b = rgb(hex)
	local function up(v: number): number
		return round(math.min(255, v * 1.25 + 20))
	end
	return toHex(up(r), up(g), up(b))
end
function AvatarCompose.mix(a: string, b: string): string
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	return toHex(round((r1 + r2) / 2), round((g1 + g2) / 2), round((b1 + b2) / 2))
end
function AvatarCompose.luma(hex: string): number
	local r, g, b = rgb(hex)
	return r * 299 + g * 587 + b * 114
end

local function slotColour(spec: AvatarKit.Spec, slot: string): string
	return AvatarKit.colourSlot(slot).list[spec.colours[slot] + 1]
end

function AvatarCompose.resolveRoles(spec: AvatarKit.Spec): { [string]: Cell }
	local out = {}
	for ch, r in KIT.roles do
		local col: string
		if r.fixed then
			col = KIT.fixed[r.fixed]
		elseif r.mix then
			col = AvatarCompose.mix(slotColour(spec, r.slot), slotColour(spec, r.mix))
		elseif r.shade == "dark" then
			col = AvatarCompose.darken(slotColour(spec, r.slot), AvatarCompose.SHADE_DARK)
		elseif r.shade == "light" then
			col = AvatarCompose.lighten(slotColour(spec, r.slot))
		else
			col = slotColour(spec, r.slot)
		end
		out[ch] = { hex = col, weight = r.weight or 1 }
	end
	return out
end

-- ------------------------------------------------------------------ layers ----
-- Sorted on (z, seq) with seq unique: a strict total order, so table.sort (not stable) lands on the
-- JavaScript's stable-sort sequence.
-- `override` (Roblox only: Expressions.luau) replaces a category's layers with others, by category
-- id - an expression-only pair of eyes in place of the chosen ones. Without it this is the port.
function AvatarCompose.layersOf(spec: AvatarKit.Spec, override: { [string]: { any } }?): ({ any }, number)
	local list = {}
	local seq, trim = 0, 0
	for _, cat in KIT.categories do
		local chosen: any = nil
		for _, o in cat.options do
			if o.id == spec.parts[cat.id] then
				chosen = o
			end
		end
		if not chosen then
			chosen = AvatarKit.option(cat.id, spec.parts[cat.id])      -- Roblox only: a k2 clothing piece
		end
		if chosen.trim and chosen.trim > trim then
			trim = chosen.trim
		end
		for _, L in (if override and override[cat.id] then override[cat.id] else chosen.layers) do
			table.insert(list, { L = L, seq = seq })
			seq += 1
		end
	end
	table.sort(list, function(a, b)
		if a.L.z ~= b.L.z then
			return a.L.z < b.L.z
		end
		return a.seq < b.seq
	end)
	local layers = {}
	for i, x in list do
		layers[i] = x.L
	end
	return layers, trim
end

function AvatarCompose.compose(raw: any, override: { [string]: { any } }?): { [string]: Grid }
	local spec = AvatarKit.sanitize(raw)
	local roles = AvatarCompose.resolveRoles(spec)
	local layers, trim = AvatarCompose.layersOf(spec, override)
	local out = {}
	for _, id in AvatarCompose.PIECES do
		local P = KIT.parts[id]
		local cells: { [number]: Cell } = {}
		local mask: { [number]: boolean } = {}
		for _, L in layers do
			if L.part ~= id then
				continue
			end
			for r, row in L.rows do
				for c = 1, #row do
					local ch = string.sub(row, c, c)
					if ch == "." then
						continue
					end
					local x, y = L.x + c - 1, L.y + r - 1
					if x < 0 or y < 0 or x >= P.w or y >= P.h then
						continue
					end
					if L.hair and y < trim then
						continue
					end
					local i = y * P.w + x + 1
					if L.clip and not mask[i] then
						continue
					end
					cells[i] = roles[ch]
					if L.base then
						mask[i] = true
					end
				end
			end
		end
		out[id] = { w = P.w, h = P.h, cells = cells }
	end
	return out
end

function AvatarCompose.halve(g: Grid): Grid
	local w, h = math.ceil(g.w / 2), math.ceil(g.h / 2)
	local cells: { [number]: Cell } = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local score: { [string]: number } = {}
			local painted = 0
			for dy = 0, 1 do
				for dx = 0, 1 do
					local sx, sy = x * 2 + dx, y * 2 + dy
					if sx < g.w and sy < g.h then
						local c = g.cells[sy * g.w + sx + 1]
						if c then
							painted += 1
							score[c.hex] = (score[c.hex] or 0) + c.weight
						end
					end
				end
			end
			if painted >= 2 then
				local best: string? = nil
				local bestScore = -1
				for hex, s in score do
					local better = s > bestScore
					if not better and s == bestScore and best then
						local lh, lb = AvatarCompose.luma(hex), AvatarCompose.luma(best)
						better = lh < lb or (lh == lb and hex < best)
					end
					if better then
						best, bestScore = hex, s
					end
				end
				cells[y * w + x + 1] = { hex = best :: string, weight = 1 }
			end
		end
	end
	return { w = w, h = h, cells = cells }
end

-- ------------------------------------------------------------------ rectangles ----
local function greedy(get: (number, number) -> string?, w: number, h: number, alpha: number, out: { Rect })
	local used: { [number]: boolean } = {}
	for r = 0, h - 1 do
		for c = 0, w - 1 do
			local col = get(c, r)
			if not col or used[r * w + c] then
				continue
			end
			local cw = 1
			while c + cw < w and get(c + cw, r) == col and not used[r * w + c + cw] do
				cw += 1
			end
			local ch = 1
			while r + ch < h do
				local same = true
				for k = 0, cw - 1 do
					if get(c + k, r + ch) ~= col then
						same = false
						break
					end
				end
				if not same then
					break
				end
				ch += 1
			end
			for j = 0, ch - 1 do
				for k = 0, cw - 1 do
					used[(r + j) * w + c + k] = true
				end
			end
			table.insert(out, { c, r, cw, ch, col, alpha } :: { any })
		end
	end
end

-- `r0`/`r1` cut out a band of rows (a limb segment), re-numbered from 0, outlined as the WHOLE grid
-- is - so no dark line crosses an elbow or a knee (avatarCompose.js piece).
function AvatarCompose.piece(g: Grid, r0: number?, r1: number?): { Rect }
	local w, H, cells = g.w, g.h, g.cells
	local top = r0 or 0
	local h = (r1 or H) - top
	local function full(c: number, r: number): string?
		if c < 0 or r < 0 or c >= w or r >= H then
			return nil
		end
		local cell = cells[r * w + c + 1]
		return if cell then cell.hex else nil
	end
	local function hexAt(c: number, r: number): string?
		return if r >= 0 and r < h then full(c, r + top) else nil
	end
	local function halo(c: number, r: number): string?
		local R = r + top
		if full(c, R) or full(c - 1, R) or full(c + 1, R) or full(c, R - 1) or full(c, R + 1) then
			return AvatarCompose.OUTLINE
		end
		return nil
	end
	local outline = {}
	greedy(halo, w, h, AvatarCompose.OUTLINE_ALPHA, outline)
	local inPlace = {}
	greedy(hexAt, w, h, 1, inPlace)
	local count: { [string]: number } = {}
	for i = top * w + 1, (top + h) * w do
		local c = cells[i]
		if c then
			count[c.hex] = (count[c.hex] or 0) + 1
		end
	end
	local base: string? = nil
	local n = -1
	for hex, k in count do
		if k > n or (k == n and base and hex < base) then
			base, n = hex, k
		end
	end
	local painter = {}
	greedy(function(c, r)
		return if hexAt(c, r) then base else nil
	end, w, h, 1, painter)
	greedy(function(c, r)
		local x = hexAt(c, r)
		return if x and x ~= base then x else nil
	end, w, h, 1, painter)
	local chosen: { Rect } = if #painter < #inPlace then painter else inPlace
	for _, rect in chosen do
		table.insert(outline, rect)
	end
	return outline
end

-- Rectangles per piece at full and half resolution, cached per code: a match draws the same few
-- characters every frame.
local CACHE: { [string]: any } = {}
function AvatarCompose.sprites(code: string): any
	local hit = CACHE[code]
	if hit then
		return hit
	end
	local spec = AvatarKit.decode(code) or AvatarKit.sanitize(nil)
	local g = AvatarCompose.compose(spec)
	local out: { [string]: any } = {}
	for _, id in AvatarCompose.PIECES do
		out[id] = { full = AvatarCompose.piece(g[id]), half = AvatarCompose.piece(AvatarCompose.halve(g[id])) }
	end
	-- The far arm and leg, darkened. Built once here rather than per draw: a sprite recognises an
	-- unchanged picture by table identity.
	for _, id in { "arm", "leg" } do
		out[id].farFull = AvatarCompose.shadeRects(out[id].full)
		out[id].farHalf = AvatarCompose.shadeRects(out[id].half)
	end
	for _, id in AvatarCompose.SEGMENTS do
		local P = KIT.parts[id]
		local full = AvatarCompose.piece(g[P.of], P.r0, P.r0 + P.h)
		out[id] = { full = full, farFull = AvatarCompose.shadeRects(full) }
	end
	CACHE[code] = out
	return out
end

function AvatarCompose.shadeRects(rects: { Rect }): { Rect }
	local out = {}
	for i, r in rects do
		out[i] = if r[5] == AvatarCompose.OUTLINE then r
			else { r[1], r[2], r[3], r[4], AvatarCompose.darken(r[5], AvatarCompose.FAR_SHADE), r[6] }
	end
	return out
end

return AvatarCompose
