--!strict
-- Roblox-only presentation: weapons that come in pairs are held one in each hand.
--
-- The web draws a pair (Twinfang's two daggers, two rivet guns, two rings) as one picture in the
-- front hand. Here each hand holds one, the way two-handed weapons work in platform fighters such
-- as Brawlhalla: strings alternate hands (jab, cross, both), uppercuts and lunges come from the
-- rear hand, spins and finishers use both, and whichever hand is not striking guards, then
-- chambers back toward the hip while the other one hits.
--
-- Nothing here changes a hitbox, damage or timing. WeaponPose (replay-held) still poses THE weapon:
-- its angle and grip are where the move's hitboxes are. The striking hand takes exactly that pose,
-- so what hits is still what is drawn; this module only decides which hand that is, and where the
-- other hand and its weapon go. A back-hand strike twists the torso, bringing the rear shoulder
-- forward so the rear arm can reach the same point.
local DualWield = {}

-- The weapons held one in each hand.
DualWield.PAIRED = { Daggers = true, Blasters = true, Gauntlets = true, Chakram = true } :: { [string]: boolean }

-- Which hand carries the move's pose. Moves not listed strike with the front hand.
local STRIKE: { [string]: string } = {
	LightNeutral1 = "front", LightNeutral2 = "back", LightNeutral3 = "both",
	LightSide1 = "front", LightSide2 = "back",
	LightUp = "back", LightDown = "front",
	AirNeutral = "both", AirForward = "front", AirUp = "back", AirDown = "both",
	Finisher = "both", AirFinisher = "both",
	SigSide = "back", SigDown = "both", SigNeutral = "both",
	Ultimate = "both",
}
DualWield.STRIKE = STRIKE

-- The hand that is not striking: its arm angle and reach (as WeaponPose's grip uses them: 0 is
-- forward, positive up, reach a fraction of the full arm) and its weapon's angle. GUARD is ready,
-- CHAMBER is pulled back toward the hip while the other hand strikes. `bend` is the elbow's, degrees.
type HandPose = { arm: number, ext: number, angle: number, bend: number }
local GUARD: { [string]: HandPose } = {
	Daggers = { arm = -0.45, ext = 0.70, angle = 0.55, bend = 12 },   -- low and forward, blade up
	Blasters = { arm = -0.20, ext = 0.85, angle = 0.0, bend = 8 },   -- levelled
	Gauntlets = { arm = 0.35, ext = 0.55, angle = 0.65, bend = 50 },  -- fist up by the chin
	Chakram = { arm = -0.55, ext = 0.70, angle = 0.0, bend = 12 },
}
local CHAMBER: { [string]: HandPose } = {
	Daggers = { arm = -2.15, ext = 0.55, angle = -2.75, bend = 40 },  -- reversed along the forearm
	Blasters = { arm = -2.00, ext = 0.55, angle = -1.35, bend = 40 }, -- muzzle down
	Gauntlets = { arm = -1.95, ext = 0.50, angle = -0.90, bend = 55 },-- fist at the hip
	Chakram = { arm = -2.10, ext = 0.55, angle = 0.0, bend = 40 },
}
DualWield.GUARD, DualWield.CHAMBER = GUARD, CHAMBER

-- Where a both-hands move puts the second weapon: behind and below the first, in the torso's
-- frame (studs, scaled by the fighter's radius and height), turned a little off it.
local BOTH = { dx = -0.40, dy = -0.045, turn = -0.18 }
-- The torso twist of a full back-hand strike: shoulder x shifts, in fractions of the radius.
DualWield.TWIST = { back = 1.0, front = -0.45 }

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function DualWield.paired(char: any): boolean
	return char.weapon ~= nil and DualWield.PAIRED[char.weapon.id] == true
end

-- How committed the body is to the move's strike: rising over the first frames, held, and falling
-- away over the last six, so the off hand chambers and the torso twists in and back out.
local function commit(s: any, move: any): number
	if s.state ~= "attack" or not move then return 0 end
	local mf, total = s.moveFrame or 0, move.total or 1
	return smooth(mf / 4) * (1 - smooth((mf - (total - 6)) / 6))
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

export type Off = { hand: string, x: number, y: number, angle: number, empty: boolean, bend: number }
export type Dual = {
	striker: string,           -- "front", "back" or "both": which hand carries the move's pose
	twist: number,             -- 0-1, the back-hand strike's torso twist
	units: number,             -- weapons in hand: 2, or a Chakram's rings left
	-- the other weapon, nil when there is none in hand: the hand holding it ("front"/"back"), its
	-- grip in the torso frame (before lean and squash, as Posture.torsoPoint takes it), its angle;
	-- `empty` when that hand has nothing in it (a Chakram with one ring out)
	off: Off?,
}

-- A shoulder in the torso frame, with the twist applied: the same points Posture hangs the arms
-- from (it adds the chest's own bend on top).
function DualWield.shoulder(char: any, hand: string, twist: number): (number, number)
	local r, h = char.radius, char.height
	if hand == "front" then return r * 0.55 + DualWield.TWIST.front * r * twist, h * 0.36 end
	return -r * 0.65 + DualWield.TWIST.back * r * twist, h * 0.36
end
local function grip(char: any, hand: string, twist: number, p: HandPose): (number, number)
	local sx, sy = DualWield.shoulder(char, hand, twist)
	local reach = char.height * 0.30 * p.ext
	return sx + math.cos(p.arm) * reach, sy + math.sin(p.arm) * reach
end

-- `wpose` is WeaponPose's pose of the weapon; `hx`/`hy` its grip in the torso frame (before lean
-- and squash), exactly where Posture puts the striking hand.
function DualWield.For(s: any, char: any, move: any, wpose: any, hx: number, hy: number): Dual?
	if not DualWield.paired(char) then return nil end
	local wid = char.weapon.id
	local units = 2
	if wid == "Chakram" then units = math.clamp(s.rings or 2, 0, 2) end
	local attacking = s.state == "attack" and move ~= nil
	local striker = if attacking then (STRIKE[move.id] or "front") else "front"
	-- one ring left: it is in the striking hand, the other hand is empty; none left, and the arms
	-- are left as the single-weapon pose has them
	if (units < 2 and striker == "both") or units == 0 then striker = "front" end
	local k = commit(s, move)
	local twist = if striker == "back" then k else 0
	local d: Dual = { striker = striker, twist = twist, units = units, off = nil }
	if units == 0 or wpose.hide then
		return d
	end
	local g, c = GUARD[wid], CHAMBER[wid]
	if striker == "both" then
		-- the second weapon follows the first, behind and below it, eased in from its guard as the
		-- move commits
		local r, h = char.radius, char.height
		local gx, gy = grip(char, "back", 0, g)
		d.off = { hand = "back", x = lerp(gx, hx + BOTH.dx * r, k), y = lerp(gy, hy + BOTH.dy * h, k),
			angle = lerp(g.angle, wpose.angle + BOTH.turn, k), empty = false, bend = lerp(g.bend, 20, k) }
		return d
	end
	local pose = { arm = lerp(g.arm, c.arm, k), ext = lerp(g.ext, c.ext, k), angle = lerp(g.angle, c.angle, k), bend = lerp(g.bend, c.bend, k) }
	local hand = if striker == "back" then "front" else "back"
	local x, y = grip(char, hand, twist, pose)
	d.off = { hand = hand, x = x, y = y, angle = pose.angle, empty = units < 2, bend = pose.bend }
	return d
end

return DualWield
