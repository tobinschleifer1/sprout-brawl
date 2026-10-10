--!strict
-- The weapon half of every ultimate (UltimateVfx), drawn at a windup, active and recovery frame of
-- all twelve, through Canvas2D's REAL transform arithmetic with the drawing primitives recorded:
-- one rect/circle/ellipse is one pooled Frame, `tri` is the six its real implementation uses, and a
-- sprite (an FxArt effect, the weapon itself) is one container Frame.
--
-- What it holds:
--   * every weapon draws an effect of its own in its ultimate, inside a Frame budget;
--   * nothing is drawn outside the ultimate, and a zero flash draws no muzzle burst;
--   * the effects are attached to the fighter - mirrored with them, near the hand;
--   * every spinning effect is drawn from a frame a Frame can represent. The hand's frame carries
--     the torso's squash and stretch, and a sprite rotated under a non-uniform scale would need a
--     shear - which a Frame cannot do, so it would be drawn skewed.
--
--     lune run tests/ultimate-vfx

local Loader = require("./loader")

local Loadout = Loader.load("Loadout")
local Canvas2D = Loader.loadFrom("src/client/", "Canvas2D")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")
local UltimateVfx = Loader.loadFrom("src/client/", "UltimateVfx")

local function fail(msg: string): never
	error(msg, 0)
end

-- Records every draw with the matrix it was made under. Transforms are Canvas2D's own.
local calls: { any } = {}
local function record(c: any, kind: string, frames: number, key: string?)
	local m = c.m
	c.used += frames
	table.insert(calls, { kind = kind, key = key, a = m.a, b = m.b, c = m.c, d = m.d, e = m.e, f = m.f })
end
Canvas2D.rect = function(c: any, x: number, y: number, w: number, h: number, _colour: any, _alpha: number?)
	for _, v in { x, y, w, h } do
		if v ~= v or math.abs(v) == math.huge then fail("non-finite rect geometry") end
	end
	record(c, "rect", 1)
end
Canvas2D.circle = function(c: any, _x: number, _y: number, _r: number, _colour: any, _alpha: number?) record(c, "circle", 1) end
Canvas2D.ellipse = function(c: any, _x: number, _y: number, _rx: number, _ry: number, _colour: any, _alpha: number?) record(c, "ellipse", 1) end
Canvas2D.tri = function(c: any, _x0: number, _y0: number, _x1: number, _y1: number, _x2: number, _y2: number,
	_colour: any, _alpha: number?)
	record(c, "tri", 6)
