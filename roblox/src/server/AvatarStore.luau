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

local AvatarStore = {}
AvatarStore.__index = AvatarStore

AvatarStore.MAX_SLOTS = 8
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
		for i = 1, AvatarStore.MAX_SLOTS do
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
		for _, k in { "best", "summits", "bestFrames" } do
			if type(src.climb[k]) == "number" then climb[k] = src.climb[k] end
		end
	end
	return { v = AvatarStore.VERSION, slots = slots, active = active, climb = climb }
end

function AvatarStore.new(dataStore: any, clock: (() -> number)?): any
	return setmetatable({
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
	self.records[userId] = AvatarStore.sanitize(raw)
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
function AvatarStore.view(self: any, userId: number): any
	local rec = self:load(userId)
	local slots = {}
	for i, s in rec.slots do
		slots[i] = { name = s.name, code = s.code }
	end
	return { slots = slots, active = rec.active, max = AvatarStore.MAX_SLOTS,
		saving = self.loaded[userId] == true, note = self.notes[userId] }
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
		if i > #rec.slots + 1 or i > AvatarStore.MAX_SLOTS then
			return false, `You can keep {AvatarStore.MAX_SLOTS} characters. Delete one first.`
		end
		local code = AvatarKit.canonical(msg.code)
		if not code then
			return false, "That is not a character."
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
function AvatarStore.flush(self: any, userId: number): boolean
	if not self.dirty[userId] then
		return true
	end
	if not (self.store and self.loaded[userId]) then
		return false
	end
	local rec = self.records[userId]
	local ok, err = pcall(function()
		self.store:SetAsync(key(userId), rec)
	end)
	if ok then
		self.dirty[userId] = nil
	else
		warn(`[Blockfall] characters for {userId} were not saved ({err}); will retry`)
	end
	return ok
end

-- Called on a timer: writes every record that has been dirty for SAVE_DELAY seconds.
function AvatarStore.tick(self: any)
	local now = self.clock()
	for userId, since in self.dirty do
		if now - since >= AvatarStore.SAVE_DELAY then
			self:flush(userId)
		end
	end
end

-- A player leaving: write what they changed, then forget them.
function AvatarStore.release(self: any, userId: number)
	self:flush(userId)
	self.records[userId], self.loaded[userId], self.dirty[userId], self.notes[userId] = nil, nil, nil, nil
end

function AvatarStore.flushAll(self: any)
	for userId in self.dirty do
		self:flush(userId)
	end
end

return AvatarStore
