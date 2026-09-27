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

local KIT: any = require(script.Parent.Data.AvatarKit)

local AvatarKit = {}
AvatarKit.KIT = KIT
AvatarKit.VERSION = KIT.version :: string
AvatarKit.CODE_LENGTH = KIT.codeLength :: number

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

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
	return type(s) == "string" and string.sub(s, 1, #AvatarKit.VERSION) == AvatarKit.VERSION and #s <= 64
end

-- `sanitizeKit`: rebuild a spec from known-good values; never throws.
function AvatarKit.sanitize(raw: any): Spec
	local src = if type(raw) == "table" then raw else {}
	local parts, colours = {}, {}
	local srcParts = if type(src.parts) == "table" then src.parts else {}
	local srcColours = if type(src.colours) == "table" then src.colours else {}
	for _, c in KIT.categories do
		local v = srcParts[c.id]
		parts[c.id] = if optionIndex(c, v) then v else KIT.defaults.parts[c.id]
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
	for _, c in KIT.categories do
		local i = optionIndex(c, spec.parts[c.id]) :: number
		table.insert(out, string.sub(DIGITS, i, i))       -- option i is digit i - 1: 1-indexed
	end
	for _, c in KIT.colours do
		local d = spec.colours[c.id]
		table.insert(out, string.sub(DIGITS, d + 1, d + 1))
	end
	return table.concat(out)
end

-- Anything that is not a kit code is nil. A missing or bad digit falls back to that slot's default,
-- so a code from an older version with fewer categories keeps every choice it has.
function AvatarKit.decode(code: any): Spec?
	if not AvatarKit.isCode(code) then
		return nil
	end
	local body = string.lower(string.sub(code, #AvatarKit.VERSION + 1))
	local function digit(k: number): number
		return if k < #body then digitOf(string.sub(body, k + 1, k + 1)) else -1
	end
	local parts, colours = {}, {}
	local n = #KIT.categories
	for i, c in KIT.categories do
		local d = digit(i - 1)
		parts[c.id] = if d >= 0 and d < #c.options then c.options[d + 1].id else KIT.defaults.parts[c.id]
	end
	for i, c in KIT.colours do
		local d = digit(n + i - 1)
		colours[c.id] = if d >= 0 and d < #c.list then d else KIT.defaults.colours[c.id]
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
	local a = { id = canon, name = "Custom", rig = "avatar", custom = true, kit = spec, palette = AvatarKit.palette(spec) }
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
function AvatarKit.partCombinations(): number
	local n = 1
	for _, c in KIT.categories do
		n *= #c.options
	end
	return n
end

return AvatarKit
