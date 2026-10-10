--!strict
-- The jointed rig: where elbows and knees go. A line-for-line port of web/src/render2d/rig.js,
-- replayed against it by tests/rig-parity.luau - read that file for the why.
--
-- Two equal bones between a root and an end; the joint on the perpendicular bisector, so nothing is
-- divided. The hand is the weapon's grip, exactly: the arm is solved to meet it, never the reverse.

local Rig = {}

Rig.RIG = {
	hip = 0.34, shoulder = 0.70, head = 0.78,
	arm = 0.30,
	armBone = 0.155,
	armBend = 0.06,
	legBone = 0.515,
	tuck = 0.45,
}
local RIG = Rig.RIG

export type Limb = { jx: number, jy: number, ex: number, ey: number, len: number }

-- `side` +1: the joint clockwise of the limb (an elbow); -1: anticlockwise (a knee).
function Rig.solveLimb(sx: number, sy: number, ux: number, uy: number, d: number, bone: number, side: number): Limb
	local half = d / 2
	local off = math.sqrt(math.max(0, bone * bone - half * half)) * side
	return {
		jx = sx + ux * half + uy * off, jy = sy + uy * half - ux * off,
		ex = sx + ux * d, ey = sy + uy * d,
		len = math.max(bone, half),
	}
end

function Rig.armPose(sx: number, sy: number, ang: number, ext: number, bend: number, h: number): Limb
	local bone = h * (RIG.armBone + RIG.armBend * bend)
	return Rig.solveLimb(sx, sy, math.cos(ang), math.sin(ang), h * RIG.arm * ext, bone, 1)
end

function Rig.legPose(hx: number, hy: number, rot: number, ll: number, bob: number, planted: boolean, tuck: number): Limb
	local dx0, dy0 = -math.sin(rot), -math.cos(rot)
	local fx = hx + dx0 * ll
	local fy = hy + dy0 * ll - (if planted then bob else 0)
	local vx, vy = fx - hx, fy - hy
	local k = 1 - RIG.tuck * math.max(0, math.min(1, tuck))
	vx *= k
	vy *= k
	local d = math.sqrt(vx * vx + vy * vy)
	-- a foot exactly at the hip has no direction of its own; it keeps the leg's
	local ux = if d > 1e-9 then vx / d else dx0
	local uy = if d > 1e-9 then vy / d else dy0
	return Rig.solveLimb(hx, hy, ux, uy, d, ll * RIG.legBone, -1)
end

return Rig
