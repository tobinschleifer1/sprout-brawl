--!nocheck
-- The touch controls at run time (client/TouchControls) and their editor (client/TouchEditor):
-- every finger its own, a button held for as long as it is pressed and pressed once when it goes
-- down, the stick's axes clamped to its rim with up positive, the lobby showing only the stick and
-- JUMP, nothing shown or held with no touch screen or with a window up; the editor storing a drag
-- where it was dropped, resizing the chosen button, fading them all, finding overlaps, resetting
-- one or all, per class, and handing back what Settings would keep.
--     lune run tests/touch-controls
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local TouchLayout = Loader.load("TouchLayout")
local function fail(msg: string): never error(msg, 0) end

local function signal()
	local fns = {}
	return { Connect = function(_, fn) table.insert(fns, fn) end, Fire = function(_, ...) for _, fn in fns do fn(...) end end }
end
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), InputBegan = signal(), Text = "", _children = {},
		AbsoluteSize = Rbx.Vector2.new(0, 0) }
	local self: any
	props.GetChildren = function() return table.clone(props._children) end
	props.GetPropertyChangedSignal = function() return signal() end
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		if key == "Parent" and value then table.insert(value._children, self) end
		props[key] = value
	end })
	return self
end
local codes = setmetatable({}, { __index = function(_, name) return name end })
local enum = setmetatable({}, { __index = function() return codes end })
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = enum }
local uis = { TouchEnabled = false, InputBegan = signal(), InputChanged = signal(), InputEnded = signal() }
local function load(name: string): any
	return luau.load(fs.readFile("src/client/" .. name .. ".luau"), { debugName = name, environment = {
		game = { GetService = function(_, s) if s == "UserInputService" then return uis end return { Shared = { TouchLayout = "TouchLayout" } } end },
		script = { Parent = { Ui = "Ui" } },
		require = function(n) if n == "Ui" then return Loader.loadFrom("src/client/", "Ui") end return TouchLayout end,
		Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Vector2 = Rbx.Vector2, Color3 = Rbx.Color3, Enum = enum,
		typeof = function(v) return type(v) end,
	}, injectGlobals = true })()
end
local Controls, Editor = load("TouchControls"), load("TouchEditor")
local Ui = Loader.loadFrom("src/client/", "Ui")

