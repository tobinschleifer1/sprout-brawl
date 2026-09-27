--!strict
-- Execute the real lobby's button callbacks. This stub only supplies Instances/signals/value
-- types; no selection or launch logic is copied into the test.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local function signal(): any
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function() for _, fn in callbacks do fn() end end }
end
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, AbsoluteSize = Rbx.Vector2.new(1024,768), Activated = signal() }
	local children, changed = {}, {}
	local self: any
	props.GetChildren = function() return table.clone(children) end
	props.FindFirstChild = function(_, name)
		for _, child in children do if child.Name == name then return child end end
		return nil
	end
	props.GetPropertyChangedSignal = function(_, name)
		changed[name] = changed[name] or signal()
		return changed[name]
	end
	props.Destroy = function()
		self:ClearAllChildren()
		if props.Parent then
			local siblings = props.Parent._children
			local at = table.find(siblings, self)
			if at then table.remove(siblings, at) end
		end
	end
	props.ClearAllChildren = function() for _, child in table.clone(children) do child:Destroy() end end
	props._children = children
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		props[key] = value
		if key == "Parent" then table.insert(value._children, self) end
		if changed[key] then changed[key]:Fire() end
	end })
	return self
end
local codes = setmetatable({}, { __index = function(_, name) return name end })
local shared = setmetatable({ Data = codes }, { __index = function(_, name) return name end })
local Select = luau.load(fs.readFile("src/client/Select.luau"), { environment = {
	game = { GetService = function() return { Shared = shared } end }, script = { Parent = { Bindings = "Bindings" } },
	require = function(name)
		if name == "Bindings" then return Loader.loadFrom("src/client/", name) end
		return Loader.load(if name == "MatchConfig" then name else "Data/" .. name)
	end,
	Enum = { Font = codes, TextXAlignment = codes, TextYAlignment = codes, ScrollingDirection = codes },
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2, Instance = { new = instance },
}, injectGlobals = true })()
local function child(root: any, name: string): any
	return assert(root:FindFirstChild(name), "missing UI control " .. name)
end
local function click(root: any, name: string) child(root, name).Activated:Fire() end
local menu = Select.new(instance("PlayerGui"))
menu:show()
click(menu.nav, "Opponents")
assert(menu:count() == 1, "bots are off by default")
click(child(menu.content,"Slot2"), "Toggle")
click(child(menu.content,"Slot3"), "Toggle")
click(child(menu.content,"Slot4"), "Toggle")
assert(menu:count() == 4, "Add CPU must make a four-fighter roster")
click(child(menu.content,"Slot4"), "hard")
assert(menu.cfg.slots[4].type == "bot-hard" and menu:count() == 4, "difficulty changes independently of count")
click(child(menu.content,"Slot4"), "Toggle")
assert(menu:count() == 3 and child(child(menu.content,"Slot4"),"Toggle").Text == "+ ADD CPU", "removed CPU must show its empty state")
click(menu.nav,"Loadout")
local old = menu.cfg
menu.cfg = Loader.load("MatchConfig").default()
menu.cfg.slots[2].type = "bot-normal" -- this launch test explicitly opts into a CPU
click(menu.content,"WeaponHammer")
assert(not menu.content:FindFirstChild("AvatarNoir"), "the fight setup must not offer an avatar: characters are made at the wardrobe")
assert(menu.cfg.slots[1].weaponId == "Hammer", "rematch callbacks must edit current cfg")
assert(old.slots[1].weaponId == "Sword", "callbacks must not mutate detached cfg")
click(menu.nav,"Rules")
click(menu.content,"Stocks5")
click(menu.content,"Itemsfalse")
assert(menu.cfg.stocks == 5 and not menu.cfg.items, "stocks and items are independent settings")
click(menu.nav,"Arenas")
assert(#menu.content:GetChildren() >= 8, "all six arena cards must be present")
click(child(menu.content,"Undertow"),"ChooseArena")
assert(menu.cfg.stageId == "Undertow", "arena card must choose its real stage")
click(menu.nav,"Controls")
for _, id in { "ult", "guard", "pickup" } do
	assert(#child(child(menu.content,id),"Keys").Text > 15, "required action must show keyboard and pad bindings")
end
local starts = 0
menu.onStart = function(cfg)
	starts += 1
	assert(cfg == menu.cfg)
	menu:waiting("Requesting…")
end
menu.start.Activated:Fire()
menu.start.Activated:Fire()
assert(starts == 1 and menu.gui.Enabled and not menu.start.Active, "double click cannot launch twice or hide lobby before snapshot")
menu:show("Retry")
assert(menu.start.Active, "failed request can be retried")
menu:navigate("Opponents")
menu.cfg.slots[2].type = "off"
menu:refresh()
menu.start.Activated:Fire()
assert(starts == 1 and not menu.start.Active, "Fight disabled without an opponent")

for _, vp in { Rbx.Vector2.new(360,640), Rbx.Vector2.new(800,600), Rbx.Vector2.new(1280,900) } do
	menu.gui.AbsoluteSize = vp
	for _, page in {"Home","Arenas","Loadout","Opponents","Rules","Controls"} do
		menu:navigate(page)
		assert(menu.content.Size.Y.Offset > 0, "content viewport must be positive")
		assert(menu.content.Position.Y.Offset + menu.content.Size.Y.Offset <= menu.summary.Position.Y.Offset, "content must not overlap footer")
		assert(menu.start.Position.Y.Offset + menu.start.Size.Y.Offset <= menu.panel.Size.Y.Offset, "Fight must remain within panel")
		for _, node in menu.content:GetChildren() do
			assert(node.Position.X.Offset >= 0 and node.Position.X.Offset + node.Size.X.Offset <= menu.content.Size.X.Offset, "content must fit horizontally")
		end
	end
end
menu.cfg = Loader.load("MatchConfig").default()
local closed = 0
menu.onClose = function() closed += 1 end
menu:openStation({ id = "armoury", name = "ARMOURY", kind = "Loadout" })
assert(menu.gui.Enabled and not menu.nav.Visible and menu.panel.Size.X.Offset <= 660, "station opens a compact panel, not the main lobby")
click(menu.content, "WeaponPike")
menu.start.Activated:Fire()
assert(not menu.gui.Enabled and closed == 1 and starts == 1, "leaving a workstation must return to the world, not launch a fight")
assert(menu.cfg.slots[1].weaponId == "Pike", "station choice persists after closing")
menu.cfg.slots[2].type = "bot-normal" -- legacy gate launch explicitly enables its opponent
menu:openStation({ id = "Undertow", name = "Undertow", kind = "Gate" })
assert(menu.cfg.stageId == "Undertow" and child(menu.content, "Heading").Text == "Undertow", "door chooses its own arena")
assert(menu.start.Text:find("ENTER ARENA", 1, true), "arena confirmation clearly enters this door")
click(menu.panel, "BackToHub")
assert(not menu.gui.Enabled and closed == 2)
local Launch = Loader.loadFrom("src/client/", "LaunchState")
local launch = Launch.new()
assert(launch:begin(1) and not launch:begin(2), "only one pending launch")
assert(not launch:expired(8.9) and launch:expired(9), "missing acknowledgement must time out")
assert(launch:begin(10), "timeout permits retry")
launch:accept(11)
assert(launch.phase == "loading", "Match alone is not playable")
launch:ready()
assert(not launch:expired(100) and launch.phase == "playing", "a live match must not time out")
launch:reset()
assert(launch.phase == "lobby")
print("PASS lobby: real buttons, rematch state, opponent controls, all pages at three sizes, bindings, launch timeout/retry")
