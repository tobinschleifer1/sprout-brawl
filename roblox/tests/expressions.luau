--!strict
-- Faces that act (src/client/Expressions.luau). Roblox only, so nothing replays this against the
-- web: every property is asserted directly.
--
-- 1. Every expression composes, on every preset and a spread of random characters, inside the head.
-- 2. Every expression changes an uncovered face, and every pair of eyes the catalogue has can blink
--    (a closed glow first drafted as the open one is what this exists for).
-- 3. The player's choices survive: no brows stays no brows, glowing/anime/lashed eyes stay except
--    where eyes close, fangs and tongues where the table keeps them.
-- 4. Covered faces: eyewear over the eyes leaves the eyes alone; a knight's helm changes nothing;
--    a brimmed or knitted hat leaves the brows.
-- 5. State -> expression, the blink schedule (rarer when small), determined on the last stock.
-- 6. The hold: no flicker shorter than HOLD frames, victory and defeat at once, a fresh start when
--    the frame count jumps, previews and matches apart.
-- 7. The head cache is bounded.
-- 8. Fighter2D draws the expression's head, and at half detail the neutral one when they look alike.
local Loader = require("./loader")
local Expressions = Loader.loadFrom("src/client/", "Expressions")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local AvatarKit = Loader.load("AvatarKit")
local KIT = Loader.load("Data/AvatarKit")

local function fail(msg: string) error(msg, 0) end
local function optionsOf(cat: string): { string }
	for _, c in KIT.categories do
		if c.id == cat then
			local out = {}
			for _, o in c.options do table.insert(out, o.id) end
			return out
		end
	end
	error("no category " .. cat)
end
-- A plain character to vary one part on: no eyewear, no headwear, ordinary eyes, brows and mouth.
local function plain(over: { [string]: string }?): string
	local spec = AvatarKit.sanitize(nil)
	spec.parts.eyes, spec.parts.brows, spec.parts.mouth, spec.parts.eyewear, spec.parts.headwear = "round", "normal", "smile", "none", "none"
	for k, v in over or {} do spec.parts[k] = v end
	return AvatarKit.encode(spec)
end

