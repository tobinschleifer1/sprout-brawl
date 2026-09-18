--!strict
-- Does Combat.luau resolve hits the way web/src/engine/combat.js does?
--
--   lune run tests/combat-parity
--
-- Phase 3a: melee swings, grabs, throws, shields, counters, ground pounds, ledge attacks. No
-- projectiles, summons or items - Combat.luau refuses those by name, so a scenario that reached one
-- would fail loudly here rather than quietly resolve to nothing.
--
-- The event stream is compared frame by frame alongside the fighters' state, because a wrong branch
-- in resolveHit shows up in the emitted damage and launch long before it shows up as a position.
--
-- THREE BRANCHES IN resolveHit ARE UNREACHABLE FROM THE ROSTER, each found by breaking the port and
-- watching nothing fail. All three are faithfully ported and none of them can run:
--   * the ARMOUR branch - no move in the game sets `armor`.
--   * the COMMAND GRAB branch - no move sets `kind: "grab"`.
--   * `onMoveActiveFrame`'s `field` kind, which is not ported at all for that reason.
--
-- Three more mutations survive because they need an ULTIMATE, which is Phase 3c: capping a summon's
-- hitlag at 4 (the only burst here deals 5 damage, where the cap and the real value coincide),
-- `hb.shieldDamageMul` (only ultimate hitboxes carry one), and skipping onHitLanded's
-- `move.id ~= "Ultimate"` guard.
--
-- PHASE 3c LEAVES FOUR, all established the same way:
--   * the crater's fade rounding. Colossus is the only `slam` in the game and its crater carries
--     `minDamage: 10`, which dominates every faded step - the only step where the rounding could
--     show is step 0, where fade is 1 and 12 x 1 is exact. Rounding or flooring makes no
--     difference to any crater that exists.
--   * the `burst` and `freeze` move kinds, and `pulse`. No weapon uses any of them. `burst` and
--     `freeze` are ported anyway because they are a dozen lines between them; `pulse` is not,
--     because it fires at nodes and nothing spawns nodes.
--   * `p.grounded` projectiles - nothing in the roster sets it.
--
-- PHASE 3d ADDS SIX, every one of them a branch the engine cannot reach:
--   * dropItem's empty-gun removal. useItem deletes a `shoot` item the instant its last charge is
--     spent, so a HELD gun is never sitting at zero uses to be dropped.
--   * the `place` branch's `not f.onGround` guard, and the `f.onGround` term in the Bulwark's
--     throw exception. Fighter only calls useItem from _stepGround, so an airborne fighter cannot
--     use an item at all.
--   * `it.spent` in stepItems, which is read there and set nowhere in the engine.
--   * `sw.total` on the Bulwark's swing. `move.total` is written for every move and read nowhere
--     in the simulation - Fighter recomputes the sum from startupEff itself.
--   * the 0.3-stud grace on an item landing. Items fall fast enough that their previous y is
--     essentially never inside it.
--   * the keg catch clearing the victim's guard buffer. It is real, but the only way to see it is
--     a victim who taps guard exactly once at the moment the keg arrives, and the timing of a
--     thrown keg's arc is not something a scripted scenario can hit reliably.
--
-- PHASE 3b'S FOUR STILL STAND:
--   * the projectile out-of-bounds cull (|x| > 200) - nothing flies that far before its lifetime
--     runs out.
--   * the `>= 4` damage threshold on the projectile-versus-summon check. Every bolt and arrow
--     spawns at chest height (y 2.55 to 3.75) and a mine's box is y 0.0 to 1.6, so they all fly
--     over it; the one projectile tall enough to touch a mine is Runebrand, which deals 15. The
--     branch is covered by 'mine shot out'; the threshold cannot be.
--   * wall, cloud and node summons, the `pulse` kind, the `teleport` recovery, `nearestNode` and
--     `fruiting` - no weapon in the roster uses any of them, so none is ported.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Fighter = Loader.load("Fighter")
local Stage = Loader.load("Stage")
local Combat = Loader.load("Combat")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")
local ItemData = Loader.load("Data/Items")

local T = serde.decode("json", fs.readFile("tests/trace-combat.json"))

local failures: { string } = {}
local checked = 0
local function fail(msg: string)
	if #failures < 10 then
		table.insert(failures, msg)
	end
end

