--!strict
-- Serial numbers and copies in existence for every cosmetic (Roblox only; docs/briefs/crates-and-
-- monetisation-plan.md, "How rare is mine?").
--
-- A serial is unique per item across every server, ever. A DataStore key takes a write only about
-- once every six seconds, so a server does not write per copy: it RESERVES a block of serials for
-- an item in one UpdateAsync (10 to start, doubling to 80 for an item it hands out within a minute
-- of the last block) and hands them out locally. Serials a server reserved but never used are
-- skipped: unique, not contiguous. Copies made and destroyed are counted locally and added to the
-- item's record with the next reservation or `flush`, so "copies in existence" lags by a flush.
--
-- With no DataStore (Studio without API access) everything is counted in memory for the session.
-- A failed reservation returns nil: the caller must not consume what was being opened.
local Mint = {}
Mint.__index = Mint

Mint.FIRST_BLOCK, Mint.MAX_BLOCK, Mint.FAST = 10, 80, 60

-- store: a DataStore (or nil); now: () -> number (os.clock on a server)
function Mint.new(store: any, now: (() -> number)?): any
	return setmetatable({
		store = store, now = now or os.clock,
		blocks = {},        -- item -> { next, last, size, at }
		pending = {},       -- item -> { minted, destroyed } not yet written
		known = {},         -- item -> { minted, destroyed } as last read or written
	}, Mint)
end

local function key(id: string): string
	return "item:" .. id
end

-- Write this server's counts for `id` (and reserve `reserve` more serials) in one UpdateAsync.
-- Returns the first reserved serial (when reserving), or nil on failure.
function Mint._write(self: any, id: string, reserve: number): number?
	local p = self.pending[id] or { minted = 0, destroyed = 0 }
	if not self.store then
		local k = self.known[id] or { reserved = 0, minted = 0, destroyed = 0 }
		local first = k.reserved + 1
		k.reserved += reserve
		k.minted += p.minted
		k.destroyed += p.destroyed
		self.known[id] = k
		self.pending[id] = { minted = 0, destroyed = 0 }
		return first
	end
	local first: number? = nil
	local ok = pcall(function()
		self.store:UpdateAsync(key(id), function(old: any)
			local rec = if type(old) == "table" then old else {}
			local reserved = if type(rec.reserved) == "number" then rec.reserved else 0
			first = reserved + 1
			return {
				reserved = reserved + reserve,
				minted = (if type(rec.minted) == "number" then rec.minted else 0) + p.minted,
				destroyed = (if type(rec.destroyed) == "number" then rec.destroyed else 0) + p.destroyed,
			}
		end)
	end)
	if not ok or not first then return nil end
	local k = self.known[id] or { reserved = 0, minted = 0, destroyed = 0 }
	k.reserved = (first :: number) - 1 + reserve
	k.minted += p.minted
	k.destroyed += p.destroyed
	self.known[id] = k
	self.pending[id] = { minted = 0, destroyed = 0 }
	return first
end

-- The next serial for `id`, or nil if one could not be reserved.
function Mint.serial(self: any, id: string): number?
	local b = self.blocks[id]
	if not b or b.next > b.last then
		local size = Mint.FIRST_BLOCK
		if b and self.now() - b.at < Mint.FAST then size = math.min(Mint.MAX_BLOCK, b.size * 2) end
		local first = self:_write(id, size)
		if not first then return nil end
		b = { next = first, last = first + size - 1, size = size, at = self.now() }
		self.blocks[id] = b
	end
	local s = (b :: any).next
	;(b :: any).next += 1
	local p = self.pending[id] or { minted = 0, destroyed = 0 }
	p.minted += 1
	self.pending[id] = p
	return s
end

-- A copy left the game (salvaged).
function Mint.destroy(self: any, id: string)
	local p = self.pending[id] or { minted = 0, destroyed = 0 }
	p.destroyed += 1
	self.pending[id] = p
end

-- Write every item's waiting counts (on a timer and at shutdown).
function Mint.flush(self: any)
	for id, p in self.pending do
		if p.minted > 0 or p.destroyed > 0 then self:_write(id, 0) end
	end
end

-- About how many copies of `id` exist: what was last written, plus this server's unwritten counts.
-- Asking marks the item as wanted, so `refreshWanted` keeps its count current.
function Mint.copies(self: any, id: string): number
	self.wanted = self.wanted or {}
	self.wanted[id] = true
	local k = self.known[id] or { minted = 0, destroyed = 0 }
	local p = self.pending[id] or { minted = 0, destroyed = 0 }
	return math.max(0, k.minted + p.minted - k.destroyed - p.destroyed)
end

-- Read the stored counts for `ids` (for display), keeping this server's own pending ones on top.
function Mint.refresh(self: any, ids: { string })
	if not self.store then return end
	for _, id in ids do
		local ok, rec = pcall(function() return self.store:GetAsync(key(id)) end)
		if ok and type(rec) == "table" then
			local k = self.known[id] or { reserved = 0, minted = 0, destroyed = 0 }
			k.minted = if type(rec.minted) == "number" then rec.minted else k.minted
			k.destroyed = if type(rec.destroyed) == "number" then rec.destroyed else k.destroyed
			self.known[id] = k
		end
	end
end

-- Re-read up to `limit` of the items players have asked about since the last call (a server loop
-- calls this every few minutes, so counts drift toward every server's, not just this one's).
function Mint.refreshWanted(self: any, limit: number)
	local ids = {}
	for id in self.wanted or {} do
		if #ids >= limit then break end
		table.insert(ids, id)
	end
	for _, id in ids do (self.wanted :: any)[id] = nil end
	self:refresh(ids)
end

return Mint
