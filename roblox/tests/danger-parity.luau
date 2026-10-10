--!strict
-- Danger.luau against web/src/render2d/danger.js: the danger percent for every stage's blast box
-- and the roster's weights, the level, and the smoke drawn. Then what parity cannot vouch for:
-- heavier fighters are in danger later, no smoke before the danger starts, more of it the closer
-- they are, embers only near the end.
--
--     lune run tests/danger-parity
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Danger = Loader.loadFrom("src/client/", "Danger")
local T = serde.decode("json", fs.readFile("tests/danger-fixture.json"))

local checked = 0
for _, c in T.percents do
	local got = Danger.percent(c.weight, c.blast)
	assert(got == c.at, `danger percent for weight {c.weight}: Luau {got}, JS {c.at}`)
	checked += 1
end
for _, row in T.levels do
	local got = Danger.level(row[1], row[2])
	assert(math.abs(got - tonumber(row[3]) :: number) < 1e-12, `level({row[1]}, {row[2]}): Luau {got}, JS {row[3]}`)
	checked += 1
end
for n, c in T.shapes do
	local got = Danger.shapes(-4.5, 2.25, 5.2, c.k, c.frame)
	assert(#got == #c.shapes, `drawing {n} (k {c.k}, frame {c.frame}): {#got} shapes, JS {#c.shapes}`)
	for i, sh in got do
		for j, v in sh do
			local want = c.shapes[i][j]
			local ok = if type(v) == "number" then math.abs(v - (tonumber(want) :: number)) < 1e-9 else v == want
			assert(ok, `drawing {n} shape {i}.{j}: JS {want}, Luau {tostring(v)}`)
			checked += 1
		end
	end
end
local marked = 0
for n, c in T.marks do
	local got = Danger.markShapes(2.5, 0, 5.2, c.left, c.frame)
	assert(#got == #c.shapes, `mark {n} (left {c.left}, frame {c.frame}): {#got} shapes, JS {#c.shapes}`)
	for i, sh in got do
		for j, v in sh do
			local want = c.shapes[i][j]
			local ok = if type(v) == "number" then math.abs(v - (tonumber(want) :: number)) < 1e-9 else v == want
			assert(ok, `mark {n} shape {i}.{j}: JS {want}, Luau {tostring(v)}`)
			checked += 1
		end
	end
	if #got > 0 then marked += 1 end
end
print(`danger: {checked} values match web/src/render2d/danger.js (and {marked} whip marks)`)
-- the mark's behaviour, not only its agreement: over the head, gone when it fades, blinking at the end
local fresh = Danger.markShapes(0, 0, 5, 200, 9)
local lowest = math.huge
for _, sh in fresh do lowest = math.min(lowest, sh[3]) end
assert(#fresh > 0 and lowest > 5, "the whip's mark sits over the head")
assert(#Danger.markShapes(0, 0, 5, 0, 9) == 0, "a faded mark draws nothing")
assert(Danger.markShapes(0, 0, 5, 30, 4)[1][7] < 1 and Danger.markShapes(0, 0, 5, 30, 0)[1][7] == 1
	and Danger.markShapes(0, 0, 5, 200, 4)[1][7] == 1, "the mark blinks only in its last second")

local blast = T.percents[1].blast
assert(Danger.percent(72, blast) < Danger.percent(100, blast) and Danger.percent(100, blast) < Danger.percent(125, blast),
	"a heavier fighter is in danger later")
local at = Danger.percent(100, blast)
assert(at > 60 and at < 250, `a mid-weight's danger percent is {at}: not a percent anyone fights at`)
assert(#Danger.shapes(0, 0, 5, Danger.level(at - Danger.DANGER.lead - 1, at), 10) == 0, "no smoke before the danger starts")
local function count(k: number): number return #Danger.shapes(0, 0, 5, k, 10) end
assert(count(0.1) < count(0.6) and count(0.6) <= count(1), "more smoke the closer they are")
local embers = 0
for _, sh in Danger.shapes(0, 0, 5, 1, 10) do if sh[6] == "#FF7A3A" then embers += 1 end end
local early = 0
for _, sh in Danger.shapes(0, 0, 5, 0.5, 10) do if sh[6] == "#FF7A3A" then early += 1 end end
assert(embers > 0 and early == 0, "embers only near the end")
print(`danger: weight 72/100/125 smoke from {Danger.percent(72, blast) - Danger.DANGER.lead}%/{at - Danger.DANGER.lead}%/{Danger.percent(125, blast) - Danger.DANGER.lead}% on {"the first stage"}; none before, more nearer, embers last`)
