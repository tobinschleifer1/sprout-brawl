--!nocheck
-- The character studio (AvatarEditor), driven through its real buttons. The stub below supplies
-- Instances, signals and value types; every behaviour is the editor's own.
--
-- What it proves: tiles show YOUR character with each option (and only redraw when their picture
-- changes); options, colours and presets apply; undo and redo; Randomise respects locks; the
-- keyboard walks options, parts and tabs; save / save-as-new / delete send what the server
-- expects; unsaved work is never dropped without asking; the layout fits phone, tablet and
-- desktop; and the preview draws the real fighter in every pose.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")

local function signal(): any
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function(_, ...) for _, fn in callbacks do fn(...) end end }
end
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), FocusLost = signal(), Text = "" }
	local children = {}
	local self: any
	props.GetPropertyChangedSignal = function() return signal() end
	props.GetChildren = function() return table.clone(children) end
	props.IsA = function(_, c) return props.ClassName == c end
	props.FindFirstChild = function(_, name)
		for _, child in children do if child.Name == name then return child end end
		return nil
	end
	props.Destroy = function()
		for _, child in table.clone(children) do child:Destroy() end
		if props.Parent then
			local siblings = props.Parent._children
			local at = table.find(siblings, self)
			if at then table.remove(siblings, at) end
		end
		props.destroyed = true
	end
	props._children = children
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		if key == "Parent" and props.Parent then
			local at = table.find(props.Parent._children, self)
			if at then table.remove(props.Parent._children, at) end
		end
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
local function click(root: any, name: string)
	local b = assert(find(root, name), "missing control " .. name)
	b.Activated:Fire()
end

local codes = setmetatable({}, { __index = function(_, name) return name end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, name) return name end })
local focused = false
local UIS = { GetFocusedTextBox = function() return focused end }

-- Drawing is recorded, not rendered: kit-draw.luau covers the real sprite.
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local sprites: { any } = {}
Canvas.sprite = function(c: any, key: string, list: any, ...: any)
	table.insert(sprites, { canvas = c, key = key, list = list })
end
local blocks = 0
Canvas.rect = function() blocks += 1 end
Canvas.ellipse = function() blocks += 1 end
Canvas.circle = function() blocks += 1 end
Canvas.tri = function() blocks += 1 end
Canvas.line = function() blocks += 1 end
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")

-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
local Editor = luau.load(fs.readFile("src/client/AvatarEditor.luau"), { debugName = "AvatarEditor", environment = {
	game = { GetService = function(_, name)
		if name == "ReplicatedStorage" then return { Shared = shared } end
		if name == "UserInputService" then return UIS end
		error("unexpected service " .. name)
	end },
	script = { Parent = codes },
	require = function(name)
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Instance = { new = instance }, Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim = Rbx.UDim, UDim2 = Rbx.UDim2,
	Enum = setmetatable({}, { __index = function() return codes end }),
}, injectGlobals = true })()

local AvatarKit = Loader.load("AvatarKit")
local KIT = AvatarKit.KIT
local function preset(id: string): string
	for _, p in KIT.presets do if p.id == id then return p.code end end
	error(id)
end
local KNIGHT, NINJA = preset("knight"), preset("ninja")

-- A deterministic stand-in for Roblox's Random (Lune has none).
local function rng(seed: number): any
	local s = seed
	return { NextInteger = function(_, a: number, b: number): number
		s = (s * 1103515245 + 12345) % 2147483648
		return a + s % (b - a + 1)
	end }
end

local sent: { any } = {}
local gui = instance("PlayerGui")
local ed = Editor.new(gui, { send = function(msg) table.insert(sent, msg) end, weapon = function() return "Sword" end, random = rng(3) })
ed:setView({ slots = { { name = "Hero", code = KNIGHT } }, active = 1, saving = true, max = 8 })
ed:layout(Rbx.Vector2.new(1280, 720))
ed:open()
local root = ed.gui
assert(ed:code() == KNIGHT and ed.name == "Hero" and not ed:dirty(), "the studio opens on the character you wear")

-- 1. Tiles are your character with each option.
local function tilesDrawn(): { [string]: string }
	local out = {}
	for id, t in ed.tiles do
		for _, sp in sprites do
			if sp.canvas == t.canvas then out[id] = string.match(sp.key, "^(k1%w+)|") end
		end
	end
	return out
