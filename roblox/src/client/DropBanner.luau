--!strict
-- The line under the results podium that says what the match earned (Roblox only; plan phase 3):
-- the drop meter ("Next drop in 2 games"), a drop in its rarity's colour, or why the match did not
-- count. `DropBanner.text` is the words and colour (pure, tested); `show` puts them on screen.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Loot = require(Shared.Loot)
local DropBanner = {}

local CRATE_COLOUR = { scrap = "#E8C88A", forge = "#FFB43C" }

local function games(n: number): string
	return if n == 1 then "1 game" else `{n} games`
end

-- `out` is Economy.matchFinished's answer. Returns the text and a hex colour.
function DropBanner.text(out: any): (string, string)
	if type(out) ~= "table" then return "", "#FFFFFF" end
	local left = if type(out.left) == "number" then out.left else nil
	local after = if left then `  ·  next drop in {games(left)}` else ""
	local d = out.drop
	if type(d) == "table" then
		if d.kind == "crate" then
			local crate = Loot.CRATES[d.crate]
			return `DROP!  {crate and crate.name or "Crate"}{after}`, CRATE_COLOUR[d.crate] or "#FFFFFF"
		elseif d.kind == "key" then
			return `DROP!  Forge Key{after}`, "#FFB43C"
		elseif d.kind == "sparks" then
			return `DROP!  {d.amount} Sparks{after}`, "#9FE8FF"
		elseif d.kind == "item" then
			local it = Cosmetics.get(d.id)
			local rarity = it and it.rarity or d.rarity or "Common"
			local colour = (Loot.RARITY[rarity] or Loot.RARITY.Common).colour
			local serial = if type(d.serial) == "number" and d.serial > 0 then `  #{d.serial}` else ""
			return `DROP!  {rarity} {it and it.name or d.id}{serial}{after}`, colour
		end
	end
	if out.capped then return "Drops are resting: back next hour", "#9AA3B4" end
	if not out.counted then return "This match did not count toward a drop", "#9AA3B4" end
	return `Next drop in {games(left or 0)}`, "#E9EBF1"
end

-- Show it across the bottom of `gui` for `seconds`, replacing any earlier banner.
function DropBanner.show(gui: Instance, out: any, seconds: number?)
	local text, colour = DropBanner.text(out)
	local old = gui:FindFirstChild("DropBanner")
	if old then old:Destroy() end
	if text == "" then return end
	local label = Instance.new("TextLabel")
	label.Name = "DropBanner"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.new(0.9, 0, 0, 34)
	label.BackgroundColor3 = Color3.fromHex("#12151C")
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromHex(colour)
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.Text = text
	label.ZIndex = 50
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	label.Parent = gui
	task.delay(seconds or 9, function()
		if label.Parent then label:Destroy() end
	end)
end

return DropBanner
