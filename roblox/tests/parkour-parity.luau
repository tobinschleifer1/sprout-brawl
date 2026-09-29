--!strict
-- Parkour.luau against web/src/engine/parkour.js: nine climbs from nine checkpoints and set-downs onto
-- every moving foothold (see tools/gen-parkour-trace.mjs), every frame's
-- fighter state, foothold, checkpoint, falls, clock and events. Within 1e-9: the fighter and
-- stage engines are themselves held to the JavaScript to 1e-12 by their own suites.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Parkour = Loader.load("Parkour")
local Loadout = Loader.load("Loadout")
local T = serde.decode("json", fs.readFile("tests/parkour-fixture.json"))
local char = Loadout.build("Classic", T.weapon)
local checked = 0
for n, case in T.cases do
	local pk = Parkour.new(Parkour.DATA.course, char, case.from, case.opts)
	if case.drop then
		-- A set-down onto a moving foothold: wait until that point of its cycle, then fall onto it.
		local still = { x = 0, y = 0, jump = false, jumpHeld = false, downTap = false }
		for _ = 1, case.drop.wait do pk:step(still) end
		pk:drain()
		for _, p in pk.stage.platforms do
			if p.id == case.drop.id then
				local f = pk.fighter
				f.x, f.y, f.vx, f.vy, f.onGround, f.platform = p.cx, p.top + case.drop.dy, 0, case.drop.vy, false, nil
			end
		end
	end
	for i, f in case.frames do
		if f.skip ~= nil then pk:skipTo(f.skip) end
		pk:step(f.input)
		if f.skipped ~= nil then
			assert(pk.skipped == f.skipped and pk.done == f.done, `climb {n} frame {i}: skipped/done differ`)
		end
		local fighter = pk.fighter
		for k, field in T.fields do
			local want, got = f.values[k], fighter[field]
			local ok = if type(got) == "number" then math.abs(got - (tonumber(want) :: number)) <= 1e-9 * math.max(1, math.abs(got)) else got == want
			assert(ok, `climb {n} from {case.from} frame {i}: {field} JS {tostring(want)}, Luau {tostring(got)}`)
			checked += 1
		end
		assert(pk.reached == f.reached and pk.deaths == f.deaths and pk.frames == f.frames, `climb {n} frame {i}: progress differs`)
		assert((if fighter.platform then fighter.platform.id else "") == f.platform, `climb {n} frame {i}: foothold differs`)
		local evs = {}
		for _, e in pk:drain() do table.insert(evs, e.type .. ":" .. tostring(e.id or e.checkpoint or e.frames)) end
		assert(table.concat(evs, ",") == f.events, `climb {n} frame {i}: events {table.concat(evs, ",")} vs {f.events}`)
		checked += 4
	end
end
print(`parkour: {checked} values across {#T.cases} climbs match web/src/engine/parkour.js`)
