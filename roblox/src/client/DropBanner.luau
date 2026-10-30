--!strict
-- The line under the results podium that says what the match earned (Roblox only; plan phase 3):
-- the drop meter ("Next drop in 2 games"), a drop in its rarity's colour, or why the match did not
-- count. `DropBanner.text` is the words and colour (pure, tested); `show` puts them on screen.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Loot = require(Shared.Loot)
local Progression = require(Shared.Progression)
local Weapons = require(Shared.Weapons)
local DropBanner = {}

local CRATE_COLOUR = { scrap = "#E8C88A", forge = "#FFB43C" }

local function games(n: number): string
	return if n == 1 then "1 game" else `{n} games`
end

-- `out` is Economy.matchFinished's answer. Returns the text and a hex colour.
function DropBanner.text(out: any): (string, string)
	if type(out) ~= "table" then return "", "#FFFFFF" end
	-- the meter moves in quarters (a CPU match is three quarters of one): say the games left, rounded up
	local left = if type(out.left) == "number" then math.ceil(out.left) else nil
	local after = if left then `  ·  next drop in {games(left)}` else ""
	local d = out.drop
	local bonus = if type(out.firstWin) == "number" and out.firstWin > 0 then `  ·  first win today +{out.firstWin} Sparks` else ""
	if type(d) == "table" then
		if d.kind == "crate" then
			local crate = Loot.CRATES[d.crate]
			return `DROP!  {crate and crate.name or "Crate"}{after}{bonus}`, CRATE_COLOUR[d.crate] or "#FFFFFF"
		elseif d.kind == "key" then
			return `DROP!  Forge Key{after}{bonus}`, "#FFB43C"
		elseif d.kind == "sparks" then
			return `DROP!  {d.amount} Sparks{after}{bonus}`, "#9FE8FF"
		elseif d.kind == "item" then
			local it = Cosmetics.get(d.id)
			local rarity = it and it.rarity or d.rarity or "Common"
			local colour = (Loot.RARITY[rarity] or Loot.RARITY.Common).colour
			local serial = if type(d.serial) == "number" and d.serial > 0 then `  #{d.serial}` else ""
			return `DROP!  {rarity} {it and it.name or d.id}{serial}{after}{bonus}`, colour
		end
	end
	if out.capped then return "Drops are resting: back next hour", "#9AA3B4" end
	if not out.counted then return "This match did not count toward a drop", "#9AA3B4" end
	return `Next drop in {games(left or 0)}{bonus}`, if bonus ~= "" then "#9FE8FF" else "#E9EBF1"
end

-- The line above it: what the match did for your level and rank. `p` is Economy._progress's answer
-- (nil when the match did not count). A level gained, a weapon unlocked or a tier reached leads.
function DropBanner.progressText(p: any): (string, string)
	if type(p) ~= "table" or type(p.xp) ~= "number" then return "", "#FFFFFF" end
	local parts = { `+{p.xp} XP` }
	local colour = "#E9EBF1"
	local level = if type(p.level) == "number" then p.level else 1
	if type(p.from) == "number" and level > p.from then
		parts[1] = `LEVEL {level}!  +{p.xp} XP`
		colour = "#FEE761"
	end
	if type(p.unlocked) == "table" and #p.unlocked > 0 then
		local names = {}
		for _, id in p.unlocked do
			local w = Weapons.BY_ID[id]
			table.insert(names, if w then w.name else tostring(id))
		end
		table.insert(parts, `Unlocked: {table.concat(names, ", ")}`)
	end
	if type(p.from) == "number" and p.from < Progression.RANKED_LEVEL and level >= Progression.RANKED_LEVEL then
		table.insert(parts, "RANKED is open")
	end
	local r = p.rank
	if type(r) == "table" then
		local tier = Progression.TIERS[math.clamp(tonumber(r.tier) or 1, 1, #Progression.TIERS)]
		local delta = tonumber(r.delta) or 0
		table.insert(parts, `{tier.name} {r.points or 0} RP ({if delta >= 0 then "+" else ""}{delta})`)
		if type(r.promoted) == "table" and #r.promoted > 0 then
			parts[#parts] = `PROMOTED TO {tier.name}!  {r.points or 0} RP`
			colour = tier.colour
		end
		if r.sparks then table.insert(parts, `+{r.sparks} Sparks`) end
		if r.key then table.insert(parts, "+1 Forge Key") end
	end
	return table.concat(parts, "  ·  "), colour
end

local function banner(gui: Instance, name: string, text: string, colour: string, lift: number, seconds: number?)
	local old = gui:FindFirstChild(name)
	if old then old:Destroy() end
	if text == "" then return end
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24 - lift)
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

-- Show it across the bottom of `gui` for `seconds`, replacing any earlier banner.
function DropBanner.show(gui: Instance, out: any, seconds: number?)
	local text, colour = DropBanner.text(out)
	banner(gui, "DropBanner", text, colour, 0, seconds)
end
-- Any line in the banner's style, `lift` px above the drop's (the next-goal line uses it).
DropBanner.line = banner
DropBanner.LINE = 34 + 8      -- one line's height and gap
-- The level and rank line, just above the drop's.
function DropBanner.showProgress(gui: Instance, p: any, seconds: number?)
	local text, colour = DropBanner.progressText(p)
	banner(gui, "ProgressBanner", text, colour, 34 + 8, seconds)
end

return DropBanner
