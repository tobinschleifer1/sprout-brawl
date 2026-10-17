--!nocheck
-- Weapons held one in each hand (src/client/DualWield.luau, Roblox only). Direct properties: each
-- hand draws one unit of the pair, strings alternate hands, the hand not striking guards and then
-- chambers, a back-hand strike twists the rear shoulder forward, a both-hands move puts the second
-- weapon beside the first, a Chakram holds only the rings it has. Both hands sitting exactly on
-- their weapons, and the move's weapon on its authored grip, are held by tests/posture.
local Loader = require("./loader")
local DualWield = Loader.loadFrom("src/client/", "DualWield")
local Posture = Loader.loadFrom("src/client/", "Posture")
local Channels = Loader.loadFrom("src/client/", "Channels")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Recorder = require("../tools/recorder")
Recorder.install(Canvas)
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local ART = Loader.load("Weapons").ART

local function state(c, name, id, mf, extra)
	local f = Fighter.new({ index = 0, char = c, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.facing, f.invincible = name, true, 1, 0
	if id then f.move = Fighter.moveOf(c, id); f.moveId = id; f.mf = mf; f.sf = mf end
	f.frameCount = 100 + (mf or 0)
	local s = Snapshot.decode(Snapshot.encode(f))
	for k, v in extra or {} do s[k] = v end
	return s
end
local function pose(c, s)
	local move = Fighter.moveOf(c, s.moveId)
	local t = s.frameCount / 60
	local ch = Channels.For(s, c, move, t)
	return Posture.For(ch, s, c, WeaponPose.For(s, c, move, t), move, t), move
end
-- every weapon draw of one fighter: its id and whether it is the second of the pair
local function draws(c, s)
	local seen = {}
	local real = Weapons2D.draw
	Weapons2D.draw = function(cv, wid, pal, p) table.insert(seen, { id = wid, off = p.offhand == true, m = table.clone(cv.m) }); return real(cv, wid, pal, p) end
	local cv = Recorder.canvas(Canvas, 300, 260)
	Canvas.world(cv, 0, 3, 26, 0, 0)
	Fighter2D.draw(cv, s, c, s.frameCount / 60)
	Weapons2D.draw = real
	return seen
end
local function bounds(rects)
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, r in rects do x0, x1, y0, y1 = math.min(x0, r[1]), math.max(x1, r[1] + r[3]), math.min(y0, r[2]), math.max(y1, r[2] + r[4]) end
	return x0, x1, y0, y1
end

-- The art: one dagger, as far ahead of its grip as the pair's front blade, with no reverse blade
-- behind the hand; one ring, half the pair's width.
do
	local px0, px1 = bounds(ART.sprites.Daggers)
	local sx0, sx1 = bounds(ART.single.Daggers)
	assert(math.abs(sx1 - px1) < 1 / 8 + 1e-9, `one dagger reaches {sx1}, the pair's front blade {px1}`)
	assert(sx0 > px0 + 0.5, "the single dagger still has the reverse blade behind the hand")
	local cx0, cx1 = bounds(ART.sprites.Chakram)
	local rx0, rx1 = bounds(ART.single.Chakram)
	assert((rx1 - rx0) < (cx1 - cx0) * 0.6, "the single ring is as wide as the pair")
	-- and that is what a hand draws: the unit's picture, narrower than the pair's
	for _, w in { "Daggers", "Chakram" } do
		assert(Weapons2D.sprite(w .. ":one").cols < Weapons2D.sprite(w).cols * 0.8, `one of the {w} draws the pair's picture`)
	end
	assert(Weapons2D.sprite("Blasters:one").cols == Weapons2D.sprite("Blasters").cols, "a weapon already drawn as one unit lost its picture")
	assert(Weapons2D.sprite("Blasters:one").rects == Weapons2D.sprite("Blasters:one").rects, "unit pictures are rebuilt per call")
end

-- The hand order itself, independent of the table the code reads: a string alternates hands and
-- ends with both (jab, cross, both), its side string goes front then back, the uppercut and the
-- lunging signature come from the rear hand, the ultimate uses both.
do
	local S = DualWield.STRIKE
	assert((S.LightNeutral1 or "front") == "front" and S.LightNeutral2 == "back" and S.LightNeutral3 == "both", "the neutral string does not go front, back, both")
	assert((S.LightSide1 or "front") == "front" and S.LightSide2 == "back", "the side string does not alternate")
	assert(S.LightUp == "back" and S.SigSide == "back" and S.Ultimate == "both", "the uppercut, lunge or ultimate is on the wrong hand")
end

local checked = 0
for wid in DualWield.PAIRED do
	local c = Loadout.build("Classic", wid)
	local r, h = c.radius, c.height
	-- Standing: one unit in each hand, the front one carrying the weapon's pose.
	local idle = draws(c, state(c, "idle"))
	assert(#idle == 2 and idle[1].id == wid .. ":one" and idle[2].id == wid .. ":one", `{wid}: standing, it does not hold one in each hand ({#idle} drawn)`)
	-- the rear hand's is drawn first, behind the body; the front one, carrying the pose, after
	assert(idle[1].off and not idle[2].off, `{wid}: standing, the second weapon is not the rear hand's, behind`)
	local rest = pose(c, state(c, "idle"))
	-- Through every move: the striking hand is the table's, and the other hand behaves.
	for id in c.moves do
		local move = Fighter.moveOf(c, id)
		local striker = DualWield.STRIKE[id] or "front"
		local mid = move.startup + math.max(1, math.floor(move.active / 2))
		local p = pose(c, state(c, "attack", id, mid))
		assert(p.dual and p.dual.striker == striker, `{wid} {id}: struck with {p.dual and p.dual.striker}, not the {striker} hand`)
		if not p.dual.off then
			-- only a move that hides the weapon outright (the Chakram's ultimate throws both) has none
			local s = state(c, "attack", id, mid)
			assert(WeaponPose.For(s, c, move, s.frameCount / 60).hide, `{wid} {id}: the second weapon went missing`)
			continue
		end
		-- the twist, measured as what it does: the same frame posed with it switched off
		local saved = DualWield.TWIST.back
		DualWield.TWIST.back = 0
		local flat = pose(c, state(c, "attack", id, mid))
		DualWield.TWIST.back = saved
		local twist = p.backX - flat.backX
		if striker == "back" then
			-- the rear shoulder comes forward to reach, the front hand holds the other weapon
			assert(twist > r * 0.5, `{wid} {id}: the rear shoulder did not twist forward for its strike ({twist})`)
			assert(p.dual.off.hand == "front", `{wid} {id}: a back-hand strike left the front hand empty`)
		else
			assert(math.abs(twist) < 1e-9, `{wid} {id}: the torso twisted for a {striker}-hand strike`)
		end
		if striker == "both" then
			-- the second weapon beside the first, not left at the guard
			local d = math.sqrt((p.offX - p.front.ex) ^ 2 + (p.offY - p.front.ey) ^ 2)
			assert(d < r * 0.6, `{wid} {id}: a both-hands strike holds the second weapon {d} away from the first`)
		else
			-- the hand not striking chambers back toward the hip: behind and below its guard
			local guard = if p.dual.off.hand == "back" then { rest.offX, rest.offY } else nil
			if guard then
				assert(p.offX < guard[1] - r * 0.3 and p.offY < guard[2], `{wid} {id}: the free hand did not chamber`)
			end
		end
		-- and the commitment eases out: the last frame is back at the guard, untwisted
		local last = pose(c, state(c, "attack", id, move.total))
		assert(last.dual.twist < 1e-9, `{wid} {id}: the twist does not ease out by the move's end`)
		checked += 1
	end
end

-- A Chakram holds the rings it has: two, one (in the striking hand, the other hand empty), none.
do
	local c = Loadout.build("Classic", "Chakram")
	local function count(rings, id, mf)
		local s = if id then state(c, "attack", id, mf, { rings = rings }) else state(c, "idle", nil, nil, { rings = rings })
		return #draws(c, s), pose(c, s)
	end
	assert(count(2) == 2, "two rings, but not one in each hand")
	local n, p = count(1)
	assert(n == 1 and p.dual.off and p.dual.off.empty, "one ring left, but two drawn or no free hand")
	assert(count(0) == 0, "no rings left, but a ring is drawn")
	local n2, p2 = count(1, "LightNeutral3", 8)
	assert(n2 == 1 and p2.dual.striker == "front", "one ring left, and a both-hands move draws two")
end

-- A weapon not held in pairs is untouched: one picture, the weapon's own, in the front hand.
for _, wid in { "Sword", "Hammer", "Longbow" } do
	local c = Loadout.build("Classic", wid)
	local d = draws(c, state(c, "attack", "LightNeutral2", 6))
	assert(#d == 1 and d[1].id == wid and not d[1].off, `{wid} is drawn as a pair`)
	assert(pose(c, state(c, "idle")).dual == nil, `{wid} is posed as a pair`)
end
print(string.format("PASS dual wield: one unit in each hand for %d moves of the four paired weapons; hands alternate as the table says, the free hand guards and chambers, back-hand strikes twist and ease out, both-hands moves pair up; a Chakram holds the rings it has; single weapons untouched; one dagger has the pair's reach", checked))