-- 1. At run time.
local presses = {}
local input = { touch = { held = {}, x = 0, y = 0 }, pressAction = function(a) table.insert(presses, a) end }
local tc = Controls.new(instance("Folder"), { input = input })
tc.gui.AbsoluteSize = Rbx.Vector2.new(812, 375)
-- no touch screen, AUTO: nothing shown
tc:apply("auto", nil)
tc:setContext("fight")
if tc.gui.Enabled then fail("the touch buttons show on a screen with no touch") end
uis.TouchEnabled = true
tc:refresh()
if not tc.gui.Enabled then fail("the touch buttons do not show on a touch screen") end
tc:apply("off", nil)
if tc.gui.Enabled then fail("touch buttons switched OFF still show") end
uis.TouchEnabled = false
tc:apply("on", nil)
if not tc.gui.Enabled then fail("touch buttons switched ON do not show without a touch screen") end
-- placed where TouchLayout says (to the pixel: Roblox's offsets are whole pixels)
local placed = TouchLayout.layout(812, 375)
for _, c in TouchLayout.CONTROLS do
	local f, p = tc.views[c.id].frame, placed[c.id]
	if math.abs(f.Position.X.Offset - (p.x - p.r)) > 1 or math.abs(f.Size.X.Offset - p.r * 2) > 1 or not f.Visible then fail(`{c.id} is not where the layout puts it: {f.Position.X.Offset} vs {p.x - p.r}, {f.Size.X.Offset} vs {p.r * 2}, {tostring(f.Visible)}`) end
end
-- a button: pressed once as it goes down, held while it is down
local L = placed.light
if tc:down(1, L.x, L.y) ~= "light" or presses[1] ~= "light" or not input.touch.held.light then fail("ATTACK did not press and hold") end
if tc:down(2, placed.guard.x + placed.guard.r * 1.1, placed.guard.y) ~= "guard" then fail("a press just outside SHIELD's edge missed it") end
if #presses ~= 2 or not input.touch.held.guard then fail("SHIELD was not held by a second finger") end
tc:up(1)
if input.touch.held.light or not input.touch.held.guard then fail("lifting one finger let go of the wrong button") end
-- two fingers on one button: held until both lift
tc:down(3, L.x, L.y); tc:down(4, L.x + 2, L.y)
tc:up(3)
if not input.touch.held.light then fail("ATTACK let go while a second finger still held it") end
tc:up(4); tc:up(2)
if next(input.touch.held) then fail("every finger lifted but a button is still held") end
-- the stick: up positive, clamped to its rim, back to rest when lifted
local S = placed.stick
if tc:down(5, S.x + S.r * 0.5, S.y) ~= "stick" or math.abs(input.touch.x - 0.5) > 1e-6 or input.touch.y ~= 0 then fail("the stick does not read a half push right") end
tc:moved(5, S.x, S.y - S.r * 3)
if math.abs(input.touch.y - 1) > 1e-6 or math.abs(input.touch.x) > 1e-6 then fail(`the stick pushed far up reads {input.touch.x},{input.touch.y}, not 0,1`) end
tc:moved(5, S.x - S.r, S.y + S.r)
if math.abs(math.sqrt(input.touch.x ^ 2 + input.touch.y ^ 2) - 1) > 1e-6 or input.touch.x >= 0 or input.touch.y >= 0 then fail("the stick is not clamped to its rim, down-left") end
tc:up(5)
if input.touch.x ~= 0 or input.touch.y ~= 0 then fail("the stick did not return to rest") end
if #presses ~= 4 then fail("the stick pressed a button") end
-- nothing under the finger: nothing
if tc:down(6, 406, 140) ~= nil then fail("a touch on empty screen took a control") end
-- the lobby: the stick and JUMP only, JUMP lifted over its row
tc:setContext("lobby", 96)
for _, c in TouchLayout.CONTROLS do
	if tc.views[c.id].frame.Visible ~= (c.lobby == true) then fail(`the lobby shows {c.id}: {tostring(tc.views[c.id].frame.Visible)}`) end
end
local lobbyLight = TouchLayout.layout(812, 375, nil, 96).light
if tc:down(7, lobbyLight.x, lobbyLight.y) ~= nil then fail("a hidden ATTACK took a press in the lobby") end
local lobbyJump = TouchLayout.layout(812, 375, nil, 96).jump
if tc:down(8, lobbyJump.x, lobbyJump.y) ~= "jump" then fail("the lobby's JUMP is not where its layout puts it") end
-- a window up: every finger let go
tc:setContext("off")
if tc.gui.Enabled or next(input.touch.held) or next(tc.owners) then fail("turning the controls off left something held") end
-- the player's own layout and see-through
tc:apply("on", { phone = { light = { dx = -1, dy = 1, s = 1.5 } }, opacity = 0.4 })
tc:setContext("fight")
local mine = TouchLayout.layout(812, 375, tc.custom).light
if math.abs(tc.views.light.frame.Position.X.Offset - (mine.x - mine.r)) > 1 or math.abs(tc.views.light.stroke.Transparency - 0.6) > 1e-6 then
	fail("the player's own layout or see-through was not applied")
end

-- 2. The editor.
local kept
local ed = Editor.new(instance("Folder"), { onDone = function(c) kept = c end })
ed:open(nil, Rbx.Vector2.new(812, 375))
if not ed:isOpen() or not string.find(ed.title.Text, "PHONE", 1, true) then fail("the editor does not say it edits the phone's layout") end
ed:drag("light", 500, 200)
local p = TouchLayout.layout(812, 375, ed.custom).light
if math.abs(p.x - 500) > 0.01 or math.abs(p.y - 200) > 0.01 then fail("a dragged button is not where it was dropped") end
if math.abs(ed.views.light.frame.Position.X.Offset - (p.x - p.r)) > 1 then fail("the editor did not redraw a dragged button") end
-- SMALLER and BIGGER: the chosen one only, within bounds
ed:select("light")
for _ = 1, 20 do ed:scale(Editor.STEP) end
if ed.custom.phone.light.s ~= TouchLayout.SCALE_MAX or ed.custom.phone.jump then fail("BIGGER did not stop at its most, or touched another") end
ed:select(nil)
ed:scale(Editor.STEP)
-- see-through, for all
for _ = 1, 20 do ed:fade(-Editor.FADE) end
if math.abs(ed.custom.opacity - TouchLayout.OPACITY_MIN) > 1e-6 then fail("FAINTER did not stop at its least") end
-- overlaps shown in red
ed:drag("heavy", 500, 200)
if ed.views.heavy.stroke.Color ~= Ui.RED or not string.find(ed.note.Text, "overlap", 1, true) then fail("two buttons on top of each other are not shown") end
-- RESET: the chosen one, then (none chosen) all
ed:select("heavy")
ed:reset()
if ed.custom.phone.heavy or not ed.custom.phone.light then fail("RESET with HEAVY chosen did not put back HEAVY alone") end
ed:select(nil)
ed:reset()
if next(ed.custom.phone) then fail("RESET with nothing chosen did not put back every button") end
-- a tablet edits the tablet's
ed:open({ phone = { jump = { dx = 1, dy = 0, s = 1 } } }, Rbx.Vector2.new(1180, 820))
ed:drag("jump", 900, 500)
if not string.find(ed.title.Text, "TABLET", 1, true) or not ed.custom.tablet.jump or ed.custom.phone.jump.dx ~= 1 then fail("a tablet's edit was not kept apart from the phone's") end
ed:done()
if ed:isOpen() or not kept or not kept.tablet.jump or kept.phone.jump.dx ~= 1 then fail("DONE did not hand back the layout") end
local again = TouchLayout.sanitize(kept)
if again.tablet.jump.dx ~= kept.tablet.jump.dx then fail("what DONE handed back would not be kept as it is") end

print("PASS touch controls: AUTO on touch screens, ON and OFF; placed as laid out; every finger its own, a button pressed once and held till its last finger lifts;")
print("  the stick up-positive and clamped, at rest when let go; the lobby's stick and JUMP; nothing held when off; the editor's drag, size, fade, overlaps, reset and classes")
