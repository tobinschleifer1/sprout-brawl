--!strict
-- How a hit looks, and the shield: the impact a landed hit draws (FxPlayer.hit), the shell a
-- shielding fighter is drawn in (ShieldArt), and what a fighter sent flying trails behind them
-- (HitReact). All Roblox-only drawing over the parity-held simulation, so what is held here is the
-- drawing's own rules, asserted directly:
--
--   * every weapon has a style of hit; each style draws its own drawing, in the attacker's weapon
--     colour, bigger for more damage, aimed along the knockback (and mirrored with the attacker's
--     facing); a heavy hit on a grounded victim kicks up dust at their feet and only then; a hit
--     with no attacker on stage draws nothing here (Effects' rings stand in);
--   * a broken shield shatters in the shield's colour, shards thrown evenly all round;
--   * the shell is exactly as big as Shield.shapes says at every strength, centred on the fighter,
--     gone at no strength, flickers below 30% and only then, cracks more as it weakens, is drawn in
--     the fighter's colour (team colour in a team match) with a see-through fill and a solid rim,
--     and flares on its rim where it was struck;
--   * speed lines stream behind a fighter flying fast in hitstun and only then, smoke trails only
--     at a higher speed, puffs stay where the fighter was, and the trail clears itself after.
--
--     lune run tests/hit-fx
local Loader = require("./loader")
local Loadout = Loader.load("Loadout")
local Weapons = Loader.load("Data/Weapons")
local Canvas2D = Loader.loadFrom("src/client/", "Canvas2D")
local FxArt = Loader.loadFrom("src/client/", "FxArt")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local Effects = Loader.loadFrom("src/client/", "Effects")
local Shield = Loader.loadFrom("src/client/", "Shield")
local ShieldArt = Loader.loadFrom("src/client/", "ShieldArt")
local HitReact = Loader.loadFrom("src/client/", "HitReact")

local function fail(msg: string): never
	error(msg, 0)
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local function angleNear(a: number, b: number): boolean
	return math.abs(math.atan2(math.sin(a - b), math.cos(a - b))) < 1e-6
end

-- ------------------------------------------------------------------ impacts ----
for _, w in Weapons.LIST do
	if not FxPlayer.CLASS[w.id] then fail(`{w.id} has no style of hit (it would fall back to a blunt crunch)`) end
end

local DRAWING = { slash = "crescent", pierce = "lance", magic = "star", blunt = "pop" }
local REP = { slash = "Sword", pierce = "Pike", magic = "Grimoire", blunt = "Hammer" }

local function hitWith(weapon: string, e: any, victimGrounded: boolean?): (any, any, boolean)
	local char = Loadout.build("Classic", weapon)
	local chars = { char, Loadout.build("Classic", "Sword") }
	local states = { { index = 0, x = 0, y = 0, moveId = "LightSide1" }, { index = 1, x = 1.5, y = 0, onGround = victimGrounded } }
	local P = FxPlayer.new()
	local ok = FxPlayer.hit(P, e, states, chars)
	return P, char, ok
end
local function event(over: any?): any
	local e = { type = "hit", x = 1, y = 1.2, damage = 8, angle = 30, facing = 1, attacker = 0, victim = 1, heavy = false }
	for k, v in over or {} do e[k] = v end
	return e
end
local function find(P: any, kind: string): any
	for _, it in P.items do if it.kind == kind then return it end end
	return nil
end

for class, weapon in REP do
	local kind = DRAWING[class]
	for _, facing in { 1, -1 } do
		local P, char, ok = hitWith(weapon, event({ facing = facing }))
		if not ok then fail(`{weapon}: the hit was not drawn`) end
		local it = find(P, kind)
		if not it then fail(`{weapon} ({class}) drew no {kind}`) end
		if it.ramp ~= FxArt.glowOf(char) then fail(`{weapon}: drawn in {it.ramp}, its weapon colour is {FxArt.glowOf(char)}`) end
		-- the knockback: 30 degrees up, away from the attacker
		local dir = math.atan2(math.sin(math.rad(30)), math.cos(math.rad(30)) * facing)
		if class == "slash" and not angleNear(it.rot, dir + math.pi / 2) then
			fail(`{weapon} facing {facing}: the cut is at {math.deg(it.rot)} degrees, across a blow at {math.deg(dir)}`)
		end
		if class == "pierce" then
			if not angleNear(it.rot, dir) then fail(`{weapon} facing {facing}: the lance points {math.deg(it.rot)}, the blow goes {math.deg(dir)}`) end
			-- driven through from behind: the streak starts on the attacker's side of the contact
			local back = (it.x - 1) * math.cos(dir) + (it.y - 1.2) * math.sin(dir)
			if back >= 0 then fail(`{weapon} facing {facing}: the lance sits ahead of the contact, not behind it`) end
		end
	end
	-- more damage, a bigger impact
	local small = find((hitWith(weapon, event({ damage = 3 }))), kind)
	local big = find((hitWith(weapon, event({ damage = 18 }))), kind)
	if not (big.size > small.size) then fail(`{weapon}: an 18-damage hit drew no bigger than a 3-damage one`) end
end

-- one variation of each impact drawing however many hits land: every variation is a sprite built
-- the first time it is seen, and the angle already makes each hit look different
do
	local char = Loadout.build("Classic", "Sword")
	local states = { { index = 0, x = 0, y = 0 }, { index = 1, x = 1.5, y = 0, onGround = true } }
	local Q = FxPlayer.new()
	for n = 1, 8 do FxPlayer.hit(Q, event({ heavy = true, angle = n * 20 }), states, { char, char }) end
	local seeds: { [string]: number } = {}
	for _, it in Q.items do
		if seeds[it.kind] and seeds[it.kind] ~= it.seed then fail(`hits drew more than one variation of the {it.kind}`) end
		seeds[it.kind] = it.seed
	end
end

-- dust under a heavy hit on a grounded victim, and only then
local function smoke(P: any): any
	for _, it in P.items do if it.kind == "burst" and it.ramp == "smoke" then return it end end
	return nil
end
local P = hitWith("Hammer", event({ heavy = true }), true)
local dust = smoke(P)
if not dust then fail("a heavy hit on a grounded victim kicked up no dust") end
if not near(dust.x, 1.5) or math.abs(dust.y - 0) > 0.6 then fail(`the dust is at ({dust.x}, {dust.y}), the victim's feet are at (1.5, 0)`) end
if smoke((hitWith("Hammer", event({ heavy = true }), false))) then fail("a heavy hit in the air kicked up dust") end
if smoke((hitWith("Hammer", event({ heavy = false }), true))) then fail("a light hit kicked up dust") end
-- a hit from no one on stage (a hazard, a disaster) is left to Effects
local none, _, drawn = hitWith("Sword", event({ attacker = -1 }))
if drawn or #none.items > 0 then fail("a hit with no attacker on stage was drawn here as well as by Effects") end
local viaSpawn = FxPlayer.new()
if not FxPlayer.spawn(viaSpawn, event(), { { index = 0, x = 0, y = 0 }, { index = 1, x = 1, y = 0 } },
	{ Loadout.build("Classic", "Axe"), Loadout.build("Classic", "Axe") }) or not find(viaSpawn, "crescent") then
	fail("FxPlayer.spawn does not route hits to the impact drawing")
end

-- ------------------------------------------------------------------ shield break ----
do
	local was = FxPlayer.shieldColour
	FxPlayer.shieldColour = function(i: number?) return if i == 2 then "#FF4A6A" else "#000000" end
	local B = FxPlayer.new()
	if not FxPlayer.spawn(B, { type = "shieldbreak", fighter = 2, x = 4, y = 3 }, {}, {}) then fail("a shield break was not drawn") end
	FxPlayer.shieldColour = was
	local sparks, angles = 0, {}
	local burst = false
	for _, it in B.items do
		if it.ramp ~= "#FF4A6A" then fail(`a shield break drew a {it.kind} in {it.ramp}, not the shield's colour`) end
		if it.kind == "burst" and near(it.x, 4) and near(it.y, 3) then burst = true end
		if it.kind == "spark" then
			sparks += 1
			table.insert(angles, math.atan2(it.y - 3, it.x - 4))
		end
	end
	if not burst then fail("a shield break drew no burst where the shield was") end
	if sparks < 6 then fail(`a shield break threw {sparks} shards`) end
	table.sort(angles)
	for i = 1, #angles do
		local gap = (if i < #angles then angles[i + 1] else angles[1] + math.pi * 2) - angles[i]
		if gap > math.pi / 2 then fail("the shards of a broken shield are thrown to one side, not all round") end
	end
end

-- ------------------------------------------------------------------ the shell ----
local draws: { any } = {}
local realDraw = FxArt.draw
FxArt.draw = function(_: any, art: any, x: number, y: number, scale: number, rot: number?, alpha: number?)
	table.insert(draws, { art = art, x = x, y = y, width = scale * art.cols / art.ppu, rot = rot, alpha = alpha })
end
local function shieldDraw(hp: number, frame: number, hit: any?, colour: string?): { any }
	table.clear(draws)
	ShieldArt.draw({}, 3, 2, 4, hp, frame, hit, colour or "#5FBF4B")
	return table.clone(draws)
end

for _, hp in { 1, 0.8, 0.5, 0.31, 0.1 } do
	local R = Shield.shapes(3, 2, 4, hp, 0, nil)[2][4]
	if not near(ShieldArt.radius(4, hp), R) then fail(`at {hp}: the shell's radius {ShieldArt.radius(4, hp)}, Shield.shapes says {R}`) end
	local d = shieldDraw(hp, 0)
	if #d ~= 1 then fail(`at {hp} with no hit: {#d} drawings, want the shell alone`) end
	if not near(d[1].width, R * 2) then fail(`at {hp}: the shell is drawn {d[1].width} wide, its diameter is {R * 2}`) end
	if not near(d[1].x, 3) or not near(d[1].y, 2) then fail(`at {hp}: the shell is centred at ({d[1].x}, {d[1].y}), not on the fighter`) end
end
if #shieldDraw(0, 0) ~= 0 then fail("an empty shield was drawn") end
-- flicker below 30%, steady above
local function alphas(hp: number): { number }
	local out = {}
	for f = 0, 11 do table.insert(out, shieldDraw(hp, f)[1].alpha) end
	return out
end
local steady, low = alphas(0.5), alphas(0.2)
for _, a in steady do if a ~= steady[1] then fail("a healthy shield flickered") end end
local lo, hi = math.huge, -math.huge
for _, a in low do lo, hi = math.min(lo, a), math.max(hi, a) end
if hi - lo < 0.3 then fail(`a shield at 20% does not flicker (alpha {lo}..{hi})`) end
-- cracks spread as it weakens: more of the shell in the brightest tone, at every step
local A = FxArt.ramp("#5FBF4B")
local function bright(level: number): number
	local n = 0
	for _, r in ShieldArt.shell("#5FBF4B", level).rects do if r[5] == A[5] then n += r[3] * r[4] end end
	return n
end
-- a whole shield is not cracked: its brightest pixels are the lit rim and the glint, nothing inside
do
	local whole = ShieldArt.shell("#5FBF4B", 0)
	local inside = 0
	for _, r in whole.rects do
		if r[5] ~= A[5] then continue end
		for y = r[2], r[2] + r[4] - 1 do
			for x = r[1], r[1] + r[3] - 1 do
				local dx, dy = x + 0.5 - whole.ax, y + 0.5 - whole.ay
				if math.sqrt(dx * dx + dy * dy) <= whole.ax - 2 then inside += 1 end
			end
		end
	end
	if inside > 2 then fail(`a whole shield has {inside - 2} crack pixels inside its rim`) end
end
for level = 1, 3 do
	if bright(level) <= bright(level - 1) then fail(`the shell at crack level {level} is no more cracked than at {level - 1}`) end
end
local levelAt = {}
for _, hp in { 0.9, 0.6, 0.4, 0.2 } do table.insert(levelAt, shieldDraw(hp, 3)[1].art) end
for i = 1, 4 do
	if levelAt[i] ~= ShieldArt.shell("#5FBF4B", i - 1) then fail(`the shield at its {i}th strength step is not drawn at crack level {i - 1}`) end
end
-- the fighter's colour; a team's in a team match; see-through inside, solid at the rim
if ShieldArt.colourOf(1, nil) ~= Effects.PLAYER_TINT[2] then fail("player 2's shield is not player 2's colour") end
if ShieldArt.colourOf(5, nil) ~= Effects.PLAYER_TINT[2] then fail("player colours do not wrap") end
if ShieldArt.colourOf(1, { [1] = { R = 1, G = 0, B = 0 } }) ~= "#FF0000" then fail("a team match's shield is not the team colour") end
local tones: { [string]: boolean } = {}
for _, hex in A do tones[hex] = true end
local fill, rim = 0, 0
for _, r in ShieldArt.shell("#5FBF4B", 0).rects do
	if not tones[r[5]] then fail(`the shell has a {r[5]} pixel, outside its colour's ramp`) end
	if r[6] < 0.5 then fill += 1 elseif r[6] == 1 then rim += 1 else fail(`a shell pixel at alpha {r[6]}`) end
end
if fill == 0 or rim == 0 then fail(`the shell needs a see-through fill and a solid rim, has {fill} and {rim}`) end
if ShieldArt.shell("#5FBF4B", 2) ~= ShieldArt.shell("#5FBF4B", 2) then fail("the shell was rebuilt for the same colour and level") end
-- struck: a flare on the rim, toward the blow
for _, at in { { 9, 2, 0 }, { 3, 9, math.pi / 2 }, { -5, 2, math.pi } } do
	local d = shieldDraw(1, 0, { k = 1, x = at[1], y = at[2] })
	if #d < 2 then fail("a struck shield drew no flare") end
	local R = ShieldArt.radius(4, 1)
	local fx, fy = 3 + math.cos(at[3]) * R, 2 + math.sin(at[3]) * R
	if not near(d[2].x, fx) or not near(d[2].y, fy) then fail(`struck from ({at[1]}, {at[2]}): the flare is at ({d[2].x}, {d[2].y}), the rim there is ({fx}, {fy})`) end
end
if #shieldDraw(1, 0, { k = 0, x = 9, y = 2 }) ~= 1 then fail("a spent hit still flares") end
FxArt.draw = realDraw

-- ------------------------------------------------------------------ flying ----
local lines: { any } = {}
local puffs: { any } = {}
local realLine = Canvas2D.line
Canvas2D.line = function(_: any, x0: number, y0: number, x1: number, y1: number)
	table.insert(lines, { x0, y0, x1, y1 })
end
FxArt.draw = function(_: any, art: any, x: number, y: number)
	table.insert(puffs, { x = x, y = y, art = art })
end
local char = Loadout.build("Classic", "Sword")
local chars = { char }
local function fly(vx: number, vy: number, state: string?, onGround: boolean?, x: number?, t: number): any
	table.clear(lines); table.clear(puffs)
	local s = { index = 0, alive = true, state = state or "hitstun", onGround = onGround or false, x = x or 0, y = 5, vx = vx, vy = vy }
	HitReact.draw({}, { s }, chars, t)
	return s
end
HitReact.clear()
fly(HitReact.LINES * 0.8, 0, nil, nil, nil, 0)
if #lines > 0 or #puffs > 0 then fail("a fighter drifting in hitstun drew speed lines or smoke") end
fly(HitReact.LINES + 8, 0, "idle", nil, nil, 0)
if #lines > 0 then fail("a fighter not in hitstun drew speed lines") end
fly(HitReact.LINES + 8, 0, nil, true, nil, 0)
if #lines > 0 then fail("a fighter on the ground drew speed lines") end
-- fast, but not smoke-fast: lines, behind them, and no smoke
local s = fly(-(HitReact.LINES + 8), 6, nil, nil, nil, 0)
if #lines == 0 then fail("a fighter flying fast in hitstun drew no speed lines") end
local cx, cy = s.x, s.y + char.height * 0.5
for _, l in lines do
	for _, p in { { l[1], l[2] }, { l[3], l[4] } } do
		if (p[1] - cx) * s.vx + (p[2] - cy) * s.vy >= 0 then fail("a speed line is ahead of the fighter, not behind") end
	end
end
if #puffs > 0 then fail(`a fighter under {HitReact.SMOKE} studs a second trailed smoke`) end
-- launched hard: smoke puffs left where they were
HitReact.clear()
local t = 0
for step = 0, 20 do
	t = step / 60
	fly(HitReact.SMOKE + 20, 0, nil, nil, step * 1.0, t)
end
if #puffs < 3 then fail(`a fighter launched hard left {#puffs} smoke puffs over a third of a second`) end
for _, p in puffs do
	if p.x > 20 + 1e-9 then fail("a smoke puff is ahead of the fighter") end
	if p.art.key == nil or not string.find(p.art.key, "smoke", 1, true) then fail("a puff is not drawn in smoke") end
end
local xs: { [number]: boolean } = {}
for _, p in puffs do xs[p.x] = true end
local distinct = 0
for _ in xs do distinct += 1 end
if distinct < 3 then fail("the smoke puffs are not left along the path") end
-- landed: the trail fades and goes
local gone = false
for step = 1, 60 do
	fly(0, 0, "idle", true, 20, t + step / 60)
	if #puffs == 0 then gone = true; break end
end
if not gone then fail("the smoke trail never cleared after landing") end
Canvas2D.line, FxArt.draw = realLine, realDraw

print("PASS hit fx: every weapon has a hit style; impacts in the weapon colour, sized by damage, aimed along the knockback both ways; dust under heavy grounded hits only")
print("  shield: Shield.shapes' size at every strength, flickers below 30% only, cracks spread, fighter/team colour, flares where struck; broken shields shatter all round")
print("  flying: speed lines behind fast hitstun only, smoke only faster, left along the path, cleared after landing")
