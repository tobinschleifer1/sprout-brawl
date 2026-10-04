--!strict
-- What a combo looks like on the client (Config.COMBO): ComboHud's counter and break readout, and
-- the effects FxPlayer / FightScene / Fighter2D give the combo events.
--
--   * the counter counts each swing once, adds up the damage, restarts on a new victim or a fresh
--     combo, shows the attacker's timed streak while it runs, marks a finisher and a break, holds
--     after the combo ends and then fades away; a lone hit is not a combo;
--   * the break readout gives the cooldown in seconds, and prompts only inside a freeze that a
--     Dodge would actually break (fourth hit on, not a finisher, off cooldown);
--   * a timed link draws a gold star that grows with the streak and flashes the fighter's
--     silhouette gold, briefly; a finisher's hit goes off bigger in gold with a screen flash and
--     the finisher shake; a break throws a shockwave in the breaker's shield colour; a chase
--     streaks toward its victim; a cancel puffs.
--
--     lune run tests/combo-hud
local Loader = require("./loader")
local Loadout = Loader.load("Loadout")
local Config = Loader.load("Config")
local ComboHud = Loader.loadFrom("src/client/", "ComboHud")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local FightScene = Loader.loadFrom("src/client/", "FightScene")
local Effects = Loader.loadFrom("src/client/", "Effects")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Fighter = Loader.load("Fighter")
local Snapshot = Loader.load("Snapshot")
local KIT = Loader.load("Data/AvatarKit")
local FxArt = Loader.loadFrom("src/client/", "FxArt")

local function fail(msg: string): never
	error(msg, 0)
end

-- ------------------------------------------------------------------ the counter ----
local hit = function(a: number, v: number, combo: number, damage: number, finisher: boolean?): any
	return { type = "hit", attacker = a, victim = v, combo = combo, damage = damage, finisher = finisher }
end
local inCombo = function(index: number, hits: number, streak: number?): any
	return { index = index, comboHits = hits, perfectStreak = streak or 0 }
