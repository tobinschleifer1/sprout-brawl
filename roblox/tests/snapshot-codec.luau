--!strict
-- Fight snapshots on the wire (shared/SnapshotCodec), against real fights: four CPU fighters on
-- every stage, with items and disasters, snapshots built exactly as MatchService builds them. Every
-- keyframe and every delta decodes to exactly the table it was made from - every field, nil and
-- -0 included - a delta needs the right base and refuses any other, and the bytes are counted.
local Loader = require("./loader")
local Match = Loader.load("Match")
local Stages = Loader.load("Data/Stages")
local Loadout = Loader.load("Loadout")
local Snapshot = Loader.load("Snapshot")
local Stage = Loader.load("Stage")
local Codec = Loader.load("SnapshotCodec")
local RemoteInput = Loader.loadFrom("src/server/", "RemoteInput")
local KIT = Loader.load("Data/AvatarKit")

local function same(a: any, b: any, where: string)
	if type(a) == "number" and type(b) == "number" then
		local ok = (a == b and (a ~= 0 or 1 / a == 1 / b)) or (a ~= a and b ~= b)
		assert(ok, `{where}: {a} became {b}`)
	elseif type(a) == "table" and type(b) == "table" then
		for k, v in a do same(v, b[k], `{where}.{k}`) end
		for k, v in b do if a[k] == nil then error(`{where}.{k}: appeared as {v}`) end end
	else
		assert(a == b, `{where}: {tostring(a)} became {tostring(b)}`)
	end
end

local WEAPONS = { "Sword", "Hammer", "Pike", "Grimoire" }
local snaps, keyBytes, deltaBytes, jsonish = 0, 0, 0, 0
for _, stage in Stages.LIST do
	local input = RemoteInput.new()
	local fighters = {}
	for i = 1, 4 do
		input:register(`bot{i}`)
		table.insert(fighters, { char = Loadout.build(KIT.presets[i + 1].code, WEAPONS[i]), skin = 0, source = `bot{i}`, isBot = true, botLevel = "hard" })
	end
	local m = Match.new({ mode = "StockFFA", stage = stage, fighters = fighters, stocks = 3, timeLimit = 180, items = true,
		disasters = "chaos", input = input, seed = 777 })
	local base: any = nil
	local decodedBase: any = nil
	for frame = 1, 1500 do
		Match.step(m)
		if frame % 2 == 0 then
			local list = table.create(#m.fighters)
			for i, f in m.fighters do list[i] = Snapshot.encode(f) end
			local snap = { id = 3, frame = m.frame, state = m.state, time = m.time, countdown = m.countdown, fighters = list,
				platforms = Stage.dynamicState(m.stage), acks = { { i = 0, n = frame, e = 1 } } }
			local key = Codec.encode(snap)
			assert(Codec.isKeyframe(key), "a snapshot with no base is a keyframe")
			same(snap, Codec.decode(key), `{stage.id} frame {frame} keyframe`)
			keyBytes += buffer.len(key)
			if base then
				local delta = Codec.encode(snap, base)
				assert(not Codec.isKeyframe(delta), "one with a base is a delta")
				local got = Codec.decode(delta, decodedBase)
				same(snap, got, `{stage.id} frame {frame} delta`)
				deltaBytes += buffer.len(delta)
				-- The wrong base, or none: refused, never guessed.
				assert(Codec.decode(delta, nil) == nil, "a delta without its base is refused")
				local wrong = table.clone(decodedBase); wrong.frame -= 2
				assert(Codec.decode(delta, wrong) == nil, "a delta against another frame is refused")
				local other = table.clone(decodedBase); other.id = 4
				assert(Codec.decode(delta, other) == nil, "a delta against another match is refused")
				decodedBase = got
			else
				decodedBase = Codec.decode(key)
			end
			base = snap
			snaps += 1
			-- What the table used to cost, roughly: every key and value written out.
			for _, f in list do for k, v in f do jsonish += #k + (if type(v) == "string" then #v + 2 else 8) + 2 end end
		end
	end
end

-- Values the fights may not have produced: every tag, and the transitions a delta has to express.
do
	local W: any = {}
	for _, pair in Snapshot.FIELDS do W[pair[1]] = pair[2] end
	local f1: any = { [W.x] = -0.0, [W.y] = 1e300, [W.vx] = 0.1, [W.vy] = -32768, [W.state] = string.rep("s", 300),
		[W.moveId] = "SigSide", [W.alive] = true, [W.onGround] = false, [W.frameCount] = 2147483647, [W.lastHitFrame] = -2147483649,
		[W.percent] = 127, [W.shield] = -128, [W.hitstun] = 40000,
		[W.stateFrame] = -129, [W.moveFrame] = -32769, [W.stocks] = 32767, [W.index] = 128 }
	local s1 = { id = 1, frame = 10, state = "play", time = 1.5, countdown = nil, fighters = { f1 } }
	same(s1, Codec.decode(Codec.encode(s1)), "edge keyframe")
	local f2 = table.clone(f1)
	f2[W.moveId], f2[W.x], f2[W.alive], f2[W.item] = nil, 0, false, "BlastKeg"
	local s2 = { id = 1, frame = 12, state = "play", time = 1.53, countdown = 3, fighters = { f2 }, platforms = { { i = 2, cx = 5.5, top = -0.0 } } }
	local base1 = Codec.decode(Codec.encode(s1))
	local copy = Codec.decode(Codec.encode(s1))
	same(s2, Codec.decode(Codec.encode(s2, s1), base1), "edge delta: a field gone, -0 to 0, true to false, a new field")
	-- The base is the client's previous snapshot, still in its interpolation buffer: untouched.
	same(copy, base1, "the base after decoding a delta against it")
	-- A roster that changed size since the base cannot be a delta: it goes as a keyframe.
	local s3 = { id = 1, frame = 14, state = "play", time = 1.56, fighters = { f2, f1 } }
	local grown = Codec.encode(s3, s2)
	assert(Codec.isKeyframe(grown), "a snapshot with a fighter more than its base is a keyframe")
	same(s3, Codec.decode(grown), "and decodes on its own")
	assert(not pcall(Codec.encode, { id = 1, frame = 1, fighters = { { [W.x] = {} } } }), "a table in a field is refused, not sent")
end

-- Malformed input decodes to nothing.
local good = Codec.encode({ id = 1, frame = 2, state = "play", time = 0, fighters = {} })
assert(Codec.decode(good) ~= nil, "an empty fight decodes")
assert(Codec.decode({}) == nil and Codec.decode(nil) == nil and Codec.decode(buffer.create(0)) == nil, "not a snapshot")
local cut = buffer.create(buffer.len(good) - 1)
buffer.copy(cut, 0, good, 0, buffer.len(cut))
assert(Codec.decode(cut) == nil, "a cut-off buffer")
local long = buffer.create(buffer.len(good) + 3)
buffer.copy(long, 0, good)
assert(Codec.decode(long) == nil, "trailing bytes")

local perKey, perDelta, perOld = keyBytes / snaps, deltaBytes / (snaps - #Stages.LIST), jsonish / snaps
assert(perDelta < perOld / 3, `a delta should be under a third of the old table: {math.floor(perDelta)} bytes against ~{math.floor(perOld)}`)
print(string.format("PASS snapshot codec: %d snapshots over %d stages decode exactly; four fighters ~%d bytes as a table, %d as a keyframe, %d as a delta",
	snaps, #Stages.LIST, perOld, perKey, perDelta))
