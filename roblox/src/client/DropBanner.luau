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
	-- past the hourly cap (Economy): against people XP still counts; against bots nothing does
	if out.capped then
		local rest = if type(out.rest) == "number" then `Drops rest for {out.rest} min` else "Drops are resting"
		return rest .. (if out.progressing then "  ·  XP still counts" else "  ·  bot matches pay again then"), "#9AA3B4"
	end
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
		if r.keyCapped then table.insert(parts, "weekly ranked keys reached") end
	end
	return table.concat(parts, "  ·  "), colour
end

-- What the Road to 50's levels paid, added up, as its own line (a big jump - back-pay to level 30 -
-- would not fit beside the level line): "+1508 Sparks · 6 Scrap Crates · 3 Forge Keys".
function DropBanner.rewardsText(p: any): (string, string)
	if type(p) ~= "table" or type(p.rewards) ~= "table" or #p.rewards == 0 then return "", "#FFFFFF" end
	local sparks, crates, keys = 0, 0, 0
	for _, r in p.rewards do
		sparks += tonumber(r.sparks) or 0
		if r.crate then crates += 1 end
		keys += tonumber(r.keys) or 0
	end
	local parts = {}
	if sparks > 0 then table.insert(parts, `+{sparks} Sparks`) end
	if crates > 0 then table.insert(parts, if crates == 1 then "Scrap Crate" else `{crates} Scrap Crates`) end
	if keys > 0 then table.insert(parts, if keys == 1 then "Forge Key" else `{keys} Forge Keys`) end
	return table.concat(parts, "  ·  "), "#FEE761"
end
-- The titles those levels gave, as a line of their own (a title is the rarest thing levels pay).
function DropBanner.titlesText(p: any): (string, string)
	if type(p) ~= "table" or type(p.rewards) ~= "table" then return "", "#FFFFFF" end
	local titles = {}
	for _, r in p.rewards do
		local it = r.title and Cosmetics.get(r.title)
		if it then table.insert(titles, it.name) end
	end
	if #titles == 0 then return "", "#FFFFFF" end
	return `NEW {if #titles == 1 then "TITLE" else "TITLES"}: {table.concat(titles, ", ")}`, "#FF6B8A"
end

-- Everything a match earned, in the order it is shown: the level and rank line, the next goal
-- (`goal`, NextGoal's), then the drop's. Each { text, colour }; empty ones left out. Pure.
function DropBanner.lines(out: any, goal: string?): { { string } }
	local list = {}
	local function add(text: string, colour: string) if text ~= "" then table.insert(list, { text, colour }) end end
	if type(out) == "table" then add(DropBanner.progressText(out.progress)) end
	if type(out) == "table" then add(DropBanner.rewardsText(out.progress)); add(DropBanner.titlesText(out.progress)) end
	if type(out) == "table" and type(out.welcome) == "table" then
		add(`Welcome back!  Away {out.welcome.away or 7} days  ·  a Scrap Crate`, CRATE_COLOUR.scrap)
	end
	add(goal or "", "#9FE8FF")
	add(DropBanner.text(out))
	return list
end

-- One strip across the bottom of `gui` - the room one line takes, over the podium's stat cards -
-- turning through `list` every EVERY seconds for SHOW_FOR, replacing any earlier one. (Three strips
-- stacked covered most of the stat cards on a phone: tools/render-ui results 812 375 earned.)
DropBanner.EVERY, DropBanner.SHOW_FOR = 3, 12
-- (replaceable, for the tests and the still renders)
DropBanner.delay = function(seconds: number, fn: () -> ()) task.delay(seconds, fn) end
function DropBanner.showAll(gui: Instance, list: { { string } })
	local old = gui:FindFirstChild("DropBanner")
	if old then old:Destroy() end
	if #list == 0 then return end
	local label = Instance.new("TextLabel")
	label.Name = "DropBanner"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.new(0.9, 0, 0, 34)
	label.BackgroundColor3 = Color3.fromHex("#12151C")
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.ZIndex = 50
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	local function showLine(k: number)
		if not label.Parent and k > 1 then return end
		local line = list[(k - 1) % #list + 1]
		label.Text, label.TextColor3 = line[1], Color3.fromHex(line[2])
		if k * DropBanner.EVERY >= DropBanner.SHOW_FOR then
			DropBanner.delay(DropBanner.EVERY, function() if label.Parent then label:Destroy() end end)
		else
			DropBanner.delay(DropBanner.EVERY, function() showLine(k + 1) end)
		end
	end
	showLine(1)
	label.Parent = gui
end

return DropBanner
