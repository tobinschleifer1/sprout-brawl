--!strict
-- Who owns which game pass (Roblox only; Products.PASSES). Asked of MarketplaceService once per
-- player per session and remembered; a purchase in this session is recorded when Roblox reports it.
-- In Studio every available pass is owned, so its perks can be playtested before the passes exist.
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)
local Passes = {}
Passes.__index = Passes

-- opts: { market = MarketplaceService (or a stand-in), studio = boolean }
function Passes.new(opts: any): any
	return setmetatable({ market = opts.market, studio = opts.studio == true, owned = {} }, Passes)
end

function Passes.owns(self: any, userId: number, id: string): boolean
	local p = Products.pass(id)
	if not p then return false end
	if self.studio then return p.available end
	local mine = self.owned[userId]
	if not mine then mine = {}; self.owned[userId] = mine end
	if mine[id] == nil then
		if p.pass == 0 or not self.market then return false end
		local ok, has = pcall(function() return self.market:UserOwnsGamePassAsync(userId, p.pass) end)
		if not ok then return false end           -- asked again next time
		mine[id] = has == true
	end
	return mine[id] == true
end

-- Roblox said this player just bought `passId` (PromptGamePassPurchaseFinished).
function Passes.bought(self: any, userId: number, passId: number): string?
	for _, p in Products.PASSES do
		if p.pass ~= 0 and p.pass == passId then
			self.owned[userId] = self.owned[userId] or {}
			self.owned[userId][p.id] = true
			return p.id
		end
	end
	return nil
end

function Passes.forget(self: any, userId: number)
	self.owned[userId] = nil
end

return Passes
