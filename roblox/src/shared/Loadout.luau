--!strict
-- A loadout is an avatar (cosmetic) plus a weapon (everything that matters), composed into exactly
-- the shape the engine expects from a character. Ported from web/src/data/loadout.js.
--
-- The point of this indirection is that the engine never learns weapons exist: Fighter, Combat and
-- Match read a character, and the weapon system is pure data composed on top. Keeping that split
-- here is what makes the rest of the port a straight translation.

local Avatars = require(script.Parent.Data.Avatars)
local Weapons = require(script.Parent.Weapons)
local AvatarKit = require(script.Parent.AvatarKit)

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

-- A preset id or a kit code (AvatarKit), exactly as web/src/data/avatars.js resolves them. A kit
-- code is its own complete description, which is what lets every client draw a character it has
-- never seen. The browser's localStorage characters are not here: Roblox saves kit codes instead.
function Loadout.avatarById(id: string?): any
	if id and Avatars.BY_ID[id] then
		return Avatars.BY_ID[id]
	end
	return AvatarKit.avatar(id) or Avatars.BY_ID[Avatars.DEFAULT_ID]
end

-- The kit code an avatar id is drawn as - a preset's (the presets are kit characters under their old
-- ids) or a kit code itself - or nil. avatars.js kitCodeOf.
function Loadout.kitCodeOf(id: string?): string?
	local a = Loadout.avatarById(id)
	return if a and a.kit then a.code else nil
end

-- The avatar id a server will accept from a client: a preset id as it is, a kit code in its
-- canonical form, anything else nil.
function Loadout.validAvatar(id: any): string?
	if type(id) ~= "string" then
		return nil
	end
	if Avatars.BY_ID[id] then
		return id
	end
	return AvatarKit.canonical(id)
end

function Loadout.build(avatarId: string?, weaponId: string?): any
	local avatar = Loadout.avatarById(avatarId)
	-- "Fists" is the unarmed kit, built like any weapon but never listed as one (Data/Weapons).
	local weapon = if weaponId == Weapons.FISTS.id then Weapons.FISTS
		else (if weaponId then Weapons.BY_ID[weaponId] else nil) or Weapons.BY_ID[Weapons.DEFAULT_ID]
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

-- A fighter for a match with weapon drops: the two weapons they carry and the fists they hold
-- between them, all on one body. `char` is what they start with - the fists.
function Loadout.buildArmed(avatarId: string?, weaponIds: { string }): any
	local kit = { Loadout.build(avatarId, weaponIds[1]), Loadout.build(avatarId, weaponIds[2] or weaponIds[1]) }
	local fists = Loadout.build(avatarId, Weapons.FISTS.id)
	return { char = fists, kit = kit, fists = fists }
end
return Loadout
