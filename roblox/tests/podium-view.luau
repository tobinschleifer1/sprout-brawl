--!strict
-- What PodiumView puts on screen, read off the Instances it builds: a card per fighter exactly where
-- the shared layout puts it, the right place and stat values on each, a winning team sharing first,
-- the winners painted in the victory pose and everyone else in defeat - standing on their pillars
-- at the layout's scale - and "Say: GG!" reaching whoever handles it.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")

local function signal(): any
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function() for _, fn in callbacks do fn() end end }
end
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, AbsoluteSize = Rbx.Vector2.new(1280, 720), Activated = signal() }
	local children = {}
	local self: any
	props.GetChildren = function() return table.clone(children) end
	props.FindFirstChild = function(_, name)
		for _, child in children do if child.Name == name then return child end end
		return nil
	end
	props.Destroy = function() table.clear(children) end
	props._children = children
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		props[key] = value
		if key == "Parent" then table.insert(value._children, self) end
	end })
	return self
end
local codes = setmetatable({}, { __index = function(_, name) return name end })

local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Podium = Loader.loadFrom("src/client/", "Podium")
local drawn: { any } = {}
local rects: { any } = {}
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	local m = c.m
	table.insert(rects, { x = m.a * x + m.e, y = m.d * y + m.f, w = w * m.a, h = h * m.d, colour = colour })
end
local FakeFighter2D = { draw = function(c: any, st: any, char: any, _t: number, _top: number?)
	local m = c.m
	table.insert(drawn, { state = st.state, index = st.index, feetX = m.e, feetY = m.f, ppu = m.a, flipped = m.d < 0, height = char.height })
end }
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2,
	Enum = setmetatable({}, { __index = function() return codes end }) }
local View = luau.load(fs.readFile("src/client/PodiumView.luau"), { environment = {
	game = { GetService = function() return { Shared = { Fighter = "Fighter", Snapshot = "Snapshot" } } end },
	script = { Parent = codes },
	require = function(name)
		if name == "Canvas2D" then return Canvas end
		if name == "Fighter2D" then return FakeFighter2D end
		if name == "Podium" then return Podium end
		if name == "HudColors" or name == "PosedFighter" or name == "Ui" then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Enum = { Font = codes, TextXAlignment = codes, TextTruncate = codes, ApplyStrokeMode = codes },
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Instance = { new = instance },
}, injectGlobals = true })()

local Loadout = Loader.load("Loadout")
local chars = { Loadout.build("Classic", "Sword"), Loadout.build("Noir", "Flail"), Loadout.build("Ember", "Axe"), Loadout.build("Moss", "Hammer") }
local function rowsFor(order: { number }, teams: { number }): { any }
	local out = {}
	for i, idx in order do
		table.insert(out, { index = idx, name = `P{idx}`, team = teams[i], score = 5 - i, kos = 4 - i, falls = i,
			sds = i - 1, damage = 100.5 * i, taken = 50.25 * i })
	end
	return out
end

local W, H = 1280, 720
local function card(root: any, i: number): any
	return root:FindFirstChild(`Card{i}`)
end
local checked = 0

-- Free for all: finishing order 2, 0, 3, 1.
local ffa = { rows = rowsFor({ 1, 0, 3, 2 }, { 1, 0, 3, 2 }), winnerTeam = 1, teams = false }
local gui = instance("ScreenGui")
local gg = 0
local view = View.new(gui, ffa, chars, Rbx.Vector2.new(W, H), function() gg += 1 end)
local root = gui:FindFirstChild("Podium")
assert(root, "the podium is built under the gui")
local slots = Podium.layout(4, W, H)
for i, row in ffa.rows do
	local c = assert(card(root, i), `card {i} missing`)
	local s = slots[i]
	-- UDim offsets are whole pixels in Roblox, so the layout's fractions land within one of them.
	local function px(a: number, b: number): boolean return math.abs(a - b) < 1 end
	assert(px(c.Position.X.Offset, s.card.x) and px(c.Position.Y.Offset, s.card.y), `card {i} at {c.Position.X.Offset},{c.Position.Y.Offset}; layout {s.card.x},{s.card.y}`)
	assert(px(c.Size.X.Offset, s.card.w) and px(c.Size.Y.Offset, s.card.h), `card {i} is not the layout's size`)
	assert(c:FindFirstChild("Place").Text == string.upper(Podium.ordinal(i)), `card {i} says {c:FindFirstChild("Place").Text}`)
	assert(string.find(c:FindFirstChild("Name").Text, row.name, 1, true), `card {i} names the wrong fighter`)
	for k, stat in Podium.STATS do
		assert(c:FindFirstChild(`Label{k}`).Text == stat[1], `card {i} row {k} label`)
		local v = c:FindFirstChild(`Value{k}`).Text
		assert(v == tostring(Podium.statValue(row, stat[2])), `card {i} {stat[1]} shows {v}`)
		checked += 1
	end
