--!strict
-- Developer Product purchases (server/Purchases) and the skip price list (shared/SkipProducts).
-- A receipt is applied once however often Roblox sends it, granted only once saved, and never
-- granted for a product nobody sells or a player who is not here.
local Loader = require("./loader")
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local Purchases = Loader.loadFrom("src/server/", "Purchases")
local SkipProducts = Loader.load("SkipProducts")
local PARKOUR = Loader.load("Data/Parkour")

-- 1. The price list: one skip per checkpoint after the start, dearer the deeper, 600 at most.
local P = SkipProducts.PRICES
assert(#P == #PARKOUR.course.checkpoints - 1, `{#P} prices for {#PARKOUR.course.checkpoints - 1} skips`)
assert(#SkipProducts.IDS == #P, "an id slot for every price")
for i = 2, #P do assert(P[i] > P[i - 1], `the skip into {i} ({P[i]}) must cost more than the one before ({P[i - 1]})`) end
assert(P[#P] == 600 and math.max(table.unpack(P)) == 600, "600 Robux at most, for the last")
for _, price in P do assert(price >= 1 and price % 1 == 0, "Robux prices are whole") end
-- Ids: 0 is "not created"; a created one is found both ways.
local saved = table.clone(SkipProducts.IDS)
SkipProducts.IDS = table.create(#P, 0)
local id, price = SkipProducts.forCheckpoint(3)
assert(id == nil and price == P[3], "an uncreated product has a price and no id")
assert(SkipProducts.checkpointFor(0) == nil, "0 is never a product")
SkipProducts.IDS[3] = 1234567
id, price = SkipProducts.forCheckpoint(3)
assert(id == 1234567 and price == P[3] and SkipProducts.checkpointFor(1234567) == 3, "a created product, both ways")
assert(SkipProducts.checkpointFor(999) == nil and SkipProducts.checkpointFor("1234567") == nil, "anything else is not a skip")
assert(SkipProducts.forCheckpoint(0) == nil and SkipProducts.forCheckpoint(#P + 1) == nil, "no skip into the start or past the Summit")
SkipProducts.IDS = saved

-- 2. Receipts.
local data: { [string]: any } = {}
local failing = false
local ds = { GetAsync = function(_, k) return data[k] end,
	UpdateAsync = function(_, k, fn) if failing then error("throttled") end local v = fn(data[k]); if v then data[k] = v end; return v end }
local store = AvatarStore.new(ds, function() return 0 end)
local here: { [number]: any } = { [1] = { UserId = 1 }, [2] = { UserId = 2 } }
local p = Purchases.new({ store = store, player = function(userId) return here[userId] end })
local runs = 0
local answer: any = true
p:on(77, function(player, receipt)
	runs += 1
	if answer == "error" then error("boom") end
	return answer
end)
local function receipt(purchase: string, userId: number?, product: number?): any
	return { PurchaseId = purchase, PlayerId = userId or 1, ProductId = product or 77 }
end

assert(p:process(receipt("a", 1, 55)) == "later", "a product nobody sells is not granted")
assert(p:process(receipt("a", 9)) == "later" and runs == 0, "a player not in this server: later, and nothing applied")
assert(p:process(receipt("a")) == "granted" and runs == 1, "a purchase is applied and granted")
assert(data.u1 and table.find(data.u1.receipts, "a"), "granted only once saved - the receipt is in the stored record")
assert(p:process(receipt("a")) == "granted" and runs == 1, "sent again, it is granted and NOT applied again")

answer = false
assert(p:process(receipt("b")) == "later" and not table.find(store:load(1).receipts, "b"), "a handler that could not apply it: later, not recorded")
answer = "error"
assert(p:process(receipt("c")) == "later", "a handler that errors: later")
answer = true

-- A save that fails: not granted, and when Roblox asks again the effect is not applied twice.
failing = true
runs = 0
assert(p:process(receipt("d")) == "later" and runs == 1, "applied, but not saved: later")
assert(p:process(receipt("d")) == "later" and runs == 1, "asked again while saving still fails: not applied again")
failing = false
assert(p:process(receipt("d")) == "granted" and runs == 1 and table.find(data.u1.receipts, "d"), "saved at last: granted, applied once")

-- Receipts survive a new server, and the list is bounded.
local fresh = Purchases.new({ store = AvatarStore.new(ds, function() return 0 end), player = function(userId) return here[userId] end })
runs = 0
fresh:on(77, function() runs += 1; return true end)
assert(fresh:process(receipt("a")) == "granted" and runs == 0, "a receipt handled before a restart is not applied again")
for i = 1, Purchases.KEEP + 10 do assert(p:process(receipt(`n{i}`, 2)) == "granted") end
assert(#store:load(2).receipts == Purchases.KEEP and store:load(2).receipts[Purchases.KEEP] == `n{Purchases.KEEP + 10}`, "the newest are kept")

-- A stored list that is too long, or holds anything but ids, is cut down when read.
do
	local long = {}
	for i = 1, 80 do long[i] = `r{i}` end
	table.insert(long, 3, 42)
	data.u5 = { v = 1, active = 1, slots = { { name = "x", code = "k1" } }, receipts = long }
	local got = AvatarStore.new(ds, function() return 0 end):load(5).receipts
	assert(#got == 50 and got[1] == "r31" and got[50] == "r80", "a long stored list keeps the newest 50 ids, strings only")
end
-- A store that cannot be read is never written over, so a purchase waits rather than be lost.
local unread = AvatarStore.new({ GetAsync = function() error("down") end, SetAsync = function() end }, function() return 0 end)
local blocked = Purchases.new({ store = unread, player = function(userId) return here[userId] end })
blocked:on(77, function() return true end)
assert(blocked:process(receipt("e")) == "later", "saving is off because the record could not be read: later")
-- No DataStore at all (Studio without API access): granted for the session.
local none = Purchases.new({ store = AvatarStore.new(nil, function() return 0 end), player = function(userId) return here[userId] end })
none:on(77, function() return true end)
assert(none:process(receipt("f")) == "granted", "no DataStore at all: granted for the session")
print(`PASS purchases: {#P} skip prices {table.concat(P, "/")} Robux; receipts applied once, granted only once saved, retried safely`)
