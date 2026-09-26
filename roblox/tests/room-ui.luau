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

local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Panel = luau.load(fs.readFile("src/client/RoomPanel.luau"), {environment={
 game={GetService=function() return {Shared=shared} end}, script={Parent=codes},
 require=function(name)
  if name=="Canvas2D" then return Canvas end
  if name=="Weapons2D" or name=="StageThumb" then return Loader.loadFrom("src/client/",name) end
  if name=="Rules" then return Loader.load("Data/Rules") end
  return Loader.load("Data/"..name)
 end,
 Enum={Font=codes,AutomaticSize=codes}, Color3=Rbx.Color3,Vector2=Rbx.Vector2,UDim=Rbx.UDim,UDim2=Rbx.UDim2,Instance={new=instance},
},injectGlobals=true})()
local Rooms=Loader.loadFrom("src/server/","Rooms")
local model=Rooms.new()
local p={UserId=1,DisplayName="Host"}
local room=model:join(p,"Triples")
local panel=Panel.new(instance("PlayerGui"))
panel.onAction=function(msg)
 local ok,why=model:edit(p,msg)
 assert(ok,why)
 panel:update(model:view(room),1)
end
panel:update(model:view(room),1)
assert(#panel.room.slots==6 and not panel.room.canStart)
assert(not panel.gui.Enabled, "entering a room must leave the world walkable")
panel:openStation("Weapons")
assert(panel.gui.Enabled and not panel.ready.Visible and not panel.start.Visible, "weapon station is focused, not a universal setup HUD")
assert(#panel.previews==12,"all twelve weapons have actual artwork")
local shapes={}
local function primitive(c, ...)
 for _, v in {...} do if type(v)=="number" then assert(v==v and math.abs(v)<math.huge,"finite weapon image") end end
 c.used+=1
end
Canvas.rect,Canvas.circle,Canvas.ellipse=primitive,primitive,primitive
local finish = Canvas.finish
Canvas.finish = function(c) c.drawn = c.used; finish(c) end
for _, size in {{100,80},{200,80},{300,100}} do
 for _, preview in panel.previews do preview.frame.AbsoluteSize=Rbx.Vector2.new(size[1],size[2]) end
 panel:drawPreviews()
 for _, preview in panel.previews do
  assert(preview.canvas.drawn>5,"each weapon must draw geometry")
  assert(#preview.canvas.stack==0,"preview leaves no transforms")
  shapes[preview.weapon.id]=preview.canvas.drawn
 end
end
panel.body:FindFirstChild("Weapon_Hammer").Activated:Fire()
assert(panel.cfg.slots[1].weaponId=="Hammer" and room.slots[1].weapon=="Hammer","image click changes server-owned loadout")
panel.page="Maps";panel:render()
-- The map board shows every stage's layout, drawn from its own geometry, after a Random tile.
local Stages = Loader.load("Data/Stages")
assert(#panel.previews == #Stages.LIST + 1, "every map has a layout thumbnail, plus Random")
assert(panel.previews[1].random, "Random comes first")
local grid = panel.body:FindFirstChild("MapGrid")
for _, preview in panel.previews do preview.frame.AbsoluteSize=Rbx.Vector2.new(170,64) end
-- Every thumbnail rectangle carries a real colour. A colour constant referenced before it is
-- declared is a nil global in Luau, and the recorder above would otherwise count it happily.
local counted = Canvas.rect
Canvas.rect = function(c, x, y, w, h, colour, ...)
  assert(colour ~= nil, "a map thumbnail drew with no colour")
  return counted(c, x, y, w, h, colour, ...)
end
panel:drawPreviews()
Canvas.rect = counted
for i, preview in panel.previews do
  if i > 1 then
    assert(preview.stage, "map previews are stages")
    -- the sky, the main floor with its cap, and one shape per platform at least
    assert(preview.canvas.drawn >= 3 + #preview.stage.platforms, `{preview.stage.id}: thumbnail draws too little`)
  else
    assert(preview.canvas.drawn >= 7, "the Random tile draws its die")
  end
  assert(#preview.canvas.stack==0, "thumbnail leaves no transforms")
end
grid:FindFirstChild("Stage_Undertow").Activated:Fire()
assert(room.stage=="Undertow")
-- The host switches to the ranked set: only ranked maps (and Random) stay on the board.
panel.body:FindFirstChild("MapSet"):FindFirstChild("MapSet_ranked").Activated:Fire()
assert(room.mapSet=="ranked","the host's map set reaches the room")
local rankedCount = 0
for _, st in Stages.LIST do if st.ranked then rankedCount += 1 end end
assert(#panel.previews == rankedCount + 1, `ranked board shows {#panel.previews - 1} maps, want {rankedCount}`)
panel.body:FindFirstChild("MapGrid"):FindFirstChild("Stage_Random").Activated:Fire()
assert(room.stage=="Random","Random is a pick the host can make")
-- Everyone votes: a tap is a ballot, and the tile shows the count.
panel.body:FindFirstChild("MapChoice"):FindFirstChild("MapChoice_vote").Activated:Fire()
assert(room.mapChoice=="vote")
panel.body:FindFirstChild("MapGrid"):FindFirstChild("Stage_TheSpan").Activated:Fire()
assert(room.slots[1].vote=="TheSpan","tapping a map in vote mode casts your ballot")
local tile = panel.body:FindFirstChild("MapGrid"):FindFirstChild("Stage_TheSpan")
assert(tile:FindFirstChild("Votes") and tile:FindFirstChild("Votes").Text=="1 vote","the tile counts ballots")
assert(string.find(tile:FindFirstChild("MapName").Text, "✓", 1, true), "your own ballot is marked")
panel.body:FindFirstChild("MapChoice"):FindFirstChild("MapChoice_host").Activated:Fire()
panel.body:FindFirstChild("MapSet"):FindFirstChild("MapSet_all").Activated:Fire()
grid = panel.body:FindFirstChild("MapGrid")
panel:openStation("Rules")
assert(panel.body:FindFirstChild("Disasters_off") and panel.body:FindFirstChild("Disasters_chaos"), "the rules console offers the disaster setting")
panel.body:FindFirstChild("Disasters_stage").Activated:Fire()
assert(room.disasters=="stage","the host's disaster choice reaches the room")
-- The battle builder: a preset sets every rule; the mode swaps lives for a clock.
panel.body:FindFirstChild("Preset"):FindFirstChild("Preset_tournament").Activated:Fire()
assert(room.mode=="stock" and room.stocks==3 and room.items==false and room.disasters=="off" and room.mapChoice=="vote" and room.mapSet=="ranked", "Tournament 1v1 sets every rule")
assert(panel.body:FindFirstChild("PresetHint").Text ~= "Custom rules", "the station names the preset in force")
assert(panel.body:FindFirstChild("Lives") and not panel.body:FindFirstChild("Time"), "a stock match offers lives, not a clock")
panel.body:FindFirstChild("Mode"):FindFirstChild("Mode_timed").Activated:Fire()
assert(room.mode=="timed", "the host's mode reaches the room")
assert(panel.body:FindFirstChild("Time") and not panel.body:FindFirstChild("Lives"), "a timed match offers a clock, not lives")
assert(panel.body:FindFirstChild("PresetHint").Text == "Custom rules", "one changed rule and the preset no longer applies")
panel.body:FindFirstChild("Time"):FindFirstChild("Time_240").Activated:Fire()
assert(room.time==240, "the clock choice reaches the room")
panel.body:FindFirstChild("Preset"):FindFirstChild("Preset_casual").Activated:Fire()
assert(room.mode=="stock" and room.disasters=="stage" and room.items==true, "Casual sets every rule")
panel.body:FindFirstChild("Disasters_stage").Activated:Fire()
panel.body:FindFirstChild("Bots OFF — add optional CPU").Activated:Fire()
assert(room.slots[2].bot=="easy","explicit optional CPU control")
panel:openStation("Players")
assert(panel.ready.Visible and panel.start.Visible, "ready controls belong to ready rail")
panel.ready.Activated:Fire()
assert(room.slots[1].ready)
panel.start.Activated:Fire()
assert(room.state=="setup","incomplete teams cannot launch")
panel:update(model:view(room),2)
panel.page="Maps";panel:render()
local before = room.stage
panel.body:FindFirstChild("MapGrid"):FindFirstChild("Stage_FoundryFloor").Activated:Fire()
assert(room.stage==before and before ~= "FoundryFloor","guest controls cannot edit host settings")
panel:hide()
panel:update(model:view(room),2)
assert(not panel.gui.Enabled, "background room update must not reopen a closed station")
local n=0
for _ in shapes do n+=1 end
assert(n==12)
print("PASS room UI: 12 real weapon images at 3 sizes, click-to-equip, map grid with Random, map sets and voting, explicit bots, ready and host guards")

local Hud = luau.load(fs.readFile("src/client/Hud.luau"), {environment={
	game={GetService=function() return {Shared=shared} end}, script={Parent=codes},
	-- The results podium has its own test (podium-view); this one is about the match HUD.
	require=function(name) if name=="PodiumView" then return {} end if name=="Callouts" then return Loader.load("Data/Callouts") end return if name=="Config" then Loader.load(name) else Loader.loadFrom("src/client/",name) end,
	Enum={Font=codes,TextXAlignment=codes,ZIndexBehavior=codes}, Color3=Rbx.Color3,Vector2=Rbx.Vector2,UDim=Rbx.UDim,UDim2=Rbx.UDim2,Instance={new=instance},
},injectGlobals=true})()
local hud=Hud.new(instance("PlayerGui"))
local roster,chars={},{}
for i=1,6 do
	roster[i]={index=i-1,team=(i-1)%2,name=`Player{i}`,weapon="Sword"}
	chars[i]=Loader.load("Loadout").build("Classic","Sword")
end
for _, size in {{360,640},{800,600},{1280,720}} do
	hud.gui.AbsoluteSize=Rbx.Vector2.new(size[1],size[2])
	hud:bind(roster,chars)
	local boxes={}
	for _, tile in hud.tiles do
		local p,s=tile.root.Position,tile.root.Size
		local x,y=p.X.Scale*size[1]+p.X.Offset,p.Y.Scale*size[2]+p.Y.Offset
		assert(x>=0 and x+s.X.Offset<=size[1] and y>=0 and y+s.Y.Offset<=size[2], "six-player HUD stays on screen")
		for _, b in boxes do assert(x>=b.x+b.w or x+s.X.Offset<=b.x or y>=b.y+b.h or y+s.Y.Offset<=b.y, "HUD tiles never overlap") end
		table.insert(boxes,{x=x,y=y,w=s.X.Offset,h=s.Y.Offset})
	end
end
print("PASS six-player HUD: all tiles on screen without overlap at phone, tablet and desktop sizes")
hud:bind(roster,chars,0)
hud:abilityEvent({type="ultready",fighter=1})
assert(not hud.abilityMessage,"another player's full meter must not be announced as yours")
hud:abilityEvent({type="ultdenied",fighter=0,reason="charge"})
assert(hud.abilityMessage:find("not charged",1,true),"index-zero local fighter receives rejection feedback")
-- The disaster banner: cool with a countdown while it warns, hot once it strikes, gone after.
do
	local COOL, HOT = Rbx.Color3.fromHex("#7FD4FF"), Rbx.Color3.fromHex("#F08B60")
	local function show(view: any): any
		hud.disasterView = view
		hud:update({}, nil, nil, chars, nil)
		return hud.disaster
	end
	local b = show({ type = "tsunami", phase = "warn", k = 0.2, frame = 30, warn = 150 })
	assert(b.Text:find("TSUNAMI INCOMING", 1, true) and b.Text:find("· 2", 1, true), `warning banner reads {b.Text}`)
	assert(b.TextColor3 == COOL, "a warning is cool")
	b = show({ type = "tsunami", phase = "strike", k = 0.1, frame = 200, warn = 150 })
	assert(b.Text:find("TSUNAMI", 1, true) and not b.Text:find("INCOMING", 1, true) and b.TextColor3 == HOT, "a strike is hot, with no countdown")
	b = show({ type = "earthquake", phase = "warn", k = 0.5, frame = 60, warn = 120, plates = {} })
	assert(b.Text:find("TREMOR", 1, true), "a plateless quake is announced as a tremor")
	b = show({ type = "tsunami", phase = "after", k = 0.5, frame = 700, warn = 150 })
	assert(b.Text == "", "nothing once it is over")
	b = show(nil)
	assert(b.Text == "", "nothing without a disaster")
	print("PASS disaster banner: cool countdown while warning, hot on strike, tremor named, gone after")
end

-- Callouts: the go call, a KO, sudden death and GAME! in the middle; the stage name above it; each
-- with the words, colour and hold of web/src/data/callouts.js, fading out at the end.
do
	local Callouts = Loader.load("Data/Callouts")
	hud.disasterView = nil
	hud:update({}, { state = "countdown", countdown = 0, time = 0 }, nil, chars, nil)
	assert(hud.callout.Text == Callouts.go.text and hud.callout.TextTransparency == 0, `the last count is the go call, got {hud.callout.Text}`)
	hud:update({}, { state = "fight", time = 0.1 }, nil, chars, nil)
	assert(hud.callout.Text == Callouts.go.text, "the go call holds into the fight")
	for _, key in { "ko", "suddendeath", "shrink", "game" } do
		hud:announce(key, if key == "ko" then "KO!  ● Player1" else nil)
		hud:update({}, { state = "fight", time = 5 }, nil, chars, nil)
		local want = if key == "ko" then "KO!  ● Player1" else Callouts[key].text
		assert(hud.callout.Text == want and hud.callout.TextTransparency == 0, `{key}: shows {hud.callout.Text}`)
		assert(hud.callout.TextColor3 == Rbx.Color3.fromHex(Callouts[key].colour), `{key}: in its colour`)
		hud.flash.start -= Callouts[key].ms / 1000 * 0.85
		hud:update({}, { state = "fight", time = 5 }, nil, chars, nil)
		assert(hud.callout.TextTransparency > 0 and hud.callout.TextTransparency < 1, `{key}: fades over its last third`)
		hud.flash.start -= Callouts[key].ms / 1000
		hud:update({}, { state = "fight", time = 5 }, nil, chars, nil)
		assert(hud.callout.TextTransparency == 1, `{key}: gone after its hold`)
	end
	hud:announce("stage", "Foundry Floor")
	hud:update({}, { state = "countdown", countdown = 150, time = 0 }, nil, chars, nil)
	assert(hud.stageName.Text == "Foundry Floor" and hud.stageName.TextTransparency == 0, "the stage name shows during the countdown")
	assert(hud.callout.Text == "3", "while the countdown keeps the middle")
	print("PASS callouts: go call, KO, sudden death, closing in and GAME! with the web's words, colours and holds; stage name above the countdown")
end
