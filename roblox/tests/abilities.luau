--!strict
-- Real key capture -> codec -> server queue -> Match -> Snapshot -> Predictor -> render channels.
local Loader = require("./loader")
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Input, Codec, Snapshot = Loader.load("Input"), Loader.load("InputCodec"), Loader.load("Snapshot")
local Match, Loadout, Stage = Loader.load("Match"), Loader.load("Loadout"), Loader.load("Stage")
local Remote = Loader.loadFrom("src/server/", "RemoteInput")
local Predictor = Loader.loadFrom("src/client/", "Predictor")
local Channels = Loader.loadFrom("src/client/", "Channels")
local Status = Loader.loadFrom("src/client/", "AbilityStatus")
local held, focused, began = "", false, nil
local codes = setmetatable({}, {__index=function(_,k) return k end})
local Sampler = luau.load(fs.readFile("src/client/InputClient.luau"), {environment={
	Enum={KeyCode=codes,UserInputType=codes,UserInputState=codes,ContextActionResult=codes,
		ContextActionPriority={High={Value=3000}}}, script={Parent={Bindings="Bindings"}},
	require=function(n) return if n=="Bindings" then Loader.loadFrom("src/client/",n) else Input end,
	game={GetService=function(_,n)
		if n=="ReplicatedStorage" then return {Shared={Input="Input"}} end
		if n=="ContextActionService" then return {BindActionAtPriority=function() end} end
		return {WindowFocusReleased={Connect=function() end}, InputBegan={Connect=function(_,fn) began=fn end}, GetFocusedTextBox=function() return if focused then {} else nil end,
			GetConnectedGamepads=function() return {} end, IsKeyDown=function(_,k) return held==k end, IsGamepadButtonDown=function() return false end}
	end},
},injectGlobals=true})()
local sampler=Sampler.new()
local stageData=Loader.load("Data/Stages").LIST[1]
for _, weapon in Loader.load("Data/Weapons").LIST do
	local char=Loadout.build("Classic",weapon.id)
	local input=Remote.new(); input:register("p1"); input:register("p2")
	local match=Match.new({mode="Training",stage=stageData,seed=1,items=false,input=input,
		fighters={{char=char,source="p1",team=0},{char=Loadout.build("Noir","Sword"),source="p2",team=1}}})
	match.state="fight"
	local f, enemy=match.fighters[1],match.fighters[2]
	local pred=Predictor.new(char,0,Stage.new(stageData,1))
	local function reset()
		f:reset(0,0,{state="idle",invincible=0}); f.onGround=true; f.platform=match.stage.main
		enemy:reset(30,0,{state="idle",invincible=0})
		sampler:reset(); held=""
		pred:applyWire(Snapshot.decode(Snapshot.encode(f))); pred.ready=true
	end
	local function step(): any
		local frame=sampler:build(sampler:levels())
		pred:push(frame); input:push("p1",{Codec.packFrame(frame)}); match:step()
		pred:reconcile(Snapshot.decode(Snapshot.encode(f)),input:consumedBy("p1"))
		return pred:state()
	end
	reset(); held="I"; began({KeyCode="I"})
	for _=1,12 do step() end
	assert(f.state=="shield" and f.shield<50,weapon.id..": I activates and drains shield")
	assert(Channels.For(pred:state(),char,nil,0).bubble>0,weapon.id..": local predicted shield is visible")
	local shield=f.shield
	match.combat:resolveHit(enemy,f,enemy.char.moves.LightNeutral1,nil,nil,{})
	assert(f.percent==0 and f.shield<shield,weapon.id..": shield blocks an actual combat hit")
	held=""
	for _=1,60 do step() end
	assert(f.state~="shield", "release lowers the shield")
	reset(); began({KeyCode="O"}); step()
	assert(f.moveId~="Ultimate" and f.ultCharge==0,"empty meter cannot activate")
	local denied=false
	for _,e in match.events do if e.type=="ultdenied" then denied=e.reason=="charge" end end
	assert(denied,"server explains an uncharged denial")
	reset(); f.ultCharge=20; pred:applyWire(Snapshot.decode(Snapshot.encode(f)))
	assert(Status.describe(pred:state(),char):find("READY",1,true),"local full meter shows readiness")
	began({KeyCode="O"}) -- key already released before next sample: the original lost-tap defect
	local state=step()
	assert(f.moveId=="Ultimate" and f.ultCharge==0,weapon.id..": full-meter short O activates on server")
	assert(state.moveId=="Ultimate" and state.ultCharge==0,weapon.id..": local prediction displays activation")
	assert(Status.describe(state,char):find("ULTIMATE: ACTIVE",1,true))
	reset(); focused=true; began({KeyCode="O"}); focused=false; f.ultCharge=20; step()
	assert(f.moveId~="Ultimate", "typing must not latch combat input")
	began({KeyCode="O"}); sampler:reset(); step()
	assert(f.moveId~="Ultimate", "rematch reset discards lobby/menu presses")
