--!strict
-- Does Stage.luau behave like web/src/engine/stage.js, frame by frame?
--
--   lune run tests/stage-parity
--
-- tools/gen-traces.mjs drives the REAL JavaScript StageRuntime through four scenarios and records
-- what it did. This replays the same scenarios through the Luau port. Reading two files side by
-- side cannot catch a 0-vs-1 indexing slip or a comparison written the wrong way round; replaying
-- them can, and it names the first frame that differs.
--
-- Numbers arrive as decimal STRINGS - see the header of gen-traces.mjs.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Stage = Loader.load("Stage")
local StageData = Loader.load("Data/Stages")

local T = serde.decode("json", fs.readFile("tests/trace-stage.json"))

local failures: { string } = {}
local checked = 0

local function fail(msg: string)
	if #failures < 12 then
		table.insert(failures, msg)
	end
end

local function num(s: any): number
	return tonumber(s) :: number
end

-- Why a relative epsilon rather than exact equality.
--
-- Everything algebraic here IS bit-exact - the data parity test proves doubles survive the trip.
-- But Math.sin in V8 and math.sin in Luau are not the same function: given a bit-identical input
-- they return results two ulps apart, and every moving platform's position runs through one. No
-- port can fix that short of reimplementing sin, and the knockback parity test has always carried
-- the same tolerance for the same reason.
--
-- 1e-12 relative sits four orders of magnitude above that noise and far below anything a real
-- porting mistake produces: a flipped comparison, a 0-vs-1 index or a missing branch moves a
-- number by whole studs, not by its last two bits.
local EPS = 1e-12

local function near(a: number, b: number): boolean
	local diff = math.abs(a - b)
	return diff <= EPS or diff <= EPS * math.max(math.abs(a), math.abs(b))
end

local function eqNum(got: number, want: any, where: string)
	checked += 1
	if not near(got, num(want)) then
		fail(string.format("%s: Luau %.17g, JS %s", where, got, tostring(want)))
	end
end

local function eqAny(got: any, want: any, where: string)
	checked += 1
	if got ~= want and not (got == nil and want == nil) then
		fail(string.format("%s: Luau %s, JS %s", where, tostring(got), tostring(want)))
	end
end

-- Hazards are stripped on both sides: Stage.luau throws on a hazard it cannot step, which is what
-- keeps Phase 2b from being quietly forgotten.
local function build(id: string): any
	local data = table.clone(StageData.BY_ID[id])
	data.hazards = {}
	return Stage.new(data)
end

local function probeBody(o: any): any
	local b: any = {
		alive = true, onGround = false, platform = nil, dropTimer = 0,
		r = 1.1, h = 5.2, x = 0, y = 0, vy = 0, facing = 1, ledgeCooldown = 0, ledgeGrabs = 0,
		env = { updraft = 0, windX = 0, traction = 1, grip = 1, damp = 1 },
		dropped = 0,
	}
	b.dropThrough = function(self: any)
		self.dropped += 1
		self.onGround = false
		self.platform = nil
	end
	for k, v in o do
		b[k] = v
	end
	return b
end

local function checkPlatform(p: any, row: any, where: string)
	eqAny(p.id, row[1], where .. ".id")
	eqNum(p.x1, row[2], where .. ".x1")
	eqNum(p.x2, row[3], where .. ".x2")
	eqNum(p.top, row[4], where .. ".top")
	eqNum(p.bottom, row[5], where .. ".bottom")
	eqNum(p.cx, row[6], where .. ".cx")
	eqNum(p.dx, row[7], where .. ".dx")
	eqNum(p.dy, row[8], where .. ".dy")
	if row[9] ~= nil then
		eqNum(p.sink, row[9], where .. ".sink")
	end
	if row[10] ~= nil then
		eqNum(p.occupiedFrames, row[10], where .. ".occupiedFrames")
	end
end

