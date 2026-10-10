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
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
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
local COURSE_PADS = {}
for i, cp in PARKOUR.course.checkpoints do COURSE_PADS[i] = cp.pad end

-- 00. Clear of Roblox's own UI: its top bar is the top 58 px and the player list hangs from the top
--     right, and this ScreenGui ignores the inset. Seen in Studio: a SKIP button up there could not
--     be clicked. Every button sits at the bottom; the HUD text starts below the bar.
do
	local layout = View.new({}, { input = { sample = function() return {} end, reset = function() end }, send = function() end })
	for _, name in { "leaveButton", "restartButton", "recordsButton", "skipButton" } do
		local b = layout[name] or layout.gui
		assert(layout[name], `no {name}`)
		assert(b.Position.Y.Scale == 1 and b.AnchorPoint.Y == 1, `{name} is not in the bottom column`)
	end
	for _, name in { "checkpointLabel", "timerLabel", "fallsLabel", "bestLabel", "banner" } do
		local t = layout[name]
		assert(t.Position.Y.Scale == 0 and t.Position.Y.Offset >= 58, `{name} starts at {t.Position.Y.Offset} px, under Roblox's top bar`)
	end
end

-- 0. The clock reads as a player expects.
assert(View.clock(0) == "0:00.00" and View.clock(4995) == "1:23.25" and View.clock(60 * 600) == "10:00.00", "the timer format")

local stick = { frame = Input.emptyFrame() }
stick.sample = function(self) return { self.frame } end
stick.reset = function() end
local sent, left, restarts, boards = {}, 0, 0, 0
local skips: { number } = {}
local v = View.new({}, { input = stick, send = function(m) table.insert(sent, m) end,
	leave = function() left += 1 end, restart = function() restarts += 1 end, records = function() boards += 1 end,
	skip = function(index) table.insert(skips, index) end, price = function(index) return index * 7 end })
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
-- A whole character is one of the rig's two bodies: the jointed one at full detail, or the seven
-- one-piece pieces at half. Nothing missing, nothing doubled, nothing of one mixed into the other.
local BODIES = {
	["arm,arm,head,leg,leg,pelvis,torso"] = 7,
	["forearm,forearm,head,pelvis,shin,shin,thigh,thigh,torso,upperarm,upperarm"] = 11,
}
local function body(pieces: { string }): number?
	local sorted = table.clone(pieces)
	table.sort(sorted)
	return BODIES[table.concat(sorted, ",")]
end
local sprites, weapons, sky = 0, 0, 0
local pieces: { string } = {}
Canvas.rect, Canvas.circle, Canvas.ellipse = primitive, primitive, primitive
Canvas.sprite = function(c: any, key: string, ...: any)
	if string.sub(key, 1, 7) == "weapon|" then weapons += 1
	elseif string.find(key, "^realm|Lobby|sky|") then sky += 1     -- the bazaar's sky behind the course
	else sprites += 1; table.insert(pieces, string.match(key, "|(%a+)|") or key) end
	c.used += 1
