--!nocheck
-- Cosmetics worn in matches (phase 2 of docs/briefs/crates-and-monetisation-plan.md; Roblox only).
-- Direct properties: a weapon skin is its weapon's footprint exactly (same rectangles, new colours),
-- so it can never change what a player reads off the shape; a fighter wearing a skin is drawn in it,
-- with its trail and glow in the skin's palette; a worn swing trail, hit effect and KO effect draw as
-- the item says, and nothing changes for a fighter who wears none; the inventory and the loadout
-- refuse what is unknown, unowned or in the wrong place; the Locker owns everything only in Studio.
local Loader = require("./loader")
local Cosmetics = Loader.load("Cosmetics")
local Inventory = Loader.load("Inventory")
local CosmeticArt = Loader.load("CosmeticArt")
local ART = Loader.load("Weapons").ART
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Locker = Loader.loadFrom("src/server/", "Locker")
local Recorder = require("../tools/recorder")
Recorder.install(Canvas)
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")

-- 1. Every skin has art, and its art is its weapon's footprint: the same cells painted at the same
-- opacity (the compiler merges same-coloured cells, so the rectangles themselves may split
-- differently); only colours differ, and some must. Rectangles are Frames on the lowest devices, so a
-- skin may not cost more than a few more than its weapon.
local function cells(rects)
	local out, n = {}, 0
	for _, r in rects do
		for cx = math.floor(r[1] * 8 + 0.5), math.floor((r[1] + r[3]) * 8 + 0.5) - 1 do
			for cy = math.floor(r[2] * 8 + 0.5), math.floor((r[2] + r[4]) * 8 + 0.5) - 1 do
				local k = cx .. "," .. cy
				local a = r[6] or 1
				-- layered art (an aura under an outline under the body) is covered by its most opaque layer
				if not out[k] then n += 1 end
				out[k] = math.max(out[k] or 0, a)
			end
		end
	end
	return out, n
end
local function colourAt(rects)
	local out = {}
	for _, r in rects do
		for cx = math.floor(r[1] * 8 + 0.5), math.floor((r[1] + r[3]) * 8 + 0.5) - 1 do
			for cy = math.floor(r[2] * 8 + 0.5), math.floor((r[2] + r[4]) * 8 + 0.5) - 1 do out[cx .. "," .. cy] = r[5] end
		end
	end
	return out