-- ---- 1. construction: platforms, solids, ledges, blast box ----
for _, g in T.geometry do
	local st = build(g.id)
	eqNum(st.blast.left, g.blast.left, g.id .. " blast.left")
	eqNum(st.blast.right, g.blast.right, g.id .. " blast.right")
	eqNum(st.blast.top, g.blast.top, g.id .. " blast.top")
	eqNum(st.blast.bottom, g.blast.bottom, g.id .. " blast.bottom")
	checkPlatform(st.main, g.main, g.id .. " main")
	checked += 1
	if #st.platforms ~= #g.platforms then
		fail(string.format("%s: %d platforms, JS built %d", g.id, #st.platforms, #g.platforms))
	else
		for i, row in g.platforms do
			checkPlatform(st.platforms[i], row, string.format("%s platform[%d]", g.id, i))
		end
	end
	checked += 1
	if #st.solids ~= #g.solids then
		fail(string.format("%s: %d solids, JS built %d", g.id, #st.solids, #g.solids))
	else
		for i, id in g.solids do
			eqAny(st.solids[i].id, id, string.format("%s solid[%d]", g.id, i))
		end
	end
	-- Ledge ORDER matters as much as ledge content: the list is walked in order by ledgeFor, so
	-- two stages that own the same ledges in a different order are not the same stage.
	checked += 1
	if #st.ledges ~= #g.ledges then
		fail(string.format("%s: %d ledges, JS built %d", g.id, #st.ledges, #g.ledges))
	else
		for i, row in g.ledges do
			local L = st.ledges[i]
			eqNum(L.x, row[1], string.format("%s ledge[%d].x", g.id, i))
			eqNum(L.y, row[2], string.format("%s ledge[%d].y", g.id, i))
			eqNum(L.side, row[3], string.format("%s ledge[%d].side", g.id, i))
			eqAny(L.platform.id, row[4], string.format("%s ledge[%d].platform", g.id, i))
		end
	end
end

-- ---- 2. moving and sinking platforms, stepped for real ----
for _, m in T.motion do
	local st = build(m.id)
	local body = probeBody({})
	if m.standOn ~= nil then
		for _, p in st.platforms do
			if p.id == m.standOn then
				body.onGround = true
				body.platform = p
				body.x = p.cx
				body.y = p.top
			end
		end
	end
	local match = { fighters = { body } }
	-- Per-scenario, not global: a `#failures > 0` guard here meant one stage failing cut every
	-- LATER stage off after a single frame, and then reported their untouched stage.time as a
	-- second and third failure. Three bugs on the report, one bug in the code.
	local before = #failures
	local wanted: { [string]: boolean } = {}
	for _, id in m.dynamic do
		wanted[id] = true
	end
	for i = 1, m.frames do
		Stage.step(st, match)
		local got = {}
		for _, p in st.platforms do
			if wanted[p.id] then
				table.insert(got, p)
			end
		end
		local row = m.rows[i]
		for k, want in row do
			checkPlatform(got[k], want, string.format("%s frame %d platform[%d]", m.id, i, k))
		end
		if #failures > before then
			break -- the first divergent frame is the informative one; the rest are noise
		end
	end
	eqNum(st.time, m.time, m.id .. " stage.time")
	eqAny(body.dropped, m.dropped, m.id .. " dropThrough calls")

	-- Replay the scoop probes, which need the stage stepped to the same frame they were recorded
	-- at. Rebuilt rather than reused so a failure above does not leave the stage mid-trace.
	local st2 = build(m.id)
	local body2 = probeBody({})
	if m.standOn ~= nil then
		for _, p in st2.platforms do
			if p.id == m.standOn then
				body2.onGround = true
				body2.platform = p
				body2.x = p.cx
				body2.y = p.top
			end
		end
	end
	local match2 = { fighters = { body2 } }
	local byFrame: { [number]: { any } } = {}
	for _, r in m.scoop do
		local fi = num(r[1])
		byFrame[fi] = byFrame[fi] or {}
		table.insert(byFrame[fi], r)
	end
	local before2 = #failures
	for i = 0, m.frames - 1 do
		Stage.step(st2, match2)
		for _, r in byFrame[i] or {} do
			local target = nil
			for _, p in st2.platforms do
				if p.id == r[2] then
					target = p
				end
			end
			local px, py = target.cx, target.top + num(r[3])
			local f = probeBody({ x = px, y = py, vy = 0 })
			local res = Stage.collide(st2, f, px, py, px, py)
			local w = string.format("%s scoop frame %d %s off %s", m.id, i, tostring(r[2]), tostring(r[3]))
			eqNum(res.x, r[4], w .. ".x")
			eqNum(res.y, r[5], w .. ".y")
			eqAny(if res.landed then res.landed.id else nil, r[6], w .. ".landed")
			eqAny(res.wall, r[7], w .. ".wall")
			eqAny(res.bumped, r[8], w .. ".bumped")
		end
		if #failures > before2 then
			break
		end
	end
end

-- ---- 3. collide / supported / ledgeFor / surfaceUnder / nearestLedge ----
for _, q in T.queries do
	local st = build(q.id)
	for _, r in q.collide do
		local px, py = num(r[1]), num(r[2])
		local f = probeBody({ x = px, y = py, vy = num(r[5]), dropTimer = num(r[6]) })
		local res = Stage.collide(st, f, px, py, px + num(r[3]), py + num(r[4]))
		local w = string.format("%s collide(%s,%s,+%s,+%s)", q.id, r[1], r[2], r[3], r[4])
		eqNum(res.x, r[7], w .. ".x")
		eqNum(res.y, r[8], w .. ".y")
		eqAny(if res.landed then res.landed.id else nil, r[9], w .. ".landed")
		eqAny(res.wall, r[10], w .. ".wall")
		eqAny(res.bumped, r[11], w .. ".bumped")
	end
	for _, r in q.support do
		local target = nil
		for _, p in st.platforms do
			if p.id == r[3] then
				target = p
			end
		end
		local f = probeBody({ x = num(r[1]), y = num(r[2]), platform = target })
		eqAny(Stage.supported(st, f), r[4], string.format("%s supported(%s,%s,%s)", q.id, r[1], r[2], tostring(r[3])))
	end
	for _, r in q.ledge do
		local f = probeBody({ x = num(r[1]), y = num(r[2]), vy = -3, facing = num(r[3]) })
		local L = Stage.ledgeFor(st, f, r[4])
		local w = string.format("%s ledgeFor(%s,%s,facing %s,guard %s)", q.id, r[1], r[2], r[3], tostring(r[4]))
		if r[5] == nil then
			eqAny(if L then L.platform.id else nil, nil, w)
		elseif L == nil then
			fail(w .. ": Luau found no ledge, JS found " .. tostring((r[5] :: any)[4]))
			checked += 1
		else
			eqNum(L.x, (r[5] :: any)[1], w .. ".x")
			eqNum(L.side, (r[5] :: any)[3], w .. ".side")
			eqAny(L.platform.id, (r[5] :: any)[4], w .. ".platform")
		end
	end
	for _, r in q.surface do
		local s = Stage.surfaceUnder(st, num(r[1]), num(r[2]))
		eqAny(if s then s.id else nil, r[3], string.format("%s surfaceUnder(%s,%s)", q.id, r[1], r[2]))
	end
	for _, r in q.nearest do
		local near = Stage.nearestLedge(st, num(r[1]), num(r[2]))
		local id = if near.ledge then `{near.ledge.platform.id}:{near.ledge.side}` else nil
		eqAny(id, r[3], string.format("%s nearestLedge(%s,%s).ledge", q.id, r[1], r[2]))
		eqNum(near.dist, r[4], string.format("%s nearestLedge(%s,%s).dist", q.id, r[1], r[2]))
	end
end

-- ---- 3b. the moving-solid ejection branch ----
-- Unreachable from the real roster (no stage has a moving solid), so it runs on the synthetic
-- stage carried in the trace. Deleting this branch from Stage.luau passed every other check here.
do
	local st = Stage.new(T.syntheticData)
	local match = { fighters = { probeBody({}) } }
	for i, frame in T.mover do
		Stage.step(st, match)
		local slider = nil
		for _, p in st.platforms do
			if p.id == "slider" then
				slider = p
			end
		end
		checkPlatform(slider, frame.slider, string.format("mover frame %d slider", i))
		for k, r in frame.probes do
			local px, py = num(r[1]), num(r[2])
			local f = probeBody({ x = px, y = py, vy = 0 })
			local res = Stage.collide(st, f, px, py, px, py)
			local w = string.format("mover frame %d probe %d (%s,%s)", i, k, r[1], r[2])
			eqNum(res.x, r[3], w .. ".x")
			eqNum(res.y, r[4], w .. ".y")
			eqAny(if res.landed then res.landed.id else nil, r[5], w .. ".landed")
			eqAny(res.wall, r[6], w .. ".wall")
			eqAny(res.bumped, r[7], w .. ".bumped")
		end
	end
end

-- ---- 4. sudden death ----
for _, s in T.shrink do
	local st = build(s.id)
	for i, row in s.steps do
		Stage.shrink(st, 0.8)
		eqNum(st.blast.left, row[1], string.format("%s shrink[%d].left", s.id, i))
		eqNum(st.blast.right, row[2], string.format("%s shrink[%d].right", s.id, i))
		eqNum(st.blast.top, row[3], string.format("%s shrink[%d].top", s.id, i))
		eqNum(st.blast.bottom, row[4], string.format("%s shrink[%d].bottom", s.id, i))
	end
	for _, r in s.out do
		eqAny(Stage.outsideBlast(st, { x = num(r[1]), y = num(r[2]), h = 5.2 }), r[3],
			string.format("%s outsideBlast(%s,%s)", s.id, r[1], r[2]))
	end
end

print(string.format("replayed %d stage values against the JavaScript", checked))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print(string.format("Stage.luau matches web/src/engine/stage.js to within %g relative.", EPS))
