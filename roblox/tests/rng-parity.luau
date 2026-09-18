--!strict
-- The seeded generator must match web/src/engine/rng.js exactly, not approximately.
--
--   lune run tests/rng-parity
--
-- Everything downstream of it - hazard jitter, item spawns, and eventually the whole
-- server-authoritative replay - is only deterministic if this is. Bit-exact, no tolerance: this is
-- integer arithmetic, and there is nothing here for a library difference to disagree about.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Rng = Loader.load("Rng")
local T = serde.decode("json", fs.readFile("tests/rng-fixture.json"))

local failures: { string } = {}
local checked = 0

for _, case in T do
	local r = Rng.make(tonumber(case.seed) :: number)
	local vals = {}
	for i = 1, 2000 do
		vals[i] = r()
	end
	for i = 1, 3 do
		checked += 1
		if tostring(vals[i]) ~= case.first[i] and math.abs(vals[i] - (tonumber(case.first[i]) :: number)) > 0 then
			table.insert(failures, string.format("seed %s value %d: Luau %.17g, JS %s",
				tostring(case.seed), i, vals[i], case.first[i]))
		end
	end
	local sum = 0
	for _, v in vals do
		sum += v
	end
	checked += 2
	-- The sum folds all 2,000 outputs into one number: any single value being wrong moves it.
	if math.abs(sum - (tonumber(case.sum) :: number)) > 1e-9 then
		table.insert(failures, string.format("seed %s: sum of 2000 = %.17g, JS %s",
			tostring(case.seed), sum, case.sum))
	end
	if vals[2000] ~= tonumber(case.last) then
		table.insert(failures, string.format("seed %s: value 2000 = %.17g, JS %s",
			tostring(case.seed), vals[2000], case.last))
	end
end

print(string.format("checked %d generator values across %d seeds", checked, #T))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print("Rng.luau matches web/src/engine/rng.js exactly.")