local EPS = 1e-12
local function near(a: number, b: number): boolean
	local d = math.abs(a - b)
	return d <= EPS or d <= EPS * math.max(math.abs(a), math.abs(b))
end
local function num(v: any): number
	return tonumber(v) :: number
end

local function frameFrom(input: any): any
	local fr = Input.emptyFrame()
	for k, v in input or {} do
		(fr :: any)[k] = v
	end
	return fr
end

for _, spec in T.scenarios do
	local data = table.clone(StageData.BY_ID[spec.stage])
	data.hazards = {}
	local stage = Stage.new(data, 4242)
	local fighters = {}
	for i, who in spec.who do
		local f = Fighter.new({ index = i - 1, char = Loadout.build(who[1], who[2]),
			x = num(spec.at[i]), y = 0.5, stocks = 3, name = `P{i - 1}` })
		f:setState("idle")
		f.invincible = 0
		f.onGround = true
		f.platform = stage.main
		f.facing = if i == 1 then 1 else -1
		fighters[i] = f
	end
	local match = { fighters = fighters, frame = 0, stage = stage }
	local combat = Combat.new(match)
	match.combat = combat
	local ctx = { stage = stage, combat = combat, fighters = fighters }

	local frame = 0
	local broke = false
	for _, seg in spec.segments do
		if broke then break end
		for _ = 1, seg.frames do
			match.frame = frame
			if spec.pin then
				for k, f in fighters do
					f.x = num(spec.at[k])
					f.y = 0
					f.vx = 0
					if f.state ~= "hitstun" and f.hitlag == 0 then
						f.onGround = true
						f.platform = stage.main
						f.vy = 0
					end
					f.facing = if k == 1 then 1 else -1
				end
			end
			table.clear(combat.events)
			for _, f in fighters do
				table.clear(f.events)
			end
			if seg.set then
				for k, kv in seg.set do
					for field, value in kv do
						fighters[tonumber(k) + 1][field] = value
					end
				end
			end
			if seg.act then
				for _, act in seg.act do
					if act.kind == "give" then
						Combat.giveItem(combat, fighters[num(act.f) + 1], ItemData.BY_ID[act.item])
					elseif act.kind == "spawn" then
						Combat.spawnItem(combat, ItemData.BY_ID[act.item], num(act.x), num(act.y))
					elseif act.kind == "maybeSpawn" then
						combat.itemTimer = num(act.timer)
						Combat.maybeSpawnItem(combat, if act.n ~= nil then num(act.n) else #fighters)
					end
				end
			end
			fighters[1]:applyInput(frameFrom(seg.a))
			for k = 2, #fighters do
				fighters[k]:applyInput(frameFrom(seg.b))
			end
			Stage.step(stage, match)
			for _, f in fighters do
				f:step(ctx)
			end
			Combat.step(combat)

			local want = spec.rows[frame + 1]
			local at = 0
			for _, f in fighters do
				for _, k in T.fields do
					at += 1
					checked += 1
					local g, w = f[k], want[at]
					local ok
					if typeof(g) == "number" then
						ok = w ~= nil and near(g, num(w))
					else
						ok = (g == w) or (g == nil and w == nil)
					end
					if not ok then
						fail(string.format("%s frame %d P%d.%s: Luau %s, JS %s",
							spec.name, frame, f.index, k, tostring(g), tostring(w)))
						broke = true
						break
					end
				end
				if broke then break end
			end
			if broke then break end
			at += 1
			checked += 1
			if #fighters ~= num(want[at]) then
				fail(string.format("%s frame %d: %d fighters, JS had %s", spec.name, frame,
					#fighters, tostring(want[at])))
				broke = true
				break
			end
			for _, pair in { { #combat.bursts, "bursts" }, { #combat.projectiles, "projectiles" },
				{ #combat.summons, "summons" }, { #combat.debugBoxes, "debugBoxes" } } do
				at += 1
				checked += 1
				if (pair[1] :: number) ~= num(want[at]) then
					fail(string.format("%s frame %d %s: Luau %d, JS %s", spec.name, frame,
						pair[2] :: string, pair[1] :: number, tostring(want[at])))
					broke = true
				end
			end
			if broke then break end

			-- every live projectile, summon and burst, not just how many
			local lists: { any } = {
				{ combat.projectiles, "projectile", function(p: any): { any }
					return { p.x, p.y, p.vx, p.vy, p.life, p.shape } end },
				{ combat.summons, "summon", function(q: any): { any }
					return { q.type, q.x, q.y, q.life, if q.armed ~= nil then q.armed else -1,
						if q.hp ~= nil then q.hp else -1 } end },
				{ combat.bursts, "burst", function(b: any): { any }
					return { b.move.id, b.x, b.y, b.frames, b.move.damage } end },
				{ combat.items, "item", function(it: any): { any }
					return { it.def.id, it.x, it.y, it.vx, it.vy, it.uses, it.life, it.cd, it.hp,
						it.onGround, if it.held then tostring(it.held.index) else nil } end },
				{ combat.plates, "plate", function(pl: any): { any }
					return { pl.x, pl.y, pl.life, pl.cd, pl.vy } end },
			}
			for _, spec2 in lists do
				at += 1
				local wantList = want[at]
				local live = spec2[1] :: { any }
				checked += 1
				if #live ~= #wantList then
					fail(string.format("%s frame %d: %d %ss, JS had %d", spec.name, frame,
						#live, spec2[2] :: string, #wantList))
					broke = true
					break
				end
				for li, obj in live do
					local got = (spec2[3] :: any)(obj)
					local w = wantList[li]
					for ci, gv in got do
						checked += 1
						local wv = w[ci]
						local ok
						if typeof(gv) == "number" then
							ok = wv ~= nil and near(gv, num(wv))
						else
							ok = gv == wv
						end
						if not ok then
							fail(string.format("%s frame %d %s[%d] field %d: Luau %s, JS %s",
								spec.name, frame, spec2[2] :: string, li, ci, tostring(gv), tostring(wv)))
							broke = true
							break
						end
					end
					if broke then break end
				end
				if broke then break end
			end
			if broke then break end

			-- the combat event stream, in order
			at += 1
			local wantEvents = want[at]
			checked += 1
			if #combat.events ~= #wantEvents then
				local got = {}
				for _, e in combat.events do
					table.insert(got, e.type)
				end
				fail(string.format("%s frame %d: %d combat events (%s), JS had %d",
					spec.name, frame, #combat.events, table.concat(got, ","), #wantEvents))
				broke = true
			else
				for i, e in combat.events do
					local w = wantEvents[i]
					checked += 1
					if e.type ~= w[1] then
						fail(string.format("%s frame %d event %d: %s, JS %s", spec.name, frame, i,
							tostring(e.type), tostring(w[1])))
						broke = true
						break
					end
					for j, key in T.eventNums do
						local gv, wv = e[key], w[j + 1]
						checked += 1
						local ok
						if wv == nil then
							ok = gv == nil
						elseif typeof(gv) == "number" then
							ok = near(gv, num(wv))
						else
							ok = false
						end
						if not ok then
							fail(string.format("%s frame %d event %s.%s: Luau %s, JS %s", spec.name,
								frame, tostring(e.type), key, tostring(gv), tostring(wv)))
							broke = true
							break
						end
					end
					if broke then break end
					-- perfect / heavy, the two booleans the stream carries
					local wp, wh = w[#T.eventNums + 2], w[#T.eventNums + 3]
					checked += 2
					if (e.perfect ~= wp and not (e.perfect == nil and wp == nil))
						or (e.heavy ~= wh and not (e.heavy == nil and wh == nil)) then
						fail(string.format("%s frame %d event %s flags: Luau %s/%s, JS %s/%s",
							spec.name, frame, tostring(e.type), tostring(e.perfect), tostring(e.heavy),
							tostring(wp), tostring(wh)))
						broke = true
						break
					end
				end
			end
			if broke then break end

			-- the fighters' own event stream: jump, land, tech, shieldbreak, counter
			at += 1
			local parts = {}
			for _, f in fighters do
				local types = {}
				for _, e in f.events do
					table.insert(types, e.type)
				end
				table.insert(parts, table.concat(types, ","))
			end
			checked += 1
			if table.concat(parts, "|") ~= want[at] then
				fail(string.format("%s frame %d fighter events: Luau %s, JS %s", spec.name, frame,
					table.concat(parts, "|"), tostring(want[at])))
				broke = true
				break
			end
			frame += 1
		end
	end
end

print(string.format("replayed %d combat values across %d scenarios", checked, #T.scenarios))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print(string.format("Combat.luau matches web/src/engine/combat.js to within %g relative.", EPS))
