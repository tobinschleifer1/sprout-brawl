--!strict
-- A loadout is an avatar (cosmetic) plus a weapon (everything that matters), composed into exactly
-- the shape the engine expects from a character. Ported from web/src/data/loadout.js.
--
-- The point of this indirection is that the engine never learns weapons exist: Fighter, Combat and
-- Match read a character, and the weapon system is pure data composed on top. Keeping that split
-- here is what makes the rest of the port a straight translation.

local Avatars = require(script.Parent.Data.Avatars)
local Weapons = require(script.Parent.Data.Weapons)

local Loadout = {}

local STAT_KEYS = { "weight", "runSpeed", "walkSpeed", "airSpeed", "jumps", "jumpVelocity",
	"fallSpeed", "height", "radius" }

-- Stat spread comes only from the weapon:
--   stats.set  absolute overrides    { weight = 96 }
--   stats.mul  multipliers on BASE   { runSpeed = 0.97 }
function Loadout.applyStats(weapon: any): { [string]: number }
	local s = weapon.stats or {}
	local out = table.clone(Avatars.BASE)
	for _, k in STAT_KEYS do
		if s.mul and s.mul[k] ~= nil then
			out[k] = out[k] * s.mul[k]
		end
		if s.set and s.set[k] ~= nil then
			out[k] = s.set[k]
		end
	end
	-- math.round is NOT JavaScript's Math.round: Luau rounds halves away from zero, JS rounds them
	-- toward +infinity, so the two disagree at -2.5. Identical here only because jumps is always
	-- positive. Anything ported later that rounds a value which can go negative needs
	-- math.floor(x + 0.5) instead.
	out.jumps = math.max(1, math.round(out.jumps))
	return out
end

function Loadout.avatarById(id: string?): any
	-- Presets only for now. web/src/data/avatars.js also resolves player-made characters through a
	-- runtime registry, which is part of the character-creator question and not ported yet.
	return (if id then Avatars.BY_ID[id] else nil) or Avatars.BY_ID[Avatars.DEFAULT_ID]
end

function Loadout.build(avatarId: string?, weaponId: string?): any
	local avatar = Loadout.avatarById(avatarId)
	local weapon = (if weaponId then Weapons.BY_ID[weaponId] else nil) or Weapons.BY_ID[Weapons.DEFAULT_ID]

	local out = Loadout.applyStats(weapon) :: any
	out.id = `{avatar.id}:{weapon.id}`
	out.name = weapon.name              -- the HUD names the weapon; the avatar is who you look like
	out.avatar = avatar
	out.weapon = weapon
	out.archetype = weapon.archetype
	out.tagline = weapon.tagline
	out.bio = weapon.blurb
	out.palette = avatar.palette        -- body colours
	out.weaponPalette = weapon.palette  -- weapon mesh + trail colours
	out.trail = weapon.trail
	out.rig = avatar.rig
	out.recovery = weapon.recovery
	out.mechanic = weapon.mechanic
	out.signature = weapon.signature
	out.moves = weapon.moves            -- shared by reference: move tables are read-only at runtime
	return out
end

return Loadout
