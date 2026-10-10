--!strict
-- AvatarKit.luau and AvatarCompose.luau against web/src/data/avatarKit.js and
-- render2d/avatarCompose.js: every code (good, short and malformed), every sanitised spec, every
-- resolved colour, the layer order, and every piece's rectangles at full and half resolution for
-- 249 characters - the presets, forty random ones, and every option of every category.
--
-- Then the properties the parity cannot vouch for, measured on the Luau itself: the server's
-- canonical() turns anything into a valid code; a preset code decodes to its own choices; the
-- rectangles fit their canvases.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local AvatarKit = Loader.load("AvatarKit")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local T = serde.decode("json", fs.readFile("tests/kit-fixture.json"))

local checked = 0
local function same(a: any, b: any, where: string)
	if type(a) == "table" and type(b) == "table" then
		for k, v in b do
			same(a[k], v, `{where}.{k}`)
		end
		for k in a do
			assert(b[k] ~= nil, `{where}.{k}: Luau has a key the JavaScript does not`)
		end
	else
		assert(a == b, `{where}: JS {tostring(b)}, Luau {tostring(a)}`)
		checked += 1
	end
end

-- Codes.
for _, c in T.codes do
	same(AvatarKit.isCode(c.input), c.isCode, `isCode({c.input})`)
	same(AvatarKit.canonical(c.input) or false, c.canonical, `canonical({c.input})`)
	same(AvatarKit.decode(c.input) or false, c.spec, `decode({c.input})`)
end
for i, s in T.sanitized do
	same(AvatarKit.sanitize(if s.raw == false then nil else s.raw), s.spec, `sanitize #{i}`)
end
local codes = checked

-- Composition.
local function rects(got: { any }, want: { any }, where: string)
	assert(#got == #want, `{where}: {#got} rectangles, JS {#want}`)
	for i, r in got do
		for j = 1, 6 do
			same(r[j], want[i][j], `{where}[{i}][{j}]`)
		end
	end
end
for _, s in T.sprites do
	local spec = AvatarKit.decode(s.code)
	same(AvatarKit.palette(spec), s.palette, `{s.code} palette`)
	local roles = Compose.resolveRoles(spec)
	for ch, hex in s.roles do
		same(roles[ch].hex, hex, `{s.code} role {ch}`)
	end
	local layers, trim = Compose.layersOf(spec)
	same(trim, s.trim, `{s.code} trim`)
	assert(#layers == #s.order, `{s.code}: {#layers} layers, JS {#s.order}`)
	for i, L in layers do
		same(`{L.part}:{L.z}:{L.x}:{L.y}`, s.order[i], `{s.code} layer {i}`)
	end
	local sp = Compose.sprites(s.code)
	for id, p in s.pieces do
		rects(sp[id].full, p.full, `{s.code} {id}`)
		-- the jointed rig's segments are cut at full detail only; a half copy would be dead weight
		assert((p.half == nil) == (sp[id].half == nil), `{s.code} {id}: half resolution on one side only`)
		if p.half then rects(sp[id].half, p.half, `{s.code} {id} (half)`) end
	end
	for id, want in s.farSegments do
		rects(sp[id].farFull, want, `{s.code} far {id}`)
	end
	rects(Compose.shadeRects(sp.arm.full), s.farArm, `{s.code} far arm`)
	rects(Compose.shadeRects(sp.leg.half), s.farLegHalf, `{s.code} far leg (half)`)
end
-- A band cut where the silhouette narrows: outlined as the whole grid is, not as the band alone.
do
	local g = T.probe.grid
	local cells = {}
	for i = 1, g.w * g.h do cells[i] = g.cells[i] end
	rects(Compose.piece({ w = g.w, h = g.h, cells = cells } :: any, 3, 6), T.probe.band, "the narrowing probe's band")
end
print(`kit: {codes} code values and {checked - codes} composed values across {#T.sprites} characters match the web`)

-- Properties, on the Luau.
-- 1. The server's gate: anything a client could send comes out as a full-length valid code or nil.
local hostile: { any } = { "k1", "k1" .. string.rep("z", 40), "k1\0\0\0", "k1🙂🙂", "k1" .. string.rep("9", 62), 5, true, {}, "Classic" }
for _, h in hostile do
	local ok, out = pcall(AvatarKit.canonical, h)
	assert(ok, `canonical threw on {tostring(h)}: {out}`)
	if out ~= nil then
		assert(#out == AvatarKit.CODE_LENGTH and AvatarKit.decode(out) ~= nil, `canonical({tostring(h)}) = {out}`)
		assert(AvatarKit.canonical(out) == out, `canonical is not idempotent on {out}`)
	end
end
-- 2. Presets carry the choices their names promise.
local knight
for _, p in AvatarKit.KIT.presets do
	if p.id == "knight" then knight = AvatarKit.decode(p.code) end
end
assert(knight and knight.parts.headwear == "knight" and knight.parts.top == "armor", "the knight preset lost its helm or its armour")
-- 3. Every rectangle sits inside its piece's canvas, at both resolutions.
local inside = 0
for _, s in T.sprites do
	local sp = Compose.sprites(s.code)
	for id, p in sp do
		local P = AvatarKit.KIT.parts[id]
		for _, half in { false, true } do
			local w, h = if half then math.ceil(P.w / 2) else P.w, if half then math.ceil(P.h / 2) else P.h
			for _, r in (if half then p.half or {} else p.full) do
				assert(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= w and r[2] + r[4] <= h, `{s.code} {id}: rectangle leaves the canvas`)
				inside += 1
			end
		end
	end
end
-- 4. The combination count the creator will show is the JavaScript's.
assert(tostring(AvatarKit.partCombinations()) == T.combos or math.abs(AvatarKit.partCombinations() - (tonumber(T.combos) :: number)) < 1e3,
	`combinations: Luau {AvatarKit.partCombinations()}, JS {T.combos}`)
print(`kit: hostile codes become valid ones, presets keep their parts, {inside} rectangles inside their canvases`)
