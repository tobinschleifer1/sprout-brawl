--!strict
-- The Skyline Climb's paid skips: one Developer Product per checkpoint, its price rising the deeper
-- you go - gently through the middle, steeply into the last two levels - to 600 Robux for the last,
-- the jump into the Summit.
--
-- ============================== SET THIS UP IN THE CREATOR DASHBOARD ==============================
-- Robux prices are not set here. Each skip is a Developer Product you create for this experience
-- (Creator Dashboard -> the experience -> Monetization -> Developer Products -> Create), priced as
-- in PRICES, and its id goes in IDS at the same position. An id of 0 means "not created yet": the
-- SKIP button still shows the price but says skipping is not available, and nothing is sold.
-- The price a player is actually charged is the product's, so keep the two in step; the button
-- shows the product's real price once it can read it (ClimbRecords / ParkourView ask Marketplace).
-- ================================================================================================
--
-- A skip is always ONE checkpoint forward from where the player is (server/ClimbProgress.skip):
-- the product only says what it cost. Skipping is saved as the checkpoint to resume from, but the
-- leaderboards and the Summit count take only checkpoints actually climbed to, and a climb with a
-- skip in it never sets a best time.

local SkipProducts = {}

-- Robux, for the skip INTO checkpoint i (1 = Chimney Stack ... 19 = Crown Perch, 20 = the Summit).
SkipProducts.PRICES = {
	5, 8, 10, 15, 20,          -- levels 1-5
	25, 30, 40, 50, 60,        -- levels 6-10
	75, 90, 110, 130, 150,     -- levels 11-15
	180, 220, 275,             -- levels 16-18
	400, 600,                  -- levels 19 and 20
}

-- Developer Product ids, same positions. 0 = not created yet.
SkipProducts.IDS = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

-- The product and price for skipping into checkpoint `index` (0-based, as the climb counts).
function SkipProducts.forCheckpoint(index: number): (number?, number?)
	local price = SkipProducts.PRICES[index]
	if not price then return nil, nil end
	local id = SkipProducts.IDS[index]
	return if id and id ~= 0 then id else nil, price
end

-- Which checkpoint a product skips into, or nil if it is not a skip.
function SkipProducts.checkpointFor(productId: any): number?
	if type(productId) ~= "number" or productId == 0 then return nil end
	for i, id in SkipProducts.IDS do
		if id == productId then return i end
	end
	return nil
end

return SkipProducts
