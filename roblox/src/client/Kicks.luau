--!strict
-- Roblox-only presentation: Rocket Boots fight with the legs.
--
-- Every Rocket Boots move is a kick (RobloxWeapons.luau), but the replay-held poses (Channels,
-- WeaponPose) know only weapons held in the hand, so the boots used to throw punches at nothing.
-- This poses the legs instead, on the move's own timing and aimed at its own hitboxes:
--
--   wind-up    the kicking knee chambers - the foot drawn up under the hip
--   active     the leg snaps out along the line from its hip to the hitbox's centre, at full
--              length (or onto the centre, when that is nearer), on exactly the frames Combat
--              counts the box as live (moveFrame + startup - startupEff)
--   recovery   it recoils to the chamber, then sets down into the stance
--
-- The other leg plants (grounded) or tucks (airborne); the arms take a fighter's guard and the rear
-- one counter-swings against the kick. High kicks lean the torso back, sweeps drop the hips. A leg
-- keeps one length (Movement.gait), so the knee folds by exactly what the pose leaves over. Nothing
-- here changes a hitbox, damage or timing: the leg points at the box, it does not move it.
local Movement = require(script.Parent.Movement)
local Kicks = {}

Kicks.WEAPON = "RocketBoots"

-- Which leg kicks: 1 is the near (left) leg, drawn over the body, 2 the far one; "split" both, out
-- to the box's front and back edges; "both" together; "bicycle" one then the other through the
-- active frames; "redline" the ultimate's three windows (forward, reverse, both). `lean` tilts the
-- torso back (radians) for a high kick, `drop` lowers the hips (a fraction of the leg) for a sweep,
-- `axe` lifts the foot overhead in the wind-up and brings it down onto the box.
type Style = { leg: any, lean: number?, drop: number?, axe: boolean? }
Kicks.MOVES = {
	LightNeutral1 = { leg = 1 },                        -- Toe Kick
	LightNeutral2 = { leg = 2, lean = 0.10 },           -- Heel Kick, the other leg
	LightNeutral3 = { leg = 1, lean = 0.25 },           -- Roundhouse
	LightSide1 = { leg = 1, lean = 0.12 },              -- Side Kick
	LightSide2 = { leg = 2, lean = 0.18 },              -- Push Kick
	LightUp = { leg = 1, lean = 0.45 },                 -- Rising Heel
	LightDown = { leg = 1, drop = 0.30 },               -- Low Sweep
	AirNeutral = { leg = "split" },                     -- Spin Kick
	AirForward = { leg = 1, lean = 0.10 },              -- Front Kick
	AirUp = { leg = "bicycle", lean = 0.35 },           -- Bicycle
	AirDown = { leg = "both" },                         -- Stomp
	Finisher = { leg = 1, lean = 0.20, axe = true },    -- Axe Kick
	AirFinisher = { leg = 1, axe = true },              -- Falling Axe
	SigSide = { leg = 1, lean = 0.15 },                 -- Jet Kick
	SigDown = { leg = 1, drop = 0.35 },                 -- Burnout Sweep
	SigNeutral = { leg = 1, lean = 0.50 },              -- Ignition Heel
	Ultimate = { leg = "redline", lean = 0.15 },        -- Redline Reversal
} :: { [string]: Style }
local REDLINE: { any } = { 1, 2, "both" }
-- the stance: the hips' drop (a fraction of the leg) and each foot's step out past its hip, studs
local STANCE, WIDTH = 0.05, 0.35

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

function Kicks.wears(char: any): boolean
	return char.weapon ~= nil and char.weapon.id == Kicks.WEAPON
end

-- The frame Combat judges hitboxes on (Combat.activeHitboxes: moveFrameAbs).
function Kicks.frameAbs(s: any, move: any): number
	local eff = if s.startupEff and s.startupEff > 0 then s.startupEff else move.startup
	return (s.moveFrame or 0) + (move.startup - eff)
