--!strict
-- Kit character codes: a port of the code half of web/src/data/avatarKit.js.
--
-- A kit character is a 27-character code - 'k1', one base-36 digit per part category, one per
-- colour slot - and the code IS the avatar id. It travels through the DataStore, the room, the
-- roster and the hub presence exactly where a preset id like "Classic" does, which is why none of
-- those needed to learn that player-made characters exist. Shared, because the server checks
-- every code a client sends before it lets it into a room: canonical() rebuilds a code out of
-- known-good digits and never throws, so anything a client can send becomes a valid character.
--
-- Held to the JavaScript by tests/kit-parity.luau.
--
-- K2 (Roblox only; docs/briefs/clothing-catalogue.md, "Joining the kit"). Clothing pieces
-- (RobloxClothing) are options k1 cannot name: its one digit per category holds only the free
-- options, and a new category would move every saved code's colours. So a character wearing a piece
-- is a 'k2' code: k1's own digits, unchanged in layout, then three characters per piece worn - the
-- category's position (one base-36 digit) and the piece's permanent number (two). A category with a
-- piece keeps its default's digit underneath. A character wearing no piece is still a k1 code, so
-- every existing code, and everything the JavaScript can make, reads and writes exactly as before.
-- An unknown piece number, or one named under the wrong category, falls back to the digit beneath
-- it. Wearing a piece is not owning it: the server strips pieces their wearer does not own (`strip`).

local KIT: any = require(script.Parent.Data.AvatarKit)
local Clothing: any = require(script.Parent.RobloxClothing)

local AvatarKit = {}
AvatarKit.KIT = KIT
AvatarKit.VERSION = KIT.version :: string
AvatarKit.CODE_LENGTH = KIT.codeLength :: number

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
AvatarKit.K2 = "k2"

-- Clothing pieces as kit options, by id and by permanent number.
type Piece = { id: string, n: number, category: string, option: any }
local PIECE: { [string]: Piece } = {}
local PIECE_N: { [number]: Piece } = {}
for _, it in Clothing.items do
	local p = { id = it.id, n = it.n, category = it.category,
		option = { id = it.id, name = it.name, layers = it.layers, trim = it.trim, piece = it.n } }
	PIECE[it.id], PIECE_N[it.n] = p, p
end

export type Spec = { parts: { [string]: string }, colours: { [string]: number } }

local function digitOf(ch: string): number
	local at = string.find(DIGITS, ch, 1, true)
	return if at then at - 1 else -1
end

local function optionIndex(cat: any, id: any): number?
	for i, o in cat.options do
		if o.id == id then
			return i
		end
	end
	return nil
end

