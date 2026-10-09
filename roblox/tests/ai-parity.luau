--!strict
-- Do the Luau bots make the same decisions as web/src/engine/ai.js?
--
--   lune run tests/ai-parity
--
-- No scripting and no `set`: the bots play, and the only reason that is reproducible at all is that
-- every decision draws from the match's seeded generator. One wrong comparison anywhere in ai.js
-- sends the match somewhere else within a few frames, which makes this the bluntest test in the
-- suite and also the most sensitive - it is the only one where a single mis-ported `<=` shows up as
-- two completely different matches.
--
-- Each bot's scratch state is compared alongside its position, because a bot can be in the right
-- place with the wrong plan, and the plan decides the next second of play.
--
-- Three things this does not cover:
--   * the `setup` plan. It is READ and never assigned - the comment in ai.js notes that an
--     archetype-string fix left `setup` and `lasso` unreachable, and only `lasso` was restored.
--     Ported faithfully at three lines; it cannot run.
--   * `st.fetchCd`, the 180-frame cooldown after giving up on an item. Reaching it needs a bot to
--     walk at the same item for a hundred frames without closing, and the highest `st.fetch` any
--     scenario here produces is 15 - even with items dropped across Smeltworks' pit.
--   * the keg's near throw bound of 6 studs, which needs a bot holding a Blast Keg while standing
--     between 2 and 6 studs from its target.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Match = Loader.load("Match")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")
local ItemData = Loader.load("Data/Items")
local Combat = Loader.load("Combat")

local T = serde.decode("json", fs.readFile("tests/trace-ai.json"))

local failures: { string } = {}
local checked = 0
local function fail(msg: string)
	if #failures < 8 then
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

local idle = {
	kb2Active = false,
	poll = function(_) end,
	get = function(_): any
		return Input.emptyFrame()
	end,
}

for _, spec in T.scenarios do
	local fighters = {}
	for i, who in spec.who do
		-- with `drops`, the weapon is a pair the fighter arms from drops
		local A = if spec.drops then Loadout.buildArmed(who[1], who[2]) else { char = Loadout.build(who[1], who[2]) }
		table.insert(fighters, { char = A.char, kit = A.kit, fists = A.fists, skin = 0,
			team = if spec.teamOf then num(spec.teamOf[i]) else i - 1,
			source = `p{i - 1}`, isBot = true, botLevel = who[3], name = `P{i - 1}` })
	end
	local m = Match.new({
		mode = spec.mode or "StockFFA", stage = StageData.BY_ID[spec.stage], input = idle,
		seed = num(spec.seed),
		stocks = if spec.stocks ~= nil then num(spec.stocks) else 3,
		timeLimit = if spec.timeLimit ~= nil then num(spec.timeLimit) else 180,
		items = not not spec.items, weaponDrops = not not spec.drops, fighters = fighters,
	})

	-- `rewind`: see gen-ai-traces.mjs
	if spec.rewind then m.combat.rewindOf = function(f: any): number return (f.index * 5 + m.frame) % 14 end end
	if spec.percent then
		for i, p in spec.percent do m.fighters[i].percent = num(p) end
	end
	local broke = false
	local launched = false
	for frame = 1, num(spec.frames) do
		if m.state == "results" then
			break
		end
		-- `launch`: see gen-ai-traces.mjs
		if spec.launch and not launched and m.state == "fight" then
			launched = true
			local a, v = m.fighters[1], m.fighters[2]
			for _, f in { a, v } do
				f.onGround = true; f.platform = m.stage.main; f.y = m.stage.main.top
				f.vx = 0; f.vy = 0; f.invincible = 0
				f:setState("idle")
			end
			a.x = -1.2; v.x = 1.2; a.facing = 1; v.facing = -1
			a:startMove(spec.launch)
		end
		if spec.drop then
			for _, d in spec.drop do
				if num(d.at) == frame - 1 then
					Combat.spawnItem(m.combat, ItemData.BY_ID[d.item], num(d.x), num(d.y))
				end
			end
		end
		-- `ops`: see gen-ai-traces.mjs
		for _, op in (spec.ops and spec.ops[tostring(frame - 1)]) or {} do
			if op.set then
				for k, kv in op.set do
					for field, value in kv do m.fighters[num(k) + 1][field] = value end
				end
			end
			if op.dropAt ~= nil then
				local f = m.fighters[num(op.dropAt) + 1]
				Combat.spawnDrop(m.combat, f.x, f.y + 0.5)
			end
		end
		table.clear(m.events)
		Match.step(m)
		local want = spec.rows[frame]
		if want == nil then
			break
		end
		local at = 0
		local function expect(got: any, label: string, numeric: boolean)
			at += 1
			checked += 1
			local w = want[at]
			local ok
			if w == nil then
				ok = got == nil
			elseif numeric and typeof(got) == "number" then
				ok = near(got, num(w))
			else
				ok = tostring(got) == tostring(w)
			end
			if not ok and not broke then
				fail(string.format("%s frame %d %s: Luau %s, JS %s",
					spec.name, frame, label, tostring(got), tostring(w)))
				broke = true
			end
		end

		expect(m.state, "state", false)
		expect(m.frame, "frame", true)
		for _, f in m.fighters do
			for _, k in T.fields do
				expect(f[k], `P{f.index}.{k}`, true)
			end
			local ai = f.ai
			for _, k in T.ai do
				expect(if ai then ai[k] else nil, `P{f.index}.ai.{k}`, false)
			end
			-- chain.i is 1-based here and 0-based in the JavaScript, because Luau arrays are.
			-- The same step runs either way; the index is reported zero-based so the two agree.
			expect(if ai and ai.chain then `{ai.chain.name}:{ai.chain.i - 1}:{ai.chain.t}` else nil,
				`P{f.index}.ai.chain`, false)
		end
		if broke then break end

		at += 1
		local wantEvents = want[at]
		checked += 1
		if #m.events ~= #wantEvents then
			local got = {}
			for _, e in m.events do
				table.insert(got, e.type)
			end
			fail(string.format("%s frame %d: %d events (%s), JS had %d", spec.name, frame,
				#m.events, table.concat(got, ","), #wantEvents))
			broke = true
		else
			for i, e in m.events do
				local w = wantEvents[i]
				checked += 1
				if tostring(e.type) ~= tostring(w[1])
					or (w[2] ~= nil and tostring(e.fighter) ~= tostring(w[2]))
					or (w[3] ~= nil and tostring(e.by) ~= tostring(w[3])) then
					fail(string.format("%s frame %d event %d: Luau %s/%s/%s, JS %s/%s/%s",
						spec.name, frame, i, tostring(e.type), tostring(e.fighter), tostring(e.by),
						tostring(w[1]), tostring(w[2]), tostring(w[3])))
					broke = true
					break
				end
			end
		end
		if broke then break end
	end
end

print(string.format("replayed %d bot values across %d scenarios", checked, #T.scenarios))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print(string.format("Ai.luau matches web/src/engine/ai.js to within %g relative.", EPS))
