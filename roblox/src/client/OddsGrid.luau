--!strict
-- What is in a crate, as pictures (Roblox only; the owner's ask, 2026-11-04): Odds & Details shows
-- each rarity as a heading with its share, then a card per item - its picture, name, kind and odds -
-- in the rarity's colour, the way a case's contents are shown. Used by the Locker's and the Shop's
-- odds windows, filled from LockerScreen.oddsRows, so the numbers are still Loot's own.
--
-- Cards are kept by item id, not by row: switching to the guaranteed opening shows and hides cards
-- and changes their odds, and never redraws a picture. (By row, every card past the first tier held
-- a different item after the switch, and each switch redrew the lot.)
local Shared = game:GetService("ReplicatedStorage").Shared
local Loot = require(Shared.Loot)
local Ui = require(script.Parent.Ui)
local OddsGrid = {}

OddsGrid.CELL = Vector2.new(132, 156)
OddsGrid.ART = Vector2.new(OddsGrid.CELL.X - 12, 86)   -- the picture's well, inside the card's edge
OddsGrid.HEADING = 28
OddsGrid.Z = 11                                        -- inside an odds window, which is at 10

local function colourOf(rarity: string): Color3
	return Color3.fromHex((Loot.RARITY[rarity] or Loot.RARITY.Common).colour)
end

function OddsGrid.new(list: Instance): any
	return { list = list, headings = {}, grids = {}, cards = {} }
end

local function heading(g: any, rarity: string): any
	local h = g.headings[rarity]
	if h then return h end
	local f = Ui.make("Frame", g.list, { Name = "Tier_" .. rarity, BackgroundTransparency = 1, ZIndex = OddsGrid.Z,
		Size = UDim2.new(1, -10, 0, OddsGrid.HEADING) })
	local l = Ui.text(f, rarity, 16, Ui.TEXT, Ui.DISPLAY, true)
	l.Name, l.ZIndex, l.TextXAlignment, l.Size = "Label", OddsGrid.Z, Enum.TextXAlignment.Left, UDim2.new(0.5, 0, 1, 0)
	local v = Ui.text(f, "", 14, Ui.TEXT, nil, true)
	v.Name, v.ZIndex, v.TextXAlignment = "Value", OddsGrid.Z, Enum.TextXAlignment.Right
	v.Position, v.Size = UDim2.fromScale(0.5, 0), UDim2.new(0.5, 0, 1, 0)
	-- tiers in their colour, deepened to read on a pale window
	local col = colourOf(rarity)
	if Ui.lightPanels() then col = Ui.shade(col, -0.35) end
	l.TextColor3, v.TextColor3 = col, col
	h = { frame = f, label = l, value = v }
	g.headings[rarity] = h
	return h
end

local function grid(g: any, rarity: string): any
	local f = g.grids[rarity]
	if f then return f end
	-- (cards draw their stroke 3 px outside their box: padded in so the first column's is not clipped)
	f = Ui.make("Frame", g.list, { Name = "Grid_" .. rarity, BackgroundTransparency = 1, ZIndex = OddsGrid.Z,
		Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	Ui.make("UIPadding", f, { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) })
	Ui.make("UIGridLayout", f, { CellSize = UDim2.fromOffset(OddsGrid.CELL.X, OddsGrid.CELL.Y), CellPadding = UDim2.fromOffset(Ui.GAP, Ui.GAP),
		SortOrder = Enum.SortOrder.LayoutOrder })
	g.grids[rarity] = f
	return f
end

local function card(g: any, id: string, rarity: string, name: string, kind: string, drawArt: (Instance, string, number, number) -> ()): any
	local c = g.cards[id]
	if c then return c end
	local colour = colourOf(rarity)
	local f = Ui.card(grid(g, rarity), "Item_" .. id, colour)
	f.ZIndex = OddsGrid.Z
	Ui.paintCard(f, colour)
	local art = Ui.make("Frame", f, { Name = "Thumb", BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.72, BorderSizePixel = 0,
		ZIndex = OddsGrid.Z, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(OddsGrid.ART.X, OddsGrid.ART.Y) })
	Ui.corner(art, 6)
	if Ui.lightPanels() then Ui.mount(art, colour) end
	drawArt(art, id, OddsGrid.ART.X, OddsGrid.ART.Y)
	-- the odds on a dark pill over the picture's corner, as a price sits on a shop card
	local odds = Ui.pricePill(f, "")
	odds.Name, odds.ZIndex = "Odds", OddsGrid.Z + 2
	odds.TextSize = Ui.px(12, Ui.DISPLAY)
	odds.AnchorPoint, odds.Position, odds.Size = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4), UDim2.fromOffset(70, 18)
	local n, nStroke = Ui.faceText(f, name, 14, colour)
	n.Name, n.ZIndex = "Name", OddsGrid.Z
	Ui.fit(n, 10)
	n.Position, n.Size = UDim2.fromOffset(6, OddsGrid.ART.Y + 10), UDim2.new(1, -12, 0, 20)
	Ui.paintTitle(n, nStroke, colour)
	local k, kStroke = Ui.faceText(f, kind, 12, colour, Ui.LABEL)
	k.Name, k.ZIndex = "Kind", OddsGrid.Z
	k.Position, k.Size = UDim2.fromOffset(6, OddsGrid.ART.Y + 32), UDim2.new(1, -12, 0, 16)
	Ui.paintSecondary(k, kStroke, colour)
	c = { frame = f, odds = odds }
	g.cards[id] = c
	return c
end

-- Show `rows` (LockerScreen.oddsRows): headings in order, each followed by its rarity's cards.
function OddsGrid.fill(g: any, rows: { any }, drawArt: (Instance, string, number, number) -> ())
	local shown: { [any]: boolean } = {}
	local order, inTier = 0, 0
	for _, r in rows do
		if r.kind == "tier" then
			local h = heading(g, r.rarity)
			order += 1
			h.frame.LayoutOrder, h.value.Text = order, r.value
			shown[h.frame] = true
			local f = grid(g, r.rarity)
			order += 1
			f.LayoutOrder = order
			shown[f] = true
			inTier = 0
		else
			local c = card(g, r.id, r.rarity, r.name, r.kindLabel, drawArt)
			inTier += 1
			c.frame.LayoutOrder, c.odds.Text = inTier, r.value
			shown[c.frame] = true
		end
	end
	for _, h in g.headings do h.frame.Visible = shown[h.frame] == true end
	for _, f in g.grids do f.Visible = shown[f] == true end
	for _, c in g.cards do c.frame.Visible = shown[c.frame] == true end
end

return OddsGrid
