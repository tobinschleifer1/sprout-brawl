--!nocheck
-- Phase 6: direct promises, using the shipping catalogue, server loop, renderer and UI.
-- Every assertion group has a targeted mutation in tools/mutate-movement.py --suite emotes.
local fs, luau, Rbx = require('@lune/fs'), require('@lune/luau'), require('@lune/roblox')
local Loader = require('./loader')
local Cosmetics, Inventory, Loot, Products = Loader.load('Cosmetics'), Loader.load('Inventory'), Loader.load('Loot'), Loader.load('Products')
local Loadout, Input, Codec = Loader.load('Loadout'), Loader.load('Input'), Loader.load('InputCodec')
local Emotes = Loader.loadFrom('src/client/', 'Emotes')
local Events = Loader.loadFrom('src/server/', 'EmoteEvents')
local Locker = Loader.loadFrom('src/server/', 'Locker')
local Shop = Loader.loadFrom('src/server/', 'Shop')
local Fx = Loader.loadFrom('src/client/', 'FxPlayer')
local Posed = Loader.loadFrom('src/client/', 'PosedFighter')
local Channels = Loader.loadFrom('src/client/', 'Channels')
local WeaponPose = Loader.loadFrom('src/client/', 'WeaponPose')
local Posture = Loader.loadFrom('src/client/', 'Posture')
local F2 = Loader.loadFrom('src/client/', 'Fighter2D')
local Canvas = Loader.loadFrom('src/client/', 'Canvas2D')
local ItemArt = Loader.loadFrom('src/client/', 'ItemArt')
local Recorder = require('../tools/recorder')
local function near(a,b,msg,eps) assert(math.abs(a-b) < (eps or 1e-8), msg) end
local function distance(a,b)
 local d=0; for k,v in a do d += math.abs(v-b[k]) end; return d