end
do
	local H = ComboHud.new()
	ComboHud.event(H, hit(0, 1, 1, 3), 0)
	local v = ComboHud.view(H, { inCombo(0, 0, 0), inCombo(1, 1) }, 0)
	if v[0] then fail("a single hit showed a combo counter") end
	ComboHud.event(H, hit(0, 1, 2, 4), 0.1)
	-- a multi-hit swing: its ticks share the combo number, so they do not count again, but damage adds
	ComboHud.event(H, hit(0, 1, 2, 1.5), 0.12)
	ComboHud.event(H, hit(0, 1, 3, 6), 0.2)
	v = ComboHud.view(H, { inCombo(0, 0, 2), inCombo(1, 3) }, 0.2)
	local c = v[0]
	if not c or c.hits ~= 3 or c.damage ~= 15 or c.perfect ~= 2 or c.alpha ~= 1 then
		fail(`three swings (one a two-tick multi-hit): got {c and c.hits} hits, {c and c.damage} damage, perfect {c and c.perfect}`)
	end
	-- the victim gets out: held, then gone - and the attacker's streak (still 2 in their state until
	-- they start a new move) is no longer this combo's
	v = ComboHud.view(H, { inCombo(0, 0, 2), inCombo(1, 0) }, 0.3)
	if not v[0] or v[0].alpha ~= 1 or v[0].perfect ~= 0 then fail("a finished combo did not hold at full, streak cleared") end
	v = ComboHud.view(H, { inCombo(0, 0, 0), inCombo(1, 0) }, 0.3 + ComboHud.HOLD * 0.5)
	if not v[0] or math.abs(v[0].alpha - 0.5) > 1e-9 then fail(`halfway through the hold the counter is at {v[0] and v[0].alpha}`) end
	v = ComboHud.view(H, { inCombo(0, 0, 0), inCombo(1, 0) }, 0.3 + ComboHud.HOLD + 0.01)
	if v[0] or H.combos[0] then fail("a finished combo never went away") end
	-- after it ended, the next hit starts a new count, not 4
	ComboHud.event(H, hit(0, 1, 1, 3), 2)
	ComboHud.event(H, hit(0, 1, 2, 3), 2.1)
	v = ComboHud.view(H, { inCombo(0, 0), inCombo(1, 2) }, 2.1)
	if not v[0] or v[0].hits ~= 2 or v[0].damage ~= 6 then fail("a new combo carried the old one's count or damage") end
	-- a lone hit that ended, then a combo on the same victim while it is still held: the new combo
	-- does not carry the lone hit's damage
	local L = ComboHud.new()
	ComboHud.event(L, hit(0, 1, 1, 7), 0)
	ComboHud.view(L, { inCombo(0, 0), inCombo(1, 0) }, 0.1)          -- they got out
	ComboHud.event(L, hit(0, 1, 1, 3), 0.2)
	ComboHud.event(L, hit(0, 1, 2, 3), 0.3)
	local lv = ComboHud.view(L, { inCombo(0, 0), inCombo(1, 2) }, 0.3)
	if not lv[0] or lv[0].damage ~= 6 then fail(`a combo after an ended lone hit shows {lv[0] and lv[0].damage} damage, want 6`) end
	-- a different victim starts afresh
	ComboHud.event(H, hit(0, 2, 2, 5), 2.2)
	v = ComboHud.view(H, { inCombo(0, 0), inCombo(1, 2), inCombo(2, 2) }, 2.2)
	if not v[0] or v[0].damage ~= 5 then fail("switching victims kept the previous combo's damage") end
	-- finisher and break
	local F = ComboHud.new()
	ComboHud.event(F, hit(3, 1, 1, 3), 0)
	ComboHud.event(F, hit(3, 1, 2, 9, true), 0.1)
	v = ComboHud.view(F, { inCombo(3, 0), inCombo(1, 2) }, 0.1)
	if not v[3] or not v[3].finisher then fail("a finisher was not marked") end
	local B = ComboHud.new()
	for k = 1, 4 do ComboHud.event(B, hit(0, 1, k, 3), k * 0.1) end
	ComboHud.event(B, { type = "combobreak", fighter = 1 }, 0.5)
	v = ComboHud.view(B, { inCombo(0, 0), inCombo(1, 4) }, 0.5)
	if not v[0] or not v[0].broken or v[0].alpha ~= 1 then fail("a broken combo was not marked broken") end
	-- hazards and projectiles of nobody (attacker -1) are not anybody's combo
	local Z = ComboHud.new()
	ComboHud.event(Z, hit(-1, 1, 1, 9), 0)
	ComboHud.event(Z, hit(-1, 1, 2, 9), 0)
	if next(ComboHud.view(Z, { inCombo(1, 2) }, 0)) then fail("a hazard's hits showed as a combo") end
end

-- ------------------------------------------------------------------ the break readout ----
do
	local base = { state = "hitstun", hitlag = 4, comboHits = Config.COMBO.breakFrom, breakable = true, breakCooldown = 0 }
	local function with(o: any): any
		local t = table.clone(base)
		for k, val in o do t[k] = val end
		return t
	end
	if not ComboHud.breakView(base).prompt then fail("no prompt in a breakable freeze") end
	if ComboHud.breakView(with({ hitlag = 0 })).prompt then fail("prompted outside the freeze") end
	if ComboHud.breakView(with({ comboHits = Config.COMBO.breakFrom - 1 })).prompt then fail("prompted before the fourth hit") end
	if ComboHud.breakView(with({ breakable = false })).prompt then fail("prompted in a finisher's freeze") end
	local cd = ComboHud.breakView(with({ breakCooldown = 150 }))
	if cd.prompt or math.abs(cd.cooldown - 2.5) > 1e-9 then fail(`on cooldown: prompt {cd.prompt}, {cd.cooldown}s`) end
	if ComboHud.breakView(with({ state = "air" })).prompt then fail("prompted out of hitstun") end
end

-- ------------------------------------------------------------------ the effects ----
local sword = Loadout.build("Classic", "Sword")
local states = { { index = 0, x = 0, y = 0 }, { index = 1, x = 4, y = 0 } }
local chars = { sword, Loadout.build("Noir", "Sword") }
local function find(P: any, kind: string, ramp: string?): any
	for _, it in P.items do if it.kind == kind and (ramp == nil or it.ramp == ramp) then return it end end
	return nil
