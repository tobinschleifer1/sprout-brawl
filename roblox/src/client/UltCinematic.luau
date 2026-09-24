--!strict
-- The ultimate's cutscene beat, ported from web/src/render2d/ultCinematic.js - read that file for
-- the design. Pure, driven only by frames since activation; tests/cinematic-parity.luau holds it
-- to the JavaScript frame by frame.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local UltCinematic = {}
UltCinematic.FREEZE = Config.ULTIMATE.freezeFrames
UltCinematic.INVINCIBLE = Config.ULTIMATE.invincibleFrames
UltCinematic.BAND = { ["in"] = 6, hold = 12, out = 6 }
UltCinematic.ZOOM = 1.35
UltCinematic.DIM = 0.65

local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end
local function easeOut(k: number): number
	return 1 - (1 - k) * (1 - k)
end

-- Whether an ultimate's cutscene is finished with, so its record can be dropped. NOT the same as
-- "not active": this client draws a few frames behind its newest snapshot, so the event always
-- arrives while the drawn frame is still short of it - elapsed is negative - and dropping the record
-- then meant the cutscene never showed at all (found in Studio). Only the far side ends it.
function UltCinematic.over(elapsed: number): boolean
	return elapsed >= math.max(UltCinematic.FREEZE, UltCinematic.INVINCIBLE)
end

function UltCinematic.at(elapsed: number): any
	local e = elapsed
	local FREEZE, INV, B = UltCinematic.FREEZE, UltCinematic.INVINCIBLE, UltCinematic.BAND
	if not (e >= 0) or e >= FREEZE then
		return { active = false, dim = 0, zoom = 1, slide = 1, band = 0, glow = e >= 0 and e < INV }
	end
	local dim = UltCinematic.DIM * math.min(clamp(e / 4, 0, 1), clamp((FREEZE - e) / 4, 0, 1))
	local zoom = 1 + (UltCinematic.ZOOM - 1) * math.min(easeOut(clamp(e / 8, 0, 1)), clamp((FREEZE - e) / 4, 0, 1))
	local outAt = B["in"] + B.hold
	local slide, band
	if e < B["in"] then
		slide, band = -1 + easeOut(e / B["in"]), e / B["in"]
	elseif e < outAt then
		slide, band = 0, 1
	else
		local k = clamp((e - outAt) / B.out, 0, 1)
		slide, band = k * k, 1 - k
	end
	return { active = true, dim = dim, zoom = zoom, slide = slide, band = band, glow = e < INV }
end

function UltCinematic.punch(x: number, y: number, ppu: number, fx: number, fy: number, zoom: number): any
	local k = (zoom - 1) / (UltCinematic.ZOOM - 1)
	return { x = x + (fx - x) * k, y = y + (fy - y) * k, ppu = ppu * zoom }
end

UltCinematic.GOLD = "#FFD45A"
local function shape(...: any): { any }
	return { ... }
end
function UltCinematic.glowShapes(c: any, fx: number, fy: number, h: number): { any }
	if not c.glow then
		return {}
	end
	local cy = fy + h * 0.5
	return {
		shape("e", fx, cy, h * 0.62, h * 0.72, UltCinematic.GOLD, 0.30),
		shape("e", fx, cy, h * 0.46, h * 0.60, UltCinematic.GOLD, 0.55),
		shape("e", fx, cy, h * 0.34, h * 0.52, "#FFF4C8", 0.45),
	}
end

UltCinematic.TILT = -0.14
function UltCinematic.bannerLayout(c: any, W: number, H: number): any
	if not c.active or c.band <= 0 then
		return nil
	end
	local h = math.min(H, W * 0.5625) * 0.17
	local cx, cy = W / 2 + c.slide * W * 1.15, H * 0.40
	local cos, sin = math.cos(UltCinematic.TILT), math.sin(UltCinematic.TILT)
	local function along(d: number, n: number?): (number, number)
		local nn = n or 0
		return cx + cos * d - sin * nn, cy + sin * d + cos * nn
	end
	local px, py = along(-h * 2.1, h * 0.5)
	local wx, wy = along(-h * 0.9)
	local tx, ty = along(h * 1.6)
	return {
		cx = cx, cy = cy, w = W * 1.6, h = h, rot = UltCinematic.TILT, alpha = c.band, stripe = h * 0.1,
		portrait = { x = px, y = py, size = h * 1.3 },
		weapon = { x = wx, y = wy, size = h * 0.85 },
		text = { x = tx, y = ty, size = h * 0.42 },
	}
end

return UltCinematic
