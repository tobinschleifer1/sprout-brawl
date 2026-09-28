--!strict
-- Who is standing where in the lobby, as it crosses the wire ten times a second.
--
-- It used to be a table per person - area, userId, name, avatar code, weapon, x, z, y, facing,
-- moving - to everyone in the same place, every tenth of a second. That is quadratic in the crowd,
-- and the names and 27-character avatar codes almost never change: 24 people in the market cost
-- every one of them about 36 KB/s, as much as a fight's snapshots.
--
-- So the two halves go separately. Positions are a buffer: 29 bytes a person (x and z whole, so a
-- position arrives exactly as it was sent; the hop height is cosmetic and capped at 6 studs, so
-- f32). Who they are - name, avatar, weapon - is a roster sent with it only when it has changed for
-- that player (`signature`), and the client keeps the last one it was sent (`decode`).

local PresenceCodec = {}

local HEADER = 8 + 2                 -- area (f64), count (u16)
local ENTRY = 8 + 8 + 8 + 4 + 1      -- userId, x, z (f64), y (f32), flags (u8)
PresenceCodec.ENTRY = ENTRY
PresenceCodec.MAX = 65535

-- entries: { { userId, x, z, y, facing, moving, ... } }, all in `area`.
function PresenceCodec.encode(area: number, entries: { any }): buffer
	local n = math.min(#entries, PresenceCodec.MAX)
	local b = buffer.create(HEADER + n * ENTRY)
	buffer.writef64(b, 0, area)
	buffer.writeu16(b, 8, n)
	for i = 1, n do
		local e = entries[i]
		local at = HEADER + (i - 1) * ENTRY
		buffer.writef64(b, at, e.userId)
		buffer.writef64(b, at + 8, e.x)
		buffer.writef64(b, at + 16, e.z)
		buffer.writef32(b, at + 24, e.y or 0)
		buffer.writeu8(b, at + 28, (if e.facing == -1 then 1 else 0) + (if e.moving then 2 else 0))
	end
	return b
end

-- Who is in a group, for the roster: sent only when this changes.
function PresenceCodec.roster(entries: { any }): { any }
	local out = table.create(#entries)
	for i, e in entries do
		out[i] = { userId = e.userId, name = e.name, avatar = e.avatar, weapon = e.weapon }
	end
	return out
end

function PresenceCodec.signature(entries: { any }): string
	local parts = table.create(#entries)
	for i, e in entries do
		parts[i] = `{e.userId}\0{e.name}\0{e.avatar}\0{e.weapon}`
	end
	return table.concat(parts, "\1")
end

-- The entries back, in the shape the lobby draws (Plaza2D.setPeers): positions from the buffer,
-- identity from `roster` (userId -> { name, avatar, weapon }). Anyone the roster does not know yet
-- is left out until it does. A malformed buffer decodes to nothing.
function PresenceCodec.decode(b: any, roster: { [number]: any }): { any }
	if typeof(b) ~= "buffer" or buffer.len(b) < HEADER then return {} end
	local area = buffer.readf64(b, 0)
	local n = buffer.readu16(b, 8)
	if buffer.len(b) ~= HEADER + n * ENTRY then return {} end
	local out = {}
	for i = 1, n do
		local at = HEADER + (i - 1) * ENTRY
		local userId = buffer.readf64(b, at)
		local who = roster[userId]
		if who then
			local flags = buffer.readu8(b, at + 28)
			table.insert(out, {
				area = area, userId = userId, name = who.name, avatar = who.avatar, weapon = who.weapon,
				x = buffer.readf64(b, at + 8), z = buffer.readf64(b, at + 16), y = buffer.readf32(b, at + 24),
				facing = if bit32.band(flags, 1) ~= 0 then -1 else 1, moving = bit32.band(flags, 2) ~= 0,
			})
		end
	end
	return out
end

-- A roster as it arrived (a list) into the lookup `decode` reads.
function PresenceCodec.index(list: any): { [number]: any }
	local out = {}
	if type(list) ~= "table" then return out end
	for _, who in list do
		if type(who) == "table" and type(who.userId) == "number" then out[who.userId] = who end
	end
	return out
end

return PresenceCodec
