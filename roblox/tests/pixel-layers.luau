--!nocheck
-- Overlapping layers draw the same picture in fewer Frames, and only where that is exact.
--
-- PixelGrid.layers lets a rectangle cover cells a later rectangle paints over (an outline becomes a
-- filled silhouette under its body). That is the same picture only if every rectangle is opaque,
-- nothing translucent or empty is ever covered, and the sprite is drawn at full opacity: two
-- translucent rectangles on top of each other add up. Each of those is asserted on its own, then the
-- shipping art is repainted both ways and compared pixel for pixel.
local Probe = require("../tools/perf-probe")
local P = Probe.new(960, 540)
local Rbx = require("@lune/roblox")
local PixelGrid = P:load("src/client/PixelGrid")
local Canvas = P:load("src/client/Canvas2D")
local FxArt = P:load("src/client/FxArt")
local RealmArt = P:load("src/client/RealmArt")
local FxPlayer = P:load("src/client/FxPlayer")
local Realms = P:load("src/shared/Realms")

-- ---------------------------------------------------------------- the algorithm ----
-- Tones 1-4 opaque, 5 translucent, 0 empty. The rectangles are painted in order, last wins; the
-- coverage count of every cell says whether a translucent cell was drawn over or under anything.
local function opaque(v: number): boolean return v <= 4 end
local function check(g: any, rects: { any }, what: string)
	local top = table.create(g.w * g.h, 0)
	local cover = table.create(g.w * g.h, 0)
	for _, r in rects do
		assert(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= g.w and r[2] + r[4] <= g.h and r[3] >= 1 and r[4] >= 1, `{what}: a rectangle outside the grid`)
		for y = r[2], r[2] + r[4] - 1 do
			for x = r[1], r[1] + r[3] - 1 do
				local i = y * g.w + x + 1
				top[i], cover[i] = r[5], cover[i] + 1
			end
		end
	end
	for i, v in g.cells do
		assert(top[i] == v, `{what}: cell {i} paints {top[i]}, the grid says {v}`)
		if v == 0 then assert(cover[i] == 0, `{what}: an empty cell was covered`) end
		if v ~= 0 and not opaque(v) then assert(cover[i] == 1, `{what}: a translucent cell was drawn {cover[i]} times`) end
	end
end
do
	local seed = 99
	local function rnd(n: number): number
		seed = (seed * 48271) % 2147483647
		return seed % n
	end
	local fewer, same, more = 0, 0, 0
	for trial = 1, 600 do
		local g = PixelGrid.new(1 + rnd(14), 1 + rnd(14))
		-- blobs, not noise: a few filled boxes of a tone over each other, some cells left empty
		for _ = 1, 1 + rnd(5) do
			PixelGrid.rect(g, rnd(g.w), rnd(g.h), 1 + rnd(g.w), 1 + rnd(g.h), 1 + rnd(5))
		end
		for _ = 1, rnd(6) do PixelGrid.put(g, rnd(g.w), rnd(g.h), rnd(6)) end
		local layers = PixelGrid.layers(g, opaque)
		check(g, layers, `trial {trial}`)
		local plain = PixelGrid.merge(g)
		if #layers < #plain then fewer += 1 elseif #layers == #plain then same += 1 else more += 1 end
	end
	assert(fewer > 60, `layers were fewer than a partition in only {fewer} of 600 grids`)
	print(`  600 random grids exact; fewer {fewer}, equal {same}, more {more}`)
