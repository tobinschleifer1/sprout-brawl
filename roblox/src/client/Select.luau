--!strict
-- Station option panel, opened by proximity interaction in Hub2D. The lobby itself is a world.
-- All callbacks read self.cfg, never a slot captured before a rematch.
local Shared = game:GetService("ReplicatedStorage").Shared
local Stages = require(Shared.Data.Stages)
local Weapons = require(Shared.Data.Weapons)
local Avatars = require(Shared.Data.Avatars)
local MatchConfig = require(Shared.MatchConfig)
local Bindings = require(script.Parent.Bindings)
local Select = {}
Select.__index = Select
local INK, PANEL, CHIP = Color3.fromRGB(13,17,23), Color3.fromRGB(24,29,36), Color3.fromRGB(39,46,56)
local WHITE, DIM = Color3.fromRGB(235,230,216), Color3.fromRGB(173,185,192)
local AMBER, TEAL = Color3.fromRGB(240,177,82), Color3.fromRGB(102,186,178)
local PAGES = { "Home", "Arenas", "Loadout", "Opponents", "Rules", "Controls" }
local MODE_LABELS = { StockFFA = "Stock / free-for-all", TimedFFA = "Timed / free-for-all",
	StockTeams = "Stock / teams", TimedTeams = "Timed / teams" }

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name, f.Position, f.Size = name, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
	f.BackgroundColor3, f.BorderSizePixel, f.Parent = color, 0, parent
	return f
end
local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, px: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Position, t.Size = name, text, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
	t.BackgroundTransparency, t.TextSize, t.TextColor3 = 1, px, color
	t.Font, t.TextWrapped = Enum.Font.GothamBold, true
	t.TextXAlignment, t.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Center
	t.Parent = parent
	return t
end
local function diagram(parent: Instance, stage: any, x: number, y: number, w: number)
	local back = box(parent, "Layout", x,y,w,82, INK)
	back.ClipsDescendants = true
	local function platform(x1: number, x2: number, top: number, solid: boolean)
		box(back, "Platform", w/2+x1*w/140, 60-top*0.85, math.max(2,(x2-x1)*w/140), if solid then 9 else 4, if solid then AMBER else TEAL)
	end
	if stage.main then platform(stage.main.x1,stage.main.x2,stage.main.y,true) end
	for _, p in stage.platforms or {} do platform(p.x-p.w/2,p.x+p.w/2,p.y,p.solid == true) end
end

