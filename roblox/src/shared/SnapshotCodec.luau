--!strict
-- A fight's snapshot as it crosses the wire: a buffer, and after the first, only what changed.
--
-- A snapshot is the whole authoritative state of every fighter (Snapshot.encode), 30 times a second
-- to everyone in the fight. As a table it cost ~1.1 KB with four fighters - ~34 KB/s to every
-- player, on a reliable channel, where a connection that falls behind queues everything after it:
-- that queue is lag. Between two snapshots 1/30s apart most of a fighter does not change - stocks,
-- index, item, shield, usually state and percent - so a DELTA carries, per fighter, a bitmask of the
-- fields that changed and those values alone, against the snapshot sent before it (`base`).
--
-- Deltas are safe because the Snapshot remote is reliable and ordered: the client always holds the
-- snapshot the server sent last. A client that does not - just joined, rejoined, started watching -
-- cannot decode a delta (`decode` returns nil) and waits for a KEYFRAME, which carries every field
-- and needs no base. MatchService sends one at the start, every KEYFRAME_EVERY frames, and after any
-- rejoin or new viewer.
--
-- Every number is carried exactly: an integer in the fewest bytes that hold it, anything else
-- (and -0) as a full f64. Prediction replays from these values, so a rounded x would be a drift.
-- The decoded snapshot is the same table the old wire carried - short names, `fighters`,
-- `platforms`, `acks` - so everything past this file is unchanged.

local Snapshot = require(script.Parent.Snapshot)

