--!strict
-- Moving the touch controls (Roblox only; the owner's ask, 2026-11-02, after Fortnite's mobile HUD
-- editor): every control on screen at once, over a dimmed fight; drag one to move it, tap one to
-- choose it, then SMALLER / BIGGER; the buttons' see-through for all of them; RESET puts the chosen
-- one back (or, with none chosen, all of them); DONE keeps it. It edits this device's class - a
-- phone's and a tablet's layouts are kept apart (TouchLayout) - and says which.
local UIS = game:GetService("UserInputService")
local TouchLayout = require(game:GetService("ReplicatedStorage").Shared.TouchLayout)
local Ui = require(script.Parent.Ui)

local TouchEditor = {}
TouchEditor.__index = TouchEditor

TouchEditor.STEP = 0.1          -- SMALLER / BIGGER
TouchEditor.FADE = 0.1          -- the see-through steps

-- opts: { onDone = (custom) -> () }
function TouchEditor.new(parent: Instance?, opts: any): any
	local self = setmetatable({ opts = opts, custom = TouchLayout.sanitize(nil), selected = nil :: string?, dragging = nil :: any,
		views = {}, size = Vector2.new(0, 0) }, TouchEditor)
	local gui = Ui.make("ScreenGui", parent, { Name = "BlockfallTouchEditor", ResetOnSpawn = false, Enabled = false, DisplayOrder = 40,
		IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.gui = gui
	Ui.make("Frame", gui, { Name = "Dim", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1) })
	for _, c in TouchLayout.CONTROLS do
		local f = Ui.make("TextButton", gui, { Name = "Edit_" .. c.id, Text = "", AutoButtonColor = false, BackgroundColor3 = Ui.INK,
			BorderSizePixel = 0, ZIndex = 2 })
		Ui.make("UICorner", f, { CornerRadius = UDim.new(1, 0) })
		local stroke = Ui.stroke(f, Ui.WHITE, 3)
		local t = Ui.text(f, if c.id == "stick" then "MOVE" else (c.label or c.id), 14, Ui.WHITE, Ui.DISPLAY, true)
		t.Name, t.Size, t.TextScaled, t.ZIndex = "Label", UDim2.fromScale(1, 1), true, 3
		Ui.make("UITextSizeConstraint", t, { MaxTextSize = 18, MinTextSize = 9 })
		f.InputBegan:Connect(function(io: InputObject)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				self:select(c.id)
				self.dragging = { id = c.id, input = io }
			end
		end)
		self.views[c.id] = { frame = f, stroke = stroke }
	end
	-- the toolbar, top centre
	local bar = Ui.make("Frame", gui, { Name = "Bar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -20, 0, 92), BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0, ZIndex = 4 })
	Ui.make("UISizeConstraint", bar, { MaxSize = Vector2.new(560, 92) })
	Ui.make("UICorner", bar, { CornerRadius = UDim.new(0, 10) })
	Ui.stroke(bar, Ui.INK, 3)
	local title = Ui.text(bar, "", 15, Ui.TEXT, Ui.DISPLAY, true)
	title.Name, title.Position, title.Size, title.ZIndex = "Title", UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 20), 5
	self.title = title
	local note = Ui.text(bar, "", 12, Ui.SUB, Ui.LABEL, true)
	note.Name, note.Position, note.Size, note.ZIndex = "Note", UDim2.fromOffset(12, 26), UDim2.new(1, -24, 0, 16), 5
	self.note = note
	local row = Ui.make("Frame", bar, { Name = "Row", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 48), Size = UDim2.new(1, -16, 0, 36), ZIndex = 5 })
	Ui.make("UIListLayout", row, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	for i, b in { { "Smaller", "SMALLER", function() self:scale(-TouchEditor.STEP) end }, { "Bigger", "BIGGER", function() self:scale(TouchEditor.STEP) end },
		{ "Fainter", "FAINTER", function() self:fade(-TouchEditor.FADE) end }, { "Bolder", "BOLDER", function() self:fade(TouchEditor.FADE) end },
		{ "Reset", "RESET", function() self:reset() end }, { "Done", "DONE", function() self:done() end } } :: { { any } } do
		local btn = Ui.button(row, b[2], if b[1] == "Done" then Ui.GREEN elseif b[1] == "Reset" then Ui.RED else Ui.PANEL2, b[3], { small = true })
		btn.Name, btn.LayoutOrder, btn.Size, btn.ZIndex = b[1], i, UDim2.new(1 / 6, -5, 1, 0), 6
	end
	UIS.InputChanged:Connect(function(io: InputObject)
		local d = self.dragging
		if not d or not self.gui.Enabled then return end
		if io == d.input or (d.input.UserInputType == Enum.UserInputType.MouseButton1 and io.UserInputType == Enum.UserInputType.MouseMovement) then
			self:drag(d.id, io.Position.X, io.Position.Y)
		end
	end)
	UIS.InputEnded:Connect(function(io: InputObject)
		if self.dragging and (io == self.dragging.input or io.UserInputType == Enum.UserInputType.MouseButton1) then self.dragging = nil end
	end)
	return self
end

function TouchEditor.class(self: any): string
	return TouchLayout.class(self.size.X, self.size.Y)
end

-- Open on the player's layout (Settings.touch), sized for a screen of `size`.
function TouchEditor.open(self: any, custom: any, size: Vector2)
	self.custom, self.size, self.selected, self.dragging = TouchLayout.sanitize(custom), size, nil, nil
	self.gui.Enabled = true
	self:render()
end
function TouchEditor.isOpen(self: any): boolean
	return self.gui.Enabled == true
end

local function entry(self: any, id: string): any
	local mine = self.custom[self:class()]
	mine[id] = mine[id] or { dx = 0, dy = 0, s = 1 }
	return mine[id]
end
function TouchEditor.select(self: any, id: string?)
	self.selected = id
	self:render()
end
-- A control dragged so its centre is at (x, y).
function TouchEditor.drag(self: any, id: string, x: number, y: number)
	local e = entry(self, id)
	e.dx, e.dy = TouchLayout.offsetFor(self.size.X, self.size.Y, id, x, y)
	self.custom = TouchLayout.sanitize(self.custom)
	self:render()
end
-- The chosen control a step bigger or smaller.
function TouchEditor.scale(self: any, by: number)
	if not self.selected then return end
	local e = entry(self, self.selected)
	e.s += by
	self.custom = TouchLayout.sanitize(self.custom)     -- (which keeps it within SCALE_MIN..MAX)
	self:render()
end
-- Every control a step more or less see-through.
function TouchEditor.fade(self: any, by: number)
	self.custom.opacity = math.clamp(self.custom.opacity + by, TouchLayout.OPACITY_MIN, TouchLayout.OPACITY_MAX)
	self:render()
end
-- The chosen control back to its default; with none chosen, all of them (on this class).
function TouchEditor.reset(self: any)
	local class = self:class()
	if self.selected then self.custom[class][self.selected] = nil else self.custom[class] = {} end
	self.custom = TouchLayout.sanitize(self.custom)
	self:render()
end
function TouchEditor.done(self: any)
	self.gui.Enabled = false
	self.dragging = nil
	if self.opts.onDone then self.opts.onDone(TouchLayout.sanitize(self.custom)) end
end

function TouchEditor.render(self: any)
	local w, h = self.size.X, self.size.Y
	if w <= 0 or h <= 0 then return end
	local placed = TouchLayout.layout(w, h, self.custom)
	local clash: { [string]: boolean } = {}
	for _, pair in TouchLayout.overlaps(placed) do clash[pair[1]], clash[pair[2]] = true, true end
	local alpha = 1 - self.custom.opacity
	for _, c in TouchLayout.CONTROLS do
		local p, v = placed[c.id], self.views[c.id]
		v.frame.Position = UDim2.fromOffset(p.x - p.r, p.y - p.r)
		v.frame.Size = UDim2.fromOffset(p.r * 2, p.r * 2)
		v.frame.BackgroundTransparency = math.clamp(alpha + 0.25, 0, 1)
		v.stroke.Color = if self.selected == c.id then Ui.GOLD elseif clash[c.id] then Ui.RED else Ui.WHITE
		v.stroke.Thickness = if self.selected == c.id then 5 else 3
	end
	local class = self:class()
	self.title.Text = `TOUCH LAYOUT  ·  {if class == "tablet" then "TABLET" else "PHONE"}  ·  {math.floor(self.custom.opacity * 100 + 0.5)}% solid`
	self.note.Text = if next(clash) then "Red buttons overlap: a press may hit the wrong one."
		elseif self.selected then `{(TouchLayout.BY_ID[self.selected].label or "Stick")}: drag it, or SMALLER / BIGGER. RESET puts it back.`
		else "Drag a button to move it. Tap one to resize it. RESET with none chosen resets all."
end

return TouchEditor