end
click(root, "Group_hair")
assert(ed.category == "hair" and find(root, "Cat_hair") and find(root, "Cat_facialHair"), "the Hair tab holds hair and facial hair")
table.clear(sprites)
ed:renderTiles()                      -- nothing changed: nothing redrawn
assert(#sprites == 0, "tiles redrew without their pictures changing")
ed.tileKey = nil
ed:rebuildTiles()
local drawn = tilesDrawn()
local hairCat = AvatarKit.category("hair")
for _, o in hairCat.options do
	local code = assert(drawn[o.id], `no picture on the {o.id} tile`)
	local spec = AvatarKit.decode(code)
	assert(spec.parts.hair == o.id, `the {o.id} tile shows {spec.parts.hair}`)
	local mine = AvatarKit.decode(ed:code())
	mine.parts.hair = o.id
	assert(AvatarKit.encode(mine) == code, `the {o.id} tile is not your character with that hair`)
end

-- 2. Choosing an option applies it, is undoable, and redraws no tile.
table.clear(sprites)
click(root, "Option_afro")
assert(ed.spec.parts.hair == "afro" and ed:dirty() and ed.status.Text == "Unsaved changes", "picking a hair did not apply it")
local tileSprites = 0
for _, sp in sprites do for _, t in ed.tiles do if sp.canvas == t.canvas then tileSprites += 1 end end end
assert(tileSprites == 0, "picking an option redrew the option tiles")
assert(ed.tiles.afro.pick.Enabled and not ed.tiles.crew.pick.Enabled, "the picked tile is not the one marked")
-- A colour recolours the tiles (they show your colours).
click(root, "Swatch_hair_11")
assert(ed.spec.colours.hair == 11, "the swatch did not paint the hair")
local after = tilesDrawn()
assert(after.crew and AvatarKit.decode(after.crew).colours.hair == 11, "the tiles did not take the new hair colour")
ed:undo()
assert(ed.spec.colours.hair ~= 11 and ed.spec.parts.hair == "afro", "undo did not step back one change")
ed:undo()
assert(ed:code() == KNIGHT and not ed:dirty(), "two undos should be back at the saved knight")
ed:redo()
assert(ed.spec.parts.hair == "afro", "redo did not reapply")

-- 3. Randomise respects locks: lock the hair and its colour survives twenty rolls; everything
--    else changes.
click(root, "Lock")
assert(ed.locks.hair and ed.lockButton.Text == "LOCKED", "the lock did not lock")
ed:selectCategory("brows")
click(root, "Lock")                   -- hair and brows are the only parts painted in hair colour
local hair, hairColour = ed.spec.parts.hair, ed.spec.colours.hair
local r = rng(7)
local changedTop, changedColour = false, false
for _ = 1, 20 do
	local top = ed.spec.parts.top
	ed:randomize(r)
	assert(ed.spec.parts.hair == hair, "Randomise changed locked hair")
	if ed.spec.parts.top ~= top then changedTop = true end
	if ed.spec.colours.hair ~= hairColour then changedColour = true end
end
-- Facial hair is also drawn in hair colour and is NOT locked, so the colour is still free.
assert(changedColour, "a colour shared with an unlocked part was frozen")
-- facial hair is painted in hair colour and is not locked, so the colour is free to change; lock it too
ed:selectCategory("facialHair")
click(root, "Lock")
hairColour = ed.spec.colours.hair
for _ = 1, 20 do
	ed:randomize(r)
	assert(ed.spec.colours.hair == hairColour, "Randomise changed a colour every part of which is locked")
end
assert(changedTop, "Randomise never changed an unlocked part")
for _, id in { "hair", "brows", "facialHair" } do ed:toggleLock(id) end

-- 4. Random part: a different option every press.
ed:selectCategory("eyes")
for _ = 1, 10 do
	local before = ed.spec.parts.eyes
	click(root, "RandomPart")
	assert(ed.spec.parts.eyes ~= before, "RANDOM PART left the part as it was")
end

-- 5. The keyboard.
local eyes = ed.spec.parts.eyes
ed:key("Right", false)
assert(ed.spec.parts.eyes ~= eyes, "Right did not step the option")
ed:key("Left", false)
assert(ed.spec.parts.eyes == eyes, "Left did not step back")
ed:key("Down", false)
assert(ed.category == "brows", `Down should move to the next part (brows), went to {ed.category}`)
ed:key("E", false)
assert(ed.group == "hair", `E should move to the next tab, went to {ed.group}`)
local before = ed:code()
ed:pick("hair", "bald")
ed:key("Z", true)
assert(ed:code() == before, "Ctrl+Z did not undo")
focused = true
ed:key("Right", false)
assert(ed:code() == before, "typing a name moved the option")
focused = false

-- 6. Presets.
click(root, "Group_presets")
assert(find(root, "Preset_ninja") and not ed.lockButton.Visible, "the Presets tab lists presets, with no part lock")
click(root, "Preset_ninja")
assert(ed:code() == NINJA and ed.tiles.ninja.pick.Enabled, "a preset did not put the whole character on")

-- 7. Save, save as new, delete.
ed.nameBox.Text = "  Kage <3  "
ed.nameBox.FocusLost:Fire()
assert(ed.name == "Kage 3", `the name should be cleaned as the server cleans it, got "{ed.name}"`)
click(root, "Save")
local msg = sent[#sent]
assert(msg.action == "save" and msg.slot == 1 and msg.code == NINJA and msg.name == "Kage 3", "Save did not send the character")
ed:setView({ slots = { { name = "Kage 3", code = NINJA } }, active = 1, saving = true, max = 8 })
assert(not ed:dirty() and string.find(ed.status.Text, "Saved"), "a confirmed save should leave nothing unsaved")
assert(ed.saveButton.Text == "WEARING", "the character you wear should say so")
ed:pick("hair", "mohawk")
click(root, "SaveNew")
assert(sent[#sent].slot == 2 and sent[#sent].action == "save", "SAVE AS NEW should use the next slot")
ed:setView({ slots = { { name = "Kage 3", code = NINJA }, { name = "Kage 3", code = sent[#sent].code } }, active = 2, saving = true, max = 8 })
assert(ed.editing == 2 and not ed:dirty(), "after saving as new you are editing the new character")
assert(find(root, "Slot_1") and find(root, "Slot_2") and find(root, "SlotNew"), "the slot strip shows both characters and a +")
click(root, "Delete")
assert(ed.confirmBox.Visible, "Delete must ask first")
click(root, "Yes")
assert(sent[#sent].action == "delete" and sent[#sent].slot == 2, "Delete sent the wrong request")
ed:setView({ slots = { { name = "Kage 3", code = NINJA } }, active = 1, saving = true, max = 8 })
assert(ed.editing == 1 and ed:code() == NINJA, "after a delete you edit the character that remains")

-- 8. Unsaved work is never dropped without asking.
ed:pick("hair", "afro")
ed:setView({ slots = { { name = "Kage 3", code = NINJA }, { name = "Two", code = KNIGHT } }, active = 1, saving = true, max = 8 })
click(root, "Slot_2")
assert(ed.confirmBox.Visible and ed.editing == 1, "switching character with unsaved changes must ask")
click(root, "No")
assert(ed.spec.parts.hair == "afro", "saying No lost the edit")
click(root, "Slot_2")
click(root, "Yes")
assert(ed.editing == 2 and ed:code() == KNIGHT, "saying Yes should open the other character")
ed:pick("hair", "afro")
click(root, "Close")
assert(ed.confirmBox.Visible and ed:isOpen(), "closing with unsaved changes must ask")
click(root, "Yes")
assert(not ed:isOpen() and ed:code() == KNIGHT, "closing without saving should throw the edit away")
ed:open()

-- 9. Saving off: said, not hidden.
ed:setView({ slots = { { name = "Kage 3", code = NINJA } }, active = 1, saving = false, max = 8, note = "Saving is off right now." })
assert(string.find(ed.status.Text, "Saving is off"), "the studio must say when saving is off")

-- A whole character is one of the rig's two bodies: the jointed one at full detail, or the eight
-- pieces with one-piece limbs at half. Nothing missing, nothing doubled, nothing of one mixed into the other.
local BODIES = {
	["abdomen,arm,arm,chest,head,leg,leg,pelvis"] = 8,
	["abdomen,chest,forearm,forearm,head,pelvis,shin,shin,thigh,thigh,upperarm,upperarm"] = 12,
}
local function body(pieces: { string }): number?
	local sorted = table.clone(pieces)
	table.sort(sorted)
	return BODIES[table.concat(sorted, ",")]
end

-- 10. The preview is the real fighter, in every pose, and leaves team colours alone.
Fighter2D.teamColours = { [0] = Rbx.Color3.new(1, 0, 0) }
for _, p in Editor.POSES do
	click(root, "Pose_" .. p[1])
	table.clear(sprites)
	ed:draw(10 + math.random())
	local mine = {}
	for _, sp in sprites do if string.find(sp.key, ed:code(), 1, true) == 1 then table.insert(mine, string.match(sp.key, "|(%a+)|")) end end
	assert(body(mine) == 12, `{p[1]}: the preview drew {table.concat(mine, ",")}, want the character's whole jointed body`)
end
assert(Fighter2D.teamColours and Fighter2D.teamColours[0], "the preview cleared the match's team colours")
Fighter2D.teamColours = nil

-- 11. Layout: phone, tablet, desktop. The panes sit inside the panel and do not overlap.
local function rect(f: any): { number }
	return { f.Position.X.Offset, f.Position.Y.Offset, f.Size.X.Offset, f.Size.Y.Offset }
end
local function overlap(a: { number }, b: { number }): boolean
	return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end
for _, size in { { 390, 844 }, { 1024, 768 }, { 1920, 1080 }, { 1366, 768 } } do
	ed:layout(Rbx.Vector2.new(size[1], size[2]))
	local W, H = ed.size.X, ed.size.Y
	local preview, editor = rect(ed.preview), rect(ed.editor)
	local footerTop = H - ed.footer.Size.Y.Offset
	for name, r0 in { preview = preview, editor = editor } do
		assert(r0[1] >= 0 and r0[2] >= 56 and r0[1] + r0[3] <= W and r0[2] + r0[4] <= footerTop, `{size[1]}x{size[2]}: the {name} pane leaves its space`)
		assert(r0[3] > 150 and r0[4] > 150, `{size[1]}x{size[2]}: the {name} pane is too small ({r0[3]}x{r0[4]})`)
	end
	assert(not overlap(preview, editor), `{size[1]}x{size[2]}: preview and editor overlap`)
	local cell = ed.gridLayout.CellSize.X.Offset
	assert(cell >= 64 and math.floor((editor[3] - 16) / (cell + 8)) >= 2, `{size[1]}x{size[2]}: option tiles are {cell}px, fewer than two a row`)
	assert(ed.grid.Size.Y.Offset >= 80, `{size[1]}x{size[2]}: no room for the option grid`)
	assert(ed.wide == (size[1] >= 760 and size[1] >= size[2] * 1.05), "the wrong arrangement for this shape")
end
-- Earned parts: shown behind a lock and not wearable until earned; picking one says where it is
-- earned; the arrows and Randomise pass over it; earning it (the server's `unlocked`) opens it.
do
	ed:setView({ slots = { { name = "Kage 3", code = NINJA } }, active = 1, saving = true, max = 8 })
	ed:layout(Rbx.Vector2.new(1280, 720))
	ed:selectGroup("extras")
	ed:selectCategory("headwear")
	local tile = assert(ed.tiles.skylineCrown, "the Skyline Crown has a tile")
	assert(tile.label.Text == "LOCKED · Skyline Crown", `it is shown locked: {tile.label.Text}`)
	local before = ed:code()
	click(root, "Option_skylineCrown")
	assert(ed:code() == before and string.find(ed.status.Text, "Crown Perch", 1, true) and string.find(ed.status.Text, "level 19", 1, true),
		`picking it changes nothing and says where it is earned: {ed.status.Text}`)
	-- The arrows skip it: the option before it steps round to the first.
	local opts = AvatarKit.category("headwear").options
	ed:pick("headwear", opts[#opts - 1].id)
	ed:step(1)
	assert(ed.spec.parts.headwear == opts[1].id, `stepping past the locked crown lands on {ed.spec.parts.headwear}`)
	-- Randomise never hands one out.
	local r = rng(11)
	for _ = 1, 300 do
		ed:randomize(r)
		assert(ed.spec.parts.headwear ~= "skylineCrown" and ed.spec.parts.neck ~= "summitMantle", "Randomise gave out an earned part")
	end
	ed:selectCategory("neck")
	for _ = 1, 100 do
		ed:randomizePart("neck", r)
		assert(ed.spec.parts.neck ~= "summitMantle", "Random part gave out the mantle")
	end
	-- Earned: unlocked, labelled plainly, and wearable.
	ed:selectCategory("headwear")
	ed:setView({ slots = { { name = "Kage 3", code = NINJA } }, active = 1, saving = true, max = 8, unlocked = { "skylineCrown" } })
	assert(ed.tiles.skylineCrown.label.Text == "Skyline Crown", "earned while looking at it, it loses its lock")
	click(root, "Option_skylineCrown")
	assert(ed.spec.parts.headwear == "skylineCrown", "and can be worn")
end
-- the chosen tab is gold, the others are not
do
	local Ui = Loader.loadFrom("src/client/", "Ui")
	ed:selectGroup("hair")
	assert(ed.groupButtons.hair.BackgroundColor3 == Ui.GOLD and ed.groupButtons.body.BackgroundColor3 ~= Ui.GOLD, "the chosen tab is not the gold one")
	ed:selectGroup("body")
	assert(ed.groupButtons.body.BackgroundColor3 == Ui.GOLD and ed.groupButtons.hair.BackgroundColor3 ~= Ui.GOLD, "the gold tab did not follow the choice")
end
print("PASS creator: tiles show your character per option and redraw only on change; options, colours, presets, undo/redo; locked Randomise; keyboard; save / save-as-new / delete; unsaved work guarded; saving-off said; real fighter preview in five poses; phone, tablet and desktop layouts")
