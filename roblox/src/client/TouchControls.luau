--!strict
-- The touch controls on screen (Roblox only; the owner's ask, 2026-11-02): a stick at the left, the
-- fight's buttons fanned at the right, where TouchLayout puts them for this screen and this player.
-- They feed InputClient like a third device - held actions and the stick's axes in
-- InputClient.touch, a press edge through InputClient.pressAction - so the fight, the lobby and the
-- climb all read them without knowing they are touches.
--
-- Every finger is its own: one on the stick and one holding SHIELD while a third taps ATTACK is
-- three touches, each tracked from where it went down until it lifts. A touch that went down on a
-- real button (gameProcessed: the lobby's prompt, a menu) is that button's, never a control's.
local UIS = game:GetService("UserInputService")
local TouchLayout = require(game:GetService("ReplicatedStorage").Shared.TouchLayout)
local Ui = require(script.Parent.Ui)

local TouchControls = {}
TouchControls.__index = TouchControls

-- A press anywhere within SLOP of a button's radius is that button's (the nearest, if two).
TouchControls.SLOP = 1.15
-- The stick takes a touch this far out from its centre, in radii (thumbs land wide of it).
TouchControls.STICK_REACH = 1.5

-- opts: { input = InputClient (its `touch` table and pressAction) }
function TouchControls.new(parent: Instance?, opts: any): any
	local self = setmetatable({ input = opts.input, context = "off", mode = "auto", custom = TouchLayout.sanitize(nil),
		lift = 0, placed = {}, owners = {}, held = {}, views = {}, size = Vector2.new(0, 0) }, TouchControls)
	local gui = Ui.make("ScreenGui", parent, { Name = "BlockfallTouch", ResetOnSpawn = false, Enabled = false, DisplayOrder = 12,
		IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.gui = gui
	for _, c in TouchLayout.CONTROLS do
		local f = Ui.make("Frame", gui, { Name = "Touch_" .. c.id, BackgroundColor3 = Ui.INK, BorderSizePixel = 0, Active = false })
		Ui.make("UICorner", f, { CornerRadius = UDim.new(1, 0) })
		local stroke = Ui.stroke(f, Ui.WHITE, 3)
		local view: any = { frame = f, stroke = stroke }
		if c.id == "stick" then
			local knob = Ui.make("Frame", f, { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.45, 0.45), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0 })
			Ui.make("UICorner", knob, { CornerRadius = UDim.new(1, 0) })
			view.knob = knob
		else
			local t = Ui.text(f, c.label or c.id, 14, Ui.WHITE, Ui.DISPLAY, true)
			t.Name, t.Size = "Label", UDim2.fromScale(1, 1)
			t.TextScaled = true
			Ui.make("UITextSizeConstraint", t, { MaxTextSize = 18, MinTextSize = 9 })
			Ui.make("UIPadding", t, { PaddingLeft = UDim.new(0.14, 0), PaddingRight = UDim.new(0.14, 0) })
			view.label = t
		end
		self.views[c.id] = view
	end
	self:bind()
	return self
end

-- Is this a touch screen (or have the settings switched the buttons on)?
function TouchControls.wanted(self: any): boolean
	if self.mode == "on" then return true end
	if self.mode == "off" then return false end
	local ok, touch = pcall(function() return UIS.TouchEnabled end)
	return ok and touch == true
end

-- The settings' touch mode and layout (Settings.touchMode, Settings.touch).
function TouchControls.apply(self: any, mode: string, custom: any)
	self.mode, self.custom = mode, TouchLayout.sanitize(custom)
	self:refresh()
end
-- "fight" (every control), "lobby" (the stick and JUMP, JUMP lifted over the lobby's buttons by
-- `lift` px) or "off".
function TouchControls.setContext(self: any, context: string, lift: number?)
	if context == self.context and (lift or 0) == self.lift then return end
	self.context, self.lift = context, lift or 0
	self:refresh()                        -- (off: refresh lets every finger go)
end

-- Is control `c` shown now?
function TouchControls.shows(self: any, c: any): boolean
	if self.context == "fight" then return true end
	return self.context == "lobby" and c.lobby == true
end

-- Lay the controls out for a screen of `size` (the GUI's AbsoluteSize).
function TouchControls.layout(self: any, size: Vector2)
	self.size = size
	self.placed = TouchLayout.layout(size.X, size.Y, self.custom, if self.context == "lobby" then self.lift else nil)
	local alpha = 1 - self.custom.opacity
	for _, c in TouchLayout.CONTROLS do
		local p, v = self.placed[c.id], self.views[c.id]
		v.frame.Position = UDim2.fromOffset(p.x - p.r, p.y - p.r)
		v.frame.Size = UDim2.fromOffset(p.r * 2, p.r * 2)
		v.frame.Visible = self:shows(c)
		v.frame.BackgroundTransparency = math.clamp(alpha + 0.25, 0, 1)
		v.stroke.Transparency = alpha
		if v.label then v.label.TextTransparency = alpha end
		if v.knob then v.knob.BackgroundTransparency = alpha end
	end
end

function TouchControls.refresh(self: any)
	local on = self.context ~= "off" and self:wanted()
	self.gui.Enabled = on
	if not on then self:releaseAll(); return end
	local size = self.gui.AbsoluteSize
	if size.X > 0 and size.Y > 0 then self:layout(size) end
end

-- The control a touch at (x, y) is on, or nil: the stick within its reach, a button within SLOP,
-- the nearest when two are in reach.
function TouchControls.hit(self: any, x: number, y: number): string?
	local best, bestD = nil, math.huge
	for _, c in TouchLayout.CONTROLS do
		local p = self.placed[c.id]
		if p and self:shows(c) then
			local d = math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2)
			local reach = p.r * (if c.id == "stick" then TouchControls.STICK_REACH else TouchControls.SLOP)
			if d <= reach and d / p.r < bestD then best, bestD = c.id, d / p.r end
		end
	end
	return best
end

-- A finger (any key: an InputObject, or a test's number) went down at (x, y). Returns the control.
function TouchControls.down(self: any, key: any, x: number, y: number): string?
	local id = self:hit(x, y)
	if not id then return nil end
	self.owners[key] = id
	if id == "stick" then
		self:moved(key, x, y)
	else
		local action = TouchLayout.BY_ID[id].action
		self.held[id] = (self.held[id] or 0) + 1
		self.input.touch.held[action] = true
		self.input.pressAction(action)
		self.views[id].frame.BackgroundTransparency = 0.1
	end
	return id
end
-- A finger moved: the stick follows it (clamped to its rim).
function TouchControls.moved(self: any, key: any, x: number, y: number)
	if self.owners[key] ~= "stick" then return end
	local p = self.placed.stick
	local dx, dy = (x - p.x) / p.r, (y - p.y) / p.r
	local len = math.sqrt(dx * dx + dy * dy)
	if len > 1 then dx, dy = dx / len, dy / len end
	self.input.touch.x, self.input.touch.y = dx, -dy         -- (up is positive to the game)
	self.views.stick.knob.Position = UDim2.fromScale(0.5 + dx * 0.5, 0.5 + dy * 0.5)
end
-- A finger lifted.
function TouchControls.up(self: any, key: any)
	local id = self.owners[key]
	if not id then return end
	self.owners[key] = nil
	if id == "stick" then
		self.input.touch.x, self.input.touch.y = 0, 0
		self.views.stick.knob.Position = UDim2.fromScale(0.5, 0.5)
	else
		self.held[id] = math.max(0, (self.held[id] or 1) - 1)
		if self.held[id] == 0 then
			self.input.touch.held[TouchLayout.BY_ID[id].action] = nil
			self:layout(self.size)
		end
	end
end
function TouchControls.releaseAll(self: any)
	for key in self.owners do self:up(key) end
	self.owners, self.held = {}, {}
	table.clear(self.input.touch.held)
	self.input.touch.x, self.input.touch.y = 0, 0
end

function TouchControls.bind(self: any)
	local function point(io: InputObject): (number, number)
		return io.Position.X, io.Position.Y
	end
	-- (a mouse drives them too when the settings switch them ON: a desktop can try the layout)
	local function ours(io: InputObject): boolean
		return io.UserInputType == Enum.UserInputType.Touch
			or (self.mode == "on" and io.UserInputType == Enum.UserInputType.MouseButton1)
	end
	UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if processed or not self.gui.Enabled or not ours(io) then return end
		self:down(io, point(io))
	end)
	UIS.InputChanged:Connect(function(io: InputObject)
		if self.owners[io] then self:moved(io, point(io))
		elseif self.mode == "on" and io.UserInputType == Enum.UserInputType.MouseMovement then
			-- (the mouse's button and its movement are different InputObjects)
			for key, id in self.owners do
				if id == "stick" and typeof(key) == "Instance" and (key :: any).UserInputType == Enum.UserInputType.MouseButton1 then self:moved(key, point(io)) end
			end
		end
	end)
	UIS.InputEnded:Connect(function(io: InputObject)
		if self.owners[io] then self:up(io) end
	end)
	self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:refresh() end)
end

return TouchControls