function AvatarKit.isCode(s: any): boolean
	if type(s) ~= "string" or #s > 64 then return false end
	local v = string.sub(s, 1, #AvatarKit.VERSION)
	return v == AvatarKit.VERSION or v == AvatarKit.K2
end

-- A clothing piece by id, or nil.
function AvatarKit.piece(id: any): Piece?
	return if type(id) == "string" then PIECE[id] else nil
end

-- A category's option by id: a free option, or a clothing piece of that category; nil otherwise.
function AvatarKit.option(catId: string, id: any): any
	local c = AvatarKit.category(catId)
	if not c then return nil end
	local i = optionIndex(c, id)
	if i then return c.options[i] end
	local p = AvatarKit.piece(id)
	return if p and p.category == catId then p.option else nil
end

-- The clothing pieces a character wears, in category order.
function AvatarKit.pieces(spec: Spec): { string }
	local out = {}
	for _, c in KIT.categories do
		local p = PIECE[spec.parts[c.id]]
		if p and p.category == c.id then table.insert(out, p.id) end
	end
	return out
end

-- The character with every piece its wearer does not own taken off (the category's default).
function AvatarKit.strip(spec: Spec, owns: (string) -> boolean): Spec
	local parts = table.clone(spec.parts)
	for _, id in AvatarKit.pieces(spec) do
		local ok, has = pcall(owns, id)
		if not (ok and has == true) then parts[PIECE[id].category] = KIT.defaults.parts[PIECE[id].category] end
	end
	return { parts = parts, colours = spec.colours }
end

-- `sanitizeKit`: rebuild a spec from known-good values; never throws.
function AvatarKit.sanitize(raw: any): Spec
	local src = if type(raw) == "table" then raw else {}
	local parts, colours = {}, {}
	local srcParts = if type(src.parts) == "table" then src.parts else {}
	local srcColours = if type(src.colours) == "table" then src.colours else {}
	for _, c in KIT.categories do
		local v = srcParts[c.id]
		local p = PIECE[v]
		parts[c.id] = if optionIndex(c, v) or (p and p.category == c.id) then v else KIT.defaults.parts[c.id]
	end
	for _, c in KIT.colours do
		local v = srcColours[c.id]
		local ok = type(v) == "number" and v % 1 == 0 and v >= 0 and v < #c.list
		colours[c.id] = if ok then v else KIT.defaults.colours[c.id]
	end
	return { parts = parts, colours = colours }
end

function AvatarKit.encode(raw: any): string
	local spec = AvatarKit.sanitize(raw)
	local out = { AvatarKit.VERSION }
	local worn = {}
	for k, c in KIT.categories do
		local p = PIECE[spec.parts[c.id]]
		local i = optionIndex(c, if p then KIT.defaults.parts[c.id] else spec.parts[c.id]) :: number
		table.insert(out, string.sub(DIGITS, i, i))       -- option i is digit i - 1: 1-indexed
		if p then
			local hi, lo = p.n // 36, p.n % 36
			table.insert(worn, string.sub(DIGITS, k, k) .. string.sub(DIGITS, hi + 1, hi + 1) .. string.sub(DIGITS, lo + 1, lo + 1))
		end
	end
	for _, c in KIT.colours do
		local d = spec.colours[c.id]
		table.insert(out, string.sub(DIGITS, d + 1, d + 1))
	end
	if #worn > 0 then
		out[1] = AvatarKit.K2
		table.insert(out, table.concat(worn))
	end
	return table.concat(out)
end

-- Anything that is not a kit code is nil. A missing or bad digit falls back to that slot's default.
-- (That does not make a code from a version with fewer categories readable: its colour digits would
-- be read as the new categories. A new category needs a new version - see avatarKit.js, THE CODE.)
function AvatarKit.decode(code: any): Spec?
	if not AvatarKit.isCode(code) then
		return nil
	end
	local body = string.lower(string.sub(code, #AvatarKit.VERSION + 1))
	local extra = ""
	local n = #KIT.categories
	if string.sub(code, 1, #AvatarKit.K2) == AvatarKit.K2 then
		extra = string.sub(body, n + #KIT.colours + 1)
		body = string.sub(body, 1, n + #KIT.colours)
	end
	local function digit(k: number): number
		return if k < #body then digitOf(string.sub(body, k + 1, k + 1)) else -1
	end
	local parts, colours = {}, {}
	for i, c in KIT.categories do
		local d = digit(i - 1)
		parts[c.id] = if d >= 0 and d < #c.options then c.options[d + 1].id else KIT.defaults.parts[c.id]
	end
	for i, c in KIT.colours do
		local d = digit(n + i - 1)
		colours[c.id] = if d >= 0 and d < #c.list then d else KIT.defaults.colours[c.id]
	end
	-- k2: the pieces worn, three characters each; anything unreadable is left as the digit beneath
	for at = 1, #extra - 2, 3 do
		local k, hi, lo = digitOf(string.sub(extra, at, at)), digitOf(string.sub(extra, at + 1, at + 1)), digitOf(string.sub(extra, at + 2, at + 2))
		local c = KIT.categories[k + 1]
		local p = if hi >= 0 and lo >= 0 then PIECE_N[hi * 36 + lo] else nil
		if c and p and p.category == c.id then parts[c.id] = p.id end
	end
	return { parts = parts, colours = colours }
end

function AvatarKit.canonical(code: any): string?
	local spec = AvatarKit.decode(code)
	return if spec then AvatarKit.encode(spec) else nil
end

local function colourList(slot: string): { string }
	for _, c in KIT.colours do
		if c.id == slot then
			return c.list
		end
	end
	error("no colour slot " .. slot)
end

-- The five-colour palette the rest of the game reads off an avatar (smear ghosts, hauled-weapon dirt).
function AvatarKit.palette(spec: Spec): { [string]: string }
	local function pick(slot: string): string
		return colourList(slot)[spec.colours[slot] + 1]
	end
	return { primary = pick("top"), secondary = pick("trim"), tertiary = pick("bottom"),
		accent = pick("skin"), glow = pick("accessory") }
end

-- A code as an avatar in a preset's shape, cached per code: every client builds the same few
-- characters over and over (one per fighter per match), and the result is read-only.
local CACHE: { [string]: any } = {}
function AvatarKit.avatar(code: any): any
	local canon = AvatarKit.canonical(code)
	if not canon then
		return nil
	end
	local hit = CACHE[canon]
	if hit then
		return hit
	end
	local spec = AvatarKit.decode(canon) :: Spec
	local a = { id = canon, code = canon, name = "Custom", rig = "avatar", custom = true, kit = spec, palette = AvatarKit.palette(spec) }
	CACHE[canon] = a
	return a
end

function AvatarKit.defaultCode(): string
	return AvatarKit.encode(KIT.defaults)
end

function AvatarKit.category(id: string): any
	for _, c in KIT.categories do
		if c.id == id then
			return c
		end
	end
	return nil
end

function AvatarKit.colourSlot(id: string): any
	for _, c in KIT.colours do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- How many characters the parts alone make. A float: it is past 2^53 and only ever displayed.
-- The reward a part needs before it can be worn (data/parkour.js REWARDS), or nil for anyone's.
function AvatarKit.unlockOf(catId: string, optionId: string): string?
	local c = AvatarKit.category(catId)
	if not c then return nil end
	for _, o in c.options do
		if o.id == optionId then return o.unlock end
	end
	return nil
end

-- Every reward a character's parts need (avatarKit.js kitUnlocks). The server saves a code only for
-- a player who owns them all; everyone can still see it.
function AvatarKit.unlocks(spec: Spec): { string }
	local out = {}
	for _, c in KIT.categories do
		local u = AvatarKit.unlockOf(c.id, spec.parts[c.id])
		if u then table.insert(out, u) end
	end
	return out
end

function AvatarKit.partCombinations(): number
	local n = 1
	for _, c in KIT.categories do
		n *= #c.options
	end
	return n
end

return AvatarKit
