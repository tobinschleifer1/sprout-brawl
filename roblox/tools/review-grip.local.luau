--!nocheck
local Loader = require("../tests/loader")
local C = Loader.loadFrom("src/client/", "Canvas2D")
local Draw = Loader.loadFrom("src/client/", "Fighter2D")
local Parts = Loader.loadFrom("src/client/", "PostureArt").parts
local F, L, S, W = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot"), Loader.load("Weapons")
C.IMAGES = false
C.rect, C.circle, C.ellipse, C.tri, C.line = function()end,function()end,function()end,function()end,function()end
local hand, grip
C.sprite = function(c,key,rects,x0,y1,pw,ph,cols,rows)
 local id=string.match(key,"|(%a+)|")
 if id=="forearm" then
  local P=Parts.forearm
  local x,y=x0+P.ox*pw,y1-(P.oy+P.span)*ph
  hand={c.m.a*x+c.m.c*y+c.m.e,c.m.b*x+c.m.d*y+c.m.f}
 elseif string.find(key,"weapon",1,true)==1 then grip={c.m.e,c.m.f} end
end
for _,wid in {"Sword","Pike","Chakram"} do
 local char=L.build("Classic",wid)
 for _,id in {"LightSide1","SigSide","Ultimate"} do
  local f=F.new({index=0,char=char,x=0,y=0,stocks=3})
  f.onGround,f.invincible,f.facing=true,0,1
  f:setState("idle");f:startMove(id)
  for _,frame in {f.startupEff, f.startupEff+1} do
   f.mf=frame;hand,grip=nil,nil
   local c=C.inFrame({AbsoluteSize={X=800,Y=600}})
   C.setTransform(c,26,0,0,-26,400,300)
   Draw.draw(c,S.decode(S.encode(f)),char,0)
   if hand and grip then print(wid,id,frame,"hand/grip gap studs",math.sqrt((hand[1]-grip[1])^2+(hand[2]-grip[2])^2)/26) end
  end
 end
end
