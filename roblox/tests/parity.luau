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
-- The shipping modules use Roblox-style `require(script.Parent.X)`. Rather than compromise that for
-- testability, this loads their source with a shimmed `script` and `require`.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")

local SHARED = "src/shared/"

local loaded: { [string]: any } = {}

local function loadModule(name: string): any
	if loaded[name] then
		return loaded[name]
	end
	local source = fs.readFile(SHARED .. name .. ".luau")

	-- `script.Parent.Foo` resolves to the string "Foo", which the shimmed require turns back into
	-- a loaded module. That is enough for a flat module folder, which is what Shared is.
	local parentIndex = setmetatable({}, {
		__index = function(_, key: string)
			return key
		end,
	})
	local fakeScript = { Parent = parentIndex, Name = name }

	local env = {
		script = fakeScript,
		require = function(target: any): any
			if typeof(target) == "string" then
				return loadModule(target)
			end
			error("parity shim: unsupported require target " .. tostring(target))
		end,
	}

	local chunk = luau.load(source, { debugName = name, environment = env, injectGlobals = true })
	loaded[name] = chunk()
	return loaded[name]
end

local Knockback = loadModule("Knockback")
local Config = loadModule("Config")

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
	local base, growth, damage, pct, weight, expectLaunch, expectStun =
		row[1], row[2], row[3], row[4], row[5], row[6], row[7]
	local got = Knockback.launchSpeed(base, growth, damage, pct, weight)
	checked += 1
	if not near(got, expectLaunch) then
		fail(string.format("launchSpeed(%g,%g,%g,%g,%g) = %.9f, JS says %.9f", base, growth, damage, pct, weight, got, expectLaunch))
	end
	local stun = Knockback.hitstun(got)
	checked += 1
	if stun ~= expectStun then
		fail(string.format("hitstun(%.6f) = %d, JS says %d", got, stun, expectStun))
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

-- a handful of constants that the rest of the port reads
local constants: { { any } } = {
	{ "FRAME", Config.FRAME, 1 / 60 },
	{ "GRAVITY", Config.GRAVITY, 150 },
	{ "LAUNCH_DRAG", Config.LAUNCH_DRAG, 0.985 },
	{ "TUMBLE_THRESHOLD", Config.TUMBLE_THRESHOLD, 45 },
	{ "HITSTUN_CAP", Config.HITSTUN_CAP, 60 },
	{ "HITLAG_CAP", Config.HITLAG_CAP, 12 },
	{ "DI_MAX", Config.DI_MAX, 12 },
	{ "INPUT_BUFFER", Config.INPUT_BUFFER, 6 },
	{ "TECH.window", Config.TECH.window, 8 },
	{ "SHIELD.max", Config.SHIELD.max, 50 },
}
for _, c in constants do
	checked += 1
	if not near(c[2] :: number, c[3] :: number) then
		fail(string.format("Config.%s = %s, expected %s", c[1] :: string, tostring(c[2]), tostring(c[3])))
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