local SnapshotCodec = {}
-- How many bytes a packet is (the client's `buffer` is a local name for its snapshot list there).
function SnapshotCodec.size(packed: buffer): number
	return buffer.len(packed)
end
SnapshotCodec.KEYFRAME_EVERY = 60   -- frames: a client that lost its base recovers within a second

local WIRE: { string } = {}
for i, pair in Snapshot.FIELDS do WIRE[i] = pair[2] end
-- The changed-field mask is two 32-bit words: fields 1-32 in the first, 33-64 in the second.
assert(#WIRE <= 64, "a fighter's changed-field mask is 64 bits")
local function bitOf(k: number): (number, number)
	if k <= 32 then return 1, bit32.lshift(1, k - 1) end
	return 2, bit32.lshift(1, k - 33)
end

-- ------------------------------------------------------------------ writer ----
local T_NIL, T_FALSE, T_TRUE, T_I8, T_I16, T_I32, T_F64, T_STR = 0, 1, 2, 3, 4, 5, 6, 7

local function writer()
	local w = { b = buffer.create(256), n = 0 }
	local function room(k: number)
		if w.n + k > buffer.len(w.b) then
			local bigger = buffer.create(math.max(buffer.len(w.b) * 2, w.n + k))
			buffer.copy(bigger, 0, w.b, 0, w.n)
			w.b = bigger
		end
	end
	function w.u8(v: number) room(1); buffer.writeu8(w.b, w.n, v); w.n += 1 end
	function w.u16(v: number) room(2); buffer.writeu16(w.b, w.n, v); w.n += 2 end
	function w.u32(v: number) room(4); buffer.writeu32(w.b, w.n, v); w.n += 4 end
	function w.f64(v: number) room(8); buffer.writef64(w.b, w.n, v); w.n += 8 end
	function w.value(v: any)
		local t = type(v)
		if v == nil then
			w.u8(T_NIL)
		elseif t == "boolean" then
			w.u8(if v then T_TRUE else T_FALSE)
		elseif t == "number" then
			local int = v == v and v % 1 == 0 and not (v == 0 and 1 / v < 0)
			if int and v >= -128 and v <= 127 then
				w.u8(T_I8); room(1); buffer.writei8(w.b, w.n, v); w.n += 1
			elseif int and v >= -32768 and v <= 32767 then
				w.u8(T_I16); room(2); buffer.writei16(w.b, w.n, v); w.n += 2
			elseif int and v >= -2147483648 and v <= 2147483647 then
				w.u8(T_I32); room(4); buffer.writei32(w.b, w.n, v); w.n += 4
			else
				w.u8(T_F64); w.f64(v)
			end
		elseif t == "string" then
			local len = math.min(#v, 65535)
			w.u8(T_STR); w.u16(len); room(len); buffer.writestring(w.b, w.n, v, len); w.n += len
		else
			error(`SnapshotCodec: a {t} cannot cross the wire`)
		end
	end
	function w.done(): buffer
		local out = buffer.create(w.n)
		buffer.copy(out, 0, w.b, 0, w.n)
		return out
	end
	return w
end

-- ------------------------------------------------------------------ reader ----
local function reader(b: buffer)
	local r = { n = 0 }
	local function need(k: number)
		if r.n + k > buffer.len(b) then error("short") end
	end
	function r.u8(): number need(1); local v = buffer.readu8(b, r.n); r.n += 1; return v end
	function r.u16(): number need(2); local v = buffer.readu16(b, r.n); r.n += 2; return v end
	function r.u32(): number need(4); local v = buffer.readu32(b, r.n); r.n += 4; return v end
	function r.f64(): number need(8); local v = buffer.readf64(b, r.n); r.n += 8; return v end
	function r.value(): any
		local tag = r.u8()
		if tag == T_NIL then return nil
		elseif tag == T_FALSE then return false
		elseif tag == T_TRUE then return true
		elseif tag == T_I8 then need(1); local v = buffer.readi8(b, r.n); r.n += 1; return v
		elseif tag == T_I16 then need(2); local v = buffer.readi16(b, r.n); r.n += 2; return v
		elseif tag == T_I32 then need(4); local v = buffer.readi32(b, r.n); r.n += 4; return v
		elseif tag == T_F64 then return r.f64()
		elseif tag == T_STR then
			local len = r.u16(); need(len)
			local v = buffer.readstring(b, r.n, len); r.n += len; return v
		end
		error("tag")
	end
	return r
end

-- ------------------------------------------------------------------ encode ----
-- Whether a field must be sent again. `~=` alone misses 0 becoming -0 (they compare equal), and a
-- decoded snapshot has to be the one that was encoded, sign of zero included.
local function differs(a: any, b: any): boolean
	if a ~= b then return true end
	return a == 0 and 1 / a ~= 1 / b
end

-- `snap` is the table MatchService builds: { id, frame, state, time, countdown, fighters = { wire
-- tables }, platforms?, acks? }. With `base` (the snapshot sent before it, to the same audience)
-- it is a delta; without, a keyframe.
function SnapshotCodec.encode(snap: any, base: any?): buffer
	local w = writer()
	local delta = base ~= nil and #base.fighters == #snap.fighters
	w.u8(if delta then 1 else 0)
	w.f64(snap.id)
	w.u32(snap.frame)
	if delta then w.u32((base :: any).frame) end
	w.value(snap.state); w.value(snap.time); w.value(snap.countdown)
	w.u8(#snap.fighters)
	for i, f in snap.fighters do
		local prev = if delta then (base :: any).fighters[i] else nil
		local mask = { 0, 0 }
		for k, key in WIRE do
			if not prev or differs(prev[key], f[key]) then
				local word, bit = bitOf(k)
				mask[word] = bit32.bor(mask[word], bit)
			end
		end
		w.u32(mask[1]); w.u32(mask[2])
		for k, key in WIRE do
			local word, bit = bitOf(k)
			if bit32.btest(mask[word], bit) then w.value(f[key]) end
		end
	end
	local platforms = snap.platforms
	w.u16(if platforms then #platforms else 65535)
	for _, p in platforms or {} do w.u16(p.i); w.value(p.cx); w.value(p.top) end
	local acks = snap.acks
	w.u8(if acks then #acks else 255)
	for _, a in acks or {} do w.u8(a.i); w.value(a.n); w.value(a.e) end
	return w.done()
end

-- The snapshot back, in the old wire shape. A delta needs `base` - the last snapshot decoded, from
-- the same match, at the frame it was made against - and returns nil without it (wait for a
-- keyframe). Anything malformed is nil too.
function SnapshotCodec.decode(b: any, base: any?): any
	if typeof(b) ~= "buffer" then return nil end
	local ok, snap = pcall(function()
		local r = reader(b)
		local delta = r.u8() == 1
		local id = r.f64()
		local frame = r.u32()
		if delta then
			local baseFrame = r.u32()
			if not base or base.id ~= id or base.frame ~= baseFrame then return nil end
		end
		local out: any = { id = id, frame = frame, state = r.value(), time = r.value(), countdown = r.value() }
		local n = r.u8()
		if delta and #(base :: any).fighters ~= n then return nil end
		out.fighters = table.create(n)
		for i = 1, n do
			local mask = { r.u32(), r.u32() }
			local f = if delta then table.clone((base :: any).fighters[i]) else {}
			for k, key in WIRE do
				local word, bit = bitOf(k)
				if bit32.btest(mask[word], bit) then f[key] = r.value() end
			end
			out.fighters[i] = f
		end
		local np = r.u16()
		if np ~= 65535 then
			out.platforms = table.create(np)
			for i = 1, np do out.platforms[i] = { i = r.u16(), cx = r.value(), top = r.value() } end
		end
		local na = r.u8()
		if na ~= 255 then
			out.acks = table.create(na)
			for i = 1, na do out.acks[i] = { i = r.u8(), n = r.value(), e = r.value() } end
		end
		if r.n ~= buffer.len(b) then return nil end
		return out
	end)
	return if ok then snap else nil
end

-- Whether a buffer is a keyframe (decodable without a base).
function SnapshotCodec.isKeyframe(b: any): boolean
	return typeof(b) == "buffer" and buffer.len(b) > 0 and buffer.readu8(b, 0) == 0
end

return SnapshotCodec
