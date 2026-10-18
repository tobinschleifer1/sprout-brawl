--!strict
-- A player's saved characters: up to eight named kit codes and which one they are wearing.
--
-- Stored in a DataStore under the player's user id, so a character outlives the server. The store
-- is injected (`AvatarStore.new(dataStore)`) so tests/avatar-store.luau drives the real code with a
-- fake one - including one that fails, which is the case that matters: Studio without "Enable
-- Studio Access to API Services" throws on every call, and a live DataStore throttles. Neither may
-- cost a player their character or stop them playing, so a store that cannot be reached leaves the
-- player with a working session-only wardrobe and a note saying saving is off, and nothing is ever
-- written over a record that could not be read (see `loaded`).
--
-- Everything read back is rebuilt through AvatarKit.canonical and a name cleaner: the record came
-- from a DataStore, which a previous version of this code - or an exploit of it - wrote.
--
-- Names are private: they are shown only to their owner, in the creator. Anything shown to other
-- players would have to go through TextService filtering first; other players see DisplayName.

local AvatarKit = require(game:GetService("ReplicatedStorage").Shared.AvatarKit)
local Inventory = require(game:GetService("ReplicatedStorage").Shared.Inventory)

local AvatarStore = {}
AvatarStore.__index = AvatarStore

AvatarStore.MAX_SLOTS = 8
-- what a record keeps (the Wardrobe pass raises a player's limit to this; a lost pass keeps them)
AvatarStore.STORED_SLOTS = 16
AvatarStore.MAX_NAME = 20
AvatarStore.VERSION = 1
AvatarStore.SAVE_DELAY = 6          -- seconds: a burst of edits is one write, not twenty
local RETRIES = 3

local function cleanName(raw: any, fallback: string): string
	local s = if type(raw) == "string" then raw else ""
	s = string.gsub(s, "[^%w %.%-_']", "")
	s = string.gsub(s, "%s+", " ")
	s = string.match(s, "^%s*(.-)%s*$") or ""
	if #s == 0 then
		return fallback
	end
	return string.sub(s, 1, AvatarStore.MAX_NAME)
end
AvatarStore.cleanName = cleanName

-- A record as it may be stored: rebuilt, never trusted.
function AvatarStore.sanitize(raw: any): any
	local src = if type(raw) == "table" then raw else {}
	local slots = {}
	if type(src.slots) == "table" then
		for i = 1, AvatarStore.STORED_SLOTS do
			local s = src.slots[i]
			if type(s) ~= "table" then
				break
			end
			table.insert(slots, { name = cleanName(s.name, `Fighter {i}`),
				code = AvatarKit.canonical(s.code) or AvatarKit.defaultCode() })
		end
	end
	if #slots == 0 then
		slots[1] = { name = "Fighter 1", code = AvatarKit.defaultCode() }
	end
	local active = if type(src.active) == "number" and src.active % 1 == 0 and src.active >= 1 and src.active <= #slots
		then src.active else 1
	-- Skyline Climb progress rides in the same record (ClimbProgress cleans it field by field when it
	-- reads it); only plain numbers are carried, so nothing else a record holds can slip through.
	local climb = nil
	if type(src.climb) == "table" then
		climb = {}
		for _, k in { "best", "climbed", "summits", "bestFrames" } do
			if type(src.climb[k]) == "number" then climb[k] = src.climb[k] end
		end
	end
	-- Purchase ids already delivered (server/Purchases), so a receipt Roblox sends again is not
	-- granted twice: strings only, the most recent 50.
	local receipts = nil
	if type(src.receipts) == "table" then
		receipts = {}
		for _, id in src.receipts do
			if type(id) == "string" and #id <= 100 then table.insert(receipts, id) end
		end
		while #receipts > 50 do table.remove(receipts, 1) end
	end
	-- Earned rewards (the Skyline Climb's): the avatar parts they unlock. Short strings only.
	local rewards = {}
	if type(src.rewards) == "table" then
		for _, id in src.rewards do
			if type(id) == "string" and #id <= 40 and not table.find(rewards, id) and #rewards < 32 then table.insert(rewards, id) end
		end
	end
	-- Cosmetics owned and worn (Inventory cleans them against the catalogue).
	local inventory = Inventory.sanitize(src.inventory)
	return { v = AvatarStore.VERSION, slots = slots, active = active, climb = climb, receipts = receipts, rewards = rewards,
		inventory = inventory }
end

function AvatarStore.new(dataStore: any, clock: (() -> number)?, opts: any?): any
	return setmetatable({
		sessionOnly = opts and opts.sessionOnly == true,
		busy = {}, closing = {}, revisions = {},
		store = dataStore,         -- nil: saving is off (no DataStore service at all)
		clock = clock or os.clock,
		records = {},              -- userId -> record
		loaded = {},               -- userId -> true once the stored record was READ successfully
		wait = nil :: ((number) -> ())?, -- backoff between read retries; task.wait on a server
		dirty = {},                -- userId -> clock time it became dirty
		notes = {},                -- userId -> why saving is off, for the creator to show
	}, AvatarStore)
end

local function key(userId: number): string
	return "u" .. tostring(userId)
end

-- Read (with retries) and cache a player's record. Never throws. On failure the player gets the
-- default wardrobe for this session and the record is marked unloaded, so it is never saved over
-- whatever is really stored.
function AvatarStore.load(self: any, userId: number): any
	if self.records[userId] then
		return self.records[userId]
	end
	-- Install one placeholder before yielding. Other readers cannot start a competing load.
	local placeholder = AvatarStore.sanitize(nil)
	self.records[userId] = placeholder
	local raw, ok, err = nil, false, "no DataStore"
	if self.store then
		for attempt = 1, RETRIES do
			ok, err = pcall(function()
				raw = self.store:GetAsync(key(userId))
			end)
			if ok then
				break
			end
			if attempt < RETRIES and self.wait then
				self.wait(attempt)
			end
		end
	end
	if self.records[userId] ~= placeholder then return placeholder end -- released during the read
	local clean = AvatarStore.sanitize(raw)
	for k, v in clean do placeholder[k] = v end
	self.revisions[userId] = if type(raw) == "table" then raw._revision or 0 else 0
	local revision = self.revisions[userId]
	if type(revision) ~= "number" or revision < 0 or revision % 1 ~= 0 or revision >= Inventory.MAX_INTEGER then ok = false end
	if ok then
		self.loaded[userId] = true
		self.notes[userId] = nil
	else
		self.notes[userId] = "Saving is off right now: your characters last until you leave."
		if self.store then
			warn(`[Blockfall] characters for {userId} could not be loaded ({err}); session-only`)
		end
	end
	return self.records[userId]
end

function AvatarStore.active(self: any, userId: number): string
	local rec = self:load(userId)
	return rec.slots[rec.active].code
end

-- What the creator shows its owner.
-- How many characters this player may keep: MAX_SLOTS, or STORED_SLOTS with the Wardrobe pass
-- (`self.wardrobe(userId)`, set by the server entry point).
function AvatarStore.slotsFor(self: any, userId: number): number
	local ok, has = pcall(function() return self.wardrobe and self.wardrobe(userId) end)
	return if ok and has == true then AvatarStore.STORED_SLOTS else AvatarStore.MAX_SLOTS
end

function AvatarStore.view(self: any, userId: number): any
	local rec = self:load(userId)
	local slots = {}
	for i, s in rec.slots do
		slots[i] = { name = s.name, code = s.code }
	end
	return { slots = slots, active = rec.active, max = self:slotsFor(userId),
		saving = self.loaded[userId] == true, note = self.notes[userId], unlocked = table.clone(rec.rewards) }
end

-- An edit from the creator. Returns ok, error text. `slot` may be one past the end to add a slot.
function AvatarStore.apply(self: any, userId: number, msg: any): (boolean, string?)
	if type(msg) ~= "table" then
		return false, "Bad request."
	end
	local rec = self:load(userId)
	local i = msg.slot
	if type(i) ~= "number" or i % 1 ~= 0 or i < 1 then
		return false, "Bad slot."
	end
	if msg.action == "save" then
		local cap = self:slotsFor(userId)
		if i > #rec.slots + 1 or i > cap then
			return false, `You can keep {cap} characters. Delete one first.`
		end
		local code = AvatarKit.canonical(msg.code)
		if not code then
			return false, "That is not a character."
		end
		-- An earned part is saved only for a player who has earned it (the Skyline Climb's rewards).
		for _, need in AvatarKit.unlocks(AvatarKit.decode(code) :: any) do
			if not table.find(rec.rewards, need) then
				return false, "That part is earned on the Skyline Climb. Collect it first."
			end
		end
		rec.slots[i] = { name = cleanName(msg.name, `Fighter {i}`), code = code }
		if msg.wear ~= false then
			rec.active = i
		end
	elseif msg.action == "wear" then
		if not rec.slots[i] then
			return false, "No character there."
		end
		rec.active = i
	elseif msg.action == "delete" then
		if not rec.slots[i] then
			return false, "No character there."
		end
		if #rec.slots == 1 then
			return false, "You need at least one character."
		end
		table.remove(rec.slots, i)
		-- Deleting what you wear puts on the character that slid into its place (or the new last
		-- one); deleting one before it keeps you in the same character, one slot earlier.
		if rec.active == i then
			rec.active = math.min(i, #rec.slots)
		elseif rec.active > i then
			rec.active -= 1
		end
	else
		return false, "Unknown action."
	end
	self.dirty[userId] = self.dirty[userId] or self.clock()
	return true, nil
end

-- Write one player's record now. Only a record that was read successfully is ever written:
-- writing a default wardrobe over a record we failed to read would delete their characters.
-- A reward earned: kept in the record, and its part can now be saved. False if already had.
function AvatarStore.grant(self: any, userId: number, id: string): boolean
	local rec = self:load(userId)
	if table.find(rec.rewards, id) then return false end
	table.insert(rec.rewards, id)
	self.dirty[userId] = self.dirty[userId] or self.clock()
	return true
end

-- A detached snapshot is essential: Roblox serializes at the call, while local writers can run
-- during the yield. Equality after the write preserves edits made by those writers.
local function copy(v: any): any
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = copy(x) end
	return out
end
local function equal(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in a do if not equal(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

-- Optimistic fencing: every write must replace exactly the version this server read. This is
-- sufficient for single-record economy commits; multi-record trading still needs its own protocol.
function AvatarStore._write(self: any, userId: number, snapshot: any): boolean
	local revision = self.revisions[userId]
	local value = copy(snapshot)
	value._revision = revision + 1
	local ok, result = pcall(function()
		return self.store:UpdateAsync(key(userId), function(old: any)
			local current = if type(old) == "table" then old._revision or 0 else 0
			if current ~= revision then return nil end
			return value
		end)
	end)
	if ok and result ~= nil then
		self.revisions[userId] = revision + 1
		return true
	end
	-- A cancelled compare-and-swap means this session is stale. Never retry its snapshot over
	-- the winner. A transport failure is retryable for wardrobe saves, but economy fails closed.
	if ok then self.loaded[userId] = nil end
	warn(`[Blockfall] record {userId} save failed or conflicted; no economy result acknowledged`)
	return false
end

function AvatarStore.flush(self: any, userId: number): boolean
	if self.busy[userId] or not (self.store and self.loaded[userId]) then return false end
	if not self.dirty[userId] then return true end
	self.busy[userId] = true
	local rec = self.records[userId]
	local snapshot = copy(rec)
	local ok = self:_write(userId, snapshot)
	if ok and equal(rec, snapshot) then self.dirty[userId] = nil end
	self.busy[userId] = nil
	return ok
end

-- Run on a private inventory and commit the entire debit/reward/pity/meter in one write BEFORE
-- exposing it. The lock covers mint/policy/save yields, and blocks wardrobe flush and Locker edits.
function AvatarStore.inventoryTransaction(self: any, userId: number, fn: (any) -> (boolean, any)): (boolean, any)
	local rec = self:load(userId)
	if self.busy[userId] or self.closing[userId] then return false, "your record is busy; try again" end
	-- Studio (sessionOnly) with no record read - no DataStore, or API access off - spends for the
	-- session only and never writes; a live server refuses to spend without a durable record.
	local session = self.sessionOnly and not self.loaded[userId]
	if not self.loaded[userId] and not self.sessionOnly then
		return false, "saving is unavailable; rejoin before spending"
	end
	self.busy[userId] = true
	local inv = copy(rec.inventory)
	local ran, ok, result = pcall(fn, inv)
	if not ran then ok, result = false, "the request failed; try again" end
	if self.closing[userId] or self.records[userId] ~= rec then ok, result = false, "session ended" end
	if ok then
		local snapshot = copy(rec)
		snapshot.inventory = inv
		if self.store and not session and not self:_write(userId, snapshot) then
			-- An error may be an acknowledged-by-storage write whose reply was lost. Do not reveal
			-- the roll, retry a different roll, or permit a later wardrobe flush to overwrite it.
			self.loaded[userId] = nil
			ok, result = false, "saving is unavailable; rejoin to check your locker"
		else
			local old = rec.inventory
			table.clear(old)
			for k, v in inv do old[k] = v end
			if equal(rec, snapshot) then self.dirty[userId] = nil end
		end
	end
	self.busy[userId] = nil
	if self.closing[userId] then self:release(userId) end
	return ok, result
end

-- Called on a timer; single-flight flush prevents heartbeat jobs reordering saves.
function AvatarStore.tick(self: any)
	local now = self.clock()
	for userId, since in self.dirty do
		if now - since >= AvatarStore.SAVE_DELAY then self:flush(userId) end
	end
	for userId in self.closing do self:release(userId) end
end

function AvatarStore.release(self: any, userId: number)
	self.closing[userId] = true
	if self.busy[userId] then return end
	if self.loaded[userId] and self.dirty[userId] then
		local saved = self:flush(userId)
		-- flush may yield: an edit arriving meanwhile still needs its own write.
		if self.loaded[userId] and (not saved or self.dirty[userId]) then return end
	end
	self.records[userId], self.loaded[userId], self.dirty[userId], self.notes[userId] = nil, nil, nil, nil
	self.closing[userId], self.revisions[userId] = nil, nil
end

function AvatarStore.flushAll(self: any)
	for userId in self.records do self:release(userId) end
end

return AvatarStore
