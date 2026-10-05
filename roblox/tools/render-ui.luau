--!nocheck
-- Development tool, not a test: one of the game's screens built by its real module against
-- stand-in Instances (Recorder.gui), with anything it draws on the game canvas recorded - written as
-- JSON for tools/gui-svg.mjs, so a screen can be looked at without Studio.
--
--   lune run tools/render-ui <out.json> <plaza|studio|hud> [width] [height] [variant]
--     plaza   variant: "x,z" where you stand (beside a station shows its prompt; the default shows
--             the tip), or "stamps" to open the stamp panel
--     studio  variant: a tab - presets, body, face, hair, outfit, extras
--     hud     variant: "fight" (mid-fight, a full ultimate) or "countdown" (the combo card, "3")
--
-- Pictures drawn into a GUI frame (Canvas2D.inFrame: the studio's tiles and preview, the stamp
-- icons) are not placed - only the screen-wide canvas is - so those frames show empty.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Rbx = require("@lune/roblox")
local Loader = require("../tests/loader")
local Recorder = require("./recorder")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Input = Loader.load("Input")
local shapes = Recorder.install(Canvas)

local screen = process.args[2] or "plaza"
local W = tonumber(process.args[3] or "1280") or 1280
local H = tonumber(process.args[4] or "720") or 720
local variant = process.args[5]

local new, made = Recorder.gui(W, H)
local enumNames = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
Loader.gui = { Instance = { new = new }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = enumNames }
-- frames' own canvases draw nowhere (see above)
Canvas.inFrame = function()
	local f = Recorder.canvas(Canvas, 100, 100)
	f.pool, f.poolState = {}, {}
	return f
end

local codes = setmetatable({}, { __index = function(_, k) return k end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) },
	{ __index = function(_, k) return k end })
local function never() return false end
local services = setmetatable({ ReplicatedStorage = { Shared = shared } }, { __index = function()
	local stub = { GetFocusedTextBox = never, IsKeyDown = never, IsGamepadButtonDown = never }
	stub.InputBegan = { Connect = function() end }
	return stub
end })
local function load(name: string): any
	return luau.load(fs.readFile("src/client/" .. name .. ".luau"), { debugName = name, environment = {
		game = { GetService = function(_, s) return services[s] end },
		script = { Parent = codes },
		require = function(target)
			if target == "InputClient" then return { new = function() return {
				frame = Input.emptyFrame(), sample = function(self) return { self.frame } end, reset = function() end,
			} end } end
			if target == "PodiumView" then return {} end
			if type(target) == "string" and fs.isFile("src/client/" .. target .. ".luau") then return Loader.loadFrom("src/client/", target) end
			return Loader.load(target)
		end,
		Instance = { new = new }, Enum = enumNames, Color3 = Rbx.Color3, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Vector2 = Rbx.Vector2,
		Random = { new = function() return { NextInteger = function(_, a) return a end, NextNumber = function() return 0.5 end } end },
		typeof = function(v) return type(v) end,
	}, injectGlobals = true })()
end

local playerGui = new("PlayerGui")
local KIT = Loader.load("Data/AvatarKit")
local c = Recorder.canvas(Canvas, W, H)

if screen == "plaza" then
	local Plaza2D = load("Plaza2D")
	local Social = load("LobbySocial")
	local social = Social.new(playerGui, { localId = 1, clock = function() return 0 end, send = function() end })
	social:setEnabled(true)
	if variant == "stamps" then social:toggle("Stamps") end
	local hub = Plaza2D.new(playerGui)
	local cfg = Loader.load("MatchConfig").default()
	for _, p in KIT.presets do if p.id == "knight" then cfg.slots[1].avatarId = p.code end end
	hub:show(cfg)
	-- "x,z": where you stand (beside a station shows its prompt)
	local x, z = 0, 8
	if variant and string.find(variant, ",") then
		local a, b = string.match(variant, "^([%-%d%.]+),([%-%d%.]+)$")
		x, z = tonumber(a) or 0, tonumber(b) or 8
	end
	hub.model:setScene(hub.model.data, { x = x, z = z })
	hub.camX = x
	for _ = 1, 20 do table.clear(shapes); hub:step(1 / 60, false); hub:draw(c, 1 / 60) end
elseif screen == "studio" then
	local Editor = load("AvatarEditor")
	local ed = Editor.new(playerGui, { send = function() end, weapon = function() return "Sword" end })
	ed.gui.AbsoluteSize = Rbx.Vector2.new(W, H)
	ed:open()
	ed:layout(Rbx.Vector2.new(W, H))
	if variant then ed:selectGroup(variant) end
	table.clear(shapes)
	-- a backdrop where the plaza would be
	c:screen()
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromRGB(40, 46, 70), 1)
elseif screen == "hud" then
	local Hud = load("Hud")
	local Loadout = Loader.load("Loadout")
	local hud = Hud.new(playerGui)
	local roster, chars = {}, {}
	local names = { "etondes", "Rival", "CPU", "Ally" }
	local weapons = { "Scythe", "Sword", "Hammer", "Daggers" }
	for i = 1, 4 do
		roster[i] = { index = i - 1, team = (i - 1) % 2, name = names[i], weapon = weapons[i] }
		chars[i] = Loadout.build("Classic", weapons[i])
	end
	hud:bind(roster, chars, 0, true)
	local countdown = variant == "countdown"
	local states = {}
	for i = 1, 4 do
		states[i] = { index = i - 1, percent = ({ 0, 47, 112, 168 })[i], stocks = ({ 3, 2, 3, 1 })[i], alive = true,
			ultCharge = ({ 20, 9, 4, 0 })[i], state = if i == 1 then "idle" else "run", onGround = true, x = 0, y = 0 }
	end
	if countdown then for _, st in states do st.percent, st.ultCharge = 0, 0 end end
	local snap = { state = if countdown then "countdown" else "fight", countdown = 150, time = 16 }
	-- a dusk sky where the arena would be
	c:screen()
	for b = 0, 11 do
		local k = b / 11
		Canvas.rect(c, 0, b * H / 12, W, H / 12 + 1, Rbx.Color3.new(0.12 + 0.2 * k, 0.1 + 0.12 * k, 0.3 + 0.2 * k), 1)
	end
	hud:update(states, snap, nil, chars, { fighters = roster, timed = true, timeLimit = 180 })
else
	error("unknown screen " .. screen)
end

local nodes = Recorder.nodes(made, W, H)
fs.writeFile(process.args[1], serde.encode("json", { w = W, h = H, shapes = shapes, nodes = nodes }))
print(`{screen} at {W}x{H}: {#shapes} canvas shapes, {#nodes} GUI nodes`)
