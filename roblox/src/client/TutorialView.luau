--!strict
-- The tutorial on screen (Tutorial holds the lessons): the offer a first-time player sees in the
-- lobby, each lesson's card (the fight stopped behind it), the goal along the top while the player
-- does it, and the card at the end. Sibling ZIndex, so nothing here can be drawn under its own
-- window as the Shop's balance was.
local Ui = require(script.Parent.Ui)
local Tutorial = require(script.Parent.Tutorial)

local TutorialView = {}
TutorialView.__index = TutorialView

TutorialView.CARD_W, TutorialView.CARD_H = 560, 300
TutorialView.GOAL_Y = 132

-- opts: { keyOf = (action) -> string (the key's name as the menu writes it), onContinue, onSkip,
-- onStart, onFinish }
function TutorialView.new(parent: Instance?, opts: any): any
	local self = setmetatable({ opts = opts }, TutorialView)
	local gui = Ui.make("ScreenGui", parent, { Name = "BlockfallTutorial", ResetOnSpawn = false, Enabled = false,
		DisplayOrder = 30, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.gui = gui
	-- the stopped fight dimmed behind a card
	local dim = Ui.make("Frame", gui, { Name = "Dim", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false })
	self.dim = dim

	-- the card: a lesson's, the end's, or the lobby's offer
	local card = Ui.panel(gui, "Card", Ui.BLUE, "LESSON", 44)
	card.AnchorPoint, card.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0.92, 0, 0, TutorialView.CARD_H)
	Ui.make("UISizeConstraint", card, { MaxSize = Vector2.new(TutorialView.CARD_W, TutorialView.CARD_H) })
	card.Visible = false
	self.card = card
	self.cardTitle = card:FindFirstChild("Title", true)
	local step = Ui.text(card, "", 14, Ui.SUB, Ui.LABEL, true)
	step.Name, step.AnchorPoint, step.Position, step.Size = "Step", Vector2.new(1, 0), UDim2.new(1, -14, 0, 12), UDim2.fromOffset(120, 20)
	step.TextXAlignment, step.ZIndex = Enum.TextXAlignment.Right, 3
	self.step = step
	local body = Ui.text(card, "", 17, Ui.TEXT, Ui.LABEL, true)
	body.Name, body.Position, body.Size = "Body", UDim2.fromOffset(18, 58), UDim2.new(1, -36, 0, 92)
	body.TextWrapped, body.TextXAlignment, body.TextYAlignment = true, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
	self.body = body
	-- the keys this lesson uses, on caps, each with what it does
	local keys = Ui.make("Frame", card, { Name = "Keys", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 156),
		Size = UDim2.new(1, -36, 0, 64) })
	Ui.make("UIListLayout", keys, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center })
	self.keys = keys
	local go = Ui.button(card, "CONTINUE", Ui.GREEN, function() self:pressContinue() end)
	go.Name, go.AnchorPoint, go.Position, go.Size = "Continue", Vector2.new(1, 1), UDim2.new(1, -18, 1, -16), UDim2.fromOffset(180, 46)
	self.go = go
	local hint = Ui.text(card, "or press Enter", 13, Ui.SUB, Ui.LABEL, true)
	hint.Name, hint.AnchorPoint, hint.Position, hint.Size = "Hint", Vector2.new(1, 1), UDim2.new(1, -206, 1, -26), UDim2.fromOffset(120, 20)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	self.hint = hint
	local skip = Ui.button(card, "SKIP TUTORIAL", Ui.shade(Ui.PANEL2, -0.2), function() if self.opts.onSkip then self.opts.onSkip() end end)
	skip.Name, skip.AnchorPoint, skip.Position, skip.Size = "Skip", Vector2.new(0, 1), UDim2.new(0, 18, 1, -16), UDim2.fromOffset(160, 40)
	self.skip = skip

	-- the goal, top centre, while the player does it - under the HUD's clock, key hints and ability
	-- pill (Hud: the pill's foot is at 124)
	local goal = Ui.make("Frame", gui, { Name = "Goal", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TutorialView.GOAL_Y),
		Size = UDim2.fromOffset(440, 64), BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0, Visible = false })
	Ui.make("UICorner", goal, { CornerRadius = UDim.new(0, 10) })
	Ui.stroke(goal, Ui.INK, 3)
	local goalTitle = Ui.text(goal, "", 13, Ui.SUB, Ui.LABEL, true)
	goalTitle.Name, goalTitle.Position, goalTitle.Size = "GoalTitle", UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 18)
	goalTitle.TextXAlignment = Enum.TextXAlignment.Left
	local goalText = Ui.text(goal, "", 20, Ui.TEXT, Ui.DISPLAY, true)
	goalText.Name, goalText.Position, goalText.Size = "GoalText", UDim2.fromOffset(14, 26), UDim2.new(1, -110, 0, 30)
	goalText.TextXAlignment = Enum.TextXAlignment.Left
	local goalKeys = Ui.text(goal, "", 15, Ui.TEXT, Ui.DISPLAY, true)
	goalKeys.Name, goalKeys.AnchorPoint, goalKeys.Position, goalKeys.Size = "GoalKeys", Vector2.new(1, 0), UDim2.new(1, -14, 0, 26), UDim2.fromOffset(90, 30)
	goalKeys.TextXAlignment = Enum.TextXAlignment.Right
	local bar = Ui.make("Frame", goal, { Name = "Bar", BackgroundColor3 = Ui.GREEN, BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 1, -7), Size = UDim2.new(0, 0, 0, 4) })
	self.goal, self.goalTitle, self.goalText, self.goalKeys, self.goalBar = goal, goalTitle, goalText, goalKeys, bar
	-- a way out while a lesson runs, not only from a card (a player who cannot land the grab, or the
	-- knock-outs, must never be left to quit Roblox to get out)
	local leave = Ui.button(goal, "LEAVE", Ui.shade(Ui.PANEL2, -0.2), function() if self.opts.onSkip then self.opts.onSkip() end end, { small = true })
	leave.Name, leave.AnchorPoint, leave.Position, leave.Size = "Leave", Vector2.new(0, 0.5), UDim2.new(1, 10, 0.5, 0), UDim2.fromOffset(76, 34)
	self.leave = leave
	return self