end

-- The window that shapes this frame: the one it is in, else the next to come, else the last.
local function window(move: any, fa: number): (any, number)
	local boxes = move.hitboxes or {}
	for i, hb in boxes do
		if fa <= hb.frames[2] then return hb, i end
	end
	return boxes[#boxes], #boxes
end

export type Kick = {
	feet: { any },             -- per leg, as Movement's feet: { x, y, len }, in the posture frame
	active: { boolean },       -- which legs are striking this frame
	dirs: { any },             -- per striking leg, the unit direction it kicks along
	reach: { number },         -- per striking leg, from the foot to the box's far edge, studs
	lean: number, drop: number,-- the torso's tilt back and the hips' drop, already eased
	commit: number,            -- 0-1, how far into the kick the body is (for the arms)
	aim: { number },           -- the unit direction from the hips to the box: what the arms swing against
	ignite: boolean,           -- the first active frames of a move that burns fuel
}

-- `bob` is the body's offset above the feet (the posture frame's origin): the ground is at -bob.
function Kicks.For(s: any, char: any, move: any, bob: number): Kick?
	if not Kicks.wears(char) or s.state ~= "attack" or not move then return nil end
	local style = Kicks.MOVES[move.id]
	local hb, wi = window(move, Kicks.frameAbs(s, move))
	if not style or not hb then return nil end
	local h, r = char.height, char.radius
	local L = Movement.gait(char).leg
	local fa = Kicks.frameAbs(s, move)
	local a, b = hb.frames[1], hb.frames[2]
	local ground = s.onGround == true
	local prevEnd = if wi > 1 then move.hitboxes[wi - 1].frames[2] else 0
	-- the body's commitment: in over the wind-up, out over the recovery
	local commit = smooth(fa / math.max(1, a - 1)) * (1 - smooth((fa - b) / math.max(1, move.total - b)))
	-- a fighting stance sits a little low (a leg is exactly as long as the hips are high, so a
	-- stance any wider than the hips needs the knees to give), and a sweep drops lower still
	-- (grounded, the authored bob is cancelled: the kick's stance owns the body's height)
	local drop = STANCE * L + (style.drop or 0) * L * commit + (if ground then bob else 0)
	local hipY = h * 0.34 - drop
	-- the kicking hip turns into the kick: its socket swings forward as the body commits
	local leg = style.leg
	if leg == "redline" then leg = REDLINE[wi] or 1 end
	local kicks = if type(leg) == "number" then { [leg] = true } else { true, true }
	local root = { -r * 0.30, r * 0.30 }
	for i = 1, 2 do
		if kicks[i] and type(leg) == "number" then root[i] = lerp(root[i], r * 0.30, commit) end
	end
	-- the near (left) leg stands behind, under its own hip, the far one ahead: most kicks come
	-- off the back foot, the hip turning through
	local stance = if ground then { { -r * 0.30 - WIDTH, -bob }, { r * 0.30 + WIDTH, -bob } }
		else { { r * 0.25, hipY - L * 0.70 }, { -r * 0.30, hipY - L * 0.80 } }
	local function hipOf(i: number): (number, number) return root[i], hipY end
	local target = { hb.offset[1], hb.offset[2] - bob }
	-- the full extension of leg i at a point: along the line from its hip, a leg's length out
	local function extend(i: number, tx: number, ty: number): (number, number, number, number)
		local hx, hy = hipOf(i)
		local dx, dy = tx - hx, ty - hy
		local d = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
		local reach = math.min(L * 0.995, d)
		return hx + dx / d * reach, hy + dy / d * reach, dx / d, dy / d
	end
	local function chamber(i: number, ux: number, uy: number): (number, number)
		local hx, hy = hipOf(i)
		if style.axe then return hx + 0.25 * L, hy + 0.85 * L end -- overhead, to come down
		return hx + ux * 0.30 * L, hy - L * 0.45 + math.max(0, uy) * L * 0.30
	end
	-- the phase of the current window: 0 rest .. 1 chambered, then struck, then back
	local function placed(i: number, tx: number, ty: number): (number, number, number, number, boolean)
		local ex, ey, ux, uy = extend(i, tx, ty)
		local cx, cy = chamber(i, ux, uy)
		local sx, sy = stance[i][1], stance[i][2]
		if wi > 1 and fa <= a then sx, sy = cx, cy end -- between windows the leg stays chambered
		if fa < a then
			local k = smooth((fa - prevEnd) / math.max(1, a - 1 - prevEnd))
			return lerp(sx, cx, k), lerp(sy, cy, k), ux, uy, false
		elseif fa <= b then
			return ex, ey, ux, uy, true
		end
		local next = move.hitboxes[wi + 1]
		local span = (if next then next.frames[1] else move.total) - b
		local u = (fa - b) / math.max(1, span)
		if u < 0.35 or next then
			local k = smooth(u / 0.35)
			return lerp(ex, cx, k), lerp(ey, cy, k), ux, uy, false
		end
		local k = smooth((u - 0.35) / 0.65)
		return lerp(cx, sx, k), lerp(cy, sy, k), ux, uy, false
	end
	local out: Kick = { feet = {}, active = { false, false }, dirs = {}, reach = {}, lean = (style.lean or 0) * commit,
		drop = drop, commit = commit, aim = { 1, 0 }, ignite = (move.fuelCost or 0) > 0 and fa >= a and fa <= a + 1 }
	do
		local dx, dy = target[1], target[2] - hipY
		local d = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
		out.aim = { dx / d, dy / d }
	end
	local kicking: { [number]: { number } } = {}
	if leg == "split" then
		local half = hb.size[1] / 2
		kicking[1] = { target[1] + half, target[2] }
		kicking[2] = { target[1] - half, target[2] }
	elseif leg == "both" then
		kicking[1] = { target[1] + 0.2, target[2] }
		kicking[2] = { target[1] - 0.2, target[2] }
	elseif leg == "bicycle" then
		-- the first half of the active frames the near leg, the second the far one
		local second = fa > (a + b) / 2
		kicking[if second then 2 else 1] = target
	else
		kicking[leg :: number] = target
	end
	for i = 1, 2 do
		local t = kicking[i]
		local x, y
		if t then
			local ux, uy, on
			x, y, ux, uy, on = placed(i, t[1], t[2])
			if on then
				out.active[i] = true
				out.dirs[i] = { ux, uy }
				-- from the foot to the box's far side along the kick: what the blast shows (measured
				-- from the box's centre, so a split kick's legs, aimed at its edges, reach them too)
				local far = math.abs(ux) * hb.size[1] / 2 + math.abs(uy) * hb.size[2] / 2
				out.reach[i] = math.max(0, (target[1] - x) * ux + (target[2] - y) * uy + far)
			end
		elseif leg == "bicycle" and fa >= a and fa <= b then
			-- the leg that just kicked, or is about to: chambered, pedalling
			local ux = (target[1] - root[i]) / L
			x, y = chamber(i, math.clamp(ux, -1, 1), 1)
		else
			-- the leg not kicking: planted where it stands, or tucked under in the air
			x, y = stance[i][1], stance[i][2]
		end
		out.feet[i] = { x = x, y = y, len = L, rootX = root[i], rootY = hipY }
	end
	return out
end

-- Wearing the boots, the hands have nothing to hold: in these states the front one keeps a guard
-- up instead of reaching for a weapon that is not there.
local GUARDED = { idle = true, run = true, dash = true, jumpsquat = true, landing = true, air = true, attack = true }
function Kicks.guards(char: any, s: any): boolean
	return Kicks.wears(char) and GUARDED[s.state] == true and not s.tumbling
end

return Kicks
