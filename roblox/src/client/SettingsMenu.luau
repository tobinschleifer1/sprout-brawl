--!strict
-- SETTINGS (Roblox only; the owner's ask, 2026-11-02): music and sound volume, screen shake, the
-- hints, the tutorial again, and every key. Settings (shared) decides what may be set and keeps it
-- whole; this draws it and hands each change to `onChange` (init.client applies it and sends it to
-- be saved).
--
-- Rebinding: press an action's key, then the key you want. Escape cancels. A key another action
-- had first is swapped with this one's old key, and the menu says which.
local Settings = require(game:GetService("ReplicatedStorage").Shared.Settings)
local Bindings = require(script.Parent.Bindings)
local Ui = require(script.Parent.Ui)

local SettingsMenu = {}
SettingsMenu.__index = SettingsMenu

SettingsMenu.HEAD = 60
SettingsMenu.ROW = 40
SettingsMenu.STEP = 0.1          -- what - and + move a volume by

-- `defaults`: the keyboard as the game ships it (a copy of Bindings.keyboard taken before any
-- settings were applied). opts: { onChange = (settings) -> (), onTutorial = () -> () }
function SettingsMenu.new(parent: Instance?, defaults: { [string]: { string } }, opts: any): any
	local self = setmetatable({ opts = opts, defaults = defaults, settings = Settings.sanitize(nil), rows = {},
		listening = nil :: string?, note = "" }, SettingsMenu)
	local root = Ui.make("ScreenGui", parent, { Name = "BlockfallSettings", ResetOnSpawn = false, Enabled = false, DisplayOrder = 22,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.root = root
	local HEAD = SettingsMenu.HEAD
	local panel = Ui.panel(root, "Settings", Ui.INDIGO, "SETTINGS", HEAD)
	panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.new(1, -24, 1, -90)
	Ui.make("UISizeConstraint", panel, { MaxSize = Vector2.new(720, 620) })
	self.panel = panel
	Ui.closeButton(panel, function() self:close() end, HEAD)
	local body = Ui.make("ScrollingFrame", panel, { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, HEAD + 12), Size = UDim2.new(1, -28, 1, -(HEAD + 24)), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
	Ui.make("UIListLayout", body, { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder })
	Ui.make("UIPadding", body, { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4) })
	self.body = body
	local order = 0
	local function nextOrder(): number order += 1; return order end
	local function heading(text: string)
		local h = Ui.text(body, text, 18, Ui.TEXT, Ui.DISPLAY, true)
		h.Name, h.LayoutOrder, h.Size, h.TextXAlignment = "Head_" .. text, nextOrder(), UDim2.new(1, 0, 0, 26), Enum.TextXAlignment.Left
	end
	local function row(name: string): any
		local r = Ui.make("Frame", body, { Name = name, BackgroundTransparency = 1, LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, SettingsMenu.ROW) })
		return r
	end
	local function label(r: any, text: string): any
		local t = Ui.text(r, text, 16, Ui.TEXT, Ui.LABEL, true)
		t.Name, t.Size, t.TextXAlignment = "Label", UDim2.new(0.45, 0, 1, 0), Enum.TextXAlignment.Left
		return t
	end

	-- SOUND: two volumes, each - [bar] +
	heading("SOUND")
	self.volumes = {}
	for _, v in { { "music", "Music" }, { "sfx", "Sound effects" } } do
		local key = v[1]
		local r = row("Volume_" .. key)
		label(r, v[2])
		local minus = Ui.button(r, "-", Ui.PANEL2, function() self:nudge(key, -SettingsMenu.STEP) end)
		minus.Name, minus.AnchorPoint, minus.Position, minus.Size = "Down", Vector2.new(0, 0.5), UDim2.new(0.45, 0, 0.5, 0), UDim2.fromOffset(36, 34)
		local track = Ui.make("Frame", r, { Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.45, 44, 0.5, 0),
			Size = UDim2.new(0.55, -140, 0, 14), BackgroundColor3 = Ui.PANEL2, BorderSizePixel = 0 })
		Ui.stroke(track, Ui.INK, 2)
		local fill = Ui.make("Frame", track, { Name = "Fill", BackgroundColor3 = Ui.GREEN, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) })
		local plus = Ui.button(r, "+", Ui.PANEL2, function() self:nudge(key, SettingsMenu.STEP) end)
		plus.Name, plus.AnchorPoint, plus.Position, plus.Size = "Up", Vector2.new(1, 0.5), UDim2.new(1, -48, 0.5, 0), UDim2.fromOffset(36, 34)
		local pct = Ui.text(r, "", 15, Ui.TEXT, Ui.DISPLAY, true)
		pct.Name, pct.AnchorPoint, pct.Position, pct.Size = "Value", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(44, 30)
		pct.TextXAlignment = Enum.TextXAlignment.Right
		self.volumes[key] = { fill = fill, value = pct }
	end

	-- GAME: switches, and the tutorial again
	heading("GAME")
	self.switches = {}
	for _, v in { { "shake", "Screen shake" }, { "hints", "Control hints in a fight" } } do
		local key = v[1]
		local r = row("Switch_" .. key)
		label(r, v[2])
		local b = Ui.button(r, "", Ui.GREEN, function() self:flip(key) end)
		b.Name, b.AnchorPoint, b.Position, b.Size = "Toggle", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(96, 34)
		self.switches[key] = b
	end
	local tr = row("Tutorial")
	label(tr, "Learn the moves")
	local tb = Ui.button(tr, "PLAY TUTORIAL", Ui.BLUE, function()
		self:close()
		if self.opts.onTutorial then self.opts.onTutorial() end
	end)
	tb.Name, tb.AnchorPoint, tb.Position, tb.Size = "StartTutorial", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(170, 34)

	-- TOUCH: the on-screen buttons of a phone or tablet, and their layout (TouchControls, TouchEditor)
	heading("TOUCH")
	local mr = row("TouchMode")
	label(mr, "Touch buttons")
	local mode = Ui.button(mr, "", Ui.PANEL2, function() self:cycleTouch() end)
	mode.Name, mode.AnchorPoint, mode.Position, mode.Size = "Mode", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(150, 34)
	self.touchMode = mode
	local lr = row("TouchLayout")
	label(lr, "Move and resize them")
	local edit = Ui.button(lr, "EDIT LAYOUT", Ui.BLUE, function()
		self:close()
		if self.opts.onEditTouch then self.opts.onEditTouch() end
	end)
	edit.Name, edit.AnchorPoint, edit.Position, edit.Size = "EditTouch", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(150, 34)

	-- CONTROLS: every action and its keys
	heading("CONTROLS")
	local note = Ui.text(body, "Press a key box, then the key you want. Escape cancels.", 13, Ui.SUB, Ui.LABEL, true)
	note.Name, note.LayoutOrder, note.Size, note.TextXAlignment = "KeyNote", nextOrder(), UDim2.new(1, 0, 0, 20), Enum.TextXAlignment.Left
	note.TextWrapped = true
	self.keyNote = note
	for _, action in Settings.ACTIONS do
		local r = row("Key_" .. action)
		label(r, Settings.NAMES[action])
		local b = Ui.button(r, "", Ui.PANEL2, function() self:listen(action) end)
		b.Name, b.AnchorPoint, b.Position, b.Size = "Bind", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(150, 34)
		self.rows[action] = b
	end
	local rr = row("ResetKeys")
	local reset = Ui.button(rr, "RESET KEYS", Ui.shade(Ui.RED, -0.1), function() self:resetKeys() end)
	reset.Name, reset.AnchorPoint, reset.Position, reset.Size = "Reset", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(150, 34)
	self:render()
	return self