end
Canvas2D.sprite = function(c: any, key: string, rects: { any }, x0: number, y1: number, pw: number, ph: number,
	cols: number, rows: number, _alpha: number?)
	if #rects == 0 then fail("a sprite with no rectangles") end
	-- the sprite's centre, in the space the transform maps to
	local m = c.m
	local cx, cy = x0 + cols * pw / 2, y1 - rows * ph / 2
	record(c, "sprite", 1, key)
	calls[#calls].x = m.a * cx + m.c * cy + m.e
	calls[#calls].y = m.b * cx + m.d * cy + m.f
end

local WEAPONS = {
	"Sword", "Scythe", "Blasters", "Grimoire", "Axe", "Pike",
	"Gauntlets", "Hammer", "Longbow", "Flail", "Shield", "Daggers", "Whip",
}
-- The most Frames the weapon-side effects may claim on one fighter in one frame. Measured peak is
-- printed below; this is the ceiling, not the target.
local VFX_BUDGET = 60

local function canvas(sx: number?, sy: number?): any
	local c = { used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 } }
	setmetatable(c, { __index = Canvas2D })
	-- the world flips y, as Canvas2D.world does; the fighter's facing and squash on top of it
	Canvas2D.setTransform(c, 20, 0, 0, -20, 400, 300)
	Canvas2D.scale(c, sx or 1, sy or 1)
	return c
end

local function snapshot(move: any, frame: number): any
	return {
		index = 1, state = "attack", stateFrame = frame, moveFrame = frame,
		moveId = "Ultimate", startupEff = move.startup, charge = 0,
		vx = 0, onGround = true, ultCooldown = 0, ultShots = 3,
	}
end

local function draw(c: any, weaponId: string, char: any, pose: any)
	UltimateVfx.drawUltimate(c, weaponId, char.weaponPalette, pose, 1.25)
	UltimateVfx.drawMuzzle(c, weaponId, char.weaponPalette, pose, 1.25)
end

local checked, peakVfx, peakWhere = 0, 0, ""
local drew: { [string]: number } = {}
local similar = 0
for _, weaponId in WEAPONS do
	local char = Loadout.build("Classic", weaponId)
	local move = char.moves.Ultimate or fail(`{weaponId} has no Ultimate move`)
	local frames = {
		{ name = "windup", frame = math.max(1, math.floor(move.startup * 0.7)) },
		{ name = "active", frame = move.startup + 1 },
		{ name = "active", frame = move.startup + math.floor(move.active * 0.6) },
		{ name = "end", frame = move.startup + move.active + math.max(1, math.floor(move.recovery / 2)) },
	}
	for _, phase in frames do
		local pose = WeaponPose.For(snapshot(move, phase.frame), char, move, 1.25)
		if not pose.ult or pose.ult.phase ~= phase.name then
			fail(`{weaponId}/{phase.name}: WeaponPose produced phase {tostring(pose.ult and pose.ult.phase)}`)
		end
		-- Facing right, unsquashed; then facing left; then squashed as a heavy landing squashes.
		table.clear(calls)
		local right = canvas()
		local ok, err = pcall(draw, right, weaponId, char, pose)
		if not ok then fail(`{weaponId}/{phase.name}: draw errored: {tostring(err)}`) end
		if #right.stack ~= 0 then fail(`{weaponId}/{phase.name}: transform stack ended at {#right.stack}`) end
		local rightCalls = table.clone(calls)
		drew[weaponId] = (drew[weaponId] or 0) + right.used
		if right.used > VFX_BUDGET then fail(`{weaponId}/{phase.name}: {right.used} Frames, over the {VFX_BUDGET} budget`) end
		if right.used > peakVfx then peakVfx, peakWhere = right.used, `{weaponId}/{phase.name}@{phase.frame}` end

		table.clear(calls)
		local left = canvas(-1, 1)
		draw(left, weaponId, char, pose)
		if left.used ~= right.used then fail(`{weaponId}/{phase.name}: facing left drew {left.used} Frames, right {right.used}`) end
		for i, r in rightCalls do
			local l = calls[i]
			if r.kind == "sprite" then
				-- mirrored about the fighter: x reflects through the origin's screen x, y is unchanged
				if math.abs((l.x - 400) + (r.x - 400)) > 1e-6 or math.abs(l.y - r.y) > 1e-6 then
					fail(`{weaponId}/{phase.name}: {r.key} is not mirrored with the fighter ({r.x},{r.y}) vs ({l.x},{l.y})`)
				end
				-- attached: within a few weapon-lengths of the hand, not somewhere across the stage
				if math.sqrt((r.x - 400) ^ 2 + (r.y - 300) ^ 2) > 20 * 16 then
					fail(`{weaponId}/{phase.name}: {r.key} drawn {r.x},{r.y}, far from the hand`)
				end
			end
		end

		table.clear(calls)
		local squashed = canvas(1.3, 0.75)
		draw(squashed, weaponId, char, pose)
		for _, r in calls do
			if r.kind == "sprite" and r.key and not string.find(r.key, "^weapon") and (string.find(r.key, "|rune|") or
				string.find(r.key, "|swirl|") or string.find(r.key, "|pop|") or string.find(r.key, "|xslash|") or string.find(r.key, "|orb|")) then
				-- a similarity: orthogonal columns of equal length - something a Frame can be
				local dot = r.a * r.c + r.b * r.d
				local la, lc = r.a * r.a + r.b * r.b, r.c * r.c + r.d * r.d
				if math.abs(dot) > 1e-6 * la or math.abs(la - lc) > 1e-6 * la then
					fail(`{weaponId}/{phase.name}: {r.key} is drawn skewed under the torso's squash`)
				end
				similar += 1
			end
		end
		checked += 1
	end
end

-- Every weapon's ultimate puts effects of its own on the weapon in at least one sampled phase.
for _, weaponId in WEAPONS do
	if (drew[weaponId] or 0) == 0 then
		fail(`{weaponId}: the ultimate drew no weapon effects in any phase`)
	end
end
if similar == 0 then fail("no spinning effect was checked for skew") end

-- Zero is falsy in the JavaScript and truthy in Luau. A resting pose must not emit a muzzle burst
-- because `if pose.flash` was translated literally, and no ultimate means no ultimate effects.
local quiet = canvas()
UltimateVfx.drawUltimate(quiet, "Blasters", {}, { ult = nil, flash = 0 }, 0)
UltimateVfx.drawMuzzle(quiet, "Blasters", {}, { angle = 0, ox = 0, oy = 0, flash = 0 }, 0)
if quiet.used ~= 0 then
	fail(`zero flash/no ultimate claimed {quiet.used} Frames`)
end
-- and a live flash does draw one
local flash = canvas()
UltimateVfx.drawMuzzle(flash, "Blasters", {}, { angle = 0, ox = 0, oy = 0, flash = 1 }, 0)
if flash.used == 0 then fail("a full muzzle flash drew nothing") end

-- The weapon itself, awakened, alongside: the full weapon-and-effects draw still balances.
local full = canvas()
local char = Loadout.build("Classic", "Sword")
local pose = WeaponPose.For(snapshot(char.moves.Ultimate, char.moves.Ultimate.startup - 2), char, char.moves.Ultimate, 1)
UltimateVfx.drawUltimate(full, "Sword", char.weaponPalette, pose, 1)
Weapons2D.draw(full, "Sword", char.weaponPalette, pose)
if #full.stack ~= 0 then fail("the full sword draw left the stack unbalanced") end

print(`checked {checked} ultimate draws across every weapon, facing both ways and squashed`)
print(`{similar} spinning effects drawn without skew; peak weapon-side effects: {peakVfx} Frames at {peakWhere} (budget {VFX_BUDGET})`)
