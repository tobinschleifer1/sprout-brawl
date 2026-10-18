--!nocheck
-- Real modules and copied DataStore values, with explicit adversarial coroutine schedules.
local Loader = require("./loader")
local Store = Loader.loadFrom("src/server/", "AvatarStore")
local Economy = Loader.loadFrom("src/server/", "Economy")
local Mint = Loader.loadFrom("src/server/", "Mint")
local Locker = Loader.loadFrom("src/server/", "Locker")
local Inventory, Loot = Loader.load("Inventory"), Loader.load("Loot")
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}; for k, x in v do out[k] = copy(x) end; return out
end
local function ds()
	local d = { data = {}, writes = 0 }
	function d:GetAsync(k)
		if self.failRead then error("read failed") end
		local v = copy(self.data[k]); if self.onRead then self.onRead() end; return v
	end
	function d:SetAsync(k, v)
		v = copy(v); if self.onWrite then self.onWrite() end
		if self.failWrite then error("write failed") end
		self.data[k] = v; self.writes += 1
	end
	function d:UpdateAsync(k, fn)
		if self.failWrite then error("write failed") end
		if self.onWrite then self.onWrite() end
		local v = fn(copy(self.data[k]))
		if v then self.data[k] = copy(v); self.writes += 1 end
		return copy(v)
	end
	return d
end
local function setup(d, policy)
	local st = Store.new(d, function() return 10 end, { sessionOnly = d == nil })
	return Economy.new({ store = st, mint = Mint.new(nil, nil, true), rand = function() return 0 end,
		time = function() return 1792300000 end, paidAllowed = policy }), st
end
local function resume(co) local ok, err = coroutine.resume(co); assert(ok, err) end
local function start(fn) local co = coroutine.create(fn); resume(co); return co end
local failed, passed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed += 1; print("PASS", name) else failed += 1; warn("FAIL " .. name .. ": " .. tostring(err)) end
end

