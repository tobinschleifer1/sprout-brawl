--!nocheck
-- Overlapping action on a held blade (Fighter2D.bladeLag, Roblox only). Direct properties: the
-- blade trails the hand's turn and settles when the hand stops, dips as the run lifts the body,
-- leaves cuts and unlisted weapons alone, and turns about the grip in the drawing.
local Loader = require("./loader")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")
local Movement = Loader.loadFrom("src/client/", "Movement")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
-- a recording canvas, as tools/render-posture draws through the shipping renderer
local Recorder = require("../tools/recorder")
Recorder.install(Canvas)
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local char = Loadout.build("Classic", "Sword")
local function attack(c, id, mf)
	local f = Fighter.new({ index = 0, char = c, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.facing, f.invincible = "attack", true, 1, 0
	f.move = Fighter.moveOf(c, id); f.moveId = id; f.mf = mf; f.sf = mf; f.frameCount = 100 + mf
	return Snapshot.decode(Snapshot.encode(f)), f.move
end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end

-- Through every move of every bladed weapon: wherever the hand turned in the last frames, the
-- blade is behind it; once the hand has held still for those frames, it is exactly where it is posed.
local trailed, settled = 0, 0
local blades = {}
for wid in Fighter2D.OVERLAP do table.insert(blades, wid) end
table.sort(blades)
assert(#blades >= 5, "the bladed weapons are not all listed for overlap")
for _, wid in blades do
	local char = Loadout.build("Classic", wid)
	for id in char.moves do
		if id == "Ultimate" then continue end
		local move = Fighter.moveOf(char, id)
		for mf = 3, move.total do
			local s = attack(char, id, mf)
			local t = s.frameCount / 60
			local wp = WeaponPose.For(s, char, move, t)
			local was = attack(char, id, mf - 3)
			local turn = wrap(wp.angle - WeaponPose.For(was, char, move, (s.frameCount - 3) / 60).angle)
			local lag = Fighter2D.bladeLag(s, char, move, t, wp)
			assert(math.abs(lag) <= 0.3 + 1e-12, `{wid} {id} {mf}: the blade trails {lag} rad, past its limit`)
			if math.abs(turn) > 1.2 then
				assert(lag == 0, `{wid} {id} {mf}: a cut between poses ({turn} rad) dragged the blade`)
			elseif math.abs(turn) > 0.05 then
				assert(lag * turn < 0, `{wid} {id} {mf}: the hand turned {turn} and the blade led it by {lag}`)
				trailed += 1
			elseif math.abs(turn) < 1e-9 then
				assert(math.abs(lag) < 1e-9, `{wid} {id} {mf}: the hand is still and the blade is still moving ({lag})`)
				settled += 1
			end
		end
	end
end
assert(trailed > 100 and settled > 100, `only {trailed} trailing and {settled} settled frames checked`)

-- An ultimate's cinematic holds its move frame: nothing lags. Neither does a weapon not listed.
do
	local s, move = attack(char, "Ultimate", 30)
	assert(Fighter2D.bladeLag(s, char, move, 2, WeaponPose.For(s, char, move, 2)) == 0, "an ultimate's frozen frame lags")
	local other
	for _, w in Loader.load("Data/Weapons").LIST do
		if not Fighter2D.OVERLAP[w.id] then other = w.id; break end
	end
	local oc = Loadout.build("Classic", other)
	local os_, om = attack(oc, "LightSide2", 6)
	assert(Fighter2D.bladeLag(os_, oc, om, 2, WeaponPose.For(os_, oc, om, 2)) == 0, `{other} is not listed, and lags`)
end

-- Running: as the body rises the tip is held back down, and as it falls the tip lifts.
local up, down = 0, 0
for j = 0, 120 do
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.facing, f.invincible = "run", true, 1, 0
	f.vx = char.runSpeed; f.x = j * 0.05; f.frameCount = 0
	local s = Snapshot.decode(Snapshot.encode(f))
	local was = table.clone(s); was.x -= s.vx * 3 / 60
	local rise = Movement.bob(s, char) - Movement.bob(was, char)
	local wp = WeaponPose.For(s, char, nil, 0)
	local lag = Fighter2D.bladeLag(s, char, nil, 0, wp)
	if rise > 0.02 then assert(lag < 0, "the body rose and the blade tip rose with it"); up += 1 end
	if rise < -0.02 then assert(lag > 0, "the body fell and the blade tip fell with it"); down += 1 end
end
assert(up > 10 and down > 10, `only {up} rising and {down} falling run samples`)

-- In the drawing: the blade is drawn at its posed angle plus the lag, from the same grip.
do
	local s, move = attack(char, "LightSide2", 6)
	local t = s.frameCount / 60
	local wp = WeaponPose.For(s, char, move, t)
	local lag = Fighter2D.bladeLag(s, char, move, t, wp)
	assert(math.abs(lag) > 0.05, "this frame does not lag enough to test the drawing")
	local seen
	local real = Weapons2D.draw
	Weapons2D.draw = function(cv, wid, pal, pose) seen = { pose.angle, cv.m.e, cv.m.f }; return real(cv, wid, pal, pose) end
	local cv = Recorder.canvas(Canvas, 300, 260)
	Canvas.world(cv, 0, 3, 26, 0, 0)
	Fighter2D.draw(cv, s, char, t)
	local at = seen
	Fighter2D.OVERLAP.Sword = nil
	seen = nil
	Fighter2D.draw(cv, s, char, t)
	Fighter2D.OVERLAP.Sword = 0.4
	Weapons2D.draw = real
	assert(math.abs(at[1] - (wp.angle + lag)) < 1e-12, `the blade is drawn at {at[1]}, posed {wp.angle} with lag {lag}`)
	assert(math.abs(seen[1] - wp.angle) < 1e-12, "without overlap the blade is not drawn as posed")
	assert(at[2] == seen[2] and at[3] == seen[3], "the overlap moved the grip")
end
print(string.format("PASS overlap: " .. table.concat(blades, ", ") .. ": the blade trails the hand on %d frames and is exactly posed on %d still ones; cuts, ultimates and unlisted weapons untouched; it dips against the run's bounce (%d/%d); drawn about the same grip", trailed, settled, up, down))
