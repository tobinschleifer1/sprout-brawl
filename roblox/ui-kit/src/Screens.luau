--!strict
-- Presentation only. Actions are requests; render again from accepted server state.
local Ui = require(script.Parent.Ui)
local Screens = {}
local function place(o: any, x: number, y: number, w: number, h: number): any
 o.Position, o.Size = UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
 return o
end
local function text(parent: Instance, value: string, x: number, y: number, w: number, h: number, size: number?): any
 return place(Ui.text(parent,value,size or 18,Ui.WHITE,Ui.LABEL),x,y,w,h)
end
local function button(parent: Instance, value: string, x: number, y: number, w: number, h: number, callback: () -> (), gold: boolean?): any
 return place(Ui.button(parent,value,if gold then Ui.GOLD else Ui.BLUE,callback,{textColour=if gold then Ui.INK else Ui.WHITE}),x,y,w,h)
end
local function art(parent: Instance, name: string, id: string?, x: number, y: number, w: number, h: number): any
 return place(Ui.art(parent,name,id),x,y,w,h)
end
function Screens.new(parent: Instance, onAction: (any) -> ()): any
 local self: any = setmetatable({}, {__index=Screens})
 self.gui=Ui.make('ScreenGui',parent,{Name='BlockfallPixelUI',ResetOnSpawn=false,IgnoreGuiInset=false,DisplayOrder=30,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
 self.viewport=Ui.make('Frame',self.gui,{Name='SafeViewport',Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
 self.root=Ui.make('Frame',self.viewport,{Name='DesignCanvas',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(1280,720),BackgroundTransparency=1})
 self.scale=Ui.make('UIScale',self.root,{Scale=1})
 self.onAction=onAction
 self.connections={}
 self.mountedCleanups={}
 self.generation=0
 self.destroyed=false
 local function resize()
  local size=self.viewport.AbsoluteSize
  if size.X>0 and size.Y>0 then self.scale.Scale=math.min(size.X/1280,size.Y/720) end
 end
 table.insert(self.connections,self.viewport:GetPropertyChangedSignal('AbsoluteSize'):Connect(resize))
 resize()
 return self
end
function Screens.send(self: any, action: string, value: any?, slot: any?)
 if self.destroyed then return end
 self.onAction({action=action,value=value,slot=slot,id=self.model.id,revision=self.model.revision})
end
function Screens.mount(self: any, frame: Instance, kind: string, item: any)
 -- Connect existing Canvas2D / KitPortrait renderer through this callback.
 -- It returns an optional cleanup called before rebuilding or destroying the screen.
 if self.model.mountArt then
  local cleanup=self.model.mountArt(frame,kind,item)
  if cleanup then table.insert(self.mountedCleanups,cleanup) end
 end
end
function Screens.clear(self: any)
 for _, cleanup in self.mountedCleanups do cleanup() end
 table.clear(self.mountedCleanups)
 if self.content then self.content:Destroy() end
 self.content=Ui.make('Frame',self.root,{Name='ScreenContent',Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
 self.generation+=1
end
function Screens.show(self: any, page: string, model: any)
 assert(not self.destroyed,'UI already destroyed')
 self:clear()
 self.page,self.model=page,model
 self.gui.Enabled=true
 local p=self.content
 local background=art(p,'Background',model.background,0,0,1280,720)
 background.ScaleType=Enum.ScaleType.Crop
 -- With no image, the current game's canvas is deliberately visible through the GUI.
 text(p,model.title or string.upper(page),24,10,760,50,30).TextXAlignment=Enum.TextXAlignment.Left
 text(p,model.status or '',24,60,1000,28,16).TextXAlignment=Enum.TextXAlignment.Left
 if page=='pick' then self:pick()
 elseif page=='maps' or page=='rules' or page=='board' then self:choices()
 elseif page=='studio' then self:studio()
 elseif page=='hud' then self:hud()
 elseif page=='results' then self:results()
 elseif page=='bazaar' then self:bazaar()
 elseif page=='climb' then self:climb()
 elseif page=='notice' then self:notice()
 else error('Unknown pixel UI page: '..page) end
end
function Screens.pick(self: any)
 local p,m=self.content,self.model
 local weapons=m.weapons or {}
 for i,w in weapons do
  local x=202+((i-1)%6)*146
  local y=94+math.floor((i-1)/6)*78
  local b=button(p,w.name,x,y,134,66,function() self:send('weapon',w.id) end,w.id==m.weapon)
  b.TextSize=15
  if w.image then art(b,'Weapon',w.image,4,4,45,48); b.TextXAlignment=Enum.TextXAlignment.Right end
 end
 local slots=m.slots or {}
 local n=math.max(2,#slots)
 local gap=16
 local width=math.min(380,math.floor((1232-(n-1)*gap)/n))
 local start=(1280-(n*width+(n-1)*gap))/2
 for i,slot in slots do
  local x=start+(i-1)*(width+gap)
  local fighter=art(p,'Fighter'..i,slot.image,x,254,width,208)
  self:mount(fighter,'fighter',slot)
  local card=place(Ui.panel(p,'Slot'..i,slot.teamColour or Ui.BLUE,(if slot.isLocal then 'YOU · ' else '')..slot.name,30),x,464,width,172)
  if slot.empty then
   button(card,'+ ADD BOT',8,52,width-16,42,function() self:send('bot',m.difficulty or 'normal',i) end)
  else
   text(card,slot.weaponName or '',8,32,width-16,26,18)
   for j,stat in slot.stats or {} do
    text(card,stat.name,6,59+(j-1)*24,width*.27,20,12)
    local meter=Ui.meter(card,'Stat'..j)
    place(meter.root,width*.30,64+(j-1)*24,width*.63,12)
    meter:set(stat.value,10)
   end
   if slot.ready then text(p,'READY ✓',x,428,width,28,18).TextColor3=Ui.GREEN end
  end
 end
 button(p,'LEAVE',24,656,136,44,function() self:send('leave') end)
 button(p,'HIDE',176,656,120,44,function() self:send('hide') end)
 button(p,if m.ready then 'UNREADY' else 'READY',510,654,260,48,function() self:send('ready') end,true)
 button(p,'APPEARANCE',1040,656,216,44,function() self:send('appearance') end)
 if m.botVote then
  local vote=place(Ui.panel(p,'BotVote',Ui.GOLD,'BOT PROPOSAL',30),400,292,480,124)
  text(vote,m.botVote.message or 'Change bot?',10,34,460,32,18)
  button(vote,'YES',20,76,200,36,function() self:send('ballot',true) end)
  button(vote,'NO',260,76,200,36,function() self:send('ballot',false) end)
 end
end
function Screens.choices(self: any)
 local p,m=self.content,self.model
 local list=m.choices or {}
 local cols=if self.page=='rules' then 2 else 3
 local width=math.floor(1200/cols)-16
 local rows=math.max(1,math.ceil(#list/cols))
 local height=math.min(238,math.floor(530/rows)-12)
 for i,c in list do
  local x=40+(i-1)%cols*(width+16)
  local y=104+math.floor((i-1)/cols)*(height+12)
  local b=button(p,'',x,y,width,height,function() self:send(if self.page=='maps' then 'vote' elseif self.page=='rules' then 'rule' else 'choose',c.id) end,c.id==m.selected)
  local image=art(b,'Preview',c.image,4,4,width-8,math.max(0,height-64))
  self:mount(image,'choice',c)
  text(b,c.name,8,height-60,width-16,28,18)
  text(b,c.detail or ('Votes: '..tostring(c.votes or 0)),8,height-30,width-16,25,13)
 end
 text(p,if m.seconds then tostring(m.seconds)..'s' else '',1120,16,128,50,30).TextColor3=Ui.GOLD
 button(p,'BACK',24,656,140,44,function() self:send('back') end)
end
function Screens.studio(self: any)
 local p,m=self.content,self.model
 text(p,'SESSION-ONLY SAVES',810,20,260,30,16).TextColor3=Ui.GOLD
 button(p,'CLOSE',1100,14,152,44,function() self:send('close') end)
 local preview=art(p,'AvatarPreview',m.image,24,138,400,398)
 self:mount(preview,'avatar',m.avatar)
 local name=Ui.make('TextBox',p,{Name='FighterName',Text=m.name or '',PlaceholderText='Fighter name',ClearTextOnFocus=false,Font=Ui.BODY,TextSize=22,TextColor3=Ui.WHITE,BackgroundColor3=Ui.PANEL,BorderSizePixel=0})
 place(name,24,98,400,40)
 name.FocusLost:Connect(function() self:send('name',name.Text) end)
 for i,g in m.groups or {} do
  button(p,g.name,448+(i-1)*134,98,126,42,function() self:send('group',g.id) end,g.id==m.group).TextSize=14
 end
 local category=Ui.make('ScrollingFrame',p,{Name='Categories',BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(#(m.categories or {})*160,0),ScrollBarThickness=4,ScrollingDirection=Enum.ScrollingDirection.X})
 place(category,448,150,804,42)
 for i,c in m.categories or {} do button(category,c.name,(i-1)*160,0,150,36,function() self:send('category',c.id) end,c.id==m.category).TextSize=14 end
 local grid=Ui.make('ScrollingFrame',p,{Name='Options',BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,math.ceil(#(m.options or {})/4)*118),ScrollBarThickness=6})
 place(grid,448,206,804,300)
 for i,o in m.options or {} do
  local b=button(grid,o.name,((i-1)%4)*198,math.floor((i-1)/4)*118,186,108,function() self:send('option',o.id) end,o.id==m.option)
  b.TextSize=14
  if o.image then art(b,'Part',o.image,35,4,116,74); b.TextYAlignment=Enum.TextYAlignment.Bottom end
 end
 for i,c in m.colors or {} do
  local b=button(p,if i==m.color then '✓' else '',448+(i-1)*52,520,44,40,function() self:send('color',i) end)
  Ui.paint(b,c)
 end
 for i,pose in {'Stand','Run','Jump','Attack','Cheer'} do button(p,pose,24+(i-1)*80,554,74,38,function() self:send('pose',string.lower(pose)) end).TextSize=12 end
 button(p,'TURN',24,602,120,38,function() self:send('turn') end)
 button(p,'ZOOM',154,602,120,38,function() self:send('zoom') end)
 button(p,'SLOTS',284,602,140,38,function() self:send('slots') end)
 button(p,if m.locked then 'UNLOCK PART' else 'LOCK PART',448,580,240,42,function() self:send('lock') end)
 button(p,'RANDOM PART',708,580,240,42,function() self:send('random') end)
 button(p,'DELETE',24,662,120,38,function() self:send('delete') end)
 for i,item in {{'UNDO','undo'},{'REDO','redo'},{'SAVE AS NEW','saveNew'},{'SAVE & WEAR','save'}} do
  local b=button(p,item[1],448+(i-1)*202,656,192,44,function() self:send(item[2]) end,i==4)
  if (i==1 and not m.canUndo) or (i==2 and not m.canRedo) then b.Interactable=false; b.AutoButtonColor=false; b.TextTransparency=.55 end
 end
end
function Screens.hud(self: any)
 self.hudTiles={}
 local p,m=self.content,self.model
 local n=math.max(1,#(m.fighters or {}))
 local width=math.min(286,math.floor(1232/n)-12)
 local start=(1280-n*(width+12)+12)/2
 for i,f in m.fighters or {} do
  local card=place(Ui.panel(p,'FighterHUD'..i,f.teamColour or Ui.BLUE,(if f.isLocal then '◆ ' else '')..f.name,25),start+(i-1)*(width+12),594,width,106)
  local damage=text(card,'0%',5,26,width-10,38,30)
  local stock=text(card,'',6,64,width-12,18,14)
  local meter=Ui.meter(card,'Ultimate',10)
  place(meter.root,8,88,width-16,10)
  self.hudTiles[i]={damage=damage,stock=stock,meter=meter,card=card}
 end
 self.clock=text(p,'',535,14,210,42,30)
 self.ability=text(p,'',24,540,420,32,18)
 if m.spectating then button(p,'STOP WATCHING',1030,20,226,42,function() self:send('stopWatching') end) end
 self:updateHud(m)
end
function Screens.updateHud(self: any, m: any)
 -- Call each snapshot: mutates existing instances instead of rebuilding the screen.
 assert(self.page=='hud','updateHud requires hud page')
 assert(#(m.fighters or {})==#self.hudTiles,'Roster changed: call show again')
 self.clock.Text=if m.timed then (m.clock or '') else ''
 self.ability.Text=if m.spectating then '' else (m.ability or '')
 for i,f in m.fighters or {} do
  local tile=self.hudTiles[i]
  tile.damage.Text=tostring(math.floor((f.damage or 0)+.5))..'%'
  tile.damage.TextColor3=f.damageColour or Ui.WHITE
  tile.stock.Text=if f.eliminated then 'OUT' else string.rep('■ ',math.clamp(f.stocks or 0,0,9))
  tile.card.BackgroundTransparency=if f.eliminated then .55 else 0
  tile.meter:set(f.ultimate or 0,100)
 end
end
function Screens.results(self: any)
 local p,m=self.content,self.model
 local list=m.players or {}
 local n=math.max(1,#list)
 local width=math.min(450,math.floor(1200/n)-12)
 local start=(1280-n*(width+12)+12)/2
 for i,f in list do
  local x=start+(i-1)*(width+12)
  local image=art(p,'PodiumFighter'..i,f.image,x,180,width,290)
  self:mount(image,'podium',f)
  local card=place(Ui.panel(p,'Rank'..i,f.teamColour or Ui.BLUE,'#'..tostring(f.rank)..' · '..f.name,32),x,470,width,138)
  text(card,f.summary or '',8,40,width-16,82,18).TextWrapped=true
 end
 button(p,'SAY GG!',500,648,280,50,function() self:send('gg') end,true)
 text(p,m.returnStatus or '',930,655,326,36,16)
end
function Screens.bazaar(self: any)
 local p,m=self.content,self.model
 if m.prompt then button(p,m.prompt,460,534,360,44,function() self:send('interact') end,true) end
 for i,label in {'STAMP','SAY','PEOPLE','MAP'} do button(p,label,210+(i-1)*218,648,204,48,function() self:send(string.lower(label)) end) end
 button(p,'CHARACTER',1030,20,226,44,function() self:send('appearance') end)
end
function Screens.climb(self: any)
 local p,m=self.content,self.model
 text(p,string.format('CHECKPOINT %s  ·  TIME %s  ·  FALLS %s',m.checkpoint or 0,m.time or '0:00',m.falls or 0),250,20,780,46,24)
 for i,item in {{'LEAVE','leave'},{'RESTART','restart'},{'RECORDS','records'}} do button(p,item[1],24+(i-1)*180,650,164,44,function() self:send(item[2]) end) end
 if m.canSkip then button(p,'PAID SKIP',1050,650,206,44,function() self:send('requestPurchase') end) end
end
function Screens.notice(self: any)
 local p,m=self.content,self.model
 local card=place(Ui.panel(p,'Notice',if m.error then Ui.RED else Ui.BLUE,m.heading or 'GET READY',42),360,224,560,240)
 text(card,m.message or '',24,58,512,104,22).TextWrapped=true
 if m.error then button(card,'OK',180,176,200,44,function() self:send('acknowledge') end) end
end
function Screens.destroy(self: any)
 if self.destroyed then return end
 for _,cleanup in self.mountedCleanups do cleanup() end
 for _,connection in self.connections do connection:Disconnect() end
 self.gui:Destroy()
 self.destroyed=true
end
return Screens
