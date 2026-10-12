--!strict
-- Pixel grids drawn in code, and merged into as few rectangles as possible: the shared machinery
-- under FxArt (effects) and RealmArt (islands, platforms, skies).
--
-- A grid is w x h cells, row 0 at the TOP; a cell holds a number, 0 for empty. What a number
-- means - a tone in a ramp, an index into a palette - is the caller's business; merging only needs
-- equal numbers to be the same colour. Rectangles come out as { x, y, w, h, value } in cells, the
-- shape Canvas2D.sprite takes once the value has been turned into a colour.
local PixelGrid = {}

export type Grid = { w: number, h: number, cells: { number } }

function PixelGrid.new(w: number, h: number): Grid
	return { w = w, h = h, cells = table.create(w * h, 0) }
end

function PixelGrid.put(g: Grid, x: number, y: number, v: number)
	x, y = math.floor(x), math.floor(y)
	if x < 0 or y < 0 or x >= g.w or y >= g.h then return end
	g.cells[y * g.w + x + 1] = v
end

function PixelGrid.get(g: Grid, x: number, y: number): number
	if x < 0 or y < 0 or x >= g.w or y >= g.h then return 0 end
	return g.cells[y * g.w + x + 1]
end

-- Only ever brightens tones 1-5 (an effect's ramp): overlapping strokes keep their hottest pixel.
function PixelGrid.lift(g: Grid, x: number, y: number, v: number)
	x, y = math.floor(x), math.floor(y)
	local cur = PixelGrid.get(g, x, y)
	if cur == 0 or (v <= 5 and cur <= 5 and v > cur) then PixelGrid.put(g, x, y, v) end
end

-- Fills only cells still empty: paint behind what is already there.
function PixelGrid.under(g: Grid, x: number, y: number, v: number)
	if PixelGrid.get(g, math.floor(x), math.floor(y)) == 0 then PixelGrid.put(g, x, y, v) end
end

function PixelGrid.line(g: Grid, x0: number, y0: number, x1: number, y1: number, v: number, brighten: boolean?)
	local n = math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1))
	for i = 0, n do
		local u = i / n
		local x, y = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
		if brighten then PixelGrid.lift(g, x, y, v) else PixelGrid.put(g, x, y, v) end
	end
end

function PixelGrid.rect(g: Grid, x: number, y: number, w: number, h: number, v: number)
	for yy = math.floor(y), math.floor(y + h) - 1 do
		for xx = math.floor(x), math.floor(x + w) - 1 do PixelGrid.put(g, xx, yy, v) end
	end
end

-- A filled ellipse centred on (cx, cy), in cells.
function PixelGrid.ellipse(g: Grid, cx: number, cy: number, rx: number, ry: number, v: number)
	for y = math.floor(cy - ry), math.ceil(cy + ry) do
		for x = math.floor(cx - rx), math.ceil(cx + rx) do
			local dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1 then PixelGrid.put(g, x, y, v) end
		end
	end
end

-- A filled polygon (any simple shape), by scanline at pixel centres.
function PixelGrid.poly(g: Grid, pts: { { number } }, v: number)
	local y0, y1 = math.huge, -math.huge
	for _, p in pts do y0, y1 = math.min(y0, p[2]), math.max(y1, p[2]) end
	for y = math.max(0, math.floor(y0)), math.min(g.h - 1, math.ceil(y1)) do
		local py = y + 0.5
		local xs = {}
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			if (a[2] <= py and b[2] > py) or (b[2] <= py and a[2] > py) then
				table.insert(xs, a[1] + (py - a[2]) / (b[2] - a[2]) * (b[1] - a[1]))
			end
		end
		table.sort(xs)
		for k = 1, #xs - 1, 2 do
			for x = math.ceil(xs[k] - 0.5), math.floor(xs[k + 1] - 0.5) do PixelGrid.put(g, x, y, v) end
		end
	end
end

-- An outline of `edge` around everything drawn, on empty cells only (4-neighbour): the dark rim
-- that keeps art legible against anything behind it.
function PixelGrid.rim(g: Grid, edge: number)
	local get = PixelGrid.get
	local add = {}
	for y = 0, g.h - 1 do
		for x = 0, g.w - 1 do
			if get(g, x, y) == 0 then
				for _, o in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
					local n = get(g, x + o[1], y + o[2])
					if n ~= 0 and n ~= edge then
						table.insert(add, { x, y })
						break
					end
				end
			end
		end
	end
	for _, p in add do PixelGrid.put(g, p[1], p[2], edge) end
end

-- Greedy merge into rectangles: runs along each row, extended down while the rows below repeat
-- them. The same idea as web/src/data/weaponArt.js `merge`.
function PixelGrid.merge(g: Grid): { { number } }
	local used = table.create(g.w * g.h, false)
	local out = {}
	for y = 0, g.h - 1 do
		local x = 0
		while x < g.w do
			local i = y * g.w + x + 1
			local t = g.cells[i]
			if t == 0 or used[i] then
				x += 1
				continue
			end
			local w = 1
			while x + w < g.w and g.cells[i + w] == t and not used[i + w] do w += 1 end
			local h = 1
			while y + h < g.h do
				local ok = true
				for k = 0, w - 1 do
					local j = (y + h) * g.w + x + k + 1
					if g.cells[j] ~= t or used[j] then
						ok = false
						break
					end
				end
				if not ok then break end
				h += 1
			end
			for yy = y, y + h - 1 do
				for k = 0, w - 1 do used[yy * g.w + x + k + 1] = true end
			end
			table.insert(out, { x, y, w, h, t })
			x += w
		end
	end
	return out