end
local items, free, sources, rarities = {}, {}, {}, {}
for _,it in Cosmetics.LIST do
 if it.type == 'emote' or it.type == 'victory_pose' then
  table.insert(items,it); sources[it.source]=(sources[it.source] or 0)+1
  assert(Emotes.CLIPS[it.id] and it.blurb and #it.blurb>15, 'pose item lacks authored clip or description')
  if it.source == 'free' then table.insert(free,it) end
  if it.source == 'crate' then
   rarities[it.rarity]=true
   assert(Loot.craftCost(it.id)==Loot.RARITY[it.rarity].craft, 'crate emote is not craftable')
   for _,c in it.crates do assert(table.find(Loot.pool(c)[it.rarity],it.id), 'crate emote absent from its pool') end
  else
   assert(Loot.craftCost(it.id)==nil, 'exclusive pose is craftable')
   for c in Loot.CRATES do for _,o in Loot.odds(c,0) do assert(o.id~=it.id,'exclusive emote leaked into crate') end end
  end
 end
end
local emoteCount=0; for _,it in items do if it.type=='emote' then emoteCount+=1 end end
assert(emoteCount==12,'catalogue needs twelve emotes and six poses')
assert(Inventory.DEFAULT_EMOTES.neutral=='emote_wave' and Inventory.DEFAULT_EMOTES.forward=='emote_challenge' and Inventory.DEFAULT_EMOTES.up=='emote_cheer' and Inventory.DEFAULT_EMOTES.down=='emote_bow','direction defaults changed')
assert(#items==18 and #free==5 and sources.shop==2 and sources.pass==1 and sources.crate==10, 'phase six catalogue distribution')
for _,r in Cosmetics.RARITIES do assert(rarities[r], 'emote crate rarities incomplete') end
assert(table.find(Products.PASS_ITEMS.vip,'emote_vip'), 'VIP emote not granted by pass')
local featured={}
for d=20000,21000 do for _,f in Shop.featured(d) do
 local it=Cosmetics.get(f.id)
 assert(it.source=='crate' or it.source=='shop','free or pass item sold in shop')
 featured[f.id]=true
end end
assert(featured.emote_lunge and featured.pose_duelist,'shop-only poses never offered')

-- Free items have no transferable/salvageable instances, including hostile old records.
for _,raw in { {}, { owned={ emote_wave=true,pose_champion=true } },
 { items={ u1={ i='emote_wave',p=false },u2={ i='pose_champion',p=false } } } } do
 local inv=Inventory.sanitize(raw)
 for _,it in free do
  assert(Inventory.owns(inv,it.id),'free item not owned by everyone')
  assert(Inventory.copies(inv,it.id)==0,'free item has transferable instance')
  assert(Inventory.add(inv,it.id,10,false,'grant',1)==nil,'free item can be minted')
 end
end
local inv=Inventory.sanitize({ owned={ emote_disco=true,pose_star=true }, equipped={
 emoteNeutral='emote_wave',emoteForward='emote_disco',emoteUp='pose_star',emoteDown='emote_flex',pose='pose_star', extra='emote_wave' } })
assert(inv.equipped.emoteNeutral=='emote_wave' and inv.equipped.emoteForward=='emote_disco' and inv.equipped.pose=='pose_star','owned pose slots lost on sanitize')
assert(not inv.equipped.emoteUp and not inv.equipped.emoteDown and not inv.equipped.extra,'unowned or misplaced emote survives sanitize')
local owns=function(id) return Inventory.owns(inv,id) end
for _,direction in Inventory.EMOTE_ORDER do
 local key=Inventory.EMOTE_SLOTS[direction]
 assert(Inventory.equip(inv,'emote_disco',owns,key) and inv.equipped[key]=='emote_disco','emote direction did not equip')
 local copy=Inventory.loadout(inv); copy[key]=nil
 assert(inv.equipped[key]=='emote_disco','loadout aliases equipped emotes')
 assert(Inventory.equip(inv,nil,owns,key) and not inv.equipped[key],'emote direction did not come off')
 assert(Emotes.idFor(inv.equipped,direction)==Inventory.DEFAULT_EMOTES[direction],'empty direction lost free fallback')
end
for _,bad in { 'pose','hit','unknown' } do assert(not Inventory.equip(inv,'emote_disco',owns,bad),'emote accepted invalid slot') end
assert(not Inventory.equip(inv,'emote_flex',owns,'emoteUp'),'unowned emote equipped')
assert(not Inventory.equip(inv,'emote_disco',owns),'emote equipped without choosing direction')
assert(Emotes.poseFor({pose='emote_wave'})=='pose_champion','invalid podium pose lacks fallback')
local st={ records={},dirty={},clock=function() return 1 end }
function st:load(id) self.records[id]=self.records[id] or {inventory=Inventory.sanitize(nil)};return self.records[id] end
local locker=Locker.new({store=st,studio=false})
for _,it in free do assert(locker:owns(1,it.id),'locker hides free entitlement') end
assert(locker:apply(1,{action='equip',id='emote_cheer',slot='emoteUp'}) and locker:loadout(1).emoteUp=='emote_cheer' and st.dirty[1],'locker dropped chosen emote direction')
assert(locker:apply(1,{action='remove',slot='emoteUp'}) and not locker:loadout(1).emoteUp,'locker cannot clear emote direction')
local li=locker:inventory(1)
Inventory.add(li,'emote_disco',1,false,'crate',1)
for _,key in Inventory.EMOTE_SLOTS do assert(locker:apply(1,{action='equip',id='emote_disco',slot=key})) end
assert(locker:apply(1,{action='savePreset',slot=1}))
for uid,it in li.items do if it.i=='emote_disco' then Inventory.remove(li,uid) end end
for _,key in Inventory.EMOTE_SLOTS do assert(not li.equipped[key],'last copy left an emote equipped') end
assert(locker:apply(1,{action='wearPreset',slot=1}))
for _,key in Inventory.EMOTE_SLOTS do assert(not li.equipped[key],'preset restores unowned directional emote') end
local studio=Locker.new({store=st,studio=true})
assert(studio:apply(2,{action='equip',id='emote_disco',slot='emoteDown'}))
assert(studio:loadout(2).emoteDown=='emote_disco','Studio showcase discarded chosen emote')

-- True server entry: the consumed frame, facing, and every tick in a catch-up batch.
local messages={}
local codes=setmetatable({},{__index=function(_,k)return k end})
local shared=setmetatable({Data=setmetatable({},{__index=function(_,k)return 'Data/'..k end})},{__index=function(_,k)return k end})
local Service=luau.load(fs.readFile('src/server/MatchService.luau'),{environment={
 game={GetService=function(_,name) if name=='ReplicatedStorage' then return {Shared=shared} end
  return {PostSimulation={Connect=function()return {Disconnect=function()end}end}} end},
 script={Parent=codes},
 require=function(name)
  if name=='Net' then return {remote=function(remote)return {
   FireAllClients=function(_,data) if remote=='Events' then for _,e in data do if e.type=='emote' then table.insert(messages,e) end end end end,
   FireClient=function()end } end} end
  if name=='RemoteInput' or name=='EmoteEvents' then return Loader.loadFrom('src/server/',name) end
  return Loader.load(name)
 end,
},injectGlobals=true})()
local svc=Service.new()
svc:start({{player={UserId=1,DisplayName='One'},avatar='Classic',weapon='Sword'},
 {player={UserId=2,DisplayName='Two'},avatar='Classic',weapon='Sword'}},{mode='Training',seed=7})
local m=svc.match; m.state='fight'
local f=m.fighters[1]
local function reset(facing)
 f:reset(-8,m.stage.main.top,{state='idle',invincible=0}); f.onGround=true; f.platform=m.stage.main; f.facing=facing
 m.fighters[2]:reset(20,m.stage.main.top,{state='idle',invincible=0}); m.fighters[2].onGround=true
 for key in f.buffer do f.buffer[key]=0 end
 svc.emotes={}; m.events={}; svc.input:register('p1'); table.clear(messages)
end
local function tick(values,dt)
 local input=Input.emptyFrame(); for k,v in values do input[k]=v end
 svc.input:push('p1',{Codec.packFrame(input)}); svc:tick(dt or 1/60)
end
local cases={{0,0,1,'neutral'},{1,0,1,'forward'},{-1,0,-1,'forward'},{-1,0,1,'neutral'},{1,0,-1,'neutral'},
 {0,1,1,'up'},{0,-1,1,'down'},{1,1,1,'up'},{-1,-1,-1,'down'}}
for _,case in cases do
 reset(case[3]); tick({taunt=true,anyPress=true,x=case[1],y=case[2]})
 assert(f.state=='taunt' and f.sf==0,'taunt simulation entry changed')
 assert(#messages==1 and messages[1].type=='emote' and messages[1].fighter==0 and messages[1].slot==case[4],'server sent wrong emote slot or facing')
 assert(messages[1].start==f.frameCount,'event lost entry identity')
 local joined=svc:description().emotes[1]
 assert(joined and joined.slot==case[4],'late join lost active emote')
 tick({x=-case[1],y=-case[2]},4/60)
 assert(#messages==1,'holding direction repeats or changes emote event')
 for _=1,6 do tick({}) end
 tick({light=true,anyPress=true})
 assert(f.state~='taunt' and svc.emotes[0]==nil,'cancelled taunt kept active event')
end
-- A buffered taunt starts on the new frame's stick, not the earlier press's stick.
reset(1); f:setState('landing'); f.sf=0
tick({taunt=true,anyPress=true,y=1})
local buffered=false
for _=1,6 do tick({y=-1}); if f.state=='taunt' then buffered=true;break end end
assert(buffered and messages[#messages].slot=='down','buffered taunt used press direction instead of entry direction')
reset(1); tick({taunt=true,anyPress=true},4/60)
assert(#messages==1 and messages[1].start==f.frameCount-3,'catch-up tick missed emote entry')
for _=1,88 do tick({}) end
assert(f.state=='idle' and #svc:description().emotes==0,'emote changed taunt duration or left stale join state')

-- Events before/after snapshots, stale delivery, cancellation, and match reset.
local char=table.clone(Loadout.build('Classic','Sword')); char.cosmetics={skins={},emoteUp='emote_disco',pose='pose_star'}
local player=Fx.new()
local event={type='emote',fighter=0,slot='up',start=100}
assert(Fx.spawn(player,event,{}, {}) and player.emotes[0]==event and #player.items==0,'emote event lost or allocated effect sprites')
local s=Posed.posed(char,0,'taunt',42); s.frameCount=142
near(distance(Emotes.For(s,char,player.emotes[0]),Emotes.sample('emote_disco',42)),0,'client ignored equipped directional emote')
Fx.spawn(player,{type='emote',fighter=0,slot='down',start=90},{},{})
assert(player.emotes[0]==event,'late event overwrote current taunt')
s.state='idle'; assert(Emotes.For(s,char,event)==nil,'cancelled emote still poses fighter')
s.state='hitstun'; assert(Emotes.For(s,char,event)==nil,'hit fighter retains emote pose')
s.state='taunt'; s.frameCount=242
near(distance(Emotes.For(s,char,event),Emotes.sample('emote_wave',42)),0,'stale event animates next taunt')
Fx.clear(player); assert(next(player.emotes)==nil,'new match retains emote events')

-- Execute the shipping receiver: emotes must be available to an ahead-of-view predicted fighter,
-- while ordinary effects still wait on the interpolated scene. No copy of the handler's logic.
local clientSource=fs.readFile('src/client/init.client.luau')
local receiver
local first=assert(string.find(clientSource,'Net.remote("Events").OnClientEvent:Connect',1,true))
local last=assert(string.find(clientSource,'-- ---------------------------------------------------------------- interpolation',first,true))
receiver=string.sub(clientSource,first,last-1)
local received, pending = Fx.new(), {}
local callback
luau.load(receiver,{environment={Net={remote=function()return {OnClientEvent={Connect=function(_,fn)callback=fn end}}end},
 FxPlayer=Fx,fxPlayer=received,pendingFx=pending,hud=nil},injectGlobals=true})()
callback({event},10000)
assert(received.emotes[0]==event and #pending==0,'client receiver delays emote behind interpolation')
callback({{type='land'}},105)
assert(#pending==1 and pending[1].frame==105,'emote routing changed ordinary effect timing')
-- The real match initialization fragment clears the preceding match before restoring a join.
local restoreStart=assert(string.find(clientSource,'FxPlayer.clear(fxPlayer)',1,true))
local restoreEnd=assert(string.find(clientSource,'pendingFx = {}',restoreStart,true))
luau.load(string.sub(clientSource,restoreStart,restoreEnd-1),{environment={FxPlayer=Fx,fxPlayer=received,
 cfg={emotes={{type='emote',fighter=1,slot='down',start=200}}}},injectGlobals=true})()
assert(received.emotes[0]==nil and received.emotes[1] and received.emotes[1].slot=='down','client join did not restore active emote')

-- All channels interpolate continuously, settle to stance, and differ from every other item.
for i,it in items do
 local key=Emotes.sample(it.id,42)
 assert(distance(key,Emotes.STANCE)>30,'emote key is plain stance')
 for j=1,i-1 do assert(distance(key,Emotes.sample(items[j].id,42))>15,'two catalogue poses share a silhouette') end
 for _,frame in {0,90,100} do near(distance(Emotes.sample(it.id,frame),Emotes.STANCE),0,'emote does not end at stance') end
 for _,frame in {24,42,64} do
  assert(distance(Emotes.sample(it.id,frame-0.001),Emotes.sample(it.id,frame+0.001))<0.001,'pose jumps between keyframes')
 end
 local a,b=Emotes.sample(it.id,24),Emotes.sample(it.id,42)
 local mid=Emotes.sample(it.id,33)
 for k,v in mid do near(v,(a[k]+b[k])/2,'pose sampler does not interpolate keyframes') end
 local snap=Posed.posed(char,0,'taunt',42)
 local ch,wp=Channels.For(snap,char,nil,0),WeaponPose.For(snap,char,nil,0)
 local plain=Posture.For(ch,snap,char,wp,nil,0)
 Emotes.apply(ch,wp,key,char)
 local p=Posture.For(ch,snap,char,wp,nil,0)
 for frame=0,90,0.25 do
  local before=Channels.For(snap,char,nil,0);local after=Channels.For(snap,char,nil,0)
  Emotes.apply(before,{},Emotes.sample(it.id,frame),char)
  Emotes.apply(after,{},Emotes.sample(it.id,frame+0.001),char)
  near(before.bob,after.bob,'applied pose height jumps',0.001)
 end
 assert(math.abs(p.back.ex-plain.back.ex)+math.abs(p.back.ey-plain.back.ey)+math.abs(p.front.ex-plain.front.ex)+math.abs(p.front.ey-plain.front.ey)>0.5,'item still draws plain taunt')
 for leg,L in p.legs do
  assert(L.pose.ey+ch.bob>=-1e-8,'emote foot below floor')
  if key[if leg==1 then 'kneeL' else 'kneeR']==0 then near(L.pose.ey+ch.bob,0,'emote support foot floats') end
 end
end

-- Shipping draw: constant sprite set and count, at full and half detail, with single/paired/boot
-- weapons and both facings. Capture body and weapon grip transforms, not only sampled numbers.
local shapes=Recorder.install(Canvas)
local originalSprite, originalPosture = Canvas.sprite, Posture.For
local sprites,lastP,lastCh={},nil,nil
Canvas.sprite=function(c,key,...)
 table.insert(sprites,{key=key,m=table.clone(c.m)}); return originalSprite(c,key,...)
end
Posture.For=function(ch,...)
 lastCh=ch; lastP=originalPosture(ch,...);return lastP
end
local peakSprites,peakRects,draws=0,0,0
local elapsed=os.clock()
for _,weapon in {'Sword','Daggers','RocketBoots'} do
 local cchar=table.clone(Loadout.build('Classic',weapon)); cchar.cosmetics={skins={}}
 for _,scale in {26,5} do
  local baseline
  for _,it in items do for _,facing in {1,-1} do
   cchar.cosmetics.emoteNeutral,cchar.cosmetics.pose=it.id,it.id
   local snap=Posed.posed(cchar,0,if it.type=='emote' then 'taunt' else 'victory',42); snap.facing=facing
   table.clear(sprites);table.clear(shapes)
   local cv=Recorder.canvas(Canvas,300,260);Canvas.setTransform(cv,scale,0,0,-scale,150,220)
   F2.draw(cv,snap,cchar,0,nil)
   local body,weaponCount=0,0
   for _,sp in sprites do
    if string.sub(sp.key,1,7)=='weapon|' then weaponCount+=1 else body+=1 end
   end
   assert(body==(if scale==26 then 12 else 8),'emote adds body sprites beyond pose budget')
   assert(weaponCount==(if weapon=='Sword' then 1 else 2),'emote drops or duplicates held weapon')
   if not baseline then baseline=#sprites end
   assert(#sprites==baseline,'emote adds sprites beyond ordinary pose')
   local expected=Emotes.sample(it.id,42)
   assert(lastCh.emote,'Fighter2D skipped emote override')
   near(lastCh.emote.front,expected.front,'Fighter2D skipped emote override')
   near(lastCh.emote.back,expected.back,'Fighter2D ignored worn victory pose')
   local gx,gy=Posture.torsoPoint(lastCh,cchar.height,cchar.radius*0.55+math.cos(math.rad(expected.front))*cchar.height*0.30*expected.frontExt,
    cchar.height*0.36+math.sin(math.rad(expected.front))*cchar.height*0.30*expected.frontExt)
   near(lastP.front.ex,gx,'emote main grip detached');near(lastP.front.ey,gy,'emote main grip detached')
   if weapon=='Daggers' then near(lastP.offX,lastP.back.ex,'emote second grip detached');near(lastP.offY,lastP.back.ey,'emote second grip detached') end
   peakSprites=math.max(peakSprites,#sprites);peakRects=math.max(peakRects,#shapes);draws+=1
  end end
 end
end
-- The live scene hands the retained event to Fighter2D and clears it again for previews.
local Scene=Loader.loadFrom('src/client/','FightScene')
local state=Posed.posed(char,0,'taunt',42);state.frameCount=142
Fx.spawn(player,event,{},{})
Scene.draw(Recorder.canvas(Canvas,300,260),{view={x=0,y=3,ppu=26},shakeX=0,shakeY=0,
 states={state},chars={char},t=0,player=player,fx=Loader.loadFrom('src/client/','Effects').new()})
assert(lastCh.emote.front==Emotes.sample('emote_disco',42).front,'live scene ignores emote event')
assert(F2.emotes==nil,'live scene leaks emote events to previews')
Posture.For=originalPosture; Canvas.sprite=originalSprite
-- Thumbnails draw the same shipping key frame, not a generic effect or icon.
local realDraw=F2.draw
local thumbCalls={}
F2.draw=function(c,s,ch,t,top) table.insert(thumbCalls,{s=s,char=ch});return realDraw(c,s,ch,t,top) end
Canvas.finish=function()end
for _,it in items do
 local kind,arg=ItemArt.plan(it.id)
 assert(kind=='pose' and arg.id==it.id and arg.frame==42,'thumbnail not the item key frame')
 local cv=Recorder.canvas(Canvas,150,78);ItemArt.draw(cv,it.id,150,78)
 local call=thumbCalls[#thumbCalls]
 assert(call and call.s.stateFrame==42 and (if it.type=='emote' then call.char.cosmetics.emoteNeutral else call.char.cosmetics.pose)==it.id,'thumbnail draws wrong item')
end
F2.draw=realDraw

-- Real Locker buttons and PodiumView, with a GUI stub that exposes the rendered state.
local new=Recorder.gui(1280,720)
Loader.gui={Instance={new=new},UDim=Rbx.UDim,UDim2=Rbx.UDim2,Enum=setmetatable({},{__index=function()return codes end})}
local Screen=Loader.loadFrom('src/client/','LockerScreen')
local requests={}
local ui=Screen.new(new('ScreenGui'),{sendLocker=function(msg)table.insert(requests,msg)end,sendEconomy=function()end,drawArt=function()end})
ui:setLocker({owned={'emote_wave'},wearing={skins={}},presets={false}})
local card=ui.cardPool[1]
assert(card.direction.Visible and not card.secondary.Visible and string.find(card.meta.Text,'Free'),'free emote card lacks direction or offers salvage')
for _,direction in Inventory.EMOTE_ORDER do
 card.primary.Activated:Fire()
 assert(requests[#requests].slot==Inventory.EMOTE_SLOTS[direction] and requests[#requests].action=='equip','Locker button sends wrong direction')
 ui:setLocker({owned={'emote_wave'},wearing={skins={},[Inventory.EMOTE_SLOTS[direction]]='emote_wave'},presets={false}})
 assert(card.primary.Text=='TAKE OFF','selected emote slot is not marked worn')
 card.primary.Activated:Fire()
 assert(requests[#requests].action=='remove' and requests[#requests].slot==Inventory.EMOTE_SLOTS[direction],'Locker button clears wrong direction')
 card.direction.Activated:Fire()
end
local Podium=Loader.loadFrom('src/client/','PodiumView')
local chars={table.clone(char),table.clone(char),table.clone(char)}
chars[1].cosmetics={skins={},pose='pose_duelist'};chars[2].cosmetics={skins={},pose='pose_thinker'};chars[3].cosmetics={skins={}}
local rows={};for i=1,3 do rows[i]={index=i-1,team=if i<=2 then 0 else 1,name='Player',kos=0,falls=0,sds=0,damage=0,taken=0} end
local drawn={}; F2.draw=function(_,s,ch) table.insert(drawn,{s=s,char=ch}) end
local podium=Podium.new(new('ScreenGui'),{rows=rows,teams=true,winnerTeam=0},chars,Rbx.Vector2.new(1280,720),nil)
podium:draw(0)
assert(#drawn==3 and drawn[1].s.victoryPose=='pose_duelist' and drawn[2].s.victoryPose=='pose_thinker','podium did not use each winners worn pose')
assert(drawn[3].s.state=='defeat' and not drawn[3].s.victoryPose,'loser uses victory cosmetic')
chars[1].cosmetics={skins={}}; table.clear(drawn);podium:draw(1)
assert(drawn[1].s.victoryPose=='pose_champion','podium missing free default')
F2.draw=realDraw
print(string.format('PASS emotes: 18 distinct clips, 5 free entitlements, four slots, real server events, continuity, cancellation, thumbnails, Locker buttons and team podium; %d draws, peak %d sprites / %d rectangles; %.3f ms/draw (Lune recorder)',draws,peakSprites,peakRects,(os.clock()-elapsed)*1000/draws))