function Select.new(parent: Instance): any
	local self = setmetatable({}, Select)
	self.cfg, self.page, self.pending = MatchConfig.default(), "Home", false
	self.onStart = nil
	self.station = nil :: any
	self.onClose = nil :: (() -> ())?
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "BlockfallSelect", false, true
	gui.DisplayOrder, gui.Enabled, gui.Parent = 20, false, parent
	self.gui = gui
	local shade = box(gui,"Backdrop",0,0,0,0,INK)
	shade.Size = UDim2.fromScale(1,1)
	self.shade = shade
	local panel = box(gui,"Lobby",0,0,960,700,PANEL)
	panel.AnchorPoint, panel.Position = Vector2.new(0.5,0.5), UDim2.fromScale(0.5,0.5)
	self.panel = panel
	self.title = label(panel,"Brand","BLOCKFALL  /  FIGHT LOBBY",16,12,800,34,24,AMBER)
	local back = Instance.new("TextButton")
	back.Name, back.Text, back.Font, back.TextSize = "BackToHub", "← BACK TO LOBBY", Enum.Font.GothamBold, 12
	back.Size, back.BackgroundColor3, back.TextColor3 = UDim2.fromOffset(140, 30), CHIP, WHITE
	back.BorderSizePixel, back.Visible, back.Parent = 0, false, panel
	back.Activated:Connect(function() self:closeStation() end)
	self.back = back
	self.note = label(panel,"Status","Build your fight. Choose an arena, a weapon and your opponents.",16,48,800,38,14,DIM)
	self.nav = box(panel,"Navigation",16,92,800,38,PANEL)
	local content = Instance.new("ScrollingFrame")
	content.Name, content.BackgroundColor3, content.BorderSizePixel = "Content", PANEL, 0
	content.ScrollBarThickness, content.ScrollBarImageColor3 = 6, AMBER
	content.ScrollingDirection, content.ClipsDescendants = Enum.ScrollingDirection.Y, true
	content.CanvasSize, content.Parent = UDim2.fromOffset(0,0), panel
	self.content = content
	self.summary = label(panel,"MatchSummary","",16,0,800,38,13,WHITE)
	local start = Instance.new("TextButton")
	start.Name, start.Text, start.Font, start.TextSize = "Fight", "FIGHT", Enum.Font.GothamBold, 18
	start.BackgroundColor3, start.TextColor3, start.BorderSizePixel, start.Parent = AMBER, INK, 0, panel
	start.Activated:Connect(function()
		if self.station and self.page ~= "Gate" then
			self:closeStation()
			return
		end
		if self.pending or self:count() < MatchConfig.MIN_FIGHTERS then return end
		if self.onStart then self.onStart(self.cfg) end
	end)
	self.start = start
	local function fit()
		local vp = gui.AbsoluteSize
		self.width = math.max(280, math.min(if self.station then 660 else 1120, vp.X-24))
		local height = math.max(300, math.min(if self.station then 630 else 820, vp.Y-24))
		panel.Size = UDim2.fromOffset(self.width,height)
		self.title.Size, self.title.TextSize = UDim2.fromOffset(self.width-32,34), if self.width < 600 then 18 else 24
		if self.station then self.title.Size = UDim2.fromOffset(self.width - 184, 34) end
		back.Position = UDim2.fromOffset(self.width - 156, 14)
		self.note.Size = UDim2.fromOffset(self.width-32,38)
		local navH = if self.station then 0 elseif self.width < 850 then 80 else 38
		self.nav.Visible = self.station == nil
		self.nav.Size = UDim2.fromOffset(self.width-32,navH)
		content.Position, content.Size = UDim2.fromOffset(16,104+navH), UDim2.fromOffset(self.width-32,height-navH-208)
		self.summary.Position, self.summary.Size = UDim2.fromOffset(16,height-94), UDim2.fromOffset(self.width-32,38)
		start.Position, start.Size = UDim2.fromOffset(16,height-52), UDim2.fromOffset(self.width-32,40)
		self:build()
	end
	self.fit = fit
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return self
end
function Select.count(self: any): number
	local n = 0
	for _, sl in self.cfg.slots do if sl.type ~= "off" then n += 1 end end
	return n
end
function Select.button(self: any, parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number,
	callback: () -> (), selected: (() -> boolean)?): TextButton
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.Position, b.Size = name, text, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
	b.BackgroundColor3, b.TextColor3, b.BorderSizePixel = CHIP, WHITE, 0
	b.Font, b.TextSize, b.TextWrapped, b.Parent = Enum.Font.GothamBold, 14, true, parent
	b.Activated:Connect(function()
		if self.pending then return end
		callback()
		self:refresh()
	end)
	table.insert(self.buttons,{button=b,text=text,selected=selected})
	return b
end
function Select.navigate(self: any, page: string)
	self.page = page
	self.content.CanvasPosition = Vector2.new(0,0)
	self:build()