end

-- The keys of `actions`, as the player has them now: "J" or "W / S + J".
function TutorialView.keyLine(self: any, actions: { string }): string
	local out = {}
	for _, a in actions do table.insert(out, self.opts.keyOf(a)) end
	return table.concat(out, "  ")
end

local function showKeys(self: any, lesson: any)
	for _, c in self.keys:GetChildren() do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for i, action in lesson.keys do
		local cell = Ui.make("Frame", self.keys, { Name = "Key_" .. action, BackgroundTransparency = 1, LayoutOrder = i,
			Size = UDim2.fromOffset(110, 64) })
		local cap = Ui.keycap(cell, self.opts.keyOf(action), 18)
		cap.AnchorPoint, cap.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0)
		cap.Size = UDim2.fromOffset(math.max(44, Ui.textWidth(self.opts.keyOf(action), 18, Ui.DISPLAY) + 18), 38)
		local what = Ui.text(cell, TutorialView.ACTION_WORDS[action] or action, 12, Ui.SUB, Ui.LABEL, true)
		what.Name, what.Position, what.Size = "What", UDim2.fromOffset(0, 42), UDim2.new(1, 0, 0, 18)
	end
end
TutorialView.ACTION_WORDS = { left = "left", right = "right", up = "up", down = "down", jump = "jump", light = "light",
	heavy = "heavy", dodge = "dodge", guard = "shield (hold)", grab = "grab", ult = "ultimate" }

-- Draw the tutorial `t` (Tutorial) as it stands.
function TutorialView.render(self: any, t: any)
	self.gui.Enabled = true
	local lesson = t:lesson()
	local carding = t.phase == "card" and lesson ~= nil
	self.dim.Visible = carding or t.finished
	self.card.Visible = carding or t.finished
	self.goal.Visible = not carding and not t.finished and lesson ~= nil
	self.mode = if t.finished then "end" elseif carding then "lesson" else nil
	if carding then
		self.cardTitle.Text = lesson.title
		self.step.Text = `LESSON {t.index} / {#Tutorial.LESSONS}`
		self.body.Text = lesson.body
		self.go.Text = if lesson.fight then "FIGHT!" else "CONTINUE"
		self.skip.Visible = true
		showKeys(self, lesson)
		self.keys.Visible = true
	elseif t.finished then
		self.cardTitle.Text = "YOU'RE READY"
		self.step.Text = ""
		self.body.Text = "That's every move you need. Press PLAY in the lobby to find a real fight - you start against "
			.. "players near your own level, and CPUs that go easy on you."
		-- (a first-time player goes on to make their fighter: init.client sets `nextStep`)
		self.go.Text = if self.nextStep == "creator" then "MAKE YOUR FIGHTER" else "TO THE LOBBY"
		self.skip.Visible = false
		self.keys.Visible = false
	elseif lesson then
		self.goalTitle.Text = `LESSON {t.index} / {#Tutorial.LESSONS}  ·  {lesson.title}`
		self.goalText.Text = t:goalText()
		self.goalText.TextColor3 = if t.phase == "done" then Ui.GREEN else Ui.TEXT
		self.goalKeys.Text = self:keyLine(lesson.keys)
		self.goalBar.Size = UDim2.new(math.clamp(t.progress / lesson.need, 0, 1), -6, 0, 4)
	end
end

-- The offer in the lobby, the first time: learn, or skip it.
function TutorialView.offer(self: any)
	self.gui.Enabled = true
	self.mode = "offer"
	self.dim.Visible, self.card.Visible, self.goal.Visible = true, true, false
	self.cardTitle.Text = "WELCOME TO BLOCKFALL"
	self.step.Text = ""
	self.body.Text = "New here? A short tutorial (about three minutes) teaches you to move, attack, dodge and shield - with a Sword, "
		.. "against a CPU that waits for you. You can replay it any time from Settings."
	self.go.Text = "START"
	self.skip.Visible = true
	self.keys.Visible = false
end

function TutorialView.hide(self: any)
	self.mode = nil
	self.gui.Enabled = false
end

-- CONTINUE (or Enter): what it means depends on the card up.
function TutorialView.pressContinue(self: any)
	local mode = self.mode
	if mode == "offer" then
		self:hide()
		if self.opts.onStart then self.opts.onStart() end
	elseif mode == "lesson" then
		if self.opts.onContinue then self.opts.onContinue() end
	elseif mode == "end" then
		self:hide()
		if self.opts.onFinish then self.opts.onFinish() end
	end
end

return TutorialView
