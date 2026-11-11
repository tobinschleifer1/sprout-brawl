--!strict
-- Roblox-only weapon tuning: the design pass (docs/reviews/design-pass.md). The web build is paused
-- (owner, 2026-10-11), so a web weapon's numbers change here, on a copy of the generated data.
-- Data/Weapons itself is never touched. The replays that hold the simulation to the web build their
-- fighters from the untuned roster (Loadout.build's `untuned`), so they keep checking the engine
-- against the web's numbers while the game plays these.
local WeaponTuning = {}

-- [weapon id] = { stats = {...}, mechanic = {...}, moves = { [move id] = { field = value,
-- hitboxes = { [i] = { offset = { x, y }, size = { w, h }, frames = { a, b } } } } } }
--
-- Every key must already exist where it lands, so a misspelt one is an error rather than a change
-- that silently does nothing; a table's `add = { ... }` adds new keys. A move whose startup changes
-- keeps its hitboxes on its active frames: they move with it unless the patch gives their frames.
-- A move whose active window changes must give them. `total` is recomputed, as the web derives it.
-- Each entry names the review round that asked for it.
WeaponTuning.FOR = {} :: { [string]: any }

local function copy(v: any): any
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = copy(x) end
	return out
end
WeaponTuning.copy = copy

-- a list of numbers (an offset, a size, a frame range) is replaced whole, not merged
local function numbers(v: any): boolean
	if type(v) ~= "table" or #v == 0 then return false end
	for _, x in v do if type(x) ~= "number" then return false end end
	return true
end

local function merge(target: any, patch: any, path: string)
	for k, v in patch do
		if k == "add" then
			for nk, nv in v do target[nk] = copy(nv) end
		elseif target[k] == nil then
			error(`weapon tuning: {path}.{tostring(k)} does not exist (use add = to add it)`)
		elseif type(v) == "table" and type(target[k]) == "table" and not numbers(v) then
			merge(target[k], v, `{path}.{tostring(k)}`)
		else
			target[k] = copy(v)
		end
	end
end

local function tuneMove(move: any, patch: any, path: string)
	local startup, active = move.startup, move.active
	merge(move, patch, path)
	local shift = (move.startup or 0) - (startup or 0)
	local given = patch.hitboxes or {}
	for i, hb in move.hitboxes or {} do
		local mine = given[i]
		if not (mine and mine.frames) then
			if move.active ~= active then
				error(`weapon tuning: {path} changes its active frames, so hitbox {i} must give its frames`)
			end
			if shift ~= 0 and hb.frames then hb.frames = { hb.frames[1] + shift, hb.frames[2] + shift } end
		end
	end
	if move.startup and move.active and move.recovery then
		move.total = move.startup + move.active + move.recovery
	end
end

-- A tuned copy of `weapon`; the weapon passed in is left exactly as it was.
function WeaponTuning.apply(weapon: any, patch: any): any
	local out = copy(weapon)
	for k, v in patch do
		if k == "moves" then
			for id, mp in v do
				if not out.moves[id] then error(`weapon tuning: {weapon.id} has no move {tostring(id)}`) end
				tuneMove(out.moves[id], mp, `{weapon.id}.moves.{tostring(id)}`)
			end
		else
			merge(out, { [k] = v }, weapon.id)
		end
	end
	return out
end

return WeaponTuning