end
assert(Status.event({type="ultdenied",reason="grounded"}):find("ground",1,true))
assert(Status.event({type="ultready"}):find("YOUR",1,true))
-- The Chakram's rings (Roblox only): the count and what it leaves, nothing for any other weapon,
-- and a refused throw explained by how many rings it needed.
do
	local chak, sword = Loadout.build("Classic","Chakram"), Loadout.build("Classic","Sword")
	assert(Status.rings({rings=2},chak)=="2/2","both rings in hand")
	assert(Status.rings({rings=1},chak):find("Halo needs both",1,true),"one ring out names what it costs")
	assert(Status.rings({rings=0},chak):find("catch",1,true),"no rings says how to get one back")
	assert(Status.rings({rings=-1},sword)==nil and Status.rings({rings=2},sword)==nil,"a sword has no rings")
	assert(Status.describe({rings=1,ultCharge=0,onGround=true,state="idle"},chak):find("RINGS: 1/2",1,true),"the status line carries the rings")
	assert(not Status.describe({rings=-1,ultCharge=0,onGround=true,state="idle"},sword):find("RINGS",1,true),"no rings for a sword")
	assert(Status.event({type="dryfire",rings=2}):find("both",1,true) and Status.event({type="dryfire",rings=1}):find("No ring",1,true),"a refused throw says why")
	assert(Status.event({type="dryfire"})==nil,"a spine weapon's dry fire is not a ring message")
end
-- Rocket Boots' fuel (Roblox only): the tank, which signatures it no longer pays for, nothing for
-- any other weapon, and a refused signature explained.
do
	local boots, sword = Loadout.build("Classic","RocketBoots"), Loadout.build("Classic","Sword")
	assert(Status.fuel({fuel=100},boots)=="100/100","a full tank")
	assert(Status.fuel({fuel=18},boots):find("Ignition Heel",1,true) and Status.fuel({fuel=18},boots):find("Jet Kick",1,true)
		and not Status.fuel({fuel=18},boots):find("Burnout",1,true),"part-spent names exactly what it cannot pay for")
	assert(Status.fuel({fuel=5},boots):find("refuel",1,true),"an empty tank says how to refill it")
	assert(Status.fuel({fuel=-1},sword)==nil,"a sword has no fuel")
	assert(Status.describe({fuel=50,ultCharge=0,onGround=true,state="idle"},boots):find("FUEL: 50/100",1,true),"the status line carries the fuel")
	assert(Status.event({type="dryfire",fuel=25}):find("25 needed",1,true),"a refused signature says what it needed")
end
assert(Status.describe({ultCharge=20,onGround=false,state="air"},
	{weapon={name="Grounded test"},moves={Ultimate={grounded=true}}}):find("land first",1,true))
print("PASS abilities: all 12 weapons, real keys through prediction, shield blocks hits, held/released shield, short-tap ultimate, denial feedback, chat and reset guards")
