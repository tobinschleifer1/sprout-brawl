--!nocheck
-- Development tool: what each worn hit and KO effect costs to draw on the Frame fallback - the
-- rectangles built the first time it is seen (every flipbook frame of every drawing it uses, in its
-- ramps), its peak live rectangles in one frame, and the same for the plain effect it replaces.
--   lune run tools/cosmetic-fx-cost
local Loader = require("../tests/loader")
local Cosmetics = Loader.load("Cosmetics")
local Inventory = Loader.load("Inventory")
local Loadout = Loader.load("Loadout")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local built, live = {}, 0
Canvas.sprite = function(_c, key, rects) live += #rects; built[key] = #rects end
Canvas.rect = function() live += 1 end
Canvas.save, Canvas.restore, Canvas.translate, Canvas.rotate, Canvas.scale = function() end, function() end, function() end, function() end, function() end
local function wearing(loadout)
	local c = table.clone(Loadout.build("Classic", "Sword"))
	c.cosmetics = Inventory.cleanLoadout(loadout)
	return c
end
local states = { { index = 0, x = 0, y = 0, state = "attack", moveId = "LightNeutral1", moveFrame = 6 }, { index = 1, x = 4, y = 0, state = "idle" } }
local function cost(event, chars)
	table.clear(built)
	local P = FxPlayer.new()
	if event.type == "hit" then FxPlayer.hit(P, event, states, chars) else FxPlayer.spawn(P, event, states, chars) end
	local peak = 0
	for _ = 1, 60 do
		live = 0
		FxPlayer.draw(P, {})
		peak = math.max(peak, live)
		FxPlayer.step(P, 1 / 60)
	end
	local total = 0
	for _, n in built do total += n end
	return total, peak
end
local bare = table.clone(Loadout.build("Classic", "Sword"))
local hit = { type = "hit", attacker = 0, victim = 1, x = 1, y = 2, damage = 8, angle = 45, facing = 1, heavy = true }
local ko = { type = "ko", fighter = 1, by = 0, x = 10, y = 4 }
local b, p = cost(hit, { bare, bare })
print(string.format("%-20s built %5d  peak %4d", "plain heavy hit", b, p))
for _, it in Cosmetics.LIST do
	if it.type == "hit_effect" then
		local w = wearing({ hit = it.id })
		local t, k = cost(hit, { w, w })
		print(string.format("%-20s built %5d  peak %4d", it.id, t, k))
	end
end
for _, it in Cosmetics.LIST do
	if it.type == "ko_effect" then
		local t, k = cost(ko, { wearing({ ko = it.id }), bare })
		print(string.format("%-20s built %5d  peak %4d", it.id, t, k))
	end
end