end
function Select.refresh(self: any)
	for _, e in self.buttons do
		local on = e.selected and e.selected()
		e.button.Text = (if on then "✓ " else "") .. e.text
		e.button.BackgroundColor3, e.button.TextColor3 = if on then AMBER else CHIP, if on then INK else WHITE
	end
	for _, refresh in self.refreshers do refresh() end
	local stageName = self.cfg.stageId
	for _, s in Stages.LIST do if s.id == self.cfg.stageId then stageName = s.name end end
	local rule = if string.find(self.cfg.mode,"Timed") then `{self.cfg.time}s` else `{self.cfg.stocks} stocks`
	self.summary.Text = `{stageName}  •  {self:count()} fighters  •  {MODE_LABELS[self.cfg.mode]}  •  {rule}  •  Items {if self.cfg.items then "ON" else "OFF"}`
	self.start.Text = if self.pending then "LOADING…" elseif self:count()<2 then "ADD AN OPPONENT TO FIGHT" else `FIGHT  /  {self:count()} FIGHTERS`
	self.start.Active = not self.pending and self:count()>=2
	self.start.AutoButtonColor = self.start.Active
	self.start.BackgroundColor3, self.start.TextColor3 = if self.start.Active then AMBER else CHIP, if self.start.Active then INK else DIM
	if self.station and self.page ~= "Gate" then
		self.start.Text, self.start.Active = "RETURN TO CONCOURSE", not self.pending
		self.start.BackgroundColor3, self.start.TextColor3 = AMBER, INK
	elseif self.station and not self.pending and self:count() >= 2 then
		self.start.Text = `ENTER ARENA  /  {self:count()} FIGHTERS`
	end
	self.back.Visible, self.back.Active = self.station ~= nil and not self.pending, not self.pending
