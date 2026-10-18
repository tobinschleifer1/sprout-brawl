--!strict
-- Developer Product purchases: the game's one MarketplaceService.ProcessReceipt. Roblox allows a
-- single callback per experience, so every product the game sells registers a handler here (`on`).
--
-- Two rules, both about real money:
--
-- 1. A receipt is delivered once. Roblox calls ProcessReceipt again for a purchase until told it
--    was granted - after a crash, a failed save, the player rejoining - and a handler's effect need
--    not be idempotent (a skip is "one checkpoint on from where you are"). So the purchase ids
--    handled are kept in the player's saved record (AvatarStore, `receipts`), and a repeat is
--    acknowledged without running the handler again.
-- 2. Nothing is granted that is not saved. Roblox is told PurchaseGranted only once the record -
--    the effect and the receipt id together - is written. A failed write answers NotProcessedYet;
--    Roblox asks again later, rule 1 keeps the effect single, and the write is retried. A server
--    with no DataStore at all (Studio without API access) grants for the session: there is nothing
--    to save to, and test purchases there cost nothing.
--
-- The store and the player lookup are injected, so tests/purchases.luau drives the real code.

local Purchases = {}
Purchases.__index = Purchases

Purchases.KEEP = 50        -- receipts remembered per player: far more than can be in flight at once

-- opts: { store = AvatarStore, player = (userId) -> Player?, receipts = DataStore? }
-- `receipts` remembers EVERY purchase id ever granted, one key each, so a receipt Roblox redelivers
-- after more than KEEP newer purchases is still recognised (the record keeps only the latest KEEP).
function Purchases.new(opts: any): any
	return setmetatable({ store = opts.store, player = opts.player, receipts = opts.receipts, handlers = {} }, Purchases)
end

-- `fn(player, receipt) -> boolean`: apply the purchase, true if it was. It may yield.
function Purchases.on(self: any, productId: number, fn: (any, any) -> boolean)
	self.handlers[productId] = fn
end

-- "granted" (tell Roblox PurchaseGranted) or "later" (NotProcessedYet: it will ask again).
function Purchases.process(self: any, receipt: any): string
	if type(receipt) ~= "table" then return "later" end
	local handler = self.handlers[receipt.ProductId]
	if not handler then
		warn(`[Blockfall] a purchase of product {receipt.ProductId} has no handler; not granted`)
		return "later"
	end
	local player = self.player(receipt.PlayerId)
	if not player then return "later" end          -- not in this server: Roblox retries when they are
	local userId = receipt.PlayerId
	local mark = "r:" .. tostring(receipt.PurchaseId)
	if self.receipts then
		local ok, seen = pcall(function() return self.receipts:GetAsync(mark) end)
		if not ok then return "later" end         -- cannot tell whether it was granted: ask again later
		if seen then return "granted" end
	end
	local rec = self.store:load(userId)
	local receipts = if type(rec.receipts) == "table" then rec.receipts else {}
	rec.receipts = receipts
	if not table.find(receipts, receipt.PurchaseId) then
		local ok, applied = pcall(handler, player, receipt)
		if not ok then
			warn(`[Blockfall] purchase {receipt.PurchaseId} failed to apply: {applied}`)
			return "later"
		end
		if not applied then return "later" end
		table.insert(receipts, receipt.PurchaseId)
		while #receipts > Purchases.KEEP do table.remove(receipts, 1) end
		self.store.dirty[userId] = self.store.dirty[userId] or self.store.clock()
	end
	if self.store.store and not self.store:flush(userId) then
		return "later"
	end
	if self.receipts then
		-- written after the grant is saved; if this write fails the record's own window still holds
		-- the id for the next KEEP purchases, and Roblox asks again
		pcall(function()
			self.receipts:UpdateAsync(mark, function(old: any)
				return old or { u = userId, p = receipt.ProductId, t = os.time() }
			end)
		end)
	end
	return "granted"
end

return Purchases
