--!strict
-- The jointed rig, Rig.luau against web/src/render2d/rig.js: every joint, end and bone length the
-- JavaScript solved (tools/gen-rig-fixture.mjs), replayed. Then the properties a parity check cannot
-- see - two builds can agree on a hand that misses its grip - asserted on the Luau directly.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Rig = Loader.loadFrom("src/client/", "Rig")

local T = serde.decode("json", fs.readFile("tests/rig-fixture.json"))
local checked = 0
local function same(a: number, b: number, where: string)
	assert(math.abs(a - b) <= 1e-12 * math.max(1, math.abs(b)), `{where}: Luau {a}, JS {b}`)
	checked += 1
end
for k, v in T.rig do
	same((Rig.RIG :: any)[k], v, `RIG.{k}`)
end
local function compare(got: any, want: any, where: string)
	for _, k in { "jx", "jy", "ex", "ey", "len" } do
		same(got[k], want[k], `{where}.{k}`)
	end
end
for i, c in T.arms do
	local a = c["in"]
	compare(Rig.armPose(a[1], a[2], a[3], a[4], a[5], a[6]), c.out, `arm {i}`)
end
for i, c in T.legs do
	local a = c["in"]
	compare(Rig.legPose(a[1], a[2], a[3], a[4], a[5], a[6], a[7]), c.out, `leg {i}`)
end
print(`rig: {checked} joint values across {#T.arms} arms and {#T.legs} legs match the web`)

-- Properties.
local function dist(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
local worstGrip, worstBone = 0, 0
for _, c in T.arms do
	local a = c["in"]
	local L = Rig.armPose(a[1], a[2], a[3], a[4], a[5], a[6])
	-- the hand is the grip: exactly the one-piece arm's end, shoulder + direction x 0.30h x ext
	local gx = a[1] + math.cos(a[3]) * a[6] * 0.30 * a[4]
	local gy = a[2] + math.sin(a[3]) * a[6] * 0.30 * a[4]
	worstGrip = math.max(worstGrip, dist(L.ex, L.ey, gx, gy))
	-- both bones are drawn at the length they span: the joint is where the upper ends and the lower starts
	worstBone = math.max(worstBone, math.abs(dist(a[1], a[2], L.jx, L.jy) - L.len), math.abs(dist(L.jx, L.jy, L.ex, L.ey) - L.len))
	-- an elbow bends down (clockwise of the arm): for an arm pointing forward, the elbow is below it
	if math.abs(a[3]) < 1e-9 and a[4] < 1 then
		assert(L.jy < a[2] - 1e-6, "a forward arm's elbow is not below the line to the hand")
	end
end
assert(worstGrip < 1e-9, `a hand missed its grip by {worstGrip} studs`)
local feet, knees = 0, 0
for _, c in T.legs do
	local a = c["in"]
	local L = Rig.legPose(a[1], a[2], a[3], a[4], a[5], a[6], a[7])
	worstBone = math.max(worstBone, math.abs(dist(a[1], a[2], L.jx, L.jy) - L.len), math.abs(dist(L.jx, L.jy, L.ex, L.ey) - L.len))
	-- a planted, untucked foot within reach is exactly where the one-piece leg's foot was, minus the bob
	if a[6] and a[7] == 0 then
		local fx = a[1] - math.sin(a[3]) * a[4]
		local fy = a[2] - math.cos(a[3]) * a[4] - a[5]
		if dist(a[1], a[2], fx, fy) <= 2 * a[4] * Rig.RIG.legBone then
			assert(dist(L.ex, L.ey, fx, fy) < 1e-9, `a planted foot moved: ({L.ex}, {L.ey}) against ({fx}, {fy})`)
			feet += 1
		end
	end
	-- a knee bends forward: for a leg hanging straight down, the knee is in front of the hip-foot line
	if a[3] == 0 and math.abs(L.ex - a[1]) < 1e-9 and dist(a[1], a[2], L.ex, L.ey) < 2 * a[4] * Rig.RIG.legBone - 1e-6 then
		assert(L.jx > a[1] + 1e-6, "a knee bent backwards")
		knees += 1
	end
end
assert(worstBone < 1e-9, `a bone is drawn {worstBone} studs off the length it spans`)
assert(feet > 50 and knees >= 3, `too few cases reached the foot and knee checks ({feet}, {knees})`)
print(`PASS rig: hands exactly on the grip, joints where both bones meet, {feet} planted feet unmoved, knees forward, elbows down`)
