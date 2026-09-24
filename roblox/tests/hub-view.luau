--!strict
-- The real Hub2D controller and render path, with input/Instances and drawing primitives mocked.
-- Proves proximity, input edges, modal blocking, finite geometry and bounded drawing, not aesthetics.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Input = Loader.load("Input")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local WeaponArt = Loader.loadFrom("src/client/", "Weapons2D")
local drawWeapon = WeaponArt.draw
local drawnWeapons = {}
WeaponArt.draw = function(c, id, ...)
	drawnWeapons[id] = true
	return drawWeapon(c, id, ...)
end
local codes = setmetatable({}, { __index = function(_, key) return key end })
local shared = setmetatable({ Data = { Hub = "Data/Hub", Stages = "Data/Stages", Weapons = "Data/Weapons" } }, { __index = function(_, key) return key end })
local eDown, focused = false, false
local function instance(): any
	local obj: any = { attributes = {} }
	obj.Destroy = function() obj.destroyed = true end
	obj.Activated = { Connect = function(_, fn) obj.activate = fn end }
	obj.SetAttribute = function(_, key, value) obj.attributes[key] = value end
	return obj
end
local Hub = luau.load(fs.readFile("src/client/Hub2D.luau"), { environment = {
	game = { GetService = function(_, name)
		if name == "ReplicatedStorage" then return { Shared = shared } end
		return { GetFocusedTextBox = function() return focused end,
			IsKeyDown = function(_, key) return eDown and key == "E" end,
			IsGamepadButtonDown = function() return false end }
	end },
	script = { Parent = codes },
	require = function(name)
		if name == "InputClient" then return { new = function() return {
			frame = Input.emptyFrame(), sample = function(self) return { self.frame } end, reset = function() end,
		} end } end
		if fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2,
	Enum = { Font = codes, KeyCode = codes, UserInputType = codes }, Instance = { new = instance },
}, injectGlobals = true })()
local cfg = Loader.load("MatchConfig").default()
local hub = Hub.new({})
hub:show(cfg)
local opened = 0
hub.onInteract = function() opened += 1 end
eDown = false
hub:step(1/60, false)
hub:interact()
assert(opened == 0, "spawn is not a clickable remote menu; must approach a station")
hub.input.frame.x = 1
for _ = 1, 36 do hub:step(1/60, false) end
assert(hub.model.fighter.x > 7, "movement input must move the on-screen hub fighter")
hub.model.fighter.x, hub.model.fighter.y = 14, 0
hub.input.frame.x = 0
eDown = true
hub:step(1/60, false)
hub:step(1/60, false)
assert(opened == 1, "holding interact must open exactly once")
hub:step(1/60, true)
hub:interact()
assert(opened == 1, "station panel blocks underlying interaction")
eDown, focused = false, true
hub:step(1/60, false)
eDown = true
hub:step(1/60, false)
assert(opened == 1, "typing E in chat must not open a door")
focused = false

local function primitive(c: any, ...: any)
	for _, value in { ... } do
		if type(value) == "number" then assert(value == value and math.abs(value) < math.huge, "finite hub geometry") end
	end
	c.used += 1
end
Canvas.rect, Canvas.circle, Canvas.ellipse = primitive, primitive, primitive
local peak = 0
hub:setPeers({ {userId=2,name="Guest",avatar="Noir",weapon="Hammer",x=14,y=0,facing=1,moving=true},
	{userId=1,name="Self",avatar="Classic",weapon="Sword",x=14,y=0,facing=1} }, 1)
assert(hub.peers[2] and not hub.peers[1], "shared lobby renders peers, not a duplicate local player")
for _, size in { {360,640}, {1280,720}, {1920,1080} } do
	for _, station in Loader.load("Data/Hub").stations do
		hub.model.fighter.x, hub.model.fighter.y = station.x, 0
		hub.camX = station.x
		local c = setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {},
			m = {a=1,b=0,c=0,d=1,e=0,f=0}, gui = {AbsoluteSize={X=size[1],Y=size[2]}},
			finish = function(self) self.drawn = self.used; self.used = 0 end,
		}, {__index=Canvas})
		hub:draw(c, 1/60)
		assert(c.drawn > 100 and c.drawn < 750, "hub must draw real but bounded scenery")
		assert(#c.stack == 0, "hub leaves no transforms behind for the arena renderer")
		assert(hub.gui.attributes.NearbyStation == station.id, "visible prompt names the nearby world station")
		peak = math.max(peak, c.drawn)
	end
end
local tag = hub.peers[2].tag
hub:setPeers({}, 1)
assert(not hub.peers[2] and tag.destroyed, "departed players are removed from the lobby")
local returnX = hub.model.fighter.x
for index, format in { "Duel", "Doubles", "Triples" } do
	local view = { id = index, format = format, stage = "FoundryFloor", slots = { {userId=1,ready=false} } }
	hub:setRoom(view)
	assert(hub.model.data.id == "Prep" .. format and hub.model.fighter.x == -53, "confirmed room enters its physical preparation bay")
	assert(hub.gui.attributes.RoomId == index, "room identity exposed for live QA")
	for _, station in hub.model.data.stations do
		hub.model.fighter.x, hub.model.fighter.y = station.x, 0
		hub:setRoom(view)
		assert(hub.model.fighter.x == station.x, "ready/loadout refresh cannot teleport the player")
		hub.camX = station.x
		drawnWeapons = {}
		local c = setmetatable({ used=0,stack={},alpha=1,alphaStack={},m={a=1,b=0,c=0,d=1,e=0,f=0},
			gui={AbsoluteSize={X=1280,Y=720}},finish=function(self) self.drawn=self.used;self.used=0 end },{__index=Canvas})
		hub:draw(c,1/60)
		assert(c.drawn>100 and c.drawn<1200, "room scenery including twelve rack weapons stays bounded")
		assert(#c.stack==0 and hub.gui.attributes.NearbyStation==station.id, "station art and prompt align with physical station")
		if station.id == "Weapons" then
			for _, weapon in Loader.load("Data/Weapons").LIST do
				assert(drawnWeapons[weapon.id], "physical rack must display every actual weapon: " .. weapon.id)
			end
		end
	end
	hub:setPeers({{userId=2,area=0,name="Outsider",avatar="Classic",weapon="Sword",x=0,y=0,facing=1}},1)
	assert(not hub.peers[2], "stale concourse presence cannot leak into the preparation room")
end
hub:setRoom({left=true})
assert(hub.model.data.id=="IronConcourse" and hub.model.fighter.x==returnX,"leaving returns to the entrance, not a setup screen")
hub:hide()
local x = hub.model.fighter.x
hub.input.frame.x = 1
hub:step(1/60, false)
hub:interact()
assert(hub.model.fighter.x == x and opened == 1, "hidden lobby cannot move or interact during a match")
print(`PASS hub view: real movement, nearby interaction, modal/chat guards, thirty finite draws; peak {peak} primitives`)