end
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
		sprites, weapons, sky = 0, 0, 0
		table.clear(pieces)
		local c = canvas(size[1], size[2])
		v:draw(c, 1/60)
		assert(c.drawn > 10 and c.drawn < 700, `{cp.id} at {size[1]}x{size[2]}: {c.drawn} primitives`)
		assert(#c.stack == 0, "the climb leaves no transforms behind")
		assert(body(pieces) == sprites, `the climber is one whole body of their character, drew {table.concat(pieces, ",")}`)
		assert(weapons == 1, `and holds the course's weapon, one sprite, drew {weapons}`)
		assert(sky >= 3, `the sky behind the course is drawn ({sky} layer tiles)`)
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

-- 3b. SKIP: the next checkpoint and its price; buying moves you only when the server says so;
--     a skip is never reported as a checkpoint climbed; none past the Summit; none without a shop.
v:start(code, 0)
v:step(1/60)
assert(v.skipButton.Visible and string.find(v.skipButton.Text, "CHIMNEY STACK", 1, true) and string.find(v.skipButton.Text, "R$ 7", 1, true),
	`the button offers the next checkpoint at its price: {v.skipButton.Text}`)
v.skipButton.activate()
assert(#skips == 1 and skips[1] == 1 and v.pk.reached == 0, "clicking asks to buy the skip into 1, and moves nothing yet")
local before = #sent
v:skipTo(1)
assert(v.pk.reached == 1 and v.pk.fighter.platform.id == COURSE_PADS[2], "granted: standing on checkpoint 1")
v:step(1/60)
assert(#sent == before, "a skip is not reported to the server as a checkpoint climbed")
assert(string.find(v.banner.Text, "SKIPPED TO") and string.find(v.fallsLabel.Text, "skipped"), "the HUD says it was skipped and is not timed")
assert(string.find(v.skipButton.Text, "R$ 14", 1, true), "the button moves on to the next skip")
v.banner.Text = "unchanged"
v:skipTo(1); v:skipTo(0)
assert(v.pk.reached == 1 and v.banner.Text == "unchanged", "a grant for where you already are, or behind, moves and says nothing")
v:skipTo(N - 1)
v:step(1/60)
assert(v.pk.done and not v.skipButton.Visible and string.find(v.banner.Text, "SUMMIT"), "skipped to the Summit: finished, nothing left to buy")
assert(#sent == before, "and no Summit is claimed")
local plain = View.new({}, { input = stick, send = function() end, price = function() return 5 end })
plain:start(code, 0)
plain:step(1/60)
assert(not plain.skipButton.Visible, "no shop, no SKIP button")

-- 3c. Rewards: walked onto by someone who climbed there, it is claimed from the server and
--     announced; a skipper sees it locked; its owner does not see it at all.
do
	local crown = PARKOUR.course.rewards[1]
	local function walkOnto(view)
		local pk = view.pk
		for _ = 1, 400 do
			if math.abs(pk.fighter.x - crown.x) < 0.3 then break end
			stick.frame.x = if crown.x > pk.fighter.x then 1 else -1
			view:step(1/60)
		end
		stick.frame.x = 0
		for _ = 1, 5 do view:step(1/60) end
	end
	local function claims(): number
		local n = 0
		for _, m in sent do if m.action == "reward" and m.id == crown.id then n += 1 end end
		return n
	end
	local function crownLabel(view): any
		local c = canvas(5000, 1080)
		view.camX = crown.x
		view:draw(c, 1/60)
		local t = view.labels["reward_" .. crown.id]
		return if t and t.Visible then t.Text else nil
	end
	-- Climbed here before: gold, named, claimed on touch, then gone.
	v:setProgress({ best = crown.checkpoint, climbed = crown.checkpoint, summits = 0, rewards = {} })
	v:start(code, crown.checkpoint)
	assert(crownLabel(v) == string.upper(crown.name), `the crown waits, named: {tostring(crownLabel(v))}`)
	local before = claims()
	walkOnto(v)
	assert(claims() == before + 1, "touching it claims it from the server")
	assert(string.find(v.banner.Text, "UNLOCKED"), `and says so: {v.banner.Text}`)
	assert(crownLabel(v) == nil, "then it is gone")
	-- Skipped here: locked, and touching it claims nothing.
	v:setProgress({ best = crown.checkpoint, climbed = crown.checkpoint - 1, summits = 0, rewards = {} })
	v:start(code, crown.checkpoint - 1)
	v:skipTo(crown.checkpoint)
	assert(crownLabel(v) == "CLIMB HERE TO CLAIM", "a skipper sees it locked")
	before = claims()
	walkOnto(v)
	assert(claims() == before, "and cannot take it")
	-- Owned: not there at all.
	v:setProgress({ best = crown.checkpoint, climbed = crown.checkpoint, summits = 0, rewards = { crown.id } })
	v:start(code, crown.checkpoint)
	assert(crownLabel(v) == nil, "its owner does not see it")
	v:setProgress({ best = 0, summits = 0 })
end

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