end
function Select.build(self: any)
	self.content:ClearAllChildren()
	self.nav:ClearAllChildren()
	self.buttons, self.refreshers = {}, {}
	local cols = if self.width<850 then 3 else 6
	local navW = (self.width-32-(cols-1)*6)/cols
	for i, page in PAGES do
		self:button(self.nav,page,page,((i-1)%cols)*(navW+6),math.floor((i-1)/cols)*42,navW,36,
			function() self:navigate(page) end,function() return self.page==page end)
	end
	local w, y = self.width-44, 0
	local content = self.content
	local function heading(text: string, hint: string)
		label(content,"Heading",text,0,y,w,32,22,WHITE)
		label(content,"Description",hint,0,y+34,w,46,14,DIM)
		y += 88
	end
	local function choices(name: string, values: { any }, get: () -> any, set: (any) -> (), columns: number)
		local ncols = math.max(1,math.min(columns,math.floor(w/170)))
		local bw = (w-(ncols-1)*8)/ncols
		for i, v in values do
			self:button(content,name..tostring(v.id),v.text,((i-1)%ncols)*(bw+8),y+math.floor((i-1)/ncols)*46,bw,38,
				function() set(v.id) end,function() return get()==v.id end)
		end
		y += math.ceil(#values/ncols)*46+12
	end
	if self.page=="Gate" then
		local stage = Stages.BY_ID[self.cfg.stageId]
		heading(stage.name, stage.blurb)
		diagram(content, stage, 0, y, w)
		y += 96
		label(content, "Review", `Your weapon: {Weapons.BY_ID[self.cfg.slots[1].weaponId].name}\n{self:count() - 1} CPU opponents  •  {MODE_LABELS[self.cfg.mode]}`, 0, y, w, 70, 17, WHITE)
		y += 84
		label(content, "Stations", "Ready? Enter this arena below.\nTo change your loadout, opponents or rules, return to the concourse and visit their stations.", 0, y, w, 80, 14, DIM)
		y += 90
		label(content, "Bindings", Bindings.hint(), 0, y, w, 64, 14, AMBER)
		y += 76
	elseif self.page=="Home" then
		heading("YOUR NEXT FIGHT STARTS HERE","A dark industrial arena. Your weapon decides how you fight; your look is cosmetic.")
		local stage = Stages.LIST[1]
		for _, s in Stages.LIST do if s.id==self.cfg.stageId then stage=s end end
		diagram(content,stage,0,y,w)
		y += 92
		label(content,"ArenaName",stage.name.."  /  "..stage.archetype,0,y,w,36,18,TEAL)
		y += 46
		self:button(content,"CustomFight","CUSTOM FIGHT  /  choose your arena",0,y,w,44,function() self:navigate("Arenas") end)
		y += 56
		self:button(content,"DuelPreset","DUEL PRESET  /  you + 1 normal CPU",0,y,w,44,function()
			self.cfg.mode="StockFFA"
			for i=2,4 do self.cfg.slots[i].type=if i==2 then "bot-normal" else "off" end
			self:navigate("Opponents")
		end)
		y += 56
		self:button(content,"BrawlPreset","FULL BRAWL PRESET  /  you + 3 normal CPUs",0,y,w,44,function()
			self.cfg.mode="StockFFA"
			for i=2,4 do self.cfg.slots[i].type="bot-normal" end
			self:navigate("Opponents")
		end)
		y += 62
		label(content,"KeyHints",Bindings.hint(),0,y,w,58,14,AMBER)
		y += 68
	elseif self.page=="Arenas" then
		heading("CHOOSE YOUR ARENA","Six layouts. Read the terrain and select a card before pressing Fight.")
		local columns = if w>=650 then 2 else 1
		local cw = (w-(columns-1)*12)/columns
		for i,s in Stages.LIST do
			local x,top=((i-1)%columns)*(cw+12),y+math.floor((i-1)/columns)*254
			local card=box(content,s.id,x,top,cw,242,INK)
			diagram(card,s,10,10,cw-20)
			label(card,"Theme",s.theme.."  /  "..s.archetype,10,96,cw-20,32,13,TEAL)
			label(card,"Blurb",s.blurb,10,130,cw-20,60,13,DIM)
			self:button(card,"ChooseArena",s.name,10,198,cw-20,34,function() self.cfg.stageId=s.id end,function() return self.cfg.stageId==s.id end)
		end
		y += math.ceil(#Stages.LIST/columns)*254
	elseif self.page=="Loadout" then
		heading("WEAPON + LOOK","Weapons change your moves and mechanics. Looks change no stats.")
		local weapons,avatars={},{}
		for _,a in Weapons.LIST do table.insert(weapons,{id=a.id,text=a.name}) end
		for _,a in Avatars.LIST do table.insert(avatars,{id=a.id,text=a.name}) end
		choices("Weapon",weapons,function() return self.cfg.slots[1].weaponId end,function(id) self.cfg.slots[1].weaponId=id end,3)
		label(content,"LooksLabel","YOUR LOOK",0,y,w,30,18,TEAL)
		y += 38
		choices("Avatar",avatars,function() return self.cfg.slots[1].avatarId end,function(id) self.cfg.slots[1].avatarId=id end,3)
	elseif self.page=="Opponents" then
		heading("BUILD THE ROSTER","Add up to three CPUs. Count, difficulty and weapon are separate choices.")
		for i=2,4 do
			local card=box(content,"Slot"..i,0,y,w,164,INK)
			local title=label(card,"SlotStatus","",12,8,w-144,32,16,TEAL)
			local toggle=self:button(card,"Toggle","",w-120,8,108,32,function()
				local sl=self.cfg.slots[i]
				sl.type=if sl.type=="off" then "bot-normal" else "off"
			end)
			local bw=(w-40)/3
			for k,level in MatchConfig.BOT_LEVELS do
				self:button(card,level,string.upper(level),12+(k-1)*(bw+8),48,bw,34,
					function() self.cfg.slots[i].type="bot-"..level end,function() return self.cfg.slots[i].type=="bot-"..level end)
			end
			local weapon=label(card,"WeaponName","",56,91,w-112,32,14,WHITE)
			local function cycle(delta: number)
				local sl,at=self.cfg.slots[i],1
				for k,def in Weapons.LIST do if def.id==sl.weaponId then at=k end end
				sl.weaponId=Weapons.LIST[(at-1+delta)%#Weapons.LIST+1].id
			end
			self:button(card,"PreviousWeapon","<",12,91,36,32,function() cycle(-1) end)
			self:button(card,"NextWeapon",">",w-48,91,36,32,function() cycle(1) end)
			local team=self:button(card,"Team","",12,130,w-24,26,function() self.cfg.slots[i].team=1-(self.cfg.slots[i].team%2) end)
			table.insert(self.refreshers,function()
				local sl=self.cfg.slots[i]
				title.Text=`CPU {i-1}  /  {if sl.type=="off" then "EMPTY" else "IN FIGHT"}`
				toggle.Text=if sl.type=="off" then "+ ADD CPU" else "REMOVE"
				weapon.Text=Weapons.BY_ID[sl.weaponId].name
				team.Visible=string.find(self.cfg.mode,"Teams")~=nil
				team.Text=if sl.team%2==self.cfg.slots[1].team%2 then "TEAM: YOUR SIDE  /  change" else "TEAM: OPPOSITION  /  change"
			end)
			y += 176
		end
	elseif self.page=="Rules" then
		heading("SET THE RULES","Choose the win condition. Items are independent of stocks and time.")
		local modes={}
		for _,m in MatchConfig.MODES do table.insert(modes,{id=m,text=MODE_LABELS[m]}) end
		choices("Mode",modes,function() return self.cfg.mode end,function(id) self.cfg.mode=id end,2)
		label(content,"StockLabel","STOCKS  /  used in stock modes",0,y,w,30,16,TEAL)
		y += 38
		local stocks={}
		for n=MatchConfig.STOCKS.min,MatchConfig.STOCKS.max do table.insert(stocks,{id=n,text=`{n} stocks`}) end
		choices("Stocks",stocks,function() return self.cfg.stocks end,function(id) self.cfg.stocks=id end,5)
		label(content,"TimeLabel","DURATION  /  used in timed modes",0,y,w,30,16,TEAL)
		y += 38
		choices("Time",{{id=60,text="1 minute"},{id=180,text="3 minutes"},{id=300,text="5 minutes"},{id=600,text="10 minutes"}},function() return self.cfg.time end,function(id) self.cfg.time=id end,4)
		choices("Items",{{id=true,text="Items ON"},{id=false,text="Items OFF"}},function() return self.cfg.items end,function(id) self.cfg.items=id end,2)
	elseif self.page=="Controls" then
		heading("KNOW YOUR CONTROLS","Move: WASD / arrow keys / left stick / D-pad. Keyboard and gamepad work throughout a match.")
		for _,a in Bindings.actions do
			local card=box(content,a.id,0,y,w,112,INK)
			label(card,"Action",a.name,12,8,w-24,26,17,AMBER)
			label(card,"Keys",`Keyboard: {Bindings.key(a.id)}   •   Pad: {Bindings.pad(a.id)}`,12,36,w-24,32,14,WHITE)
			label(card,"How",a.hint,12,70,w-24,36,13,DIM)
			y += 124
		end
	end
	self.content.CanvasSize=UDim2.fromOffset(0,y+8)
	self:refresh()
end
function Select.show(self: any, note: string?)
	self.pending=false
	self.note.Text=note or "Build your fight. Choose an arena, a weapon and your opponents."
	self.gui.Enabled=true
	self:build()
end
function Select.waiting(self: any, note: string)
	self.pending,self.note.Text,self.gui.Enabled=true,note,true
	self:refresh()
end
function Select.hide(self: any)
	self.pending,self.gui.Enabled=false,false
end
function Select.openStation(self: any, station: any)
	self.station, self.page = station, station.kind
	if station.kind == "Gate" then self.cfg.stageId = station.id end
	self.title.Text = station.name
	self.shade.BackgroundTransparency = 0.4
	self.content.CanvasPosition = Vector2.new(0, 0)
	self.fit()
	self:show(if station.kind == "Gate" then "ARENA ENTRANCE  /  review your fight" else "Make your choices, then return to the concourse.")
end
function Select.closeStation(self: any)
	if self.pending then return end
	self:hide()
	if self.onClose then self.onClose() end
end
return Select