test("concurrent opens and crafts cannot spend the same balance", function()
	for _, action in { "open", "craft" } do
		local e = setup(nil); local inv = e:inventory(1)
		inv.crates.forge, inv.keys.forge.earned, inv.sparks = 1, 1, 30
		local calls = 0
		e.mint.serial = function() calls += 1; if calls == 1 then coroutine.yield() end; return calls end
		local arg = if action == "open" then "forge" else "sword_rustwood"
		local first; local co = start(function() first = e[action](e, 1, arg) end)
		assert(not e[action](e, 1, arg), "a second request passed the same balance check")
		resume(co); assert(first and #e:view(1).items == 1)
		assert(inv.crates.forge == (if action == "open" then 0 else 1))
		assert(inv.keys.forge.earned == (if action == "open" then 0 else 1))
		assert(inv.sparks == (if action == "craft" then 0 else 30))
	end
end)
test("success is durable before rejoin; failed saves reveal no roll", function()
	local d = ds(); local e, st = setup(d); local inv = e:inventory(1)
	inv.crates.scrap = 2; st.dirty[1] = 1; assert(st:flush(1)); assert(e:open(1, "scrap"))
	local fresh = Store.new(d):load(1).inventory
	assert(fresh.crates.scrap == 1 and next(fresh.items), "success preceded the durable debit/reward")
	d.failWrite = true
	assert(not e:open(1, "scrap"), "failed save acknowledged a roll")
	assert(#e:view(1).items == 1 and not e:open(1, "scrap"), "an unsaved roll was exposed or rerolled")
end)
test("two servers cannot overwrite a committed spend", function()
	local d = ds(); d.data.u1 = Store.sanitize(nil); d.data.u1.inventory.crates.scrap = 1
	local a, b = setup(d), setup(d); a:inventory(1); b:inventory(1)
	assert(a:open(1, "scrap")); assert(not b:open(1, "scrap"), "stale server spent the same crate")
	local fresh = Store.new(d):load(1).inventory
	assert(fresh.crates.scrap == 0 and Inventory.copies(fresh, Loot.roll("scrap", 0, function() return 0 end)) == 1)
end)
test("edits during save stay dirty and concurrent flushes cannot reorder", function()
	local d = ds(); local st = Store.new(d); local rec = st:load(1)
	rec.inventory.sparks = 30; st.dirty[1] = 1
	d.onWrite = function() d.onWrite = nil; coroutine.yield() end
	local co = start(function() assert(st:flush(1)) end)
	rec.inventory.sparks = 60; st.dirty[1] = st.dirty[1] or 1
	assert(not st:flush(1), "concurrent flush started")
	resume(co); assert(st.dirty[1], "save cleared a concurrent edit")
	assert(st:flush(1) and d.data.u1.inventory.sparks == 60)
end)
test("release during reservation cannot publish an orphan reward", function()
	local d = ds(); local e, st = setup(d); e:inventory(1).crates.scrap = 1; st.dirty[1] = 1; st:flush(1)
	e.mint.serial = function() coroutine.yield(); return 1 end
	local ok; local co = start(function() ok = e:open(1, "scrap") end)
	st:release(1); resume(co); assert(not ok, "departed request granted after release")
	local inv = Store.new(d):load(1).inventory; assert(inv.crates.scrap == 1 and not next(inv.items))
end)
test("a concurrent load/release cannot install a late record", function()
	local d = ds(); local st = Store.new(d)
	d.onRead = function() d.onRead = nil; coroutine.yield() end
	local co = start(function() st:load(1) end); st:load(1); st:release(1); resume(co)
	assert(not st.records[1] and not st.loaded[1], "late load resurrected a departed record")
end)
test("failed reads never allow economy grants or writes", function()
	local d = ds(); d.data.u1 = Store.sanitize(nil); d.data.u1.inventory.sparks = 500; d.failRead = true
	local e, st = setup(d); e:inventory(1).sparks = 30
	assert(not e:craft(1, "sword_rustwood"), "failed-load record minted")
	st:release(1); assert(d.writes == 0 and d.data.u1.inventory.sparks == 500)
end)
test("Studio with its record unreadable spends for the session and never writes", function()
	local d = ds(); d.data.u1 = Store.sanitize(nil); d.data.u1.inventory.sparks = 500; d.failRead = true
	local st = Store.new(d, function() return 10 end, { sessionOnly = true })
	local e = Economy.new({ store = st, mint = Mint.new(nil, nil, true), rand = function() return 0 end, time = function() return 1792300000 end })
	e:inventory(1).sparks = 30
	assert(e:craft(1, "sword_rustwood"), "Studio without API access cannot test crafting")
	st:release(1); assert(d.writes == 0 and d.data.u1.inventory.sparks == 500, "a session-only Studio record was written")
end)
test("serials, dates and uid sequence survive beyond the balance cap", function()
	local inv = Inventory.sanitize(nil); inv.seq = 1000007
	local uid = Inventory.add(inv, "sword_rustwood", 1000009, true, "crate", 1792300000)
	local clean = Inventory.sanitize(inv)
	assert(clean.items[uid].s == 1000009 and clean.items[uid].t == 1792300000, "serial/date clamped")
	assert(clean.seq == inv.seq and clean.items[uid].p)
	Inventory.remove(clean, uid); assert(Inventory.sanitize(clean).seq == clean.seq, "uid sequence went backwards")
end)
test("paid provenance cannot be laundered by salvage or sanitizing", function()
	local e = setup(nil); local inv = e:inventory(1)
	local uid = Inventory.add(inv, "sword_starforged", 3, true, "crate", 1792300000)
	assert(not e:salvage(1, uid) and inv.items[uid].p and inv.sparks == 0, "paid copy became untagged Sparks")
	local clean = Inventory.sanitize({ items = { u0 = { i = "sword_rustwood", p = "true" } } })
	assert(clean.items.u0.p, "malformed provenance became earned")
end)
test("paid-key policy fails closed and binds the disclosed pity", function()
	for _, policy in { false, function() return false end, function() error("policy unavailable") end } do
		local e = setup(nil, policy); local inv = e:inventory(1); inv.crates.forge, inv.keys.forge.paid = 1, 1
		assert(not e:open(1, "forge", 0), "restricted/missing/failed policy allowed a paid key")
		assert(inv.crates.forge == 1 and inv.keys.forge.paid == 1)
		inv.keys.forge.earned = 1; assert(e:open(1, "forge", 0))
	end
	local e = setup(nil, function() return true end); local inv = e:inventory(1)
	inv.crates.forge, inv.keys.forge.paid, inv.pity.forge = 1, 1, 39
	assert(not e:open(1, "forge", 0), "paid roll used odds different from the disclosure")
	local ok, res = e:open(1, "forge", 39); assert(ok and res.paid and inv.items[res.uid].p)
end)
test("full locker does not mint phantom copies", function()
	local e = setup(nil); local inv = e:inventory(1)
	for n = 1, Inventory.MAX_OWNED do Inventory.add(inv, "sword_rustwood", n, false, "drop", 1) end
	inv.sparks = 30; local before = e.mint:copies("sword_rustwood")
	assert(not e:craft(1, "sword_rustwood") and e.mint:copies("sword_rustwood") == before, "full locker minted a phantom copy")
end)
test("mint flush keeps concurrent deltas without double flushing", function()
	local d = ds(); local m = Mint.new(d); m:serial("sword_rustwood")
	d.onWrite = function() d.onWrite = nil; coroutine.yield() end
	local co = start(function() m:flush() end)
	m:serial("sword_rustwood"); m:destroy("sword_rustwood"); m:flush(); resume(co); m:flush()
	assert(d.data["item:sword_rustwood"].minted == 2 and d.data["item:sword_rustwood"].destroyed == 1, "mint deltas lost/doubled")
end)
test("unsafe counters and missing live stores never yield serials", function()
	local d = ds(); d.data["item:sword_rustwood"] = { reserved = 0/0 }
	assert(Mint.new(d):serial("sword_rustwood") == nil, "NaN serial handed out")
	d.data["item:sword_rustwood"] = { reserved = 9007199254740990 }
	assert(Mint.new(d):serial("sword_rustwood") == nil, "serial exceeded exact integers")
	assert(Mint.new(nil):serial("sword_rustwood") == nil, "live server minted local serials")
end)
test("hostile client payloads cannot spend or equip", function()
	local e, st = setup(nil); local inv = e:inventory(1); inv.sparks, inv.crates.scrap = 100, 1
	local l = Locker.new({ store = st })
	for _, value in { false, 0/0, math.huge, {}, string.rep("x", 100000) } do
		for _, msg in { { action = value }, { action = "open", crate = value }, { action = "craft", id = value }, { action = "salvage", uid = value } } do
			local ok, accepted = pcall(function() return e:apply(1, msg) end); assert(ok and not accepted)
		end
		local ok, accepted = pcall(function() return l:apply(1, { action = "equip", id = value }) end); assert(ok and not accepted)
	end
	assert(inv.sparks == 100 and inv.crates.scrap == 1 and not next(inv.items))
end)
test("qualifying time belongs to the player, excluding countdown/elimination", function()
	local r = { mode = "StockFFA", frames = 10000 }
	assert(not Economy.qualifies(r, { damage = 1, fightFrames = 44 * 60 }), "global match length qualified a short-lived fighter")
	assert(Economy.qualifies(r, { taken = 1, fightFrames = 45 * 60 }))
	assert(not Economy.qualifies({ mode = "Training", frames = 10000 }, { damage = 100, fightFrames = 10000 }))
	assert(not Economy.qualifies(r, { damage = 1, fightFrames = 0/0 }))
end)
test("rolling hourly cap and drop meter survive boundary hopping and rejoin", function()
	local d = ds(); local e = setup(d); local t = 3590
	e.time = function() return t end
	local result, row = { mode = "StockFFA", frames = 4000 }, { damage = 1, fightFrames = 4000 }
	for _ = 1, 12 do assert(e:matchFinished(1, result, row).counted) end
	local left = e:inventory(1).meter
	local again = setup(d); again.time = function() return t end
	assert(again:inventory(1).meter == left, "rejoin reset the meter")
	t = 3601
	assert(not again:matchFinished(1, result, row).counted, "hour-boundary/rejoin bypassed twelve per rolling hour")
	assert(again:inventory(1).meter == left)
	t = 7190; assert(again:matchFinished(1, result, row).counted)
end)
test("release retains edits arriving during its final save", function()
	local d = ds(); local st = Store.new(d); local rec = st:load(1)
	rec.inventory.sparks = 10; st.dirty[1] = 1
	d.onWrite = function() d.onWrite = nil; coroutine.yield() end
	local co = start(function() st:release(1) end)
	rec.inventory.sparks = 20; st.dirty[1] = 1
	resume(co)
	assert(st.records[1] and st.dirty[1], "release discarded an edit that was not in its save")
	st:tick(); assert(not st.records[1] and d.data.u1.inventory.sparks == 20)
end)
test("locker cannot edit a candidate during an economy transaction", function()
	local e, st = setup(nil); local inv = e:inventory(1); inv.sparks = 30
	Inventory.add(inv, "sword_rustwood", 1, false, "drop", 1)
	e.mint.serial = function() coroutine.yield(); return 2 end
	local co = start(function() assert(e:craft(1, "sword_rustwood")) end)
	local l = Locker.new({ store = st })
	assert(not l:apply(1, { action = "equip", id = "sword_rustwood" }))
	resume(co); assert(l:apply(1, { action = "equip", id = "sword_rustwood" }))
end)
test("a save in flight exposes no candidate item and admits no competing spend", function()
	local d = ds(); local e, st = setup(d); local inv = e:inventory(1)
	inv.crates.scrap, inv.sparks = 1, 30; st.dirty[1] = 1; assert(st:flush(1))
	d.onWrite = function() d.onWrite = nil; coroutine.yield() end
	local co = start(function() assert(e:open(1, "scrap")) end)
	assert(coroutine.status(co) == "suspended", "opening did not wait for storage")
	assert(#e:view(1).items == 0 and inv.crates.scrap == 1, "candidate leaked before commit")
	assert(not e:craft(1, "sword_rustwood") and not st:flush(1))
	resume(co); assert(#e:view(1).items == 1 and inv.crates.scrap == 0 and inv.sparks == 30)
end)
test("a committed write with a lost reply cannot be rerolled or overwritten", function()
	local d = ds(); local e, st = setup(d); e:inventory(1).crates.scrap = 1
	st.dirty[1] = 1; assert(st:flush(1))
	local update = d.UpdateAsync
	d.UpdateAsync = function(self, key, fn) update(self, key, fn); error("reply lost after commit") end
	assert(not e:open(1, "scrap") and #e:view(1).items == 0)
	assert(not e:open(1, "scrap") and not st:flush(1))
	st:release(1); d.UpdateAsync = update
	local again = setup(d); local inv = again:inventory(1)
	assert(inv.crates.scrap == 0 and #again:view(1).items == 1 and not again:open(1, "scrap"))
end)
print(`Economy security: {passed} passed, {failed} failed`)
assert(failed == 0, "economy security regressions")