end
assert(string.find(root:FindFirstChild("PodiumTitle").Text, "P1 WINS", 1, true), "the title names the winner")

view:draw(10)
assert(#drawn == 4, `{#drawn} figures drawn, want 4`)
-- The sky's bands, then View.PILLAR_RECTS rectangles a pillar - its body first, its cap at CAP_AT
-- - at the layout's geometry, the winner's cap gold.
local GOLD = Loader.loadFrom("src/client/", "Ui").GOLD
local sky, per = View.SKY_BANDS, View.PILLAR_RECTS
assert(#rects == sky + 4 * per, `{#rects} rectangles, want {sky} sky bands and {per} for each of 4 pillars`)
for b = 1, sky do assert(rects[b].x == 0 and rects[b].w == W, `sky band {b} does not span the screen`) end
for i = 1, 4 do
	local body, cap = rects[sky + (i - 1) * per + 1], rects[sky + (i - 1) * per + View.CAP_AT]
	local s = slots[i]
	assert(body.x == s.pillar.x and body.y == s.pillar.y and body.w == s.pillar.w and body.h == s.pillar.h, `pillar {i} geometry`)
	assert(cap.x == s.cap.x and cap.y == s.cap.y and cap.w == s.cap.w and cap.h == s.cap.h, `cap {i} geometry`)
	assert((cap.colour == GOLD) == (i == 1), `only first place has a gold cap (pillar {i})`)
	for k = 2, per do
		local r = rects[sky + (i - 1) * per + k]
		assert(r.x >= s.pillar.x - 1e-9 and r.x + r.w <= s.pillar.x + s.pillar.w + 1e-9 or k >= View.CAP_AT,
			`pillar {i}'s detail {k} spills off the pillar`)
	end
end
for i, d in drawn do
	local s = slots[i]
	local row = ffa.rows[i]
	assert(d.index == row.index, `figure {i} is fighter {d.index}, want {row.index}`)
	assert(d.state == (if i == 1 then "victory" else "defeat"), `figure {i} pose {d.state}`)
	assert(math.abs(d.feetX - s.cx) < 1e-9 and math.abs(d.feetY - s.top) < 1e-9, `figure {i} does not stand on its pillar`)
	assert(math.abs(d.ppu * d.height - s.figureH) < 1e-9, `figure {i} is not the layout's height`)
	assert(d.flipped, "figures are drawn y-up, as the match draws them")
end

assert(not root:FindFirstChild("GGBubble").Visible, "a GG bubble shows before anyone said GG")
view.gg.Activated:Fire()
assert(gg == 1, "Say: GG! reaches its handler")
view:draw(10.5)
local bubble = root:FindFirstChild("GGBubble")
assert(bubble.Visible and bubble.Text == "GG!", "saying GG puts no bubble up")
assert(math.abs(bubble.Position.X.Offset + bubble.Size.X.Offset / 2 - slots[1].cx) < 1, "the GG bubble is not over the winner")
view:draw(13)
assert(not bubble.Visible, "the GG bubble outstays its two seconds")

-- Teams: green (0) beat orange (1). Both winners share first and both celebrate.
table.clear(drawn)
local teams = { rows = rowsFor({ 0, 2, 1, 3 }, { 0, 0, 1, 1 }), winnerTeam = 0, teams = true }
local gui2 = instance("ScreenGui")
local tv = View.new(gui2, teams, chars, Rbx.Vector2.new(W, H), nil)
local root2 = gui2:FindFirstChild("Podium")
local want = { "1ST", "1ST", "2ND", "2ND" }
for i = 1, 4 do
	assert(card(root2, i):FindFirstChild("Place").Text == want[i], `team card {i} says {card(root2, i):FindFirstChild("Place").Text}`)
end
assert(string.find(root2:FindFirstChild("PodiumTitle").Text, "GREEN TEAM WINS", 1, true), "team title")
-- A duel run as a team match (every lobby room is) names the player.
local duel = { rows = rowsFor({ 1, 0 }, { 1, 0 }), winnerTeam = 1, teams = true }
local gui3 = instance("ScreenGui")
View.new(gui3, duel, chars, Rbx.Vector2.new(W, H), nil)
local t3 = gui3:FindFirstChild("Podium"):FindFirstChild("PodiumTitle").Text
assert(t3 == "P1 WINS", `a 1v1 as teams is titled {t3}`)
tv:draw(3)
for i, d in drawn do
	assert(d.state == (if i <= 2 then "victory" else "defeat"), `team figure {i} pose {d.state}`)
end

-- A posed fighter carries every field the pose code reads.
local st = View.posed(chars[1], 0, "victory", 12)
assert(st.state == "victory" and st.stateFrame == 12 and st.onGround == true and st.x == 0 and st.y == 0, "posed fighter shape")
print(`podium view: {checked} stat cells, cards on the layout, winners celebrate, teams share first`)
