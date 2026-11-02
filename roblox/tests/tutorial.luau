--!nocheck
-- The first-time tutorial (the owner's ask, 2026-11-02): its lessons (client/Tutorial), its cards
-- (client/TutorialView) and its room (Rooms.tutorial).
--
-- The lessons are proved against the real simulation, not against hand-written events: a scripted
-- player runs the whole tutorial in a real Training match with the Sword against a still CPU,
-- doing what each card asks, and every lesson must be finished by the moves it teaches - an event
-- name or field the lesson waits for that the game never sends would leave a new player stuck.
--     lune run tests/tutorial
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Tutorial = Loader.loadFrom("src/client/", "Tutorial")
local Settings = Loader.load("Settings")
local Match = Loader.load("Match")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local Stages = Loader.load("Data/Stages")
local Weapons = Loader.load("Data/Weapons")
local Rooms = Loader.loadFrom("src/server/", "Rooms")

local function fail(msg: string): never error(msg, 0) end

-- 1. The rules of a lesson, by hand.
do
	local t = Tutorial.new(0)
	if t:lesson().id ~= "move" or t.phase ~= "card" or not t:stopped() then fail("the tutorial does not open on the first card, stopped") end
	-- a card up: nothing counts
	if t:frame({ x = 1 }, 0) then fail("a frame counted while a card was up") end
	if t:continue() ~= nil or t.phase ~= "goal" or t:stopped() then fail("CONTINUE did not hand the controls back") end
	for _ = 1, 44 do t:frame({ x = 1 }, 0) end
	t:frame({ x = 0 }, 0)
	if t.phase ~= "goal" or t.progress ~= 44 then fail("standing still counted as running") end
	t:frame({ x = -1 }, 1)
	if t.phase ~= "done" then fail("45 frames of running did not finish MOVE") end
	if t:goalText() ~= "DONE!" then fail("a finished lesson does not say so") end
	if t:tick(1 + Tutorial.DONE_HOLD - 0.01) ~= nil then fail("the next card came before the done was seen") end
	if t:tick(1 + Tutorial.DONE_HOLD) ~= "next" or t:lesson().id ~= "jump" or t.phase ~= "card" then fail("the next lesson's card did not come up") end
	t:continue()
	-- someone else's double jump is not yours
	t:event({ type = "doublejump", fighter = 1 }, 2)
	if t.progress ~= 0 then fail("the CPU's double jump counted for the player") end
	if t:goalText() ~= "Double jump  0 / 2" then fail(`the goal reads "{t:goalText()}"`) end
	t:event({ type = "doublejump", fighter = 0 }, 2)
	t:event({ type = "jump", fighter = 0 }, 2)
	if t.progress ~= 1 then fail("a single jump counted as a double") end
	-- the fight lesson sets the CPU fighting when its card is closed, never while it is up
	local f = Tutorial.new(0)
	f.index = #Tutorial.LESSONS
	if f:lesson().id ~= "fight" or not f:lesson().fight then fail("the last lesson is not the fight") end
	if f:continue() ~= "fight" then fail("closing the fight card did not set the CPU fighting") end
	f.phase = "card"
	if f:continue() ~= nil then fail("the CPU was set fighting twice") end
	f:event({ type = "ko", fighter = 1, by = 0 }, 0)
	f:event({ type = "ko", fighter = 0, by = 1 }, 0)
	if f.progress ~= 1 then fail("being knocked out counted as a knock-out") end
	f:event({ type = "ko", fighter = 1, by = 0 }, 0)
	if f.phase ~= "done" or f:tick(10) ~= "finished" or not f.finished or not f:stopped() then fail("the last lesson did not finish the tutorial") end
	-- every lesson shows real, rebindable keys, and its words fit its card
	for _, l in Tutorial.LESSONS do
		for _, k in l.keys do
			if not Settings.NAMES[k] then fail(`lesson {l.id} shows a key for "{k}", which is not an action`) end
		end
		if #l.body > 170 then fail(`lesson {l.id}'s card says {#l.body} characters; the card holds about 170`) end
		if (l.count == nil) == (l.held == nil) then fail(`lesson {l.id} must count events or held frames, one of them`) end
	end
	-- the aim lesson's moves are the Sword's own
	local sword = Weapons.BY_ID.Sword
	local up, down = false, false
	for _, m in sword.moves or {} do
		if string.find(m.id or "", "Up") then up = true end
		if string.find(m.id or "", "Down") then down = true end
	end
	if not (up and down) then fail("the Sword has no Up and Down moves for the aim lesson to wait for") end
end

-- 2. The whole tutorial, played in the real simulation by a scripted player who does what each
-- card says. Frames are the player's; the CPU stands still (as Rooms.tutorial makes it) until the
-- fight lesson, when it is set to "easy" exactly as the server does.
do
	local stage
	for _, s in Stages.LIST do if s.id == Rooms.TUTORIAL_STAGE then stage = s end end
	if not stage then fail(`the tutorial's stage {Rooms.TUTORIAL_STAGE} does not exist`) end
	local frames = {}
	local inputs = { poll = function() end, get = function(_, src) return frames[src] or Input.emptyFrame() end }
	local m = Match.new({ mode = "Training", stage = stage, stocks = 3, timeLimit = 600, items = false, weaponDrops = false,
		disasters = "off", input = inputs, seed = 12345,
		fighters = {
			{ char = Loadout.build("Classic", "Sword"), team = 0, source = "p1", isBot = false, botLevel = "normal", name = "You" },
			{ char = Loadout.build("Classic", "Sword"), team = 1, source = "bot2", isBot = true, botLevel = "dummy", name = "CPU" },
		} })
	local me, cpu = m.fighters[1], m.fighters[2]
	-- the still CPU must be where a new player can walk to: on the floor the player lands on
	do
		local probe = Match.new({ mode = "Training", stage = stage, stocks = 3, weaponDrops = false, disasters = "off", seed = 1,
			input = { poll = function() end, get = function() return Input.emptyFrame() end },
			fighters = { { char = Loadout.build("Classic", "Sword"), source = "a", isBot = true, botLevel = "dummy", team = 0 },
				{ char = Loadout.build("Classic", "Sword"), source = "b", isBot = true, botLevel = "dummy", team = 1 } } })
		for _ = 1, 600 do Match.step(probe); table.clear(probe.events) end
		local a, b = probe.fighters[1], probe.fighters[2]
		if math.abs(a.y - b.y) > 0.01 or math.abs(a.y - probe.stage.main.top) > 0.01 or #(stage.hazards or {}) > 0 then
			fail(`on {stage.id} the still CPU stands at y {b.y} and the player at y {a.y}: not both on the main floor, or the stage has hazards`)
		end
	end
	local t = Tutorial.new(0)
	local seen: { [string]: number } = {}
	local clock = 0
	local held = { jump = false, light = false, heavy = false, dodge = false, guard = false, grab = false }
	local function press(f, key)
		-- an edge only on the frame it goes down; held while it stays down
		f[key] = not held[key]
		held[key] = true
		f[key .. "Held"] = true
	end
	local tick = 0
	local finishedAt = nil
	for frame = 1, 60 * 240 do
		clock = frame / 60
		if t:stopped() and not t.finished then
			if t:continue() == "fight" then cpu.botLevel = "easy" end
		end
		local lesson = t:lesson()
		local f = Input.emptyFrame()
		local pressed = {}
		if m.state ~= "countdown" and lesson and t.phase == "goal" then
			tick += 1
			local dx = cpu.x - me.x
			local toward = if dx > 0 then 1 else -1
			local function approach(range) if math.abs(dx) > range then f.x = toward end end
			local id = lesson.id
			if id == "move" then
				f.x = if (tick // 60) % 2 == 0 then 1 else -1
			elseif id == "jump" then
				if tick % 50 == 1 or tick % 50 == 14 then pressed.jump = true end
			elseif id == "light" then
				approach(1.4)
				if math.abs(dx) <= 1.6 and tick % 24 == 0 then pressed.light = true end
			elseif id == "aim" then
				approach(1.4)
				if tick % 30 < 6 then f.y = if (tick // 30) % 2 == 0 then 1 else -1 end
				if tick % 30 == 2 then pressed.light = true end
			elseif id == "heavy" then
				approach(1.6)
				if math.abs(dx) <= 1.8 and tick % 50 == 0 then pressed.heavy = true end
			elseif id == "dodge" then
				f.x = if (tick // 40) % 2 == 0 then -1 else 1
				if tick % 40 == 5 then pressed.dodge = true end
			elseif id == "shield" then
				pressed.guard = true
			elseif id == "grab" then
				approach(0.9)
				if math.abs(dx) <= 1.2 and tick % 30 == 0 then pressed.grab = true end
			elseif id == "fight" then
				approach(1.6)
				if math.abs(dx) <= 1.8 then
					if tick % 45 == 0 then pressed.heavy = true elseif tick % 12 == 0 then pressed.light = true end
				end
				-- knocked off: back to the stage as the jump lesson taught (jumps, then up + heavy)
				local edge = m.stage.main
				if me.x < edge.x1 + 2 or me.x > edge.x2 - 2 or me.y < edge.top - 0.5 then
					f.x = if me.x > 0 then -1 else 1
					pressed.light, pressed.heavy = nil, nil
					if tick % 16 == 0 then pressed.jump = true end
					if me.y < edge.top - 2 and tick % 16 == 8 then f.y = 1; pressed.heavy = true end
				end
			end
		end
		for key in held do
			if pressed[key] then press(f, key) else held[key] = false end
		end
		frames.p1 = f
		if not t:stopped() then t:frame(f, clock) end
		Match.step(m)
		for _, e in m.events do
			seen[e.type] = (seen[e.type] or 0) + 1
			t:event(e, clock)
		end
		table.clear(m.events)
		local before = t.index
		t:tick(clock)
		if t.index ~= before then tick = 0 end
		if t.finished then finishedAt = frame; break end
	end
	if not t.finished then
		local l = t:lesson()
		local list = {}
		for k, n in seen do table.insert(list, `{k}={n}`) end
		table.sort(list)
		fail(`the scripted player was stuck on lesson {t.index} ({l and l.id}, {t.progress}/{l and l.need}) after 4 minutes; events: {table.concat(list, " ")}`)
	end
	if cpu.botLevel ~= "easy" then fail("the CPU was never set fighting") end
	print(`  (the scripted player finished all {#Tutorial.LESSONS} lessons in {math.floor(finishedAt / 60)} s of play)`)
end

-- 3. The room: the player's own, the Sword only, a still CPU, Training rules, nothing paid.
do
	local m = Rooms.new()
	local p = { UserId = 5, DisplayName = "P5" }
	local room, why = m:tutorial(p)
	if not room or why then fail("the tutorial room was refused") end
	if m:get(5) ~= room or room.state ~= "playing" then fail("the player is not in a running tutorial room") end
	local roster, opts = m:roster(room, function() return 1 end)
	if #roster ~= 2 or roster[1].player ~= p or roster[1].weapon ~= "Sword" or roster[1].kit[2] ~= "Sword" then fail("the tutorial is not the player with the Sword") end
	if roster[2].player or roster[2].botLevel ~= "dummy" then fail(`the tutorial's CPU plays {tostring(roster[2].botLevel)}, not standing still`) end
	if opts.mode ~= "Training" or opts.weaponDrops or not opts.tutorial or opts.stage ~= Rooms.TUTORIAL_STAGE or opts.items then
		fail("the tutorial's rules are not Training, Sword only, on its own stage")
	end
	room.tutorialBot = "easy"
	if select(1, m:roster(room))[2].botLevel ~= "easy" then fail("the fight lesson's CPU does not fight") end
	-- not twice, not from a room, and nothing left behind
	if m:tutorial(p) then fail("a second tutorial was opened over the first") end
	m:leave(p)
	if m:get(5) or m.rooms[room.id] then fail("leaving the tutorial left its room behind") end
	m:queue(p, "Duel")
	local queued = m:queued(5)
	local again = m:tutorial(p)
	if not again or m:queued(5) or not queued then fail("starting the tutorial from the queue did not leave the queue") end
	-- (Economy never pays a Training match: tests/economy holds that for every mode named Training)
end

-- 4. The cards on screen.
do
	local function signal()
		local fns = {}
		return { Connect = function(_, fn) table.insert(fns, fn) end, Fire = function() for _, fn in fns do fn() end end }
	end
	local function instance(class: string): any
		local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), Text = "", _children = {} }
		local self: any
		props.GetChildren = function() return table.clone(props._children) end
		props.IsA = function(_, c) return c == "GuiObject" and class ~= "UIListLayout" and class ~= "UICorner" and class ~= "UIStroke" end
		props.FindFirstChild = function(_, name, deep)
			local function look(node)
				for _, c in node._children do
					if c.Name == name then return c end
					if deep then local d = look(c); if d then return d end end
				end
				return nil
			end
			return look(self)
		end
		props.Destroy = function()
			local parent = props.Parent
			if parent then
				local i = table.find(parent._children, self)
				if i then table.remove(parent._children, i) end
			end
		end
		self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
			if key == "Parent" and value then table.insert(value._children, self) end
			props[key] = value
		end })
		return self
	end
	local codes = setmetatable({}, { __index = function(_, name) return name end })
	Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
	local calls = {}
	local View = Loader.loadFrom("src/client/", "TutorialView")
	local root = instance("Folder")
	local view = View.new(root, {
		keyOf = function(a) return ({ light = "J", heavy = "K", left = "A", right = "D", jump = "Space", up = "W", down = "S",
			dodge = "L", guard = "I", grab = "U", ult = "O" })[a] or "?" end,
		onStart = function() table.insert(calls, "start") end, onSkip = function() table.insert(calls, "skip") end,
		onContinue = function() table.insert(calls, "continue") end, onFinish = function() table.insert(calls, "finish") end,
	})
	local function find(node, name)
		for _, c in node._children do
			if c.Name == name then return c end
			local d = find(c, name)
			if d then return d end
		end
		return nil
	end
	view:offer()
	if not view.card.Visible or not view.gui.Enabled or view.mode ~= "offer" then fail("the offer is not on screen") end
	find(root, "Continue").Activated:Fire()
	if calls[1] ~= "start" or view.gui.Enabled then fail("START did not start the tutorial and close the offer") end
	local t = Tutorial.new(0)
	t.index = 3                                           -- LIGHT ATTACK
	view:render(t)
	if view.mode ~= "lesson" or not view.card.Visible or view.goal.Visible then fail("a lesson's card is not up alone") end
	if view.step.Text ~= `LESSON 3 / {#Tutorial.LESSONS}` or view.cardTitle.Text ~= "LIGHT ATTACK" then fail("the card names the wrong lesson") end
	local cap = find(find(view.keys, "Key_light"), "Key")
	if not cap or cap.Text ~= "J" then fail("the card does not show the player's own key for a light attack") end
	if not view.hint.Visible then fail("a keyboard's card does not say Enter continues") end
	-- on a touch screen: no Enter to press
	view.opts.touch = function() return true end
	view:render(t)
	if view.hint.Visible then fail("a touch screen's card says to press Enter") end
	view.opts.touch = nil
	view:pressContinue()
	if calls[2] ~= "continue" then fail("CONTINUE on a lesson did not continue") end
	t:continue()
	view:render(t)
	if view.card.Visible or not view.goal.Visible or view.goalKeys.Text ~= "J" or view.goalText.Text ~= "Land light attacks  0 / 3" then
		fail(`the goal is not on screen as the lesson runs: {view.goalText.Text} [{view.goalKeys.Text}]`)
	end
	-- LEAVE on the goal bar: a way out while a lesson runs
	if not find(view.goal, "Leave") then fail("a running lesson has no way out") end
	find(view.goal, "Leave").Activated:Fire()
	if calls[3] ~= "skip" then fail("LEAVE during a lesson did nothing") end
	if view.goal.Position.Y.Offset < 125 then fail("the goal bar sits over the HUD's ability pill (its foot is at 124)") end
	table.remove(calls, 3)
	find(root, "Skip").Activated:Fire()
	if calls[3] ~= "skip" then fail("SKIP TUTORIAL did nothing") end
	t.finished, t.phase = true, "finished"
	view:render(t)
	if view.mode ~= "end" or find(root, "Skip").Visible then fail("the end card offers to skip a finished tutorial") end
	if view.go.Text ~= "TO THE LOBBY" then fail("a replayed tutorial's end card does not go to the lobby") end
	-- the first time, it goes on to make your fighter (init.client opens the studio on its press)
	view.nextStep = "creator"
	view:render(t)
	if view.go.Text ~= "MAKE YOUR FIGHTER" then fail("a first tutorial's end card does not go on to the character studio") end
	view:pressContinue()
	if calls[4] ~= "finish" or view.gui.Enabled then fail("TO THE LOBBY did not finish the tutorial") end
end

print("PASS tutorial: nine lessons, each stopping the fight for its card and counting only the player's own moves; a scripted player finishes them all in the real simulation;")
print("  the CPU fights only once the last card is closed; the room is the player's own, Sword only, Training rules; the cards show the player's own keys")
