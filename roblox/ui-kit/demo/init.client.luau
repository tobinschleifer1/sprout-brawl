--!strict
-- Standalone local UI demonstration. Never copy this fake state adapter into production.
local Players=game:GetService('Players')
local Kit=game:GetService('ReplicatedStorage'):WaitForChild('BlockfallPixelUI')
local Screens=require(Kit.Screens)
local Ui=require(Kit.Ui)
local names={'Sword','Scythe','Blasters','Grimoire','Battle Axe','Warpike','Gauntlets','War Hammer','Longbow','Chain Flail','Shield','Dual Daggers'}
local ids={'Sword','Scythe','Blasters','Grimoire','Axe','Pike','Gauntlets','Hammer','Longbow','Flail','Shield','Daggers'}
local stats={{6,6,7,6},{6,6,6,5},{4,5,7,7},{5,7,6,5},{8,8,4,4},{6,5,5,6},{4,4,9,8},{9,9,3,3},{6,4,5,6},{6,6,5,5},{6,7,5,4},{3,3,9,9}}
local weapons={}
for i,name in names do weapons[i]={id=ids[i],name=name} end
local selected=1
local ui: any
local function pick()
 local values={}
 for i,name in {'DMG','DEF','DEX','SPD'} do values[i]={name=name,value=stats[selected][i]} end
 ui:show('pick',{id='demo',revision=1,title='BLOCKFALL · NATIVE UI DEMO',status='Local example · artwork mounts use your existing game renderer',weapons=weapons,weapon=ids[selected],slots={{name='PLAYER 1',isLocal=true,weaponName=names[selected],stats=values},{name='OPEN SLOT',empty=true} :: any}})
end
ui=Screens.new(Players.LocalPlayer:WaitForChild('PlayerGui'),function(a: any)
 if a.action=='weapon' then selected=table.find(ids,a.value) or 1; pick()
 elseif a.action=='ready' then
  local choices={}
  for _,name in {'Hall of Champions','Bifrost Bridge','Dwarven Forge','Sky Temple','Sunscorch Ruins','Viking Harbor','Crystal Mines','Thunder Canyon','Muspel Peak','Random'} do table.insert(choices,{id=name,name=name}) end
  ui:show('maps',{title='CHOOSE ARENA',choices=choices,status='Local demonstration: select a map to advance'})
 elseif a.action=='vote' then ui:show('rules',{title='MATCH RULES',choices={{id='Tournament',name='Tournament 1v1',detail='3 stocks · items off'},{id='Casual',name='Casual',detail='3 stocks · items on'},{id='Chaos',name='Chaos',detail='3 minutes · all disasters'},{id='current',name='Keep current',detail='Existing rules'}}})
 elseif a.action=='rule' then ui:show('hud',{title='SKY TEMPLE · HUD PREVIEW',status='Use the demo navigation below to change screen.',timed=a.value=='Chaos',clock='2:14',ability='SHIELD READY',fighters={{name='YOU',isLocal=true,damage=42,stocks=3,ultimate=60},{name='RIVAL',isLocal=false,damage=86,stocks=2,ultimate=100}}})
 elseif a.action=='appearance' then
  ui:show('studio',{title='CHARACTER STUDIO',name='My Fighter',groups={{id='presets',name='PRESETS'},{id='body',name='BODY'},{id='face',name='FACE'},{id='hair',name='HAIR'},{id='outfit',name='OUTFIT'},{id='extras',name='EXTRAS'}},group='hair',categories={{id='hair',name='Hair'},{id='facial',name='Facial hair'}},category='hair',options={{id='short',name='Short'},{id='long',name='Long'}},option='short',colors={Ui.GOLD,Ui.BLUE,Ui.RED,Ui.GREEN}})
 elseif a.action=='close' or a.action=='back' or a.action=='leave' then pick()
 else print('[PixelUI demo] Request:',a.action,a.value) end
end)
pick()
-- Navigation belongs to the demo only, outside the game content.
local nav=Ui.make('Frame',ui.gui,{Name='DemoNavigation',BackgroundColor3=Ui.PANEL,Position=UDim2.new(0,8,1,-30),Size=UDim2.fromOffset(570,28),ZIndex=50})
for i,label in {'SELECT','BAZAAR','RESULTS','CLIMB','ERROR'} do
 local b=Ui.button(nav,label,Ui.BLUE,function()
  if i==1 then pick()
  elseif i==2 then ui:show('bazaar',{title='SKYHOLD BAZAAR',prompt='E · USE'})
  elseif i==3 then ui:show('results',{title='VICTORY',players={{name='YOU',rank=1,summary='KOs 3 · Falls 1'},{name='RIVAL',rank=2,summary='KOs 1 · Falls 3'}}})
  elseif i==4 then ui:show('climb',{title='SKY CLIMB',checkpoint=3,time='0:42',falls=1,canSkip=true})
  else ui:show('notice',{title='',heading='HOLD ON',message='Example request failed. Return to your room.',error=true}) end
 end,{small=true,size=12})
 b.Position,b.Size=UDim2.fromOffset((i-1)*114,0),UDim2.fromOffset(108,26)
end
