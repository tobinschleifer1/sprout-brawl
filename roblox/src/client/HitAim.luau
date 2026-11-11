--!strict
-- Roblox-only presentation: while a melee move is live, the arm and its weapon point at what the
-- move actually hits. The weapons review, round 1 (docs/reviews/weapons-round1-review.md), found
-- the drawn blade and the live hitbox disagreeing on 155 of 216 melee moves, the blade a median 16
-- degrees below its box. The authored swing (WeaponPose, held to the web by replay) is untouched;
-- this bends it toward the box over the move's active frames, from the first one (the windup is
-- the move's telegraph, and easing in over the last frames of startup turned it forward early) and
-- out over the first EASE_OUT of recovery. The hitboxes do not move.
local Posture = require(script.Parent.Posture)
local HitAim = {}
HitAim.EASE_IN, HitAim.EASE_OUT = 1, 4

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Which moves aim: a weapon's melee moves with hitboxes. Not ultimates (their own staging), not
-- projectiles, beams, slams or vortices (what hits is not the thing in the hand), and not the
-- Rocket Boots, whose kicks already strike along their boxes (Kicks).
function HitAim.aims(char: any, move: any): boolean
	if not move or not char.weapon or char.weapon.id == "RocketBoots" then return false end
	if move.id == "Ultimate" or (move.kind or "melee") ~= "melee" then return false end
	return move.hitboxes ~= nil and #move.hitboxes > 0
end

-- The frame the hitboxes are written in: a move's startup can run short (a link, a charge), and
-- the boxes keep their authored frames (Combat reads moveFrameAbs).
function HitAim.absFrame(s: any, move: any): number
	return (s.moveFrame or 0) + (move.startup - (s.startupEff or move.startup))
end

-- How much the aim applies now (0-1), and the box it aims at: the largest one live on the move's
-- nearest active frame.
function HitAim.target(s: any, move: any): (number, any?)
	local lo, hi = math.huge, -math.huge
	for _, hb in move.hitboxes do
		lo, hi = math.min(lo, hb.frames[1]), math.max(hi, hb.frames[2])
	end
	local a = HitAim.absFrame(s, move)
	local w = if a < lo then smooth((a - (lo - HitAim.EASE_IN)) / HitAim.EASE_IN)
		elseif a > hi then 1 - smooth((a - hi) / HitAim.EASE_OUT) else 1
	if w <= 0 then return 0, nil end
	local at = math.clamp(a, lo, hi)
	local best, bestArea, bestGap = nil, -1, math.huge
	for _, hb in move.hitboxes do
		-- live on that frame, or (a gap between hits) the nearest in time
		local gap = math.max(0, hb.frames[1] - at, at - hb.frames[2])
		local area = hb.size[1] * hb.size[2]
		if gap < bestGap or (gap == bestGap and area > bestArea) then best, bestArea, bestGap = hb, area, gap end
	end
	return w, best
end

-- `wpose` aimed (a copy; the one passed in is untouched), or nil when nothing changes. The angle is
-- in WeaponPose's frame, which the torso's lean turns: the world direction is angle - lean.
function HitAim.apply(s: any, char: any, move: any, ch: any, wpose: any, reach: number): any?
	if s.state ~= "attack" or not HitAim.aims(char, move) or wpose.hide or wpose.emote then return nil end
	local w, hb = HitAim.target(s, move)
	if not hb then return nil end
	local h, r = char.height, char.radius
	local sx, sy = Posture.torsoPoint(ch, h, r * 0.55, h * 0.36)
	local cx, cy = hb.offset[1], hb.offset[2]
	local aim = math.atan2(cy - sy, cx - sx) + ch.lean
	local turn = w * wrap(aim - wpose.angle)
	local out: any = table.clone(wpose)
	out.angle = wpose.angle + turn
	if wpose.trail then
		-- the swing's trail turns with the blade, and its leading end reaches the box's far edge (it
		-- was drawn the blade's length, short of boxes that reach well past it)
		local trail: any = table.clone(wpose.trail)
		trail.from = wpose.trail.from + turn
		trail.to = wpose.trail.to + turn
		out.trail = trail
		local dx, dy = math.cos(aim - ch.lean), math.sin(aim - ch.lean)
		local far = 0
		for _, k in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			far = math.max(far, (cx + k[1] * hb.size[1] / 2 - sx) * dx + (cy + k[2] * hb.size[2] / 2 - sy) * dy)
		end
		local drawn = reach * (wpose.scale or 1)
		out.trailFar = drawn + w * math.max(0, far - drawn)
	end
	return out
end

return HitAim
