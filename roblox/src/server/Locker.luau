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

-- opts: { store = AvatarStore, studio = boolean }
function Locker.new(opts: any): any
	return setmetatable({ store = opts.store, studio = opts.studio == true }, Locker)
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
		return Inventory.cleanLoadout(Locker.SHOWCASE)
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
		ok, why = Inventory.equip(inv, msg.id, function(id) return self:owns(userId, id) end)
	elseif msg.action == "remove" then
		ok, why = Inventory.equip(inv, nil, function() return false end,
			if type(msg.slot) == "string" then msg.slot else nil, if type(msg.weapon) == "string" then msg.weapon else nil)
	else
		return false, "bad request"
	end
	if ok and not self.studio then self.store.dirty[userId] = self.store.dirty[userId] or self.store.clock() end
	return ok, why
end

-- What the client is shown: owned items (everything, in Studio) and what is worn.
function Locker.view(self: any, userId: number): any
	local inv = self:inventory(userId)
	local owned = {}
	for _, it in Cosmetics.LIST do
		if self:owns(userId, it.id) then table.insert(owned, it.id) end
	end
	return { owned = owned, wearing = self:loadout(userId), studio = self.studio }
end

return Locker
