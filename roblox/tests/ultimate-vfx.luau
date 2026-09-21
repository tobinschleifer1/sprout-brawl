--!strict
-- Exercise the complete weapon draw at a representative windup, active and recovery frame for
-- all twelve ultimates, then make the VFX-only pass prove it is not merely leaning on the weapon
-- underneath. Canvas2D's primitives are instrumented here: one rect/circle is one pooled Frame and
-- `tri` is the six Frames its real implementation uses.
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

-- Instrument the exact primitive table UltimateVfx and Weapons2D loaded. This avoids inventing a
-- second drawing API in the shipping module while still counting the Frames Canvas2D would claim.
Canvas2D.save = function(c: any)
	c.stack += 1
end
Canvas2D.restore = function(c: any)
	c.stack -= 1
	if c.stack < 0 then
		fail("Canvas2D restore underflow")
	end
end
Canvas2D.translate = function(_c: any, _x: number, _y: number) end
Canvas2D.rotate = function(_c: any, _angle: number) end
Canvas2D.scale = function(_c: any, _x: number, _y: number) end
Canvas2D.rect = function(c: any, _x: number, _y: number, _w: number, _h: number,
	_colour: any, _alpha: number?)
	c.used += 1
end
Canvas2D.circle = function(c: any, _x: number, _y: number, _radius: number,
	_colour: any, _alpha: number?)
	c.used += 1
end
Canvas2D.ellipse = function(c: any, _x: number, _y: number, _rx: number, _ry: number,
	_colour: any, _alpha: number?)
	c.used += 1
end
Canvas2D.tri = function(c: any, _x0: number, _y0: number, _x1: number, _y1: number,
	_x2: number, _y2: number, _colour: any, _alpha: number?)
	c.used += 6
end

local WEAPONS = {
	"Sword", "Scythe", "Blasters", "Grimoire", "Axe", "Pike",
	"Gauntlets", "Hammer", "Longbow", "Flail", "Shield", "Daggers",
}

local function canvas(): any
	return { used = 0, stack = 0, alpha = 1 }
end

local function snapshot(move: any, frame: number): any
	return {
		index = 1, state = "attack", stateFrame = frame, moveFrame = frame,
		moveId = "Ultimate", startupEff = move.startup, charge = 0,
		vx = 0, onGround = true, ultCooldown = 0, ultShots = 3,
	}
end

local checked = 0
local peakFrames, peakWhere = 0, ""
local peakVfx, peakVfxWhere = 0, ""
local effectFrames: { [string]: number } = {}

for _, weaponId in WEAPONS do
	local char = Loadout.build("Classic", weaponId)
	local move = char.moves.Ultimate
	if not move then
		fail(`{weaponId} has no Ultimate move`)
	end
	local phaseFrames = {
		{ name = "windup", frame = math.max(1, math.floor(move.startup / 2)) },
		{ name = "active", frame = move.startup + 1 },
		{ name = "end", frame = move.startup + move.active + math.max(1, math.floor(move.recovery / 2)) },
	}

	for _, phase in phaseFrames do
		local s = snapshot(move, phase.frame)
		local pose = WeaponPose.For(s, char, move, 1.25)
		if not pose.ult or pose.ult.phase ~= phase.name then
			fail(`{weaponId}/{phase.name}: WeaponPose produced phase {tostring(pose.ult and pose.ult.phase)}`)
		end

		-- The same layer order as Fighter2D: effects behind, weapon, muzzle/cast flash in front.
		local full = canvas()
		local ok, err = pcall(function()
			UltimateVfx.drawUltimate(full, weaponId, char.weaponPalette, pose, 1.25)
			Weapons2D.draw(full, weaponId, char.weaponPalette, pose)
			UltimateVfx.drawMuzzle(full, weaponId, char.weaponPalette, pose, 1.25)
		end)
		if not ok then
			fail(`{weaponId}/{phase.name}: draw errored: {tostring(err)}`)
		end
		if full.stack ~= 0 then
			fail(`{weaponId}/{phase.name}: transform stack ended at {full.stack}`)
		end
		if full.used == 0 then
			fail(`{weaponId}/{phase.name}: draw claimed no Frames`)
		end
		if full.used > peakFrames then
			peakFrames, peakWhere = full.used, `{weaponId}/{phase.name}`
		end

		-- Count only the new module as well. Without this, deleting both VFX functions would still
		-- pass because the ordinary weapon underneath draws Frames of its own.
		local vfx = canvas()
		UltimateVfx.drawUltimate(vfx, weaponId, char.weaponPalette, pose, 1.25)
		UltimateVfx.drawMuzzle(vfx, weaponId, char.weaponPalette, pose, 1.25)
		if vfx.stack ~= 0 then
			fail(`{weaponId}/{phase.name}: VFX transform stack ended at {vfx.stack}`)
		end
		effectFrames[weaponId] = (effectFrames[weaponId] or 0) + vfx.used
		if vfx.used > peakVfx then
			peakVfx, peakVfxWhere = vfx.used, `{weaponId}/{phase.name}`
		end
		checked += 1
	end
end

-- These are the weapons for which the JavaScript source paints something outside the weapon body
-- in at least one sampled phase. Longbow enters through generic drawMuzzle; the other five weapon
-- ultimates are deliberately carried by their pose/weapon silhouette in the source of truth.
for _, weaponId in { "Sword", "Scythe", "Blasters", "Grimoire", "Axe", "Pike", "Longbow" } do
	if (effectFrames[weaponId] or 0) == 0 then
		fail(`{weaponId}: the VFX module drew no Frames in any phase`)
	end
end

-- Zero is falsy in the JavaScript and truthy in Luau. A resting pose must not accidentally emit a
-- full muzzle burst just because the direct translation said `if pose.flash then`.
local quiet = canvas()
UltimateVfx.drawUltimate(quiet, "Blasters", {}, { ult = nil, flash = 0 }, 0)
UltimateVfx.drawMuzzle(quiet, "Blasters", {}, { angle = 0, ox = 0, oy = 0, flash = 0 }, 0)
if quiet.used ~= 0 then
	fail(`zero flash/no ultimate claimed {quiet.used} Frames`)
end

print(`checked {checked} ultimate phase draws across all twelve weapons`)
print(`peak complete weapon draw: {peakFrames} Frames at {peakWhere}`)
print(`peak added ultimate VFX: {peakVfx} Frames at {peakVfxWhere}`)
