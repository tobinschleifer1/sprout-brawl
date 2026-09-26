--!strict
-- A stage as a map-select thumbnail, ported from web/src/render2d/stageThumb.js - read that file.
-- Pure: a list of { "r", x, y, w, h, colour, alpha } in the thumbnail's own pixels, y down.
local StageThumb = {}

local function px(v: number): number
	return math.floor(v + 0.5)
end
local function shape(...: any): { any }
	return { ... }
end

function StageThumb.extent(stage: any): (number, number, number, number)
	local x0, x1, y0, y1 = stage.main.x1, stage.main.x2, stage.main.y - stage.main.thickness, stage.main.y
	for _, p in stage.platforms do
		local mx = if p.moving then p.moving.x else nil
		local lo = if mx then math.min(mx.from, mx.to) else p.x
		local hi = if mx then math.max(mx.from, mx.to) else p.x
		x0, x1 = math.min(x0, lo - p.w / 2), math.max(x1, hi + p.w / 2)
		local my = if p.moving then p.moving.y else nil
		y1 = math.max(y1, if my then math.max(my.from, my.to) else p.y)
		y0 = math.min(y0, p.y - (p.thickness or (if p.solid then 5 else 1)))
	end
	return x0 - 4, x1 + 4, y0 - 2, y1 + 6
end

function StageThumb.shapes(stage: any, w: number, h: number): { any }
	local out = {}
	local pal = stage.palette or {}
	local function R(x: number, y: number, rw: number, rh: number, colour: string, alpha: number?)
		local a, b = px(x), px(y)
		local c, d = px(x + rw), px(y + rh)
		if c > a and d > b then table.insert(out, shape("r", a, b, c - a, d - b, colour, alpha or 1)) end
	end
	local stops = if pal.skyStops and #pal.skyStops > 1 then pal.skyStops
		else { { 0, pal.sky or "#8295AD" }, { 1, pal.sky or "#8295AD" } }
	for i = 1, #stops - 1 do
		R(0, stops[i][1] * h, w, (stops[i + 1][1] - stops[i][1]) * h, stops[i][2])
	end
	local x0, x1, y0, y1 = StageThumb.extent(stage)
	local ppu = math.min(w / (x1 - x0), h / (y1 - y0))
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local function X(x: number): number return w / 2 + (x - cx) * ppu end
	local function Y(y: number): number return h / 2 - (y - cy) * ppu end
	local ground, top = pal.ground or "#3E4450", pal.groundTop or "#8A94A6"
	local shelf, accent = pal.platform or "#6E7788", pal.accent or "#EBAD50"
	local function solid(a: number, b: number, topY: number, thick: number, ledges: any)
		R(X(a), Y(topY), (b - a) * ppu, thick * ppu, ground)
		R(X(a), Y(topY), (b - a) * ppu, math.max(1, ppu * 0.8), top)
		if ledges ~= false then
			R(X(a), Y(topY), math.max(1, ppu * 0.9), math.max(2, ppu * 2), accent)
			R(X(b) - math.max(1, ppu * 0.9), Y(topY), math.max(1, ppu * 0.9), math.max(2, ppu * 2), accent)
		end
	end
	local m = stage.main
	solid(m.x1, m.x2, m.y, m.thickness, m.ledges)
	for _, p in stage.platforms do
		if p.solid then
			solid(p.x - p.w / 2, p.x + p.w / 2, p.y, p.thickness or 5, p.ledges)
		else
			local mx = if p.moving then p.moving.x else nil
			if mx then
				local lo, hi = math.min(mx.from, mx.to), math.max(mx.from, mx.to)
				R(X(lo - p.w / 2), Y(p.y), (hi - lo + p.w) * ppu, math.max(1, ppu * 0.4), shelf, 0.35)
			end
			R(X(p.x - p.w / 2), Y(p.y), p.w * ppu, math.max(1, (p.thickness or 1) * ppu), shelf)
		end
	end
	return out
end

function StageThumb.random(w: number, h: number): { any }
	local out = { shape("r", 0, 0, w, h, "#1B2531", 1) }
	local s = math.floor(math.min(w, h) * 0.56)
	local x, y = math.floor((w - s) / 2), math.floor((h - s) / 2)
	table.insert(out, shape("r", x, y, s, s, "#E9E5DB", 1))
	local d = math.max(2, math.floor(s * 0.16))
	for _, uv in { { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.5, 0.5 }, { 0.25, 0.75 }, { 0.75, 0.75 } } do
		table.insert(out, shape("r", math.floor(x + s * uv[1] - d / 2), math.floor(y + s * uv[2] - d / 2), d, d, "#101721", 1))
	end
	return out
end

return StageThumb
