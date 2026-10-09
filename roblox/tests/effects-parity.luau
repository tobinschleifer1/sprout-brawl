--!strict
-- Effects.luau throws the same sparks and rings as web/src/render2d/effects.js for every match
-- event, fed the same random numbers: state and drawn shapes compared after spawning and after
-- each of four steps. Then what parity cannot vouch for: every event the web renderer reacts to
-- makes something visible, a hit's sparks take the attacker's weapon glow, heavy hits ring and
-- shake harder than light ones, and everything burns out.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Fx = Loader.loadFrom("src/client/", "Effects")
local T = serde.decode("json", fs.readFile("tests/effects-fixture.json"))

local pool = {}
for i, v in T.pool do pool[i] = tonumber(v) :: number end
local at = 0
local function rand(): number
	at += 1
	return pool[at]
end
local function glow(i: number?): string?
	if i == nil then return nil end
	local g = T.glows[i + 1]
	return if g == nil or g == serde.decode("json", "null") then nil else g
end

local function height(i: number?): number
	return if i ~= nil and T.heights[i + 1] then T.heights[i + 1] else 5
end
local checked = 0
local function near(want: any, got: any, where: string)
	if want == nil then
		assert(got == nil, `{where}: JS nil, Luau {tostring(got)}`)
	elseif type(got) == "number" then
		assert(math.abs(got - (tonumber(want) :: number)) < 1e-9, `{where}: JS {want}, Luau {got}`)
	elseif type(got) == "boolean" then
		assert(tostring(got) == tostring(want), `{where}: JS {tostring(want)}, Luau {tostring(got)}`)
	else
		assert(got == want, `{where}: JS {tostring(want)}, Luau {tostring(got)}`)
	end
	checked += 1
