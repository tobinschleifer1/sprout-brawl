--!strict
-- Replay the JavaScript's weapon poses through the Luau port and report the first one that differs.
--
--     lune run tests/weapon-parity
--
-- The pose is not a flat bag of numbers: `ult` carries a different set of keys per weapon and per
-- phase, and `trail` exists only while a blade is live. So this compares the flattened KEY SET as
-- well as the values, in both directions. A port that stops emitting `ult.chop` is a renderer that
-- silently stops drawing the chop - it has to fail here rather than look slightly wrong in Studio.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")

local Loadout = Loader.load("Loadout")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")

local function fail(msg: string): never
	error(msg, 0)
end

local trace = serde.decode("json", fs.readFile("tests/trace-weapons.json"))
local TOL = 1e-12

local function near(a: number, b: number): boolean
	if a == b then
		return true
	end
	return math.abs(a - b) <= TOL * math.max(1, math.max(math.abs(a), math.abs(b)))
end

-- The same flatten the generator uses. An array becomes 1-based indices, which is what the
-- JavaScript's `i + 1` produces, so the two key sets line up without a special case.
local function flatten(v: any, prefix: string, rows: { [string]: any })
	if v == nil then
		return
	end
	if type(v) == "table" then
		if #v > 0 then
			for i, x in ipairs(v) do
				flatten(x, `{prefix}.{i}`, rows)
			end
		else
			for key, x in pairs(v) do
				flatten(x, if prefix == "" then key else `{prefix}.{key}`, rows)
			end
		end
		return
	end
	rows[prefix] = v
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
local keysSeen: { [string]: boolean } = {}

for i, p in trace.probes do
	local char = charFor(p.avatar, p.weapon)
	-- Exactly what Snapshot.decode produces, plus char and move as arguments - the same call
	-- Weapons2D makes. A harness that folds char into the bag tests a shape no caller produces.
	local f = {
		index = p.index, state = p.state,
		vx = tonumber(p.vx), onGround = p.onGround,
		stateFrame = tonumber(p.sf), moveFrame = tonumber(p.mf),
		moveId = p.moveId,
		startupEff = tonumber(p.startupEff), charge = tonumber(p.charge),
		ultCooldown = tonumber(p.ultCooldown), ultShots = tonumber(p.ultShots),
	}
	local move = if p.moveId then char.moves[p.moveId] else nil
	local pose = WeaponPose.For(f, char, move, tonumber(p.t))

	local got: { [string]: any } = {}
	flatten(pose, "", got)
	local want = trace.outputs[i]
	local where = `probe {i} ({p.state}/{p.weapon}/{tostring(p.moveId)} mf={p.mf} t={p.t})`

	-- Every key the JavaScript produced, with its value.
	for key, wantV in want do
		keysSeen[key] = true
		local gotV = got[key]
		if gotV == nil then
			fail(`{where}: Luau did not produce {key} (JavaScript says {wantV})`)
		end
		if type(gotV) == "number" then
			local expect = tonumber(wantV)
			if expect == nil then
				fail(`{where}: {key} is a number here but "{wantV}" in the JavaScript`)
			end
			if not near(gotV, expect) then
				fail(`{where}: {key} = {gotV}, JavaScript says {expect}`)
			end
		elseif type(gotV) == "boolean" then
			if (if gotV then "true" else "false") ~= wantV then
				fail(`{where}: {key} = {tostring(gotV)}, JavaScript says {wantV}`)
			end
		else
			if tostring(gotV) ~= wantV then
				fail(`{where}: {key} = "{tostring(gotV)}", JavaScript says "{wantV}"`)
			end
		end
		checked += 1
	end
	-- And nothing extra: an invented key is a pose the renderer would act on that the web build
	-- never produces.
	for key in got do
		if want[key] == nil then
			fail(`{where}: Luau produced {key} = {tostring(got[key])}, which the JavaScript does not`)
		end
		checked += 1
	end
end

local nk = 0
for _ in keysSeen do nk += 1 end
print(`replayed {checked} weapon pose values across {#trace.probes} poses, {nk} distinct keys`)
print("WeaponPose.luau matches web/src/render2d/weapons2d.js exactly.")
