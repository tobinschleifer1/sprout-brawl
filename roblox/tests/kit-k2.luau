--!strict
-- k2 character codes and clothing (phase 6 of docs/briefs/crates-and-monetisation-plan.md;
-- docs/briefs/clothing-catalogue.md, "Joining the kit"; Roblox only): k1 untouched, k2 round trips,
-- permanent piece numbers, every malformed code a valid character, pieces drawn, and clothing worn
-- only by its owner.
local Loader = require("./loader")
local AvatarKit = Loader.load("AvatarKit")
local Clothing = Loader.load("RobloxClothing")
local Cosmetics = Loader.load("Cosmetics")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local KIT = AvatarKit.KIT
local K1 = #AvatarKit.VERSION + #KIT.categories + #KIT.colours

local seed = 20261019
local function rand(n: number): number
	seed = (seed * 16807) % 2147483647
	return seed % n + 1
end
local function same(a: any, b: any): boolean
	if not a or not b then return false end
	for _, c in KIT.categories do if a.parts[c.id] ~= b.parts[c.id] then return false end end
	for _, c in KIT.colours do if a.colours[c.id] ~= b.colours[c.id] then return false end end
	return true
end
local function randomSpec(pieces: boolean): any
	local spec = { parts = {}, colours = {} }
	for _, c in KIT.categories do spec.parts[c.id] = c.options[rand(#c.options)].id end
	for _, c in KIT.colours do spec.colours[c.id] = rand(#c.list) - 1 end
	if pieces then
		for _, it in Clothing.items do if rand(2) == 1 then spec.parts[it.category] = it.id end end
	end
	return spec
end

-- 1. Every piece's permanent number, pinned: renumbering one changes every saved code that wears it.
local PINNED = { "neon_circuit_bomber", "neon_sideband_joggers", "neon_signal_cap", "neon_voltage_sweep",
	"neon_pulse_gloves", "neon_nightstep_hightops", "frost_rimeguard_coat", "frost_ridgeguard_trousers",
	"frost_snowline_beanie", "frost_whiteout_halfcape", "frost_icebreak_mitts", "frost_snowdrift_boots",
	"candy_sugarstripe_tee", "candy_bonbon_shorts", "candy_sundae_beret", "candy_softserve_swirl",
	"candy_sugarstar_specs", "candy_taffy_trainers", "void_eventide_vest", "void_rift_pleats",
	"void_comet_tail", "void_eclipse_mantle", "void_orbit_cuffs", "void_null_visor" }
local numbers = {}
for _, it in Clothing.items do
	assert(PINNED[it.n] == it.id, `{it.id} changed its permanent number ({it.n})`)
	assert(not numbers[it.n] and it.n >= 1 and it.n < 36 * 36, `piece number {it.n} reused or out of range`)
	numbers[it.n] = true
	assert(AvatarKit.category(it.category), `{it.id} is in no kit category`)
	assert(AvatarKit.category(it.category) and not table.find((function()
		local ids = {}
		for _, o in AvatarKit.category(it.category).options do table.insert(ids, o.id) end
		return ids
	end)(), it.id), `{it.id} collides with a free option`)
	local item = Cosmetics.get(it.id)
	assert(item and item.type == "clothing" and item.source == "shop" and item.rarity == it.rarity and item.crates == nil,
		`{it.id} is not a clothing item bought outright`)
end
assert(#Clothing.items == #PINNED, "a piece was added without pinning its number here")

-- 2. A character wearing no piece is a k1 code exactly as before; k2 round trips; canonical is stable.
for _ = 1, 400 do
	local spec = randomSpec(false)
	local code = AvatarKit.encode(spec)
	assert(string.sub(code, 1, 2) == "k1" and #code == K1, "a character with no clothing left k1")
	assert(same(AvatarKit.decode(code), spec), "a k1 code did not round trip")
end
local maxLen = 0
for _ = 1, 400 do
	local spec = randomSpec(true)
	local code = AvatarKit.encode(spec)
	local worn = AvatarKit.pieces(spec)
	assert(#worn == 0 or string.sub(code, 1, 2) == "k2", "a character wearing clothing was not k2")
	assert(#worn == 0 or #code == K1 + 3 * #worn, "a k2 code is not k1's length plus three per piece")
	assert(same(AvatarKit.decode(code), spec), "a k2 code did not round trip")
	assert(AvatarKit.canonical(code) == code and AvatarKit.isCode(code), "a canonical k2 code is not canonical")
	assert(AvatarKit.avatar(code).kit.parts.top == spec.parts.top, "a k2 avatar lost its clothing")
	maxLen = math.max(maxLen, #code)
end
-- every category that has a piece, all at once, still fits the 64-character ceiling every path assumes
local all = AvatarKit.sanitize(nil)
for _, it in Clothing.items do all.parts[it.category] = it.id end
local allCode = AvatarKit.encode(all)
assert(#allCode <= 64 and AvatarKit.isCode(allCode) and same(AvatarKit.decode(allCode), all), "the fullest k2 code does not fit")

-- 3. Beneath a piece sits its category's default; reading a k2 code as k1 digits gives that default.
local one = AvatarKit.sanitize(nil)
one.parts.top = "neon_circuit_bomber"
one.colours.top = 7
local oneCode = AvatarKit.encode(one)
local under = AvatarKit.decode("k1" .. string.sub(oneCode, 3, K1))
assert(under and under.parts.top == KIT.defaults.parts.top and under.colours.top == 7, "a k2 code's k1 digits are not the default beneath")
local topAt = (function() for i, c in KIT.categories do if c.id == "top" then return i end end return 0 end)()
assert(string.sub(oneCode, K1 + 1) == string.sub("0123456789abcdefghijklmnopqrstuvwxyz", topAt, topAt) .. "01", "the piece is not written as its category and number")

-- 4. Anything malformed is still a character: unknown numbers, wrong categories, ragged tails, case.
local base = string.sub(oneCode, 1, K1)
local function topOf(code: string): string? local s = AvatarKit.decode(code) return s and s.parts.top end
local catTop = string.sub(oneCode, K1 + 1, K1 + 1)
assert(topOf(base .. catTop .. "zz") == KIT.defaults.parts.top, "an unknown piece number was not the digit beneath")
assert(topOf(base .. catTop .. "02") == KIT.defaults.parts.top, "a bottom piece was worn as a top")
assert(topOf(base .. catTop .. "0") == KIT.defaults.parts.top and topOf(base .. catTop .. "01x") == "neon_circuit_bomber", "a ragged tail broke the code")
assert(topOf(base .. catTop .. "?!") == KIT.defaults.parts.top and topOf(base .. "#01") == KIT.defaults.parts.top, "junk in the tail was read")
assert(topOf("k2" .. string.upper(string.sub(oneCode, 3))) == "neon_circuit_bomber", "an upper-case k2 code lost its piece")
assert(AvatarKit.canonical(base) == "k1" .. string.sub(base, 3), "a k2 code wearing nothing is not canonically k1")
assert(AvatarKit.decode("k3" .. string.sub(base, 3)) == nil and not AvatarKit.isCode(oneCode .. string.rep("0", 64)), "not a code was read as one")
local spoof = AvatarKit.sanitize({ parts = { top = "neon_sideband_joggers", hair = "neon_voltage_sweep" } })
assert(spoof.parts.top == KIT.defaults.parts.top and spoof.parts.hair == "neon_voltage_sweep", "sanitize let a piece into the wrong category")

-- 5. A piece is drawn: it changes its own piece of the body and nothing else's category.
local undressed = AvatarKit.sanitize(nil)
undressed.colours.top = 7
local dressed = Compose.compose(one)
local plain = Compose.compose(undressed)
local function differs(a: any, b: any): boolean
	for k, v in a.cells do if not b.cells[k] or b.cells[k].hex ~= v.hex then return true end end
	for k in b.cells do if not a.cells[k] then return true end end
	return false
end
assert(differs(plain.torso, dressed.torso), "the Circuit Bomber was not drawn on the torso")
assert(not differs(plain.head, dressed.head), "a top changed the head")
for _, it in Clothing.items do
	local s = AvatarKit.sanitize(nil)
	s.parts[it.category] = it.id
	plain = Compose.compose(AvatarKit.sanitize(nil))
	local g, changed = Compose.compose(s), false
	for _, id in Compose.PIECES do if differs(plain[id], g[id]) then changed = true end end
	assert(changed, `{it.id} draws nothing`)
	assert(#Compose.sprites(AvatarKit.encode(s)).torso.full > 0, `{it.id} broke the sprites`)
end

-- 6. Worn only by its owner: saving needs every piece owned; a piece no longer owned comes off.
local owned: { [string]: boolean } = { neon_circuit_bomber = true }
local store = AvatarStore.new(nil, function() return 0 end)
store.owns = function(_, id) return owned[id] == true end
local both = AvatarKit.sanitize(nil)
both.parts.top, both.parts.hair = "neon_circuit_bomber", "neon_voltage_sweep"
local ok, why = store:apply(1, { action = "save", slot = 1, code = AvatarKit.encode(both) })
assert(not ok and string.find(why, "do not own", 1, true), "a character wearing an unowned piece was saved")
assert(store:apply(1, { action = "save", slot = 1, code = oneCode }), "a character wearing an owned piece was refused")
assert(store:active(1) == oneCode, "an owned piece came off")
owned.neon_circuit_bomber = false
assert(topOf(store:active(1)) == KIT.defaults.parts.top and string.sub(store:active(1), 1, 2) == "k1", "a piece no longer owned stayed on")
assert(AvatarKit.decode(store:active(1)).colours.top == 7, "taking a piece off changed the colours")
store.owns = function() error("store down") end
assert(topOf(store:active(1)) == KIT.defaults.parts.top, "a piece stayed on while ownership could not be read")
store.owns = nil
assert(not store:apply(1, { action = "save", slot = 2, code = oneCode }), "clothing was saved with no ownership check at all")
local stripped = AvatarKit.strip(both, function(id) return id == "neon_voltage_sweep" end)
assert(stripped.parts.top == KIT.defaults.parts.top and stripped.parts.hair == "neon_voltage_sweep", "strip took off the wrong piece")

print(`PASS k2: k1 codes unchanged; k2 round trips (longest {maxLen}, all pieces {#allCode} of 64); {#Clothing.items} permanent piece numbers pinned; unknown, misfiled and ragged pieces fall back to the default beneath; every piece drawn; saved only by its owner and taken off when no longer owned`)
