--!strict
-- The world's scene as it crosses the wire: a keyframe, then only what changed.
--
-- The scene (SceneSnapshot: hazards, the disaster, projectiles, items, summons, bursts, the
-- ultimates' state) went out whole, 30 times a second - measured at 6-24 KB/s a player, two to five
-- times the fighter snapshots, and most of it the same every time: a hazard's positions, widths
-- and reach are constants, and a quiet hazard's whole view repeats frame after frame. So a delta
-- carries only the parts that differ from the scene sent before it - per hazard, and per
-- top-level list - and a keyframe carries everything.
--
-- Like SnapshotCodec this leans on the Scene remote being reliable and ordered: the client always
-- holds the scene the server sent last. A client that does not (just joined, rejoined) cannot apply
-- a delta (`decode` returns nil) and waits for the next keyframe - every KEYFRAME_EVERY scenes, and
-- whenever the server is told someone new is watching.
local SceneCodec = {}
SceneCodec.KEYFRAME_EVERY = 30                -- scenes: one a second at 30Hz

local function equal(a: any, b: any): boolean
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then
		-- NaN never equals itself; -0 and 0 are equal here and that is fine for drawing
		return false
	end
	for k, v in a do
		if not equal(v, b[k]) then return false end
	end
	for k in b do
		if a[k] == nil then return false end
	end
	return true
end
SceneCodec.equal = equal

-- The packet for `scene`, as a delta against `base` (the scene sent before it), or a keyframe when
-- `base` is nil. `frame` and `id` always travel.
function SceneCodec.encode(scene: any, base: any?): any
	if base == nil then
		return { k = true, s = scene }
	end
	local set, del = {}, {}
	-- hazards field by field: a hazard's view is mostly constants (positions, widths, reach) with a
	-- progress value or two that tick every frame, and sending the whole view for those was most
	-- of the stream. `hs` replaces a whole view (one that is new); `hf` patches fields of one that
	-- was already there; `hd` removes views that have gone.
	local hset, hfields, hdel = {}, {}, {}
	for key, v in scene do
		if key == "hazards" then
			local old = base.hazards or {}
			for name, view in v do
				local was = old[name]
				if type(view) == "table" and type(was) == "table" then
					local fs, fd = {}, {}
					for f, fv in view do
						if not equal(fv, was[f]) then fs[f] = fv end
					end
					for f in was do
						if view[f] == nil then table.insert(fd, f) end
					end
					if next(fs) or #fd > 0 then hfields[name] = { s = if next(fs) then fs else nil, d = if #fd > 0 then fd else nil } end
				elseif not equal(view, was) then
					hset[name] = view
				end
			end
			for name in old do
				if v[name] == nil then table.insert(hdel, name) end
			end
		elseif key ~= "frame" and key ~= "id" and not equal(v, base[key]) then
			set[key] = v
		end
	end
	for key in base do
		if scene[key] == nil then table.insert(del, key) end
	end
	local out: any = { f = scene.frame, id = scene.id }
	if next(set) then out.s = set end
	if #del > 0 then out.d = del end
	if next(hset) then out.hs = hset end
	if next(hfields) then out.hf = hfields end
	if #hdel > 0 then out.hd = hdel end
	return out
end

-- The scene `packet` describes, given `base` (the scene last decoded). Nil for a delta without a
-- base. The result shares unchanged parts with `base`; neither is modified afterwards.
function SceneCodec.decode(packet: any, base: any?): any
	if packet.k then
		return packet.s
	end
	if base == nil then
		return nil
	end
	local out = table.clone(base)
	out.frame, out.id = packet.f, packet.id
	for key, v in packet.s or {} do out[key] = v end
	for _, key in packet.d or {} do out[key] = nil end
	if packet.hs or packet.hd or packet.hf then
		local hazards = table.clone(base.hazards or {})
		for name, view in packet.hs or {} do hazards[name] = view end
		for name, patch in packet.hf or {} do
			local view = table.clone(hazards[name] or {})
			for f, fv in patch.s or {} do view[f] = fv end
			for _, f in patch.d or {} do view[f] = nil end
			hazards[name] = view
		end
		for _, name in packet.hd or {} do hazards[name] = nil end
		out.hazards = hazards
	end
	return out
end

-- Roughly what a value costs on the wire: 8 bytes a number, a string's length, a couple for each
-- key and container. For the performance overlay's "bytes sent" - not for anything exact.
function SceneCodec.estimate(v: any): number
	local t = type(v)
	if t == "number" then return 9 end
	if t == "string" then return #v + 2 end
	if t == "boolean" then return 1 end
	if t ~= "table" then return 1 end
	local n = 2
	for k, x in v do
		n += (if type(k) == "string" then #k + 2 else 1) + SceneCodec.estimate(x)
	end
	return n
end

return SceneCodec
