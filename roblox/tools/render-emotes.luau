--!nocheck
-- Shipping key frames for visual review. JSON -> tools/fight-png.mjs; frame labels name each item.
-- lune run tools/render-emotes <out.json> [pixels-per-stud=26] [weapon=Sword]
local fs, process, serde = require('@lune/fs'), require('@lune/process'), require('@lune/serde')
local Rbx = require('@lune/roblox')
local Loader = require('../tests/loader')
local Recorder = require('./recorder')
local Cosmetics, Loadout = Loader.load('Cosmetics'), Loader.load('Loadout')
local Canvas, F2 = Loader.loadFrom('src/client/','Canvas2D'), Loader.loadFrom('src/client/','Fighter2D')
local Posed = Loader.loadFrom('src/client/','PosedFighter')
local ItemArt = Loader.loadFrom('src/client/','ItemArt')
local shapes = Recorder.install(Canvas)
Canvas.finish=function()end
local scale=tonumber(process.args[2]) or 26
local weapon=process.args[3] or 'Sword'
local W,H=260,260
local frames={}
for _,it in Cosmetics.LIST do
 if it.type~='emote' and it.type~='victory_pose' then continue end
 table.clear(shapes)
 local cv=Recorder.canvas(Canvas,W,H)
 Canvas.screen(cv); Canvas.rect(cv,0,0,W,H,Rbx.Color3.fromHex('#22303f'),1)
 if weapon=='tiles' then
  ItemArt.draw(cv,it.id,W,H)
 else
  local char=table.clone(Loadout.build('Classic',weapon))
  char.cosmetics={skins={},emoteNeutral=it.id,pose=it.id}
  Canvas.setTransform(cv,scale,0,0,-scale,W*0.48,H*0.87)
  Canvas.rect(cv,-W/scale,-0.25,W*2/scale,0.25,Rbx.Color3.fromHex('#4a5a46'),1)
  local snap=Posed.posed(char,0,if it.type=='emote' then 'taunt' else 'victory',42)
  F2.draw(cv,snap,char,0,nil)
 end
 table.insert(frames,{frame=#frames,label=it.name,shapes=table.clone(shapes)})
end
fs.writeFile(process.args[1],serde.encode('json',{w=W,h=H,frames=frames}))
print(`{#frames} emote/pose key frames, {weapon}, {scale} pixels/stud`)