end
local skins = 0
for _, it in Cosmetics.LIST do
	if it.type == "weapon_skin" then
		local art = CosmeticArt[it.id]
		assert(art and art.weapon == it.weapon, `{it.id} has no art for {it.weapon}`)
		local forms = { { art.sprites, ART.sprites[it.weapon], "art" }, { art.awakened, ART.awakened[it.weapon], "awakened art" } }
		if ART.single[it.weapon] then
			table.insert(forms, { art.single, ART.single[it.weapon], "one of the pair" })
			table.insert(forms, { art.singleAwakened, ART.singleAwakened[it.weapon], "awakened one of the pair" })
		end
		for _, f in forms do
			local mine, base, what = f[1], f[2], f[3]
			assert(mine and #mine <= #base + 6, `{it.id}: its {what} is {mine and #mine} rectangles, the weapon's {#base}`)
			local a, na = cells(mine)
			local b, nb = cells(base)
			assert(na == nb, `{it.id}: its {what} paints {na} cells, the weapon {nb}`)
			for k, alpha in b do assert(a[k] == alpha, `{it.id}: its {what} differs from the weapon's shape at cell {k}`) end
			local ca, cb = colourAt(mine), colourAt(base)
			local recoloured = false
			for k, c in cb do if ca[k] ~= c then recoloured = true end end
			assert(recoloured, `{it.id}: its {what} is the weapon's own colours`)
		end
		skins += 1
	end
end
for id in CosmeticArt do assert(Cosmetics.get(id), `art for {id}, which is in no catalogue`) end

-- 2. What a drawn id names: the skin's art, its one-of-a-pair where the pair has one, the weapon's
-- own where the skin is unknown or for another weapon.
do
	local function colours(sp) local out = {}; for _, r in sp.rects do out[r[5]] = true end; return out end
	local plain, worn = Weapons2D.sprite("Sword"), Weapons2D.sprite("Sword@sword_frostbite")
	assert(worn.cols == plain.cols and worn.rows == plain.rows and colours(worn)["#CFEFFF"] and not colours(plain)["#CFEFFF"],
		"a skinned sword is not the sword in the skin's colours")
	local unit = Weapons2D.sprite("Daggers:one@daggers_neontwins")
	assert(unit.cols == Weapons2D.sprite("Daggers:one").cols and unit.cols < Weapons2D.sprite("Daggers@daggers_neontwins").cols,
		"a skinned dagger in one hand is not one dagger")
	assert(colours(unit)["#FF3CD8"] and not colours(Weapons2D.sprite("Daggers:one"))["#FF3CD8"], "a dagger in one hand is not one skinned dagger")
	assert(Weapons2D.sprite("Blasters:one@blasters_toy").cols == Weapons2D.sprite("Blasters").cols, "a skinned blaster lost its art")
	local strange = Weapons2D.sprite("Sword@daggers_neontwins")
	assert(strange.cols == plain.cols, "a skin for another weapon reshaped the sword")
	assert(not colours(strange)["#FF3CD8"], "a sword drew another weapon's skin")
	assert(Weapons2D.skinPalette("sword_frostbite").glow == "#7FE6FF" and Weapons2D.skinPalette(nil) == nil, "a skin's palette is not its own")
end

-- 3. A fighter wearing a skin is drawn in it, its trail in the skin's glow and the worn trail's
-- colours; a fighter wearing nothing is drawn exactly as before.
local function attack(char, id, mf)
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.facing, f.invincible = "attack", true, 1, 0
	f.move = Fighter.moveOf(char, id); f.moveId = id; f.mf = mf; f.sf = mf; f.frameCount = 100 + mf
	return Snapshot.decode(Snapshot.encode(f))
end
local function draws(char, s)
	local seen, trails = {}, {}
	local realDraw, realTrail = Weapons2D.draw, Weapons2D.drawTrail
	Weapons2D.draw = function(cv, wid, pal, p, ...) table.insert(seen, { id = wid, glow = pal and pal.glow }); return realDraw(cv, wid, pal, p, ...) end
	Weapons2D.drawTrail = function(cv, wid, pal, trail, scale, worn) table.insert(trails, { glow = pal.glow, worn = worn }); return realTrail(cv, wid, pal, trail, scale, worn) end
	local cv = Recorder.canvas(Canvas, 300, 260)
	Canvas.world(cv, 0, 3, 26, 0, 0)
	Fighter2D.draw(cv, s, char, s.frameCount / 60)
	Weapons2D.draw, Weapons2D.drawTrail = realDraw, realTrail
	return seen, trails
end
local function wearing(weapon, loadout)
	local c = table.clone(Loadout.build("Classic", weapon))
	c.cosmetics = Inventory.cleanLoadout(loadout)
	return c
end
do
	local bare = table.clone(Loadout.build("Classic", "Sword"))
	local seen0, trails0 = draws(bare, attack(bare, "LightSide2", 8))
	assert(#seen0 == 1 and seen0[1].id == "Sword" and seen0[1].glow == bare.weaponPalette.glow, "a fighter wearing nothing is drawn differently")
	assert(#trails0 == 1 and trails0[1].worn == nil, "a fighter wearing nothing has a worn trail")
	local c = wearing("Sword", { skins = { Sword = "sword_frostbite" }, trail = "trail_rainbow" })
	local seen, trails = draws(c, attack(c, "LightSide2", 8))
	assert(#seen == 1 and seen[1].id == "Sword@sword_frostbite", `a skinned sword drew {seen[1] and seen[1].id}`)
	assert(seen[1].glow == "#7FE6FF" and trails[1].glow == "#7FE6FF", "the skin does not colour the weapon's glow and trail")
	assert(trails[1].worn == "trail_rainbow", "the worn trail is not drawn")
	local d = wearing("Daggers", { skins = { Daggers = "daggers_venomfang" } })
	local dseen = draws(d, attack(d, "LightNeutral1", 6))
	assert(#dseen == 2 and dseen[1].id == "Daggers:one@daggers_venomfang" and dseen[2].id == "Daggers:one@daggers_venomfang", "skinned daggers are not one skinned dagger in each hand")
	-- the boots, worn on the feet, wear their skin too
	local b = wearing("RocketBoots", { skins = { RocketBoots = "boots_retro" } })
	local keys = {}
	local real = Canvas.sprite
	Canvas.sprite = function(cv, key, ...) keys[key] = true; return real(cv, key, ...) end
	draws(b, attack(b, "LightNeutral1", 3))
	Canvas.sprite = real
	assert(keys["weapon|RocketBoots@boots_retro"], "skinned boots are drawn in the plain boots")
end

-- 4. The worn trail's colours, segment by segment.
do
	local cols = {}
	local real = Canvas.rect
	Canvas.rect = function(cv, x, y, w, h, colour, a) table.insert(cols, colour); return real(cv, x, y, w, h, colour, a) end
	local cv = Recorder.canvas(Canvas, 300, 260)
	Weapons2D.drawTrail(cv, "Sword", { glow = "#123456" }, { from = 0, to = 1, alpha = 1 }, 1, "trail_ember")
	Canvas.rect = real
	local want = Weapons2D.TRAILS.trail_ember
	local ember = 0
	for i, c in cols do
		if (i - 1) / 13 <= 0.82 then
			assert(c == Canvas.hex(want[(i - 1) % #want + 1], Canvas.hex("#123456")), `trail segment {i} is not the worn trail's colour`)
			ember += 1
		end
	end
	assert(ember >= 10, "too few trail segments checked")
	for _, it in Cosmetics.LIST do
		if it.type == "swing_trail" then assert(Weapons2D.TRAILS[it.id], `{it.id} has no trail colours`) end
	end
end

-- 5. Worn hit and KO effects: every one in the catalogue draws, as its item says; none worn and the
-- weapon's own (and the plain KO burst) are kept.
do
	local states = { { index = 0, x = 0, y = 0, state = "attack", moveId = "LightNeutral1", moveFrame = 6 },
		{ index = 1, x = 4, y = 0, state = "idle" } }
	local function hit(char)
		local P = FxPlayer.new()
		FxPlayer.hit(P, { attacker = 0, victim = 1, x = 1, y = 2, damage = 6, angle = 45, facing = 1 }, states, { char, char })
		return P.items
	end
	local bare = table.clone(Loadout.build("Classic", "Sword"))
	local plainItems = hit(bare)
	for _, it in Cosmetics.LIST do
		if it.type == "hit_effect" then
			local items = hit(wearing("Sword", { hit = it.id }))
			assert(#items > 0, `{it.id} draws nothing`)
			if FxPlayer.HIT_STYLES[it.id] then
				-- its own drawing, not the weapon's
				local differs = #items ~= #plainItems
				for i, x in items do if not plainItems[i] or x.kind ~= plainItems[i].kind or x.ramp ~= plainItems[i].ramp then differs = true end end
				assert(differs, `{it.id} draws the weapon's own hit`)
			else
				assert(it.ramp, `{it.id} has neither a ramp nor a drawing`)
				for i, x in items do
					assert(x.kind == plainItems[i].kind, `{it.id} changed the hit's drawing`)
					if plainItems[i].ramp == bare.weaponPalette.glow then assert(x.ramp == it.ramp, `{it.id} did not recolour the hit`) end
				end
			end
		elseif it.type == "ko_effect" then
			local P = FxPlayer.new()
			local drew = FxPlayer.spawn(P, { type = "ko", fighter = 1, by = 0, x = 10, y = 4 }, states, { wearing("Sword", { ko = it.id }), bare })
			assert(drew and #P.items > 0, `{it.id} draws no KO`)
			for _, x in P.items do assert(math.abs(x.x - 10) < 8 and math.abs(x.y - 4) < 8, `{it.id} draws away from the blast line`) end
		end
	end
	local P = FxPlayer.new()
	assert(not FxPlayer.spawn(P, { type = "ko", fighter = 1, by = 0, x = 10, y = 4 }, states, { bare, bare }) and #P.items == 0, "a KO by someone wearing none is not the plain burst")
	assert(not FxPlayer.spawn(P, { type = "ko", fighter = 1, by = -1, x = 10, y = 4 }, states, { bare, bare }), "a KO nobody took drew a worn effect")
end

-- 6. The inventory and the loadout: only known items, in their slots, on their weapons; only owned
-- ones worn; equipping checks ownership.
do
	local hostile = {
		owned = { sword_frostbite = true, hit_sakura = true, nope = true, [5] = true, ko_blackhole = "yes" },
		equipped = { skins = { Sword = "sword_frostbite", Hammer = "sword_frostbite", Axe = "axe_glacier" },
			hit = "hit_sakura", ko = "ko_blackhole", trail = "hit_sakura", title = 12 },
	}
	local inv = Inventory.sanitize(hostile)
	assert(inv.owned.sword_frostbite and inv.owned.hit_sakura and not inv.owned.nope and not inv.owned.ko_blackhole, "an unknown or badly stored item is owned")
	assert(inv.equipped.skins.Sword == "sword_frostbite" and inv.equipped.skins.Hammer == nil, "a skin is worn on another weapon")
	assert(inv.equipped.skins.Axe == nil and inv.equipped.ko == nil, "an unowned item is worn")
	assert(inv.equipped.hit == "hit_sakura" and inv.equipped.trail == nil and inv.equipped.title == nil, "an item is worn in the wrong slot")
	local owns = function(id) return inv.owned[id] == true end
	assert(not Inventory.equip(inv, "axe_glacier", owns), "an unowned item was equipped")
	assert(not Inventory.equip(inv, "nope", owns), "an unknown item was equipped")
	inv.owned.trail_ember = true
	assert(Inventory.equip(inv, "trail_ember", owns) and inv.equipped.trail == "trail_ember", "an owned trail did not equip")
	assert(Inventory.equip(inv, nil, owns, "trail") and inv.equipped.trail == nil, "a trail did not come off")
	assert(Inventory.equip(inv, nil, owns, nil, "Sword") and inv.equipped.skins.Sword == nil, "a skin did not come off")
	local l = Inventory.cleanLoadout({ skins = { Sword = "hammer_thunderhead" }, hit = "ko_firework", ko = "ko_firework" })
	assert(l.skins.Sword == nil and l.hit == nil and l.ko == "ko_firework", "a loadout carries a misplaced item")
end

-- 7. The Locker: a live server owns only what the record says; Studio owns everything for the
-- session and dresses a player who wears nothing in the showcase; wearing saves.
do
	local function store()
		local records = {}
		return { records = records, dirty = {}, clock = function() return 1 end,
			load = function(self, id) records[id] = records[id] or { inventory = Inventory.sanitize(nil) }; return records[id] end }
	end
	local live = Locker.new({ store = store(), studio = false })
	assert(not live:owns(1, "sword_frostbite"), "a live server owns everything")
	assert(not live:apply(1, { action = "equip", id = "sword_frostbite" }), "a live server wore an unowned skin")
	live:inventory(1).owned.sword_frostbite = true
	assert(live:apply(1, { action = "equip", id = "sword_frostbite" }) and live.store.dirty[1], "wearing an owned skin did not save")
	assert(live:loadout(1).skins.Sword == "sword_frostbite" and next(live:loadout(2).skins) == nil, "a loadout is not what the player wears")
	local studio = Locker.new({ store = store(), studio = true })
	assert(studio:owns(1, "ko_dragonsbreath") and not studio:owns(1, "nope"), "Studio does not own the catalogue")
	local show = studio:loadout(1)
	assert(show.skins.Sword and show.hit and show.ko and show.trail, "Studio does not dress a bare player in the showcase")
	assert(studio:apply(1, { action = "equip", id = "trail_frost" }) and studio:loadout(1).trail == "trail_frost" and not studio.store.dirty[1],
		"Studio wearing is not session-only")
	local b1, b2 = Locker.botLoadout(1), Locker.botLoadout(2)
	assert(b1.hit ~= b2.hit and b1.ko ~= b2.ko, "Studio bots all wear the same effects")
end
print(string.format("PASS cosmetics: %d weapon skins each their weapon's exact footprint in new colours (every form); worn skins, trails, hit and KO effects drawn as their items say, nothing worn drawn as before; inventory and loadouts refuse unknown, unowned and misplaced items; the Locker owns everything only in Studio", skins))
