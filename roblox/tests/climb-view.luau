--!strict
-- ParkourView, the Skyline Climb on screen: starting and resuming, the climb's messages to the
-- server, the HUD, bounded and finite drawing, flags, leaving and restarting. Instances, input and
-- drawing primitives are stubs; the climbing is the real Parkour.luau.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Input = Loader.load("Input")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local codes = setmetatable({}, { __index = function(_, key) return key end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, key) return key end })
local function instance(): any
	local obj: any = { attributes = {}, Visible = true, TextTransparency = 0 }
	obj.Destroy = function() obj.destroyed = true end
	obj.Activated = { Connect = function(_, fn) obj.activate = fn end }
	obj.SetAttribute = function(_, key, value) obj.attributes[key] = value end
	return obj
end
local View = luau.load(fs.readFile("src/client/ParkourView.luau"), { debugName = "ParkourView", environment = {
	game = { GetService = function(_, name) if name == "ReplicatedStorage" then return { Shared = shared } end error(name) end },
	script = { Parent = codes },
	require = function(name)
		if name == "InputClient" then return { new = function() return {} end } end
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2, UDim = Rbx.UDim,
	Enum = setmetatable({}, { __index = function() return codes end }), Instance = { new = instance },
}, injectGlobals = true })()
local PARKOUR = Loader.load("Data/Parkour")
local KIT = Loader.load("Data/AvatarKit")
local N = #PARKOUR.course.checkpoints

-- 0. The clock reads as a player expects.
assert(View.clock(0) == "0:00.00" and View.clock(4995) == "1:23.25" and View.clock(60 * 600) == "10:00.00", "the timer format")

local stick = { frame = Input.emptyFrame() }
stick.sample = function(self) return { self.frame } end
stick.reset = function() end
local sent, left, restarts, boards = {}, 0, 0, 0
local v = View.new({}, { input = stick, send = function(m) table.insert(sent, m) end,
	leave = function() left += 1 end, restart = function() restarts += 1 end, records = function() boards += 1 end })
local code = KIT.presets[3].code

-- 1. A climb from the bottom.
v:start(code, 0)
assert(v.active and v.gui.Enabled and v.pk.fighter.platform.id == "main", "a climb starts on Rooftop Access")
assert(v.char.weapon.id == PARKOUR.weapon, "everyone climbs in the course's body")
stick.frame.x = 1
for _ = 1, 60 do v:step(1/60) end
assert(v.pk.fighter.x > 5, "the stick moves the climber")
stick.frame.x = 0

-- 2. Checkpoints and the Summit reach the server; the HUD follows.
local function land(id: string)
	for _, p in v.pk.stage.platforms do
		if p.id == id then
			v.pk.fighter.x, v.pk.fighter.y, v.pk.fighter.onGround, v.pk.fighter.platform = p.cx, p.top + 2, false, nil
		end
	end
	for _ = 1, 60 do v:step(1/60) end
end
land("chimney")
assert(sent[#sent].action == "checkpoint" and sent[#sent].index == 1, "a checkpoint is reported")
assert(v.checkpointLabel.Text == "CHECKPOINT 1/" .. (N - 1) .. "  ·  CHIMNEY STACK", `HUD: {v.checkpointLabel.Text}`)
assert(string.find(v.banner.Text, "CHIMNEY STACK"), "and announced")
assert(v.restartButton.Visible, "once past the bottom, you can restart from it")
land("summit")
local summit = sent[#sent]
assert(summit.action == "summit" and summit.frames == v.pk.frames and summit.frames > 0, "the Summit is reported with the climb's time")
assert(sent[#sent - 1].action == "checkpoint" and sent[#sent - 1].index == N - 1, "the Summit's checkpoint comes first")
assert(v.checkpointLabel.Text == "THE SUMMIT" and string.find(v.banner.Text, "THE SUMMIT"), "the Summit is celebrated")

-- 3. Drawing: finite, bounded, flags amber once reached, at three sizes and along the course.
local flags: { [string]: any } = {}
local function primitive(c: any, ...: any)
	for _, value in { ... } do
		if type(value) == "number" then assert(value == value and math.abs(value) < math.huge, "finite climb geometry") end
	end
	c.used += 1
end
local sprites = 0
Canvas.rect, Canvas.circle, Canvas.ellipse = primitive, primitive, primitive
Canvas.sprite = function(c: any, ...: any) sprites += 1; c.used += 1 end
local function canvas(w: number, h: number): any
	return setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
		gui = { AbsoluteSize = { X = w, Y = h } }, finish = function(self) self.drawn = self.used; self.used = 0 end }, { __index = Canvas })
end
local peak = 0
v:start(code, 0)
for _, size in { { 390, 844 }, { 1280, 720 }, { 1920, 1080 } } do
	for _, cp in PARKOUR.course.checkpoints do
		for _, p in v.pk.stage.platforms do
			if p.id == cp.pad then v.pk.fighter.x, v.pk.fighter.y = p.cx, p.top end
		end
		v.camX, v.camY = v.pk.fighter.x, v.pk.fighter.y
		sprites = 0
		local c = canvas(size[1], size[2])
		v:draw(c, 1/60)
		assert(c.drawn > 10 and c.drawn < 700, `{cp.id} at {size[1]}x{size[2]}: {c.drawn} primitives`)
		assert(#c.stack == 0, "the climb leaves no transforms behind")
		assert(sprites == 7, `the climber is the seven pieces of their character, drew {sprites}`)
		peak = math.max(peak, c.drawn)
	end
end
-- A reached flag is amber, an unreached one steel.
v:start(code, 3)
v.pk.fighter.x = 262                       -- between the Water Tower (reached) and the Scaffold (not)
v.camX = 262
v:draw(canvas(5000, 1080), 1/60)
local amber, steel = nil, nil
for id, t in v.labels do
	if id == "cp4" and t.Visible then amber = t.TextColor3 end
	if id == "cp5" and t.Visible then steel = t.TextColor3 end
end
assert(amber and math.floor(amber.R * 255 + 0.5) == 232, "a reached checkpoint's flag is amber")
assert(steel and math.floor(steel.R * 255 + 0.5) == 110, "one not yet reached is steel")

-- 4. Resuming: on the checkpoint, and the HUD says it is not a timed full climb.
v:start(code, 5)
assert(v.pk.fighter.platform.id == PARKOUR.course.checkpoints[6].pad, "resuming starts on that checkpoint")
v:step(1/60)
assert(string.find(v.fallsLabel.Text, "resumed"), "a resumed climb says it is not timed as a full climb")

-- 5. Restart and leave.
v.restartButton.activate()
assert(restarts == 1, "RESTART asks for a climb from the bottom")
v.recordsButton.activate()
assert(boards == 1, "RECORDS opens the leaderboards")
v:setProgress({ best = 4, summits = 2, bestFrames = 4995 })
assert(string.find(v.bestLabel.Text, "Billboard Scaffold") and string.find(v.bestLabel.Text, "1:23.25") and string.find(v.bestLabel.Text, "Summits: 2"), `progress: {v.bestLabel.Text}`)
v:leave()
assert(left == 1 and not v.active and not v.gui.Enabled, "leaving stops the climb and goes back to the lobby")
v:step(1/60)
assert(not v.pk, "a stopped climb does not step")
print(`PASS climb view: start and resume, checkpoints and the Summit reported, HUD and timer, {N} flags, finite bounded draws (peak {peak}), restart and leave`)