end
do
	-- a timed link: a gold star sized by the streak, and the fighter's gold flash, which fades
	local small, big = FxPlayer.new(), FxPlayer.new()
	FxPlayer.spawn(small, { type = "perfectlink", fighter = 0, x = 0, y = 2.5, streak = 1 }, states, chars)
	FxPlayer.spawn(big, { type = "perfectlink", fighter = 0, x = 0, y = 2.5, streak = 3 }, states, chars)
	local s1, s3 = find(small, "star", "gold"), find(big, "star", "gold")
	if not s1 or not s3 or not (s3.size > s1.size) then fail("a timed link's gold star does not grow with the streak") end
	local g = small.glows[0]
	if not g or g.colour ~= FxPlayer.PERFECT then fail("a timed link did not flash the fighter gold") end
	FxPlayer.step(small, FxPlayer.GLOW_TIME * 0.5)
	if not small.glows[0] then fail("the gold flash ended too soon") end
	FxPlayer.step(small, FxPlayer.GLOW_TIME)
	if small.glows[0] then fail("the gold flash never ended") end
	-- the flash reaches the drawn fighter as its silhouette tint, and the pose's own flash wins
	local tints = {}
	local spriteWas = Canvas.sprite
	Canvas.rect = function() end; Canvas.ellipse = function() end; Canvas.tri = function() end; Canvas.line = function() end
	Canvas.sprite = function(_: any, key: string) table.insert(tints, key) end
	local code
	for _, p in KIT.presets do if p.id == "knight" then code = p.code end end
	local f = Fighter.new({ index = 0, char = Loadout.build(code, "Sword"), x = 0, y = 0, stocks = 3 })
	if not f.char.avatar.kit then fail("the knight preset did not build a kit character") end
	f.state, f.onGround = "idle", true
	local cv = setmetatable({ m = { a = 24, b = 0, c = 0, d = 24, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }, { __index = Canvas })
	Fighter2D.glows = { [0] = { colour = FxPlayer.PERFECT, left = 0.1 } }
	local ok = pcall(Fighter2D.draw, cv, Snapshot.decode(Snapshot.encode(f)), f.char, 0, 0)
	Fighter2D.glows = nil
	Canvas.sprite = spriteWas
	local gold = false
	for _, k in tints do if string.find(k, FxPlayer.PERFECT, 1, true) then gold = true end end
	if not ok or not gold then fail("the gold flash did not reach the fighter's silhouette") end
	-- and the pose's own flash (here a chill tint) is not overridden by it
	table.clear(tints)
	Canvas.sprite = function(_: any, key: string) table.insert(tints, key) end
	local chilled = Snapshot.decode(Snapshot.encode(f))
	chilled.chillStacks = 2
	Fighter2D.glows = { [0] = { colour = FxPlayer.PERFECT, left = 0.1 } }
	pcall(Fighter2D.draw, cv, chilled, f.char, 0, 0)
	Fighter2D.glows = nil
	Canvas.sprite = spriteWas
	for _, k in tints do if string.find(k, FxPlayer.PERFECT, 1, true) then fail("the gold flash painted over the pose's own flash") end end

	-- a finisher's hit: bigger, gold, a screen flash, and the finisher shake
	local plain, fin = FxPlayer.new(), FxPlayer.new()
	local e = { type = "hit", attacker = 0, victim = 1, x = 2, y = 2, damage = 8, angle = 70, facing = 1 }
	FxPlayer.hit(plain, e, states, chars)
	local ef = table.clone(e); ef.finisher = true
	FxPlayer.hit(fin, ef, states, chars)
	if not find(fin, "burst", "gold") or find(plain, "burst", "gold") then fail("a finisher's hit has no gold burst, or an ordinary hit has one") end
	if not (fin.flash > 0) or plain.flash > 0 then fail("a finisher does not flash the screen, or an ordinary hit does") end
	local fx = Effects.new()
	FightScene.spawn(fx, FxPlayer.new(), ef, states, chars, function() return nil end, function() return 0.5 end, function() return 5 end, false)
	if fx.shake < FightScene.FINISHER_SHAKE then fail(`a finisher shook {fx.shake}, want {FightScene.FINISHER_SHAKE}`) end
	local fx2 = Effects.new()
	FightScene.spawn(fx2, FxPlayer.new(), e, states, chars, function() return nil end, function() return 0.5 end, function() return 5 end, false)
	if fx2.shake >= FightScene.FINISHER_SHAKE then fail("an ordinary hit shook like a finisher") end

	-- a break: a shockwave in the breaker's shield colour
	local was = FxPlayer.shieldColour
	FxPlayer.shieldColour = function(i: number?) return if i == 1 then "#4A90D9" else "#000000" end
	local Bk = FxPlayer.new()
	FxPlayer.spawn(Bk, { type = "combobreak", fighter = 1, x = 4, y = 2.5 }, states, chars)
	FxPlayer.shieldColour = was
	local ring = find(Bk, "ring", "#4A90D9")
	if not ring or ring.size < 8 then fail("a break threw no shockwave in the breaker's colour") end

	-- a chase: a streak from the attacker, pointing at its victim
	local C = FxPlayer.new()
	local above = { { index = 0, x = 0, y = 0 }, { index = 1, x = 4, y = 3 } }
	FxPlayer.spawn(C, { type = "chase", fighter = 0, victim = 1 }, above, chars)
	local lance = find(C, "lance")
	if not lance then fail("a chase drew no streak") end
	local want = math.atan2((3 + chars[2].height * 0.5) - (0 + chars[1].height * 0.5), 4 - 0)
	if math.abs(lance.rot - want) > 1e-9 then fail(`the chase streak points at {math.deg(lance.rot)} degrees, the victim is at {math.deg(want)}`) end
	if lance.ramp ~= FxArt.glowOf(sword) then fail(`the chase streak is {lance.ramp}, the weapon's glow is {FxArt.glowOf(sword)}`) end

	-- a cancel: a puff
	local K = FxPlayer.new()
	FxPlayer.spawn(K, { type = "cancel", fighter = 0, kind = "jump", x = 0, y = 2 }, states, chars)
	if not find(K, "pop") then fail("a cancel drew nothing") end
end

-- ------------------------------------------------------------------ the combo guide ----
-- Read off the data, and the same routes the weapons' own headers quote (the first two ROUTE lines,
-- measured by web/test/combo.test.mjs): the guide and the measurement name the same strings.
do
	local fs = require("@lune/fs")
	local ComboGuide = Loader.loadFrom("src/client/", "ComboGuide")
	local Weapons = Loader.load("Data/Weapons")
	local checked = 0
	for _, w in Weapons.LIST do
		local char = Loadout.build("Classic", w.id)
		local lines = ComboGuide.lines(char)
		if #lines ~= 2 then fail(`{w.id}: the guide has {#lines} lines, want the finisher and the air string`) end
		local header = fs.readFile(`../web/src/data/weapons/{string.lower(w.id)}.js`)
		local quoted = {}
		for route in string.gmatch(header, "ROUTE  ([^\n]-)   +CONFIRM") do table.insert(quoted, route) end
		local fin, air = ComboGuide.finisherRoute(char.moves), ComboGuide.airRoute(char.moves)
		local function labels(list: { any }): string
			local out = {}
			for _, x in list do table.insert(out, char.moves[if type(x) == "table" then x[1] else x].label) end
			return table.concat(out, " > ")
		end
		if not fin or labels(fin) ~= quoted[1] then fail(`{w.id}: the guide's finisher string is '{fin and labels(fin)}', the header measures '{quoted[1]}'`) end
		if not air or labels(air) ~= quoted[2] then fail(`{w.id}: the guide's air string is '{air and labels(air)}', the header measures '{quoted[2]}'`) end
		checked += 1
	end
	if checked ~= #Weapons.LIST then fail("not every weapon was checked") end
end

print("PASS combo hud: the counter counts swings, adds damage, restarts, shows the streak, marks finishers and breaks, holds and fades; the break prompt only in a breakable freeze")
print("  the combo guide names the finisher and air strings each weapon's header measures")
print("  effects: a gold star growing with the streak and a brief gold silhouette flash; a finisher bigger in gold with a screen flash and its shake; a break's shockwave; a chase's streak; a cancel's puff")