end
-- the case it exists for: an outline round a body is one rectangle under one, not five strips
do
	local g = PixelGrid.new(8, 6)
	PixelGrid.rect(g, 0, 0, 8, 6, 1)
	PixelGrid.rect(g, 1, 1, 6, 4, 2)
	local layers = PixelGrid.layers(g, opaque)
	check(g, layers, "outlined body")
	assert(#layers == 2 and #PixelGrid.merge(g) == 5, `an outlined body should be 2 rectangles against 5 strips; got {#layers} against {#PixelGrid.merge(g)}`)
	-- a hole through the body must not be painted over: nothing covers an empty cell
	PixelGrid.put(g, 3, 2, 0)
	check(g, PixelGrid.layers(g, opaque), "outlined body with a hole")
	-- and a translucent glow inside it is neither covered nor drawn over a lower layer
	PixelGrid.put(g, 4, 3, 5)
	check(g, PixelGrid.layers(g, opaque), "outlined body with a glow")
end

-- ------------------------------------------------------------- the shipping art ----
local function painted(rects: { any }, cols: number, rows: number, flip: boolean): string
	return buffer.tostring(Canvas.paint(rects, cols, rows, flip))
end
local function same(art: any, what: string)
	for _, flip in { false, true } do
		assert(painted(art.stack, art.cols, art.rows, flip) == painted(art.rects, art.cols, art.rows, flip), `{what}: the layers paint another picture`)
	end
end
local fxPlain, fxStack = 0, 0
for _, kind in FxArt.kinds() do
	for f = 0, FxArt.FRAMES[kind] - 1 do
		for seed = 1, 4 do
			for _, ramp in { "fire", "#9FE8FF" } do
				local art = FxArt.get(kind, f, ramp, "earth", seed)
				same(art, `{kind}/{f}/{seed}/{ramp}`)
				assert(art.stackKey ~= art.key and #art.stack >= 1, "the stack needs its own sprite key")
				if ramp == "fire" then fxPlain += #art.rects; fxStack += #art.stack end
			end
		end
	end
end
assert(fxStack <= fxPlain * 0.82, `effects drew {fxStack} rectangles against {fxPlain}: layering stopped paying`)
print(`  effects: {fxPlain} rectangles -> {fxStack} ({math.floor(fxStack * 100 / fxPlain)}%), every drawing repainted identically`)

local realmPlain, realmStack, arts = 0, 0, 0
local function realmArt(art: any, what: string)
	same(art, what)
	realmPlain += #art.rects; realmStack += #art.stack; arts += 1
end
for _, realm in Realms.LIST do
	for _, which in { "far", "landmark", "near", "clouds", "storm" } do realmArt(RealmArt.layer(realm, which), `{realm.id} {which}`) end
	for _, w in { 8, 14, 27, 40 } do
		for _, t in { 4, 7 } do
			local body, surface = RealmArt.island(realm, w, t, 2)
			realmArt(body, `{realm.id} island {w}x{t}`)
			realmArt(surface, `{realm.id} surface {w}`)
		end
		for _, style in { "wood", "minecart" } do realmArt(RealmArt.shelf(realm, w, 1, style), `{realm.id} {style} shelf {w}`) end
	end
end
assert(realmStack <= realmPlain * 0.8, `realm art drew {realmStack} rectangles against {realmPlain}`)
print(`  realms: {arts} drawings, {realmPlain} rectangles -> {realmStack} ({math.floor(realmStack * 100 / realmPlain)}%), all repainted identically`)

-- --------------------------------------------------------- which one gets drawn ----
-- The stack only at full opacity: no alpha passed (a caller that never fades), and a canvas that is
-- not itself faded. Anything else draws the partition, every time, so an effect is not built twice.
local drawn: { string } = {}
local sprite = Canvas.sprite
Canvas.sprite = function(_, key, rects)
	table.insert(drawn, key)
	return rects
end
local function canvas(alpha: number?): any
	local c = Canvas.inFrame(P.new("Frame"))
	if alpha then c.alpha = alpha end
	return c
end
local art = FxArt.get("burst", 2, "fire", nil, 1)
local function fx(alpha: number?, canvasAlpha: number?): string
	table.clear(drawn)
	FxArt.draw(canvas(canvasAlpha), art, 0, 0, 2, 0, alpha)
	return drawn[1]
end
assert(fx(nil) == art.stackKey, "a draw with no alpha should use the stack")
assert(fx(1) == art.key, "a caller that passes an alpha, even 1, gets the partition: it may fade")
assert(fx(0.5) == art.key, "a faded effect must not use overlapping layers")
assert(fx(nil, 0.5) == art.key, "an effect on a faded canvas must not use overlapping layers")
-- FxPlayer: an effect with no fadeAt never fades, one with fadeAt is the partition from its first frame
do
	local p = FxPlayer.new()
	FxPlayer.add(p, "burst", 0, 0, 2, 1, "fire", { seed = 1 })
	FxPlayer.add(p, "burst", 0, 0, 2, 1, "smoke", { seed = 1, fadeAt = 0.5 })
	p.items[1].age, p.items[2].age = 0.2, 0.2
	table.clear(drawn)
	FxPlayer.draw(p, canvas())
	assert(string.sub(drawn[1], -2) == "|L", `a plain effect should draw its stack, drew {drawn[1]}`)
	assert(string.sub(drawn[2], -2) ~= "|L", `a fading effect should draw its partition even before it fades, drew {drawn[2]}`)
end
-- RealmArt: islands at full opacity use the stack; a faded canvas and a fading sky tile do not
do
	local realm = Realms.LIST[1]
	local body = RealmArt.island(realm, 20, 6, 1)
	table.clear(drawn)
	RealmArt.draw(canvas(), body, 0, 0, 1)
	RealmArt.draw(canvas(0.5), body, 0, 0, 1)
	assert(drawn[1] == body.stackKey and drawn[2] == body.key, "an island draws its stack, and its partition on a faded canvas")
	local c = canvas()
	c.vpW, c.vpH = nil, nil
	c.gui = { AbsoluteSize = Rbx.Vector2.new(960, 540) }
	table.clear(drawn)
	RealmArt.overlay(c, realm, "storm", 0, 0, 1)
	RealmArt.overlay(c, realm, "storm", 0, 0, 0.5)
	local layer = RealmArt.layer(realm, "storm")
	assert(drawn[1] == layer.stackKey and drawn[#drawn] == layer.key, "a sky tile draws its stack, and its partition while it fades")
end
Canvas.sprite = sprite
print("PASS pixel layers: random grids exact (empty and translucent cells never covered); every effect and realm drawing repaints identically; the stack is only drawn at full opacity")
