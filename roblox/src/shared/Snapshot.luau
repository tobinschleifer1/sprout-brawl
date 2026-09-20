--!strict
-- The fighter snapshot: what the server sends and what the client draws.
--
-- This exists because the short wire names leaked. The snapshot used to be encoded inline in
-- MatchService and read inline in the client, and when the format changed the camera was updated
-- and the rigs were not - `s.facing` against a field called `fc` is nil, and nil is not an error
-- until something compares it. Rigs drew with no facing, no tumble and no KO hiding, and the only
-- symptom was one line in the console.
--
-- So encode and decode live together, the wire names exist nowhere else, and everything downstream
-- of `decode` reads the same long names the simulation uses. Adding a field is one edit in FIELDS.
--
-- Short names on the wire are not premature: this is 60 messages a second times the roster, and
-- `invincible` costs ten bytes more than `inv` every single frame of every match.

local Snapshot = {}

-- { simulation name, wire name }. The order is not meaningful; the pairing is.
local FIELDS = {
	{ "index", "i" },
	{ "x", "x" }, { "y", "y" }, { "vx", "vx" }, { "vy", "vy" },
	{ "facing", "fc" },
	{ "state", "st" }, { "stateFrame", "sf" }, { "moveFrame", "mf" }, { "moveId", "mv" },
	{ "percent", "pc" }, { "stocks", "sk" }, { "shield", "sh" }, { "ultCharge", "ult" },
	{ "alive", "al" }, { "onGround", "gr" }, { "tumbling", "tb" }, { "invincible", "inv" },
	{ "item", "it" },
	-- Everything below is read by render2d/channels.js and by nothing else in the client. A pose is
	-- not derivable from position and a state name: the same `attack` state looks different on the
	-- startup frames than the active ones, and startupEff is the boundary between them.
	{ "startupEff", "se" }, { "frameCount", "fn" }, { "charge", "cg" }, { "hitlag", "hl" },
	{ "fastFalling", "ff" }, { "ultCooldown", "uc" }, { "techRoll", "tr" },
	-- Read by render2d/weapons2d.js only: Deadeye counts its rounds on the rifle.
	{ "ultShots", "us" },
	-- Flattened, not nested. channels.js reads exactly one leaf out of each of these, and sending
	-- the objects would put a timer and a ledge reference on the wire 60 times a second to deliver
	-- one integer and one string.
	{ "chillStacks", "cs" }, { "ledgeAction", "la" },
}

-- The fields a snapshot carries, by the name everything except the wire uses. Exported so a test
-- can assert the decoded shape rather than trusting that a reader spotted a missing line.
Snapshot.FIELDS = FIELDS

-- Fighter fields whose name differs from the snapshot's. The rest are read straight off the fighter.
local FROM_FIGHTER: { [string]: string } = {
	stateFrame = "sf", moveFrame = "mf",
}

function Snapshot.encode(f: any): { [string]: any }
	local out = {}
	for _, pair in FIELDS do
		local name, wire = pair[1], pair[2]
		if name == "item" then
			-- The item is a live object with a hitbox and a timer on it. Only its identity crosses.
			out[wire] = if f.item then f.item.id else nil
		elseif name == "chillStacks" then
			out[wire] = f.effects.chill.stacks
		elseif name == "ledgeAction" then
			-- `la` is { kind, L }; L is the ledge the fighter is on, which the client already knows
			-- from the stage. Only the kind changes the pose.
			out[wire] = if f.la then f.la.kind else nil
		else
			out[wire] = f[FROM_FIGHTER[name] or name]
		end
	end
	return out
end

function Snapshot.decode(w: { [string]: any }): { [string]: any }
	local out = {}
	for _, pair in FIELDS do
		out[pair[1]] = w[pair[2]]
	end
	return out
end

-- Fields that may be interpolated between two snapshots. Everything absent from this list is
-- discrete - a state name, a percent, a move id - and interpolating it would produce a value the
-- simulation never held.
Snapshot.CONTINUOUS = { "x", "y" }

return Snapshot
