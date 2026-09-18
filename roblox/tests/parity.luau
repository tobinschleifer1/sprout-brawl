--!strict
-- Numerical parity between the Luau port and the JavaScript it was ported from.
--
--   lune run tests/parity
--
-- web/src/engine/knockback.js is the source of truth. tests/knockback-fixture.json is generated
-- from it (see the regenerate command in roblox/README.md). This compares every value the Luau
-- produces against that fixture. If the two ever drift, knockback stops feeling the same and this
-- fails loudly rather than shipping a subtly different game.
--

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Knockback = Loader.load("Knockback")
local Config = Loader.load("Config")

local fixture = serde.decode("json", fs.readFile("tests/knockback-fixture.json"))

local failures: { string } = {}
local checked = 0

-- Both sides are IEEE-754 doubles doing the same operations in the same order, so the only
-- tolerance needed is for the 9-decimal rounding applied when the fixture was written.
local EPS = 1e-6

local function near(a: number, b: number): boolean
	local diff = math.abs(a - b)
	return diff <= EPS or diff <= EPS * math.max(math.abs(a), math.abs(b))
end

local function fail(msg: string)
	if #failures < 12 then
		table.insert(failures, msg)
	end
end

-- launchSpeed + hitstun
for _, row in fixture.launch do
	local base, growth, damage, pct, weight, expectLaunch, expectStunFrames, expectStunSpeed =
		row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]
	local got = Knockback.launchSpeed(base, growth, damage, pct, weight)
	checked += 1
	if not near(got, expectLaunch) then
		fail(string.format("launchSpeed(%g,%g,%g,%g,%g) = %.9f, JS says %.9f", base, growth, damage, pct, weight, got, expectLaunch))
	end
	-- The stun curve is a separate formula, so it is checked separately - and hitstun is taken
	-- from IT, not from the launch, which is the ordering combat.js uses.
	local stunSpeed = Knockback.stunSpeed(base, growth, damage, pct, weight)
	checked += 1
	if not near(stunSpeed, expectStunSpeed) then
		fail(string.format("stunSpeed(%g,%g,%g,%g,%g) = %.9f, JS says %.9f", base, growth, damage, pct, weight, stunSpeed, expectStunSpeed))
	end
	local stun = Knockback.hitstun(stunSpeed)
	checked += 1
	if stun ~= expectStunFrames then
		fail(string.format("hitstun(%.6f) = %d, JS says %d", stunSpeed, stun, expectStunFrames))
	end
end

-- velocity, including directional influence
for _, row in fixture.velocity do
	local launch, angle, facing, dix, diy, hasDI, expectVx, expectVy =
		row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]
	local di = if hasDI == 1 then { x = dix, y = diy } else nil
	local v = Knockback.velocity(launch, angle, facing, di)
	checked += 2
	if not near(v.vx, expectVx) or not near(v.vy, expectVy) then
		fail(string.format("velocity(%g,%g,%g,di=%s) = (%.9f, %.9f), JS says (%.9f, %.9f)",
			launch, angle, facing, if di then string.format("%g/%g", dix, diy) else "nil",
			v.vx, v.vy, expectVx, expectVy))
	end
end

-- blockstun + hitlag
for _, row in fixture.misc do
	local d, expectBlock, expectLagLight, expectLagHeavy = row[1], row[2], row[3], row[4]
	checked += 3
	if Knockback.blockstun(d) ~= expectBlock then
		fail(string.format("blockstun(%d) = %d, JS says %d", d, Knockback.blockstun(d), expectBlock))
	end
	if Knockback.hitlag(d, false) ~= expectLagLight then
		fail(string.format("hitlag(%d,false) = %d, JS says %d", d, Knockback.hitlag(d, false), expectLagLight))
	end
	if Knockback.hitlag(d, true) ~= expectLagHeavy then
		fail(string.format("hitlag(%d,true) = %d, JS says %d", d, Knockback.hitlag(d, true), expectLagHeavy))
	end
end

-- ---------------------------------------------------------------- config ----
-- EVERY leaf of web/src/config.js, in both directions.
--
-- This used to be ten constants picked by hand, which is a sample and not a check. While it was
-- green, Config.ULTIMATE did not exist in the Luau at all and Config.ITEMS.spawnEvery still said
-- 25 against the JavaScript's 14 - both had been wrong since the day those values changed. A
-- hand-written list can only ever catch drift in the things somebody already thought to list.
local function join(path: string, k: any): string
	return if path == "" then tostring(k) else path .. "." .. tostring(k)
end

local function compareConfig(js: any, lua: any, path: string)
	local jt, lt = typeof(js), typeof(lua)
	if jt == "string" and lt == "number" then
		-- numbers travel as decimal strings; see tests/genfixture.mjs
		checked += 1
		if lua ~= tonumber(js) then
			fail(string.format("Config.%s = %.17g, JS says %s", path, lua, js))
		end
		return
	end
	if jt ~= lt then
		fail(string.format("Config.%s: JS has %s, Luau has %s", path, jt, lt))
		return
	end
	if jt ~= "table" then
		checked += 1
		if js ~= lua then
			fail(string.format("Config.%s = %s, JS says %s", path, tostring(lua), tostring(js)))
		end
		return
	end
	for k, v in js do
		local got = lua[k]
		if got == nil then
			fail(string.format("Config.%s is in the JavaScript and missing from the Luau", join(path, k)))
		else
			compareConfig(v, got, join(path, k))
		end
	end
	for k, v in lua do
		-- Functions are excluded from the JS dump and sampled separately (WEIGHT_CLASS), so they
		-- are not "extra" here.
		if js[k] == nil and typeof(v) ~= "function" then
			fail(string.format("Config.%s is in the Luau and not in the JavaScript", join(path, k)))
		end
	end
end
compareConfig(fixture.config, Config, "")

for _, row in fixture.weightClass do
	checked += 1
	local got = Config.WEIGHT_CLASS(row[1])
	if got ~= row[2] then
		fail(string.format("WEIGHT_CLASS(%s) = %s, JS says %s", tostring(row[1]), got, tostring(row[2])))
	end
end

print(string.format("checked %d values against the JavaScript fixture", checked))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print("Luau knockback matches web/src/engine/knockback.js exactly.")
