--!nocheck
-- Development tool, not a test: runs the real Hub2D draw path with a recording canvas and writes
-- what it drew - every rectangle as its four screen corners, plus the text labels - as JSON, for
-- tools/hub-svg.mjs to turn into a picture. The game renders into a ScreenGui, so Studio's
-- screenshot is empty; this is how to look at the lobby without it.
--   lune run tools/render-hub <out.json> [market|Duel|Doubles|Triples] [x] [mapChoice] [mode] [character] [z] [peers]
-- `peers` scatters that many ready-made characters around you, to see a busy roof.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local Rbx = require("@lune/roblox")
local Loader = require("../tests/loader")
local Input = Loader.load("Input")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local codes = setmetatable({}, { __index = function(_, key) return key end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, key) return key end })
local Recorder = require("./recorder")
local instance, labels = Recorder.instances()
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
local Hub = luau.load(fs.readFile(process.args[2]), { environment = {
	game = { GetService = function(_, name)
		if name == "ReplicatedStorage" then return { Shared = shared } end
		return { GetFocusedTextBox = function() return false end, IsKeyDown = function() return false end,
			IsGamepadButtonDown = function() return false end }
	end },
	script = { Parent = codes },
	require = function(name)
		if name == "InputClient" then return { new = function() return {
			frame = Input.emptyFrame(), sample = function(self) return { self.frame } end, reset = function() end,
		} end } end
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2, UDim = Rbx.UDim,
	Enum = setmetatable({}, { __index = function() return codes end }), Instance = { new = instance },
}, injectGlobals = true })()


local Draw = Loader.loadFrom("src/client/", "Fighter2D")
local draw = Draw.draw
local shapes = Recorder.install(Canvas)
local cfg = Loader.load("MatchConfig").default()
cfg.slots[1].avatarId = "Classic"
local hub=Hub.new({}); hub:show(cfg)
hub.model:setScene(hub.model.data,{x=10,z=4});hub.camX=10
hub.input.frame.y=1
local seen
Draw.draw=function(c,s,char,t,top)
 if char==hub.char then seen=table.clone(s) end
 return draw(c,s,char,t,top)
end
local scale=tonumber(process.args[3]) or 26
local W,H=if scale==5 then 80 else 260,if scale==5 then 64 else 220
local frames={}
local c=Recorder.canvas(Canvas,1280,720)
local function record(label,s,floor)
 table.clear(shapes)
 local cv=Recorder.canvas(Canvas,W,H)
 Canvas.screen(cv);Canvas.rect(cv,0,0,W,H,Rbx.Color3.fromHex("#22303f"))
 Canvas.world(cv,s.x+1.5,s.y+3.2,scale,0,0)
 Canvas.rect(cv,s.x-6,floor-1,14,1,Rbx.Color3.fromHex("#4a5a46"))
 draw(cv,s,hub.char,0,floor)
 table.insert(frames,{frame=#frames,label=label,shapes=table.clone(shapes)})
end
local wardrobe
for _,st in Loader.load("Data/Plaza").market.stations do if st.kind=="Wardrobe" then wardrobe=st end end
for frame=1,31 do
 table.clear(shapes);hub:step(1/60,false);hub:draw(c,1/60)
 if (frame-1)%6==0 then
  local st=seen
  record("depth "..frame,st,st.y)
  hub:drawWardrobe(c,wardrobe,0)
  record("mirror "..frame,seen,seen.y-0.6)
 end
end
fs.writeFile(process.args[1],require("@lune/serde").encode("json",{w=W,h=H,frames=frames}))
print("rendered lobby depth and mirror at "..scale)
