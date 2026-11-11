--!strict
-- Roblox-only weapon tuning: the design pass (docs/reviews/design-pass.md). The web build is paused
-- (owner, 2026-10-11), so a web weapon's numbers change here, on a copy of the generated data.
-- Data/Weapons itself is never touched. The replays that hold the simulation to the web build their
-- fighters from the untuned roster (Loadout.build's `untuned`), so they keep checking the engine
-- against the web's numbers while the game plays these.
local WeaponTuning = {}
-- the Whip's lash (each light's second box), flattened or not
local LASH = { [2] = { base = 16, growth = 0.4 } }
local LASH20 = { [2] = { base = 16, growth = 0.4, angle = 20 } }

-- [weapon id] = { stats = {...}, mechanic = {...}, moves = { [move id] = { field = value,
-- hitboxes = { [i] = { offset = { x, y }, size = { w, h }, frames = { a, b } } } } } }
--
-- Every key must already exist where it lands, so a misspelt one is an error rather than a change
-- that silently does nothing; a table's `add = { ... }` adds new keys. A move whose startup changes
-- keeps its hitboxes on its active frames: they move with it unless the patch gives their frames.
-- A move whose active window changes must give them. `total` is recomputed, as the web derives it.
-- Each entry names the review round that asked for it.
WeaponTuning.FOR = {
	-- Weapons round 2, from round 1's review (docs/reviews/weapons-round1-review.md).
	-- Runebrand made 158 of the Grimoire's 194 KOs: a 41-stud projectile launching 122 at 100%. At
	-- 12/28/3.6 it launches 86. (The review measured the Grimoire falling from 82% to 69%. Cutting
	-- its range, its startup or the weight barely moved it.)
	Grimoire = { moves = { SigSide = { damage = 12, base = 28, growth = 3.6 } } },
	-- Reaper's Arc's handle half launched 124 to the tip's 128, so spacing for the tip paid nothing.
	-- The handle now hits soft and reaches less (launch 66), and the tip is the reward (73% -> 64%).
	Scythe = { moves = { SigSide = { hitboxes = { [2] = { offset = { 3.6, 2.8 }, size = { 5.8, 3.6 },
		add = { damage = 11, base = 22, growth = 3.0 } } } } } },
	-- The Blasters could not finish a stock: 0.86 KOs a game, the median KO at 157%. Its chip shots
	-- hit for one more, and Scattergun, its honest finisher, launches 146 at 100% (was 132).
	Blasters = { moves = { LightNeutral1 = { damage = 3 }, LightNeutral2 = { damage = 4 }, LightSide1 = { damage = 4 },
		SigDown = { base = 34, growth = 6.4 } } },
	-- The Whip had no close game: the lash (each light's second box) did 2 damage and launched 7 at
	-- 100%, so anyone inside the tip was safe. The lash now shoves them out to the tip's distance
	-- (launch 17, flatter; measured 10% -> 19%). The up and down lashes keep their angles.
	Whip = { moves = {
		-- (round 3) Bullwhip Snap, the Whip's most-pressed move, took 16 frames to start: 12 (the
		-- review measured 12% -> 18%; its boxes move with it)
		SigSide = { startup = 12 },
		LightNeutral1 = { hitboxes = LASH20 }, LightNeutral2 = { hitboxes = LASH20 }, LightNeutral3 = { hitboxes = LASH20 },
		LightSide1 = { hitboxes = LASH20 }, LightSide2 = { hitboxes = LASH20 },
		LightUp = { hitboxes = LASH }, LightDown = { hitboxes = LASH },
	} },
	-- "The lightest, fastest fighter in the game" was the Daggers (weight 72 to 78, run 1.261 to
	-- 1.196). Three jumps to two (measured 76% -> 70%).
	-- Weapons round 3, from round 2's review. The Pike was drawn up to 3.7 studs longer than its
	-- boxes reach: the art said one thing and the hit another, on the roster's spacer, at 34%. Its
	-- boxes now reach its drawn tip (LightUp and Pike Wall upward, LightDown forward, Spin Guard
	-- round both sides).
	Pike = { moves = {
		LightUp = { hitboxes = { { offset = { 1.4, 7.2 }, size = { 1.8, 9.2 } } } },
		LightDown = { hitboxes = { { offset = { 5.45, 0.9 }, size = { 8.7, 1.6 } } } },
		SigNeutral = { hitboxes = { { offset = { 2.2, 6.9 }, size = { 3.0, 12.0 } } } },
		AirNeutral = { hitboxes = { { size = { 12.4, 5.0 } } } },
	} },
	-- "The slowest, heaviest weapon in the game" was the Hammer's claim, and the Hammer's numbers
	-- (weight 125 to 118, run 0.748 to 0.82).
	Axe = { blurb = "A two-handed axe that drags on the floor between swings. Every heavy is a lift and a drop rather than a swing: gravity does the work." },
	-- (Round 3 tried the jab and the hook a frame slower, which round 2's review suggested, after
	-- jumps and damage moved them from the top little or nothing: 79% in a 56-game spot check
	-- against 77%, so not that either.)
	Gauntlets = { stats = { set = { jumps = 2 } },
		blurb = "Steel fists and the shortest reach in the game: live in their face. Land four hits in a row and Overdrive makes everything faster still." },
} :: { [string]: any }

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
