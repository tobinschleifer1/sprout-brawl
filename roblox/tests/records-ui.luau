--!nocheck
-- ClimbRecords, the climb's leaderboards on screen: both boards filled from what the server sends,
-- you marked, the countdown to the next boards, your own record, offline and empty boards, and
-- opening and closing. Instances are stubs; every behaviour is the module's.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")

local function signal(): any
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function(_, ...) for _, fn in callbacks do fn(...) end end }
end
local made = 0
local function instance(class: string): any
	made += 1
	local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), Text = "", _children = {} }
	local self: any
	props.GetChildren = function() return table.clone(props._children) end
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		props[key] = value
		if key == "Parent" and value then table.insert(value._children, self) end
	end })
	return self
end
local function find(root: any, name: string): any
	for _, child in root:GetChildren() do
		if child.Name == name then return child end
		local deep = find(child, name)
		if deep then return deep end
	end
	return nil
end

local codes = setmetatable({}, { __index = function(_, name) return name end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, name) return name end })
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
local Records = luau.load(fs.readFile("src/client/ClimbRecords.luau"), { debugName = "ClimbRecords", environment = {
	game = { GetService = function(_, name) if name == "ReplicatedStorage" then return { Shared = shared } end error(name) end },
	script = { Parent = codes },
	require = function(name)
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Instance = { new = instance }, Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim = Rbx.UDim, UDim2 = Rbx.UDim2,
	Enum = setmetatable({}, { __index = function() return codes end }),
}, injectGlobals = true })()
local PARKOUR = Loader.load("Data/Parkour")
local CPS = PARKOUR.course.checkpoints
local LAST = #CPS - 1

-- 0. Formats.
assert(Records.clock(4995) == "1:23.25" and Records.clock(0) == "0:00.00", "times read like the climb's timer")
assert(Records.wait(30) == "under a minute" and Records.wait(4 * 60 + 59) == "4m" and Records.wait(72 * 60) == "1h 12m"
	and Records.wait(2 * 3600) == "2h 00m", "the countdown reads as a player says it")
assert(Records.reach(3, 0) == CPS[4].name and Records.reach(LAST, 2) == "Summit ×2", "HIGHEST says how far")
assert(Records.reach(LAST, 0) == CPS[LAST + 1].name, "at the last checkpoint with no Summit counted yet, it names the checkpoint")

local now = 10000
local gui = instance("PlayerGui")
local r = Records.new(gui, { localId = 7, now = function() return now end })
local panel = find(gui, "BlockfallRecords")
local fastest, highest = find(panel, "Fastest"), find(panel, "Highest")
local function row(col: any, i: number): any return find(col, `Row{i}`) end

-- 1. Before the server has answered.
assert(not r:isOpen(), "closed until asked for")
assert(find(fastest, "Empty").Visible and find(fastest, "Empty").Text == "Loading…", "loading until the boards arrive")
assert(string.find(find(panel, "Status").Text, "Waiting"), "no countdown before the first boards")

-- 2. The boards.
r:set({ speed = { { rank = 1, userId = 3, name = "ada", frames = 60 * 61 }, { rank = 2, userId = 7, name = "me", frames = 60 * 75 } },
	levels = { { rank = 1, userId = 3, name = "ada", best = LAST, summits = 4 }, { rank = 2, userId = 9, name = "bo", best = 2, summits = 0 } },
	updatedAt = now - 60, nextAt = now + 72 * 60 })
assert(row(fastest, 1).Visible and row(fastest, 2).Visible and not row(fastest, 3).Visible, "as many rows as the board has")
assert(find(row(fastest, 1), "Name").Text == "ada" and find(row(fastest, 1), "Value").Text == "1:01.00", "FASTEST shows name and time")
assert(find(row(fastest, 2), "Name").Text == "me  (you)", "you are marked")
assert(find(row(fastest, 2), "Name").TextColor3 ~= find(row(fastest, 1), "Name").TextColor3, "and coloured apart")
assert(find(row(highest, 1), "Value").Text == "Summit ×4" and find(row(highest, 2), "Value").Text == CPS[3].name, "HIGHEST shows how far")
assert(not find(fastest, "Empty").Visible, "no empty note on a board with rows")
assert(string.find(find(panel, "Status").Text, "next update in 1h 12m"), `the countdown: {find(panel, "Status").Text}`)
now += 13 * 60
r:tick()
assert(string.find(find(panel, "Status").Text, "next update in 59m"), "the countdown counts down")
-- A shorter board clears the rows it no longer has; nothing new is made.
local before = made
r:set({ speed = { { rank = 1, userId = 4, name = "cy", frames = 3000 } }, levels = {}, nextAt = now + 60 })
assert(row(fastest, 1).Visible and not row(fastest, 2).Visible, "rows left over from the last boards are hidden")
assert(find(highest, "Empty").Visible and string.find(find(highest, "Empty").Text, "Nobody"), "an empty board says so")
assert(made == before, `a new board makes no new instances ({made - before})`)

-- 3. Your record, whatever the boards say.
assert(string.find(find(panel, "Mine").Text, "not on the boards"), "no record yet")
r:setMine({ best = 5, summits = 0 })
assert(find(panel, "Mine").Text == `You: {CPS[6].name}`, `your reach: {find(panel, "Mine").Text}`)
r:setMine({ best = LAST, summits = 2, bestFrames = 4995 })
assert(find(panel, "Mine").Text == "You: Summit ×2  ·  best time 1:23.25", `your record: {find(panel, "Mine").Text}`)

-- 4. Offline (Studio, or a server without its stores).
r:set({ speed = {}, levels = {}, offline = true })
assert(string.find(find(fastest, "Empty").Text, "offline") and string.find(find(panel, "Status").Text, "live servers"), "offline says so")

-- 5. Opening and closing: the button, and E - but not the E that opened it.
r:open()
assert(r:isOpen() and panel.Enabled, "open")
assert(not r:key("E") and r:isOpen(), "the press that opened the boards does not close them")
r.openedAt = os.clock() - 1
assert(not r:key("Q") and r:isOpen(), "other keys leave them open")
assert(r:key("E") and not r:isOpen(), "E closes them")
assert(not r:key("E"), "and a closed board takes no keys")
r:toggle()
assert(r:isOpen(), "toggle opens")
find(panel, "Close").Activated:Fire()
assert(not r:isOpen(), "CLOSE closes")
-- ranks one to three wear gold, silver and bronze badges; the rest none
do
	local GOLD = Loader.loadFrom("src/client/", "Ui").GOLD
	local badges = {}
	for i = 1, 4 do
		local rank = find(row(fastest, i), "Rank")
		badges[i] = rank.BackgroundTransparency == 0 and rank.BackgroundColor3 or false
	end
	assert(badges[1] == GOLD and badges[2] and badges[3] and badges[2] ~= GOLD and badges[3] ~= badges[2], "the top three do not wear three medals")
	assert(badges[4] == false, "fourth place wears a medal")
end
print("PASS records ui: both boards from the server, you marked, countdown, your record, offline and empty, rows reused, open and close")
