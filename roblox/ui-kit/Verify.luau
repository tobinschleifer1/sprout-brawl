--!strict
-- Run in Studio: require this ModuleScript, then pass the package modules.
return function(Ui: any, Screens: any)

local host=Instance.new('Folder')
local requests={}
local view=Screens.new(host,function(a) table.insert(requests,a) end)
local cleanup=0
local mount=function() return function() cleanup+=1 end end
view:show('pick',{id='room',revision=7,title='Test',weapon='Sword',weapons={{id='Sword',name='Sword'}},slots={{name='YOU',stats={{name='DMG',value=6}}},{name='OPEN',empty=true}},mountArt=mount})
assert(view.content:FindFirstChild('Slot1'))
assert(view.content:FindFirstChild('Fighter1').Size.Y.Offset==208)
view:send('weapon','Sword')
assert(requests[1].id=='room' and requests[1].revision==7 and requests[1].value=='Sword')
view:show('maps',{choices={{id='sky',name='Sky Temple'}}})
assert(cleanup==2,'art lifecycle cleanup')
view:show('studio',{name='Test',groups={{id='hair',name='HAIR'}},options={{id='short',name='Short'}},colors={Ui.BLUE}})
assert(view.content:FindFirstChild('FighterName').Text=='Test')
view:show('hud',{fighters={{name='YOU',damage=42,stocks=3,ultimate=50}}})
local original=view.hudTiles[1].card
local count=#view.gui:GetDescendants()
for i=1,30 do view:updateHud({fighters={{name='YOU',damage=i,stocks=2,ultimate=100}}}) end
assert(original==view.hudTiles[1].card and count==#view.gui:GetDescendants(),'HUD must not allocate per update')
assert(view.hudTiles[1].damage.Text=='30%')
assert(view.clock.Text=='','stock mode clock')
for _,page in {'rules','board','results','bazaar','climb','notice'} do view:show(page,{}) end
view:destroy()
assert(view.destroyed and #host:GetChildren()==0)
host:Destroy()
return 'PASS: native instances, layout properties, action revision, mount cleanup, editor, ten screen types, allocation-stable HUD, teardown. Unparented test; no live GUI changed.'

end