end
local function compare(fx: any, want: any, where: string)
	assert(#fx.parts == #want.parts, `{where}: {#fx.parts} sparks, JS {#want.parts}`)
	for i, p in fx.parts do
		for j, v in { p.x, p.y, p.vx, p.vy, p.life, p.max, p.c, p.s } do near(want.parts[i][j], v, `{where} spark {i}.{j}`) end
	end
	assert(#fx.rings == #want.rings, `{where}: {#fx.rings} rings, JS {#want.rings}`)
	for i, r in fx.rings do
		for j, v in { r.x, r.y, r.r, r.life, r.max, r.c, r.heavy, r.rot } do near(want.rings[i][j], v, `{where} ring {i}.{j}`) end
	end
	near(want.shake, fx.shake, `{where} shake`)
	near(want.flash, fx.flash, `{where} flash`)
	local keys = {}
	for k in fx.shields do table.insert(keys, k) end
	table.sort(keys)
	assert(#keys == #want.shields, `{where}: {#keys} struck shields, JS {#want.shields}`)
	for i, k in keys do
		near(want.shields[i][1], tostring(k), `{where} struck shield {i}`)
		near(want.shields[i][2], fx.shields[k].life, `{where} shield {k} life`)
		near(want.shields[i][3], fx.shields[k].x, `{where} shield {k} x`)
		near(want.shields[i][4], fx.shields[k].y, `{where} shield {k} y`)
	end
	local shapes = Fx.shapes(fx)
	assert(#shapes == #want.shapes, `{where}: {#shapes} shapes, JS {#want.shapes}`)
	for i, sh in shapes do
		for j, v in sh do near(want.shapes[i][j], v, `{where} shape {i}.{j}`) end
	end
end

for _, case in T.cases do
	at = case.start
	local fx = Fx.new()
	if case.emitters then
		for i = 0, 39 do
			Fx.dragDirt(fx, 1.5 + i * 0.1, 0, if i % 2 == 1 then 1 else -1, 12.5, (i % 5) / 4, "#556070", rand)
			Fx.orbSparks(fx, -2, 6, if i % 2 == 1 then 30 else -30, if i % 3 ~= 0 then "#FF00AA" else nil, rand)
		end
		compare(fx, case.steps[1], `{case.name} spawn`)
		Fx.step(fx, 0.1)
		compare(fx, case.steps[2], `{case.name} step`)
	else
		for _, e in case.events do Fx.spawn(fx, e, glow, rand, height) end
		compare(fx, case.steps[1], `{case.name} spawn`)
		for k, dt in { 1 / 60, 0.05, 0.1, 0.2 } do
			Fx.step(fx, dt)
			compare(fx, case.steps[k + 1], `{case.name} step {k}`)
		end
	end
end
print(`effects: {checked} values across {#T.cases} cases match the web`)

-- Properties, asserted directly.
local r = 0
local function lcg(): number
	r = (r * 1103515245 + 12345) % 2147483648
	return r / 2147483648
end
local EVENTS = { "hit", "explosion", "block", "ko", "projectile", "beam", "ultimate", "soulescape", "crater", "rundown",
	"upheaval", "heartseeker", "anchorset", "anchorsnap", "aegis", "aegisbreak", "bleedmark", "exsanguinate", "soulgrab",
	"soulburst", "snipe", "starfall", "counter", "freeze", "summonbreak", "jump", "doublejump", "dash", "dodge", "ledge",
	"tech", "armor", "shieldbreak", "grabhit", "itembreak", "projectilebreak", "spring", "teleport", "pickup", "land" }
for _, t in EVENTS do
	local fx = Fx.new()
	Fx.spawn(fx, { type = t, x = 0, y = 5, attacker = 0, fighter = 0, radius = 3, marks = 2 }, function() return "#123456" end, lcg)
	assert(#Fx.shapes(fx) > 0, `{t} makes nothing visible`)
end
local light, heavy = Fx.new(), Fx.new()
Fx.spawn(light, { type = "hit", x = 0, y = 0, attacker = 0 }, function() return "#B77DFF" end, lcg)
Fx.spawn(heavy, { type = "hit", x = 0, y = 0, attacker = 0, heavy = true }, function() return "#B77DFF" end, lcg)
assert(light.parts[1].c == "#B77DFF", "a hit's sparks take the attacker's weapon glow")
assert(#heavy.rings == 1 and #light.rings == 0, "only heavy hits ring")
assert(heavy.shake > light.shake and light.shake > 0, "every hit shakes, heavy harder")
assert(#heavy.parts > #light.parts, "heavy hits throw more sparks")
for _ = 1, 120 do Fx.step(heavy, 1 / 60) end
assert(#heavy.parts == 0 and #heavy.rings == 0 and heavy.shake == 0, "everything burns out within two seconds")
-- a hit's look follows how hard it sent them, and the kill hit flashes the screen
local function hitFx(launch: number, kill: boolean?): any
	local fx = Fx.new()
	Fx.spawn(fx, { type = "hit", x = 0, y = 0, attacker = 0, launch = launch, kill = kill }, function() return "#B77DFF" end, lcg)
	return fx
end
local jab, mid, smash, kill = hitFx(15), hitFx(80), hitFx(170), hitFx(170, true)
assert(#jab.parts < #mid.parts and #mid.parts < #smash.parts, `sparks by strength: {#jab.parts}, {#mid.parts}, {#smash.parts}`)
assert(jab.shake < mid.shake and mid.shake < smash.shake, "a harder hit shakes harder")
assert(#jab.rings == 0 and #smash.rings == 1, "a strong hit rings, a jab does not")
assert(smash.flash == 0 and kill.flash > 0, "only the kill hit flashes the screen")
assert(#kill.rings == 2 and #kill.parts > #smash.parts and kill.shake > smash.shake, "the kill hit is bigger than any other hit")
local biggest = 0
for _, ring in kill.rings do biggest = math.max(biggest, ring.r) end
for _, ring in smash.rings do assert(ring.r * 1.2 < biggest, "the kill hit's ring is bigger than a strong hit's") end
for _ = 1, 30 do Fx.step(kill, 1 / 60) end
assert(kill.flash == 0, "the flash is gone in half a second")
-- the telegraph: a heavy starting up glints above the fighter's middle; anything else does not
local glint, quiet = Fx.new(), Fx.new()
Fx.spawn(glint, { type = "movestart", x = 0, y = 5, fighter = 0, heavy = true }, function() return nil end, lcg, function() return 6 end)
Fx.spawn(quiet, { type = "movestart", x = 0, y = 5, fighter = 0, heavy = false }, function() return nil end, lcg, function() return 6 end)
assert(#glint.rings == 1 and glint.rings[1].y > 5 and #quiet.rings == 0 and #quiet.parts == 0, "a heavy's startup glints on the upper body, a light's does not")
-- dust starts at the fighter's feet, not their middle
local tall = Fx.new()
Fx.spawn(tall, { type = "jump", x = 0, y = 10, fighter = 0 }, function() return nil end, lcg, function() return 6 end)
for _, p in tall.parts do assert(p.y == 7, `jump dust at y {p.y}, the feet are at 7`) end
print("effects: every event visible, sparks in the weapon's glow, hits by strength (sparks, ring, shake), the kill hit's burst, ring and flash, heavy startups glint, dust at the feet, all burn out")
