--!strict
-- Replay the JavaScript's animation channels through the Luau port and report the first pose that
-- differs.
--
--     lune run tests/channel-parity
--
-- The probes are DATA, carried in tests/trace-channels.json alongside the outputs, so this harness
-- and tools/gen-channel-traces.mjs cannot drift apart and quietly test different things.
--
-- Reading channels.js and Channels.luau side by side does not catch a flipped comparison, an
-- easing curve applied to the wrong phase, or the 1-indexing shift in the chill tint table. Every
-- one of those is a pose that still renders, still animates, and is simply wrong - which is the
-- class of bug this whole folder exists to make impossible.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")

local Loadout = Loader.load("Loadout")
local Channels = Loader.loadFrom("src/client/", "Channels")

local function fail(msg: string): never
	error(msg, 0)
end

local trace = serde.decode("json", fs.readFile("tests/trace-channels.json"))
local CHANNELS: { string } = trace.channels

-- The same relative tolerance the rest of the folder uses. These are trigonometry and exponentials
-- rather than sums, so the last bit or two is allowed to differ; anything structural is orders of
-- magnitude larger than this.
local TOL = 1e-12

local function near(a: number, b: number): boolean
	if a == b then
		return true
	end
	local scale = math.max(math.abs(a), math.abs(b))
	return math.abs(a - b) <= TOL * math.max(1, scale)
end

-- The channel bag is nested; the trace flattens it. Same split on both sides.
local function pick(ch: any, key: string): number
	local dot = string.find(key, ".", 1, true)
	if dot then
		return ch[string.sub(key, 1, dot - 1)][string.sub(key, dot + 1)]
	end
	return ch[key]
end

local chars: { [string]: any } = {}
local function charFor(avatar: string, weapon: string): any
	local key = avatar .. "/" .. weapon
	if not chars[key] then
		chars[key] = Loadout.build(avatar, weapon)
	end
	return chars[key]
end

local checked = 0
local states: { [string]: boolean } = {}
local weapons: { [string]: boolean } = {}

for i, p in trace.probes do
	local char = charFor(p.avatar, p.weapon)
	-- Exactly the table Snapshot.decode produces: no char, no move. Those are arguments, because
	-- they are not on the wire and a harness that quietly supplies them tests a shape that never
	-- reaches the renderer.
	local f = {
		index = p.index,
		x = tonumber(p.x), y = tonumber(p.y),
		vx = tonumber(p.vx), vy = tonumber(p.vy),
		facing = tonumber(p.facing),
		state = p.state,
		stateFrame = tonumber(p.sf), moveFrame = tonumber(p.mf),
		moveId = p.moveId,
		startupEff = tonumber(p.startupEff), frameCount = tonumber(p.frameCount),
		charge = tonumber(p.charge), hitlag = tonumber(p.hitlag),
		fastFalling = p.fastFalling, ultCooldown = tonumber(p.ultCooldown),
		techRoll = tonumber(p.techRoll), onGround = p.onGround, tumbling = p.tumbling,
		invincible = tonumber(p.invincible), shield = tonumber(p.shield),
		percent = tonumber(p.percent), stocks = tonumber(p.stocks),
		ultCharge = tonumber(p.ultCharge), alive = p.alive,
		-- The two the wire flattens. Everything past Snapshot.decode reads them like this.
		chillStacks = tonumber(p.chillStacks),
		ledgeAction = p.ledgeAction,
	}
	local move = if p.moveId then char.moves[p.moveId] else nil
	local ch = Channels.For(f, char, move, tonumber(p.t))
	local want = trace.outputs[i]

	for _, key in CHANNELS do
		local got = pick(ch, key)
		local expect = tonumber(want[key])
		if type(got) ~= "number" or got ~= got then
			fail(`probe {i} ({p.state}/{p.weapon}/{tostring(p.moveId)}): channel {key} is {tostring(got)}`)
		end
		if not near(got, expect) then
			fail(`probe {i} ({p.state}/{p.weapon}/{tostring(p.moveId)} mf={p.mf} t={p.t}): `
				.. `{key} = {got}, JavaScript says {expect}`)
		end
		checked += 1
	end

	-- tint is a colour or nothing, and visible is a boolean. Neither is a number, and both change
	-- what is drawn, so both are compared rather than skipped.
	local tint = if ch.tint == nil then "" else ch.tint
	if tint ~= want.tint then
		fail(`probe {i} ({p.state}/{p.weapon}): tint = "{tint}", JavaScript says "{want.tint}"`)
	end
	if ch.visible ~= want.visible then
		fail(`probe {i} ({p.state}/{p.weapon}): visible = {tostring(ch.visible)}, `
			.. `JavaScript says {tostring(want.visible)}`)
	end
	checked += 2
	states[p.state] = true
	weapons[p.weapon] = true
end

local ns, nw = 0, 0
for _ in states do ns += 1 end
for _ in weapons do nw += 1 end
print(`replayed {checked} channel values across {#trace.probes} poses, {ns} states, {nw} weapons`)
print("Channels.luau matches web/src/render2d/channels.js exactly.")