end

-- The settings now (from the saved record, on join).
function SettingsMenu.set(self: any, s: any)
	self.settings = Settings.sanitize(s)
	self:render()
end
local function changed(self: any)
	self:render()
	if self.opts.onChange then self.opts.onChange(self.settings) end
end
function SettingsMenu.nudge(self: any, key: string, by: number)
	local s = table.clone(self.settings)
	s[key] = (s[key] or 0) + by
	self.settings = Settings.sanitize(s)
	changed(self)
end
function SettingsMenu.flip(self: any, key: string)
	local s = table.clone(self.settings)
	s[key] = not s[key]
	self.settings = Settings.sanitize(s)
	changed(self)
end
-- AUTO (on a touch screen) -> ON -> OFF.
SettingsMenu.TOUCH_MODES = { "auto", "on", "off" }
function SettingsMenu.cycleTouch(self: any)
	local s = table.clone(self.settings)
	local i = table.find(SettingsMenu.TOUCH_MODES, s.touchMode) or 1
	s.touchMode = SettingsMenu.TOUCH_MODES[i % #SettingsMenu.TOUCH_MODES + 1]
	self.settings = Settings.sanitize(s)
	changed(self)
end
-- The layout the editor kept (TouchEditor's DONE).
function SettingsMenu.setTouch(self: any, custom: any)
	local s = table.clone(self.settings)
	s.touch = custom
	self.settings = Settings.sanitize(s)
	changed(self)
end
-- Waiting for the key to give `action`.
function SettingsMenu.listen(self: any, action: string)
	self.listening = if self.listening == action then nil else action
	self.note = if self.listening then `Press the key for {Settings.NAMES[action]}.` else ""
	self:render()
end
-- A key pressed while the menu is open (KeyCode name). Returns whether the menu used it.
function SettingsMenu.key(self: any, name: string): boolean
	local action = self.listening
	if not action then return false end
	self.listening = nil
	if name == "Escape" then
		self.note = ""
		self:render()
		return true
	end
	local s, swapped = Settings.bind(self.settings, self.defaults, action, name)
	if not s then
		self.note = swapped or "That key cannot be used."
		self:render()
		return true
	end
	self.settings = s
	self.note = if swapped then `{Settings.keyName(name)} was {Settings.NAMES[swapped]}'s key: it has {Settings.keyName(Settings.first(s, self.defaults, swapped))} now.`
		else `{Settings.NAMES[action]}: {Settings.keyName(name)}.`
	changed(self)
	return true
end
function SettingsMenu.resetKeys(self: any)
	self.listening = nil
	self.settings = Settings.resetKeys(self.settings)
	self.note = "Every key is back to how the game ships."
	changed(self)
end

function SettingsMenu.render(self: any)
	local s = self.settings
	for key, v in self.volumes do
		v.fill.Size = UDim2.fromScale(s[key], 1)
		v.value.Text = `{math.floor(s[key] * 100 + 0.5)}%`
	end
	for key, b in self.switches do
		b.Text = if s[key] then "ON" else "OFF"
		Ui.paint(b, if s[key] then Ui.GREEN else Ui.shade(Ui.PANEL2, -0.2))
	end
	self.touchMode.Text = if s.touchMode == "on" then "ON" elseif s.touchMode == "off" then "OFF" else "AUTO"
	local kb = Settings.keyboard(s, self.defaults)
	for action, b in self.rows do
		local names = {}
		for _, k in kb[action] do table.insert(names, Settings.keyName(k)) end
		b.Text = if self.listening == action then "press a key…" else table.concat(names, " / ")
		Ui.paint(b, if self.listening == action then Ui.GOLD else Ui.PANEL2)
	end
	self.keyNote.Text = if self.note ~= "" then self.note else "Press a key box, then the key you want. Escape cancels."
end

function SettingsMenu.open(self: any)
	self.listening, self.note = nil, ""
	self:render()
	self.root.Enabled = true
end
function SettingsMenu.close(self: any)
	self.listening = nil
	self.root.Enabled = false
end
function SettingsMenu.toggle(self: any)
	if self.root.Enabled then self:close() else self:open() end
end
function SettingsMenu.isOpen(self: any): boolean
	return self.root.Enabled == true
end

-- (Bindings is required for the shipped keys' shape; init.client passes the copy)
SettingsMenu.Bindings = Bindings
return SettingsMenu