-- 1. Everything composes, inside the head's canvas.
local seed = 12345
local function rnd(n: number): number seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
local codes = {}
for _, p in KIT.presets do table.insert(codes, p.code) end
for _ = 1, 60 do
	local spec = AvatarKit.sanitize(nil)
	for _, c in KIT.categories do spec.parts[c.id] = c.options[rnd(#c.options) + 1].id end
	for _, c in KIT.colours do spec.colours[c.id] = rnd(#c.list) end
	table.insert(codes, AvatarKit.encode(spec))
end
local P = KIT.parts.head
local composed = 0
for _, code in codes do
	for _, e in Expressions.LIST do
		local h = Expressions.head(code, e)
		for _, r in h.full do
			if r[1] < 0 or r[2] < 0 or r[1] + r[3] > P.w or r[2] + r[4] > P.h then fail(`{code} {e}: a rectangle leaves the head`) end
		end
		composed += 1
	end
end

-- 2. Every expression shows on an uncovered face; every pair of eyes blinks.
for _, e in Expressions.LIST do
	if Expressions.head(plain(), e).sameFull then fail(`{e} does not change an uncovered face`) end
end
local blinked = 0
for _, eyes in optionsOf("eyes") do
	if eyes ~= "closed" then
		if Expressions.head(plain({ eyes = eyes }), "blink").sameFull then fail(`{eyes} eyes do not blink`) end
		if Expressions.head(plain({ eyes = eyes }), "hurt").sameFull then fail(`{eyes} eyes do not react to a hit`) end
		blinked += 1
	end
end

-- 3. The player's choices survive.
local function specOf(code: string, e: string): (any, any)
	return Expressions.specFor(AvatarKit.decode(code) :: any, e)
end
for _, e in Expressions.LIST do
	local s = specOf(plain({ brows = "none" }), e)
	if s.parts.brows ~= "none" then fail(`{e} gave a browless face brows ({s.parts.brows})`) end
	for _, eyes in { "glow", "anime", "lashes" } do
		local s2, over = specOf(plain({ eyes = eyes }), e)
		local closes = e == "blink" or e == "hurt" or e == "dizzy"
		if not closes and (s2.parts.eyes ~= eyes or over) then fail(`{e} replaced the player's {eyes} eyes`) end
		if closes and not over then fail(`{e} on {eyes} eyes did not use its own closed or dizzy eyes`) end
	end
end
if specOf(plain({ mouth = "fangs" }), "delighted").parts.mouth ~= "fangs" then fail("delighted lost the player's fangs") end
if specOf(plain({ mouth = "fangs" }), "hurt").parts.mouth == "fangs" then fail("hurt kept fangs: the table should change it") end

-- 4. Covered faces.
for _, wear in { "shades", "goggles", "visor", "3d", "eyepatch" } do
	for _, e in Expressions.LIST do
		local s, over = specOf(plain({ eyewear = wear }), e)
		if s.parts.eyes ~= "round" or over then fail(`{e} changed eyes hidden behind {wear}`) end
	end
	if Expressions.head(plain({ eyewear = wear }), "hurt").sameFull then fail(`a {wear} wearer's hurt face shows nothing: the mouth should still react`) end
end
for _, e in Expressions.LIST do
	if not Expressions.head(plain({ headwear = "knight" }), e).sameFull then fail(`{e} changed a face inside a knight's helm`) end
	local s = specOf(plain({ headwear = "beanie" }), e)
	if s.parts.brows ~= "normal" then fail(`{e} changed brows under a beanie`) end
end
if Expressions.head(plain({ eyewear = "glasses" }), "blink").sameFull then fail("glasses hid a blink: their lenses are clear") end

-- 5. State -> expression.
local function st(over: any): any
	local s = { state = "idle", stateFrame = 3, moveFrame = 0, startupEff = 0, frameCount = 100, index = 0, stocks = 3, tumbling = false }
	for k, v in over do s[k] = v end
	return s
end
local move = { id = "LightNeutral1", active = 2, recovery = 12 }
local cases = {
	{ st({ state = "victory" }), "delighted" }, { st({ state = "defeat" }), "dejected" }, { st({ state = "stunned" }), "dizzy" },
	{ st({ state = "hitstun" }), "hurt" }, { st({ state = "hitstun", tumbling = true }), "startled" }, { st({ state = "flung" }), "startled" },
	{ st({ state = "grabbed" }), "hurt" }, { st({ state = "taunt" }), "smug" }, { st({ state = "idle" }), nil },
	{ st({ state = "idle", stocks = 1 }), "determined", true }, { st({ state = "idle", stocks = 1 }), nil, false },
	-- an attack whose move cannot be looked up (a counter burst, an item swing) is still effort
	{ st({ state = "attack", startupEff = 5, moveFrame = 3 }), "effort", false, true },
	-- late in a recovery, their own face - never a blink, even on a blink frame
	{ st({ state = "attack", startupEff = 5, moveFrame = 18, frameCount = Expressions.BLINK_EVERY - 1 }), nil },
	{ st({ state = "attack", startupEff = 5, moveFrame = 3 }), "focused" }, { st({ state = "attack", startupEff = 5, moveFrame = 6 }), "effort" },
	{ st({ state = "attack", startupEff = 5, moveFrame = 9 }), "effort" }, { st({ state = "attack", startupEff = 5, moveFrame = 18 }), nil },
}
for i, c in cases do
	local got = Expressions.of(c[1], if c[1].state == "attack" and not c[4] then move else nil, false, c[3])
	if got ~= c[2] then fail(`state case {i} ({c[1].state}): {got}, want {c[2]}`) end
end
-- blinks: Expressions.BLINK_FOR frames in every BLINK_EVERY, offset per fighter; a third as often when small
local function blinks(index: number, small: boolean): number
	local n = 0
	for fc = 0, Expressions.BLINK_EVERY * 30 - 1 do
		if Expressions.of(st({ frameCount = fc, index = index }), nil, small) == "blink" then n += 1 end
	end
	return n
end
if blinks(0, false) ~= 30 * Expressions.BLINK_FOR then fail(`{blinks(0, false)} blink frames in 30 cycles, want {30 * Expressions.BLINK_FOR}`) end
if blinks(0, true) ~= 10 * Expressions.BLINK_FOR then fail(`a small fighter blinked {blinks(0, true)} frames in 30 cycles, want a third`) end
local together = 0
for fc = 0, Expressions.BLINK_EVERY - 1 do
	if Expressions.of(st({ frameCount = fc, index = 0 }), nil, false) == "blink" and Expressions.of(st({ frameCount = fc, index = 1 }), nil, false) == "blink" then together += 1 end
end
if together > 0 then fail("two fighters blink in unison") end
-- a still picture posed at an early frame (a select-screen portrait, drawn from frame 1 forever)
-- never has its eyes shut, for any fighter slot
for index = 0, 7 do
	for fc = 0, 10 do
		if Expressions.of(st({ frameCount = fc, index = index }), nil, false) == "blink" then fail(`a portrait posed at frame {fc} (slot {index}) is blinking`) end
	end
end
if Expressions.of(st({ state = "hitstun", frameCount = 0 }), nil, false) ~= "hurt" then fail("a blink interrupted a hurt face") end

-- 6. The hold.
local charA, charB = {}, {}
-- `false` is "their own face" here: a table literal with nil holes iterates only its non-nil entries
local function run(char: any, seq: { any }, start: number): { any }
	local out = {}
	for i = 1, #seq do
		local e = seq[i]
		table.insert(out, Expressions.held(char, { index = 0, frameCount = start + i - 1 }, if e then e else nil) or false)
	end
	return out
end
local shown = run(charA, { false, "effort", false, false, false, false, false }, 1000)
-- the first frame takes its face; "effort" for one frame cannot replace it until HOLD frames have passed
if shown[2] ~= false then fail("a face changed after one frame, before its hold") end
local flick = run(charA, { "hurt", "hurt", "hurt", "hurt", "hurt", "hurt" }, 2000)        -- a jump in frames: a fresh start
if flick[1] ~= "hurt" then fail("a frame-count jump did not start the face afresh") end
-- a face taken one frame ago still yields at once to victory or defeat, and to nothing else
local won = run(charA, { "hurt", "delighted", "effort" }, 3000)
if won[1] ~= "hurt" or won[2] ~= "delighted" then fail(`victory waited out the hold ({won[1]}, {won[2]})`) end
if won[3] ~= "delighted" then fail("a face yielded to effort one frame after victory took it") end
local mixed = run(charB, { "smug" }, 2007)
if mixed[1] ~= "smug" then fail("one loadout's face leaked into another's") end
local changes, last = 0, nil
for i = 0, 59 do
	local e = Expressions.held(charA, { index = 3, frameCount = 5000 + i }, if i % 2 == 0 then "hurt" else "effort")
	if e ~= last then changes += 1; last = e end
end
if changes > 60 / Expressions.HOLD + 1 then fail(`a face flickering every frame changed {changes} times in 60 frames`) end

-- 7. The cache is bounded.
for i = 1, Expressions.CACHE_MAX + 20 do Expressions.head(codes[(i % #codes) + 1], Expressions.LIST[(i % 10) + 1]) end
if Expressions.cacheSize() > Expressions.CACHE_MAX then fail(`the head cache holds {Expressions.cacheSize()}, max {Expressions.CACHE_MAX}`) end

-- 8. Fighter2D draws the face.
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter = Loader.load("Fighter")
local Snapshot = Loader.load("Snapshot")
local Loadout = Loader.load("Loadout")
local keys: { string } = {}
local lists: { [string]: any } = {}
Canvas.rect = function() end; Canvas.ellipse = function() end; Canvas.tri = function() end; Canvas.line = function() end
Canvas.sprite = function(_: any, key: string, list: any) table.insert(keys, key); lists[key] = list end
Fighter2D.effects = nil
local function headKey(code: string, state: string, scale: number): string
	local char = Loadout.build(code, "Sword")
	local f: any = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.frameCount = state, true, 100
	table.clear(keys)
	local cv = setmetatable({ m = { a = scale, b = 0, c = 0, d = scale, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }, { __index = Canvas })
	Fighter2D.draw(cv, Snapshot.decode(Snapshot.encode(f)), char, 0, 0)
	for _, k in keys do if string.find(k, "|head|", 1, true) then return k end end
	return ""
end
local code = plain()
local hurtKey = headKey(code, "hitstun", 24)
if not string.find(hurtKey, "|head|hurt", 1, true) then fail(`a hit fighter drew head {hurtKey}, want its hurt face`) end
if lists[hurtKey] ~= Expressions.head(code, "hurt").full then fail("a hit fighter's head sprite is not the hurt face's picture") end
if string.find(headKey(code, "idle", 24), "hurt", 1, true) then fail("an idle fighter drew a hurt face") end
-- At half detail: a face that halves to exactly the neutral head is drawn AS the neutral head (no
-- second picture), and one that still differs is drawn as itself. Both kinds are found among the
-- presets and checked through a state that shows them.
local STATE_OF = { delighted = "victory", dejected = "defeat", dizzy = "stunned", hurt = "hitstun", smug = "taunt", startled = "flung" }
local sawSame, sawOwn = false, false
for _, p in KIT.presets do
	for e, state in STATE_OF do
		local h = Expressions.head(p.code, e)
		if not h.sameFull then
			local k = headKey(p.code, state, 8)
			if not string.find(k, "|head|", 1, true) then fail(`{p.id} {state}: no head drawn at half detail`) end
			local drewOwn = string.find(k, "|head|" .. e, 1, true) ~= nil
			if h.sameHalf and drewOwn then fail(`{p.id} {e}: identical to neutral at half detail, but drawn as a second picture`) end
			if not h.sameHalf and not drewOwn then fail(`{p.id} {e}: still shows at half detail, but the neutral head was drawn`) end
			if h.sameHalf then sawSame = true else sawOwn = true end
		end
	end
end
if not (sawSame and sawOwn) then fail(`the half-detail check met only one kind of face (same {sawSame}, own {sawOwn})`) end
-- the last-stock face only in a match that started with more than one stock
local function lastStockFace(start: number?): boolean
	Fighter2D.startStocks = start
	local char = Loadout.build(code, "Sword")
	local f: any = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 1 })
	f.state, f.onGround, f.frameCount = "idle", true, 100
	table.clear(keys)
	local cv = setmetatable({ m = { a = 24, b = 0, c = 0, d = 24, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }, { __index = Canvas })
	local s1 = Snapshot.decode(Snapshot.encode(f))
	s1.stocks = 1
	Fighter2D.draw(cv, s1, char, 0, 0)
	Fighter2D.startStocks = nil
	for _, k in keys do if string.find(k, "|head|determined", 1, true) then return true end end
	return false
end
if not lastStockFace(3) then fail("a fighter down to the last of three stocks does not look determined") end
if lastStockFace(1) then fail("everyone in a one-stock match looks determined from the start") end
if lastStockFace(nil) then fail("a fighter drawn outside a match (a preview, the podium) looks determined") end
local knightCode
for _, p in KIT.presets do if p.id == "knight" then knightCode = p.code end end
if string.find(headKey(knightCode, "hitstun", 24), "hurt", 1, true) then fail("a knight's helm drew a second, identical head picture") end

print(`PASS expressions: {composed} faces composed inside the head; every expression shows on an open face and {blinked} kinds of eyes blink; choices kept, covered faces left alone; states, blinks, last stock; the hold; a bounded cache; Fighter2D draws the face`)