end

-- Layered merge: fewer rectangles than `merge` for the same picture, by letting rectangles OVERLAP.
-- A rectangle of a lower layer may cover cells that a higher layer paints over afterwards, so a dark
-- outline becomes its filled silhouette and the bodies drawn on it, where `merge` cuts the outline
-- into a ring of strips. Returned bottom layer first (a sprite draws them in that order). Only
-- tones `opaque(v)` accept may be covered: a translucent cell shows whatever is under it, and an
-- empty one must stay empty, so those are merged on their own and nothing ever overlaps them.
-- The picture is the same ONLY while every rectangle is drawn at full opacity. Overlapping
-- translucent rectangles add up (two at 50% are 75%), so a faded sprite must use `merge`.
function PixelGrid.layers(g: Grid, opaque: (number) -> boolean): { { number } }
	local w, h, cells = g.w, g.h, g.cells
	local rank: { [number]: number } = {}
	local tones = {}
	local hasTranslucent = false
	for i = 1, w * h do
		local v = cells[i]
		if v ~= 0 then
			if not opaque(v) then
				hasTranslucent = true
			elseif not rank[v] then
				rank[v] = 0
				table.insert(tones, v)
			end
		end
	end
	-- lowest value first: in the effect ramps tone 1 is the dark outline and 5 the hot core, and a
	-- drawing interns its colours background first
	table.sort(tones)
	for k, v in tones do rank[v] = k end
	local out = {}
	local covered = table.create(w * h, false)
	for k, tone in tones do
		-- the cells this layer may paint: its own, and any a later layer will paint over
		local function ok(x: number, y: number): boolean
			local v = cells[y * w + x + 1]
			return v == tone or (v ~= 0 and (rank[v] or 0) > k)
		end
		local function rowOk(y: number, x0: number, x1: number): boolean
			for x = x0, x1 do if not ok(x, y) then return false end end
			return true
		end
		local function colOk(x: number, y0: number, y1: number): boolean
			for y = y0, y1 do if not ok(x, y) then return false end end
			return true
		end
		local function gain(x0: number, y0: number, x1: number, y1: number): number
			local n = 0
			for y = y0, y1 do
				for x = x0, x1 do
					local j = y * w + x + 1
					if cells[j] == tone and not covered[j] then n += 1 end
				end
			end
			return n
		end
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local i = y * w + x + 1
				if cells[i] ~= tone or covered[i] then continue end
				-- wide: the longest run through the anchor, then as far down as all of it holds
				local l, r = x, x
				while l > 0 and ok(l - 1, y) do l -= 1 end
				while r + 1 < w and ok(r + 1, y) do r += 1 end
				local d = y
				while d + 1 < h and rowOk(d + 1, l, r) do d += 1 end
				local ax0, ay0, ax1, ay1 = l, y, r, d
				-- tall: the longest column through the anchor, then as far across as all of it holds
				local t, b = y, y
				while t > 0 and ok(x, t - 1) do t -= 1 end
				while b + 1 < h and ok(x, b + 1) do b += 1 end
				local lc, rc = x, x
				while lc > 0 and colOk(lc - 1, t, b) do lc -= 1 end
				while rc + 1 < w and colOk(rc + 1, t, b) do rc += 1 end
				if gain(lc, t, rc, b) > gain(ax0, ay0, ax1, ay1) then ax0, ay0, ax1, ay1 = lc, t, rc, b end
				for yy = ay0, ay1 do
					for xx = ax0, ax1 do
						local j = yy * w + xx + 1
						-- only this layer's own cells are done; the later layers' still need theirs
						if cells[j] == tone then covered[j] = true end
					end
				end
				table.insert(out, { ax0, ay0, ax1 - ax0 + 1, ay1 - ay0 + 1, tone })
			end
		end
	end
	if hasTranslucent then
		local rest = PixelGrid.new(w, h)
		for i = 1, w * h do
			local v = cells[i]
			if v ~= 0 and not opaque(v) then rest.cells[i] = v end
		end
		for _, r in PixelGrid.merge(rest) do table.insert(out, r) end
	end
	return out
end

-- ------------------------------------------------------------------ noise ----
-- Deterministic, so a drawing is the same every time it is generated and a cache key is honest.
local P = 2147483647
function PixelGrid.hash(a: number, b: number, s: number): number
	local h = (math.floor(a) * 7919 + math.floor(b) * 104729 + math.floor(s) * 15485863 + 1013904223) % P
	if h <= 0 then h += P - 1 end
	h = (h * 48271) % P
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 48271) % P
	h = bit32.bxor(h, bit32.rshift(h, 11))
	h = (h * 48271) % P
	return h / P
end

-- Smooth 1D value noise in [0, 1).
function PixelGrid.noise(x: number, s: number): number
	local i = math.floor(x)
	local f = x - i
	local u = f * f * (3 - 2 * f)
	return PixelGrid.hash(i, 0, s) * (1 - u) + PixelGrid.hash(i + 1, 0, s) * u
end

return PixelGrid
