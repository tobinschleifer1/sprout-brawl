--!strict
-- What a disaster looks like, ported from web/src/render2d/disasterShapes.js - read that file for the
-- design. Pure: the same view gives the same shape list in both builds, and
-- tests/disaster-shapes.luau replays the JavaScript's lists to prove it.
--
-- Shapes: { "r", x, y, w, h, colour, alpha } (bottom-left, world y up) or
--         { "e", cx, cy, rx, ry, colour, alpha }.
local DisasterShapes = {}

local COOL, HOT, WHITE = "#7FD4FF", "#F08B60", "#FFFFFF"
DisasterShapes.COOL, DisasterShapes.HOT = COOL, HOT

local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end
local function pulse(frame: number, period: number): number
	return 0.5 - 0.5 * math.cos((frame % period) / period * math.pi * 2)
end
-- Shapes mix strings and numbers, which the analyser will not infer from a table literal, so they
-- are built through a varargs constructor.
local function S(...: any): { any }
	return { ... }
end
local function add(out: { any }, shape: { any })
	table.insert(out, shape)
end
local function span(stage: any): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, s in stage.solids do
		lo, hi = math.min(lo, s.x1), math.max(hi, s.x2)
	end
	return lo, hi
end
local function dashes(out: { any }, x1: number, x2: number, y: number, colour: string, alpha: number)
	local x = x1
	while x < x2 do
		add(out, S("r", x, y - 0.12, math.min(1, x2 - x), 0.24, colour, alpha))
		x += 2
	end
end

local DRAW: { [string]: (out: { any }, v: any, stage: any) -> () } = {}

DRAW.lavasurge = function(out, v, stage)
	local lo, hi = span(stage)
	local warn = v.phase == "warn"
	dashes(out, lo - 8, hi + 8, v.line, COOL, if warn then 0.5 + 0.5 * pulse(v.frame, 30) else 0.35)
	if v.level > stage.blast.bottom then
		local bottom = stage.blast.bottom - 5
		add(out, S("r", lo - 40, bottom, hi - lo + 80, v.level - bottom, "#8A2A12", 0.92))
		add(out, S("r", lo - 40, v.level - 1.2, hi - lo + 80, 1.2, "#C0461E", 1))
		add(out, S("r", lo - 40, v.level - 0.4, hi - lo + 80, 0.4, "#FF9A3C", 1))
		for i = 0, 8 do
			local x = lo + ((i * 11.3 + v.frame * 0.15) % (hi - lo))
			add(out, S("e", x, v.level - 0.2, 0.45, 0.3, "#FFE0A0", 0.5 + 0.5 * pulse(v.frame + i * 7, 40)))
		end
	end
end

DRAW.lightning = function(out, v)
	for _, s in v.strikes or {} do
		if s.live then
			add(out, S("r", s.x - 0.8, s.y, 1.6, 60, COOL, 0.45))
			add(out, S("r", s.x - 0.3, s.y, 0.6, 60, WHITE, 1))
			add(out, S("e", s.x, s.y + 0.2, 3.2, 0.8, HOT, 0.9))
		else
			add(out, S("e", s.x, s.y + 0.1, 2.5, 0.5, COOL, 0.25 + 0.35 * pulse(v.frame, 20)))
			add(out, S("e", s.x, s.y + 0.1, 0.6, 0.18, COOL, 0.9))
		end
	end
end

DRAW.tornado = function(out, v)
	local k = if v.phase == "warn" then v.k elseif v.phase == "after" then 1 - v.k else 1
	for i = 0, 7 do
		local u = i / 7
		local r = v.radiusFloor + (v.radiusTop - v.radiusFloor) * u
		local sway = math.sin((v.frame * 0.2) + i * 0.9) * 0.6 * u
		add(out, S("e", v.x + sway, v.floor + u * v.height, r, 0.9, "#C9A87A", 0.18 + 0.22 * k))
	end
	if v.phase == "warn" then
		add(out, S("r", v.x - 0.2, v.floor, 0.4, v.height, COOL, 0.5 * v.k))
	end
end

