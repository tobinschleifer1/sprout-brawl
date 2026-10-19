--!strict
-- The cosmetics a player owns and wears, on the server (Roblox only; docs/briefs/crates-and-
-- monetisation-plan.md, phase 2). Ownership lives in the saved record (AvatarStore, `inventory`,
-- cleaned by Inventory.sanitize); wearing is checked against it here, so a client can only ever wear
-- what the server says it owns, and every match reads the loadout from here (MatchService.cosmeticsFor),
-- never from the client.
--
-- In Studio everything is owned for the session (not saved), and a player who wears nothing is
-- dressed in SHOWCASE, so the cosmetics can be playtested before crates exist (phase 3). Never on a
-- live server: `studio` is RunService:IsStudio().
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Inventory = require(Shared.Inventory)
local Locker = {}
Locker.__index = Locker

-- What a Studio playtester wears until they choose: the rarest skin of every weapon, and one of each
-- effect that shows in a fight.
Locker.SHOWCASE = (function()
	local rank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
	local skins: { [string]: string } = {}
	for _, it in Cosmetics.LIST do
		if it.type == "weapon_skin" and it.weapon then
			local cur = skins[it.weapon] and Cosmetics.get(skins[it.weapon])
			if not cur or rank[it.rarity] > rank[cur.rarity] then skins[it.weapon] = it.id end
		end
	end
	return { skins = skins, hit = "hit_supernova", ko = "ko_blackhole", trail = "trail_rainbow" }
end)()

-- What Studio bot `i` wears: the showcase skins, with a different hit, KO and trail each, so a few
-- fights against bots show the range.
local BOT_HITS = { "hit_sakura", "hit_comicpow", "hit_eventhorizon", "hit_static", "hit_inkblot" }
local BOT_KOS = { "ko_firework", "ko_dragonsbreath", "ko_meteor", "ko_pixelshatter", "ko_ghostrise", "ko_balloonpop" }
local BOT_TRAILS = { "trail_ember", "trail_glitch", "trail_gold", "trail_frost", "trail_shadow" }
function Locker.botLoadout(i: number): any
	return Inventory.cleanLoadout({ skins = Locker.SHOWCASE.skins,
		hit = BOT_HITS[(i - 1) % #BOT_HITS + 1], ko = BOT_KOS[(i - 1) % #BOT_KOS + 1], trail = BOT_TRAILS[(i - 1) % #BOT_TRAILS + 1] })
end

-- opts: { store = AvatarStore, studio = boolean, vip = (userId) -> boolean }
function Locker.new(opts: any): any
	return setmetatable({ store = opts.store, studio = opts.studio == true, vip = opts.vip }, Locker)
end

function Locker.inventory(self: any, userId: number): any
	local rec = self.store:load(userId)
	rec.inventory = rec.inventory or Inventory.sanitize(nil)
	return rec.inventory
end

function Locker.owns(self: any, userId: number, id: string): boolean
	if self.studio then return Cosmetics.get(id) ~= nil end
	return self:inventory(userId).owned[id] == true
end

-- What the player wears into a match.
function Locker.loadout(self: any, userId: number): any
	local out = Inventory.loadout(self:inventory(userId))
	if self.studio and next(out.skins) == nil and out.hit == nil and out.ko == nil and out.trail == nil then
		out.skins, out.hit, out.ko, out.trail = table.clone(Locker.SHOWCASE.skins), Locker.SHOWCASE.hit, Locker.SHOWCASE.ko, Locker.SHOWCASE.trail
	end
	return out
end

-- A request from the client: { action = "equip", id = itemId } or { action = "remove", slot = ...,
-- weapon = ... }. Returns ok and why not; saves on success.
function Locker.apply(self: any, userId: number, msg: any): (boolean, string?)
	if type(msg) ~= "table" then return false, "bad request" end
	if self.store.busy and (self.store.busy[userId] or self.store.closing[userId]) then return false, "your record is busy; try again" end
	local inv = self:inventory(userId)
	local ok, why
	if msg.action == "equip" and type(msg.id) == "string" then
		ok, why = Inventory.equip(inv, msg.id, function(id) return self:owns(userId, id) end, if type(msg.slot) == "string" then msg.slot else nil)
	elseif msg.action == "remove" then
		ok, why = Inventory.equip(inv, nil, function() return false end,
			if type(msg.slot) == "string" then msg.slot else nil, if type(msg.weapon) == "string" then msg.weapon else nil)
	elseif msg.action == "savePreset" or msg.action == "wearPreset" then
		-- saved outfits: a whole loadout in one slot (VIP has five, everyone else one)
		local i = msg.slot
		local cap = self:presets(userId)
		if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > cap then return false, `you have {cap} outfit slot{if cap == 1 then "" else "s"}` end
		if msg.action == "savePreset" then
			inv.presets[i] = Inventory.cleanLoadout(inv.equipped)
			ok = true
		else
			local p = inv.presets[i]
			if not p then return false, "that outfit slot is empty" end
			-- only what is still owned is put on; the rest of the slot is left as it is
			local wear = Inventory.cleanLoadout(p)
			for weapon, id in wear.skins do if not self:owns(userId, id) then wear.skins[weapon] = nil end end
			for key in Inventory.SLOT_TYPES do
				if wear[key] and not self:owns(userId, wear[key]) then wear[key] = nil end
			end
			inv.equipped = wear
			ok = true
		end
	else
		return false, "bad request"
	end
	if ok and not self.studio then self.store.dirty[userId] = self.store.dirty[userId] or self.store.clock() end
	return ok, why
end

-- How many saved outfits this player has: Inventory.MAX_PRESETS with VIP (`opts.vip`), else one.
function Locker.presets(self: any, userId: number): number
	local ok, vip = pcall(function() return self.vip and self.vip(userId) end)
	return if ok and vip == true then Inventory.MAX_PRESETS else 1
end

-- What the client is shown: owned items (everything, in Studio), what is worn, which outfit slots
-- are filled.
function Locker.view(self: any, userId: number): any
	local inv = self:inventory(userId)
	local owned = {}
	for _, it in Cosmetics.LIST do
		if self:owns(userId, it.id) then table.insert(owned, it.id) end
	end
	local presets = {}
	for i = 1, self:presets(userId) do presets[i] = inv.presets[i] ~= nil and inv.presets[i] ~= false end
	return { owned = owned, wearing = self:loadout(userId), studio = self.studio, presets = presets }
end

return Locker
