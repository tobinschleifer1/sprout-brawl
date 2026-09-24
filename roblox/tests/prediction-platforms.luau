--!strict
-- The player can shield on ANY arena surface, not only the main floor used by the old test.
local Loader = require("./loader")
local Stage, Fighter = Loader.load("Stage"), Loader.load("Fighter")
local Snapshot, Input = Loader.load("Snapshot"), Loader.load("Input")
local Loadout = Loader.load("Loadout")
local Predictor = Loader.loadFrom("src/client/", "Predictor")
local Channels = Loader.loadFrom("src/client/", "Channels")
local checked = 0
for _, data in Loader.load("Data/Stages").LIST do
	for _, weapon in Loader.load("Data/Weapons").LIST do
		local char = Loadout.build("Classic", weapon.id)
		local stage = Stage.new(data, 11)
		for _, platform in stage.platforms do
			local x = (platform.x1 + platform.x2) / 2
			local truth = Fighter.new({index=0,char=char,x=x,y=platform.top,stocks=3})
			truth.onGround, truth.platform = true, platform
			truth:setState("shield")
			truth.ultCharge = 20
			local pred = Predictor.new(char,0,stage)
			pred:reconcile(Snapshot.decode(Snapshot.encode(truth)),0)
			assert(pred.fighter.platform==platform, data.id .. "/" .. platform.id .. ": wire ground must resolve to the actual supporting surface")
			local hold = Input.emptyFrame(); hold.guardHeld=true
			pred:push(hold)
			local state=pred:state()
			assert(state.state=="shield" and state.onGround, data.id .. "/" .. platform.id .. ": prediction must not erase a valid shield")
			assert(math.abs(state.y-platform.top)<0.01,"prediction must not teleport off a shelf")
			assert(Channels.For(state,char,nil,0).bubble>0,"shield remains visible on every surface")
			-- Reconciliation must also replace an EXISTING but stale contact, not just fill nil.
			pred.fighter.platform=stage.main
			truth:setState("idle")
			pred:reconcile(Snapshot.decode(Snapshot.encode(truth)),1)
			assert(pred.fighter.platform==platform,"stale rollback contact must be replaced")
			local ultimate=Input.emptyFrame(); ultimate.ult=true; ultimate.anyPress=true
			pred:push(ultimate)
			assert(pred:state().moveId=="Ultimate" and pred:state().ultCharge==0,
				data.id .. "/" .. platform.id .. "/" .. weapon.id .. ": full-meter ultimate starts on this surface")
			checked+=1
		end
	end
end
-- A sinking surface moved between snapshots. Restore its latest position BEFORE resolving
-- contact; packet displacement must not be applied again for every pending input frame.
do
	local data=Loader.load("Data/Stages").BY_ID.Smeltworks
	local stage=Stage.new(data,11)
	local char=Loadout.build("Classic","Blasters")
	local pred=Predictor.new(char,0,stage)
	local index,platform
	for i,p in stage.platforms do if p.id=="gantry" then index,platform=i,p end end
	local truth=Fighter.new({index=0,char=char,x=-1,y=7,stocks=3})
	truth.onGround=true; truth:setState("shield")
	local hold=Input.emptyFrame(); hold.guardHeld=true
	for _=1,3 do pred:push(hold) end
	pred:reconcile(Snapshot.decode(Snapshot.encode(truth)),0,{{i=index,cx=-1,top=7}})
	assert(pred.fighter.platform==platform and pred.fighter.state=="shield" and pred.fighter.y==7,
		"latest sinking platform geometry must reach prediction before replay")
	assert(platform.dx==0 and platform.dy==0,"network displacement is not per-tick motion")
end
-- An earthquake-dropped plate reaches the clients: dynamicState ships it and applyDynamicState moves
-- the view-only stage's copy, at the plate's own thickness.
do
	local Disasters = Loader.load("Disasters")
	local data = Loader.load("Data/Stages").BY_ID.Saltflat
	local server, client = Stage.new(data, 3), Stage.new(data, 3)
	local plate = nil
	for _, p in server.solids do if p ~= server.main and p.ledges == false and p.top < 10 then plate = p end end
	assert(plate, "Saltflat's bunker")
	local thick = plate.top - plate.bottom
	local d = { p = table.clone(Disasters.DISASTERS.earthquake.params), warn = 120, plates = { plate }, base = { plate.top }, done = true }
	Disasters.DISASTERS.earthquake.step(d, { stage = server, fighters = {}, match = {} }, "strike", 0.5, 120 + 20)
	assert((plate :: any).displaced and plate.top < d.base[1], "the quake moved and flagged the plate")
	local state = Stage.dynamicState(server)
	assert(state and #state >= 1, "a displaced solid is shipped to clients")
	Stage.applyDynamicState(client, state)
	local mirror = nil
	for i, p in server.platforms do if p == plate then mirror = client.platforms[i] end end
	assert(mirror and math.abs(mirror.top - plate.top) < 1e-9, "the client's plate is where the server's is")
	assert(math.abs((mirror.top - mirror.bottom) - thick) < 1e-9, "and keeps its own thickness")
	checked += 1
end
print(`PASS prediction supports {checked} weapon/surface combinations across every arena`)