DRAW.tsunami = function(out, v, stage)
	local lo, hi = span(stage)
	if v.phase == "warn" then
		add(out, S("r", lo - 40, v.base, hi - lo + 80, v.k * 2, COOL, 0.35))
		local edge = if v.dir > 0 then lo - 6 else hi + 6
		for i = 0, 2 do
			add(out, S("r", edge + v.dir * i * 1.2, v.crest * 0.5 - i, 1, 2 * i + 1, COOL, 0.5 + 0.5 * pulse(v.frame, 24)))
		end
		return
	end
	local fade = if v.phase == "after" then 1 - v.k else 1
	local back = if v.dir > 0 then stage.blast.left else v.x
	local front = if v.dir > 0 then v.x else stage.blast.right
	add(out, S("r", back, v.base, math.max(0, front - back), v.crest * 0.5, "#2F7A8A", 0.55 * fade))
	if v.phase == "strike" then
		add(out, S("r", v.x - v.width / 2, v.base, v.width, v.crest - v.base, "#59D9F2", 0.95))
		add(out, S("r", v.x - v.width / 2, v.crest - 0.6, v.width, 0.6, WHITE, 0.9))
	end
end

DRAW.earthquake = function(out, v)
	local seam = if v.phase == "warn" then 0.4 + 0.6 * pulse(v.frame, 16) else 0.8
	local plates = v.plates or {}
	for _, p in plates do
		add(out, S("r", p.x1 - 0.2, p.top - 3, 0.4, 3, HOT, seam))
		add(out, S("r", p.x2 - 0.2, p.top - 3, 0.4, 3, HOT, seam))
		if v.phase ~= "warn" then
			add(out, S("r", p.x1, p.top - 0.3, p.x2 - p.x1, 0.3, HOT, 0.35))
		end
	end
	if #plates == 0 and v.phase == "warn" then
		add(out, S("r", -200, -0.4, 400, 0.4, COOL, 0.3 + 0.4 * pulse(v.frame, 10)))
	end
end

DRAW.meteor = function(out, v)
	for _, r in v.rocks or {} do
		if r.shadow > 0 then
			add(out, S("e", r.x, r.y + 0.1, 0.6 + 4.4 * r.shadow, 0.4 + 0.5 * r.shadow, "#000000", 0.45))
			add(out, S("e", r.x, r.y + 0.1, 5, 0.9, COOL, 0.3 * r.shadow))
			local h = 40 * (1 - r.shadow)
			add(out, S("e", r.x - h * 0.3, r.y + h, 1.1, 1.1, "#FFE0A0", clamp(r.shadow * 1.5, 0, 1)))
			add(out, S("r", r.x - h * 0.3 - 0.3, r.y + h, 0.6, 6, HOT, 0.6 * r.shadow))
		end
		if r.live then
			add(out, S("e", r.x, r.y + 1, 5, 4, HOT, 0.85))
		end
		if r.burning then
			add(out, S("e", r.x, r.y + 0.1, 3, 0.5, "#1A0E08", 0.9))
			add(out, S("e", r.x, r.y + 0.3, 1.2, 0.3, HOT, 0.6 + 0.4 * pulse(v.frame, 12)))
		end
	end
end

function DisasterShapes.shapes(view: any, stage: any): { any }
	local out = {}
	if not view or not DRAW[view.type] then
		return out
	end
	DRAW[view.type](out, view, stage)
	return out
end

local NAMES = { lavasurge = "LAVA SURGE", lightning = "LIGHTNING STORM", tornado = "TORNADO",
	tsunami = "TSUNAMI", earthquake = "EARTHQUAKE", meteor = "METEOR SHOWER" }
function DisasterShapes.banner(view: any): any
	if not view or not NAMES[view.type] or view.phase == "after" then
		return nil
	end
	local name = if view.type == "earthquake" and #(view.plates or {}) == 0 then "TREMOR" else NAMES[view.type]
	if view.phase == "warn" then
		return { text = `{name} INCOMING`, colour = COOL, seconds = math.ceil(math.max(0, view.warn - view.frame) / 60) }
	end
	return { text = name, colour = HOT, seconds = nil }
end

return DisasterShapes
