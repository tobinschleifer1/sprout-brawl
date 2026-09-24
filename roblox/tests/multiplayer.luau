--!strict
-- Run the actual server entry point and MatchService with real simulation, virtual players,
-- deterministic clocks/signals and intercepted transport. No copied matchmaking logic.
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Loader = require("./loader")
local now = 0
local function signal(): any
	local list = {}
	return { Connect = function(_, fn)
		local record = { fn = fn, active = true }; table.insert(list, record)
		return { Disconnect = function() record.active = false end }
	end, Fire = function(_, ...)
		for _, record in table.clone(list) do if record.active then record.fn(...) end end
	end }
end
local players: any = { PlayerRemoving = signal() }
local run: any = { Heartbeat = signal(), PostSimulation = signal() }
local remotes, messages = {}, {}
local function remote(name: string): any
	if not remotes[name] then
		remotes[name] = { OnServerEvent = signal(), FireAllClients = function() error("cross-room broadcast forbidden") end,
			FireClient = function(_, player, data) table.insert(messages, { name=name, player=player, data=data }) end }
	end
	return remotes[name]
end
local codes = setmetatable({}, {__index=function(_,k) return k end})
local shared = setmetatable({Data=setmetatable({}, {__index=function(_,k) return "Data/"..k end})}, {__index=function(_,k) return k end})
local service
local instances = {}
local function module(name: string): any
	if name == "Net" then return {remote=remote} end
	if name == "MatchService" then return { new = function(...)
		local matchService = service.new(...)
		table.insert(instances, matchService)
		return matchService
	end } end
	if name == "Rooms" or name == "RemoteInput" then return Loader.loadFrom("src/server/", name) end
	return Loader.load(name)
end
local tasks = {}
local env: any = {
	game={GetService=function(_,name)
		if name == "ReplicatedStorage" then return {Shared=shared} end
		if name == "Players" then return players end
		return run
	end}, script=setmetatable({Parent=codes}, {__index=function(_,k) return k end}), require=module,
	os={clock=function() return now end},
	task={spawn=function(fn, ...) table.insert(tasks,{fn=fn,args={...}}) end, wait=function() end},
}
service = luau.load(fs.readFile("src/server/MatchService.luau"), {environment=env,injectGlobals=true})()
luau.load(fs.readFile("src/server/init.server.luau"), {environment=env,injectGlobals=true})()
local people = {}
local function send(id: number, name: string, data: any?, a: any?, b: any?)
	now += 0.11
	remote(name).OnServerEvent:Fire(people[id], data, a, b)
end
local function last(id: number, name: string): any
	for i=#messages,1,-1 do local msg=messages[i]; if msg.player==people[id] and msg.name==name then return msg.data end end
	return nil
end
local function edit(id: number, action: string, value: any?, slot: number?)
	local view=last(id,"RoomView")
	send(id,"RoomAction",{id=view.id,revision=view.revision,action=action,value=value,slot=slot})
end
for i=1,9 do
	people[i]={UserId=i,Name=`P{i}`,DisplayName=`P{i}`}
	send(i,"Hello")
end
for i=1,6 do send(i,"RoomAction",{action="join",format="Triples"}) end
for i=7,8 do send(i,"RoomAction",{action="join",format="Duel"}) end
for i=1,8 do edit(i,"ready") end
edit(1,"start")
edit(7,"start")
assert(#last(1,"Match").fighters==6 and #last(7,"Match").fighters==2)
assert(last(1,"Match").id ~= last(7,"Match").id, "generation globally unique")
assert(not last(9,"Match"), "uninvolved player stays in the hub")
messages={}
for _=1,300 do now+=1/60; run.PostSimulation:Fire(1/60) end
for id=1,8 do
	local count=0
	for _, msg in messages do
		if msg.player==people[id] and msg.name=="Snapshot" then
			count+=1
			assert(#msg.data.fighters==(if id<=6 then 6 else 2), "snapshot belongs only to recipient room")
		end
	end
	assert(count==150, "complete 30Hz snapshots for every participant")
end
assert(not last(9,"Snapshot") and not last(9,"Events") and not last(9,"Scene"))
local six=instances[1]
local before=six.input:consumedBy("p1")
send(9,"Input",{0},six.generation,0)
send(1,"Input",{0},instances[2].generation,0)
run.PostSimulation:Fire(1/60)
assert(six.input:consumedBy("p1")==before,"outsider/wrong-match packets do not feed a fighter")
send(1,"Input",{0},six.generation,0)
run.PostSimulation:Fire(1/60)
assert(six.input:consumedBy("p1")==before+1,"own-room input reaches own fighter")
-- Leaving mid-fight cancels that room only, and returns humans with no auto-CPUs.
players.PlayerRemoving:Fire(people[1])
assert(last(2,"Select") and last(2,"RoomView").state=="setup")
for _, slot in last(2,"RoomView").slots do assert(not slot.bot) end
assert(last(2,"RoomView").host==2)
local returnedRoom = last(2,"RoomView")
messages={}
run.PostSimulation:Fire(1/60)
run.PostSimulation:Fire(1/60)
assert(not last(2,"Snapshot") and last(7,"Snapshot"), "disconnect stops only affected match")
send(9,"HubPose",{area=0,x=1e20,y=-20,facing=-1,moving=true,userId=7})
run.Heartbeat:Fire(0.1)
local presence=last(9,"HubPresence")
local seen={}
for _, peer in presence do seen[peer.userId]=peer end
assert(not seen[1] and not seen[7] and not seen[8], "left/playing people excluded from shared hub")
assert(seen[9].x<200 and seen[9].y==0 and seen[9].facing==-1, "cosmetic poses bounded, sender identity preserved")
assert(#presence==1 and seen[9], "preparation-room members must not appear in the concourse")
local roomPresence=last(2,"HubPresence")
assert(#roomPresence==5, "only the five remaining teammates/opponents occupy this preparation room")
for _, peer in roomPresence do assert(peer.userId>=2 and peer.userId<=6 and peer.area==returnedRoom.id, "room presence isolation") end
send(2,"HubPose",{area=0,x=66,y=0})
run.Heartbeat:Fire(0.1)
for _, peer in last(2,"HubPresence") do
	if peer.userId==2 then assert(peer.x==-53, "stale or forged area cannot move a room avatar") end
end
send(2,"HubPose",{area=returnedRoom.id,x=1e20,y=0})
run.Heartbeat:Fire(0.1)
for _, peer in last(2,"HubPresence") do
	if peer.userId==2 then assert(peer.x==69, "preparation room uses its own bounds") end
end
send(9,"HubPose",{area=0,x=0/0,y=10})
run.Heartbeat:Fire(0.1)
for _, peer in last(9,"HubPresence") do assert(peer.x==peer.x, "NaN cannot poison hub renderer") end
-- Explicit bot match can finish and cleanly return; completion targets no other room.
send(9,"RoomAction",{action="join",format="Duel"})
edit(9,"bot","normal",2); edit(9,"ready"); edit(9,"start")
assert(#last(9,"Match").fighters==2)
send(9,"RoomAction",{action="leave"})
assert(last(9,"RoomView").left)
messages={}
local active=instances[2]
Loader.load("Match").finish(active.match)
active:tick(1/60)
assert(last(7,"Results") and last(8,"Results") and not last(2,"Results") and not last(9,"Results"), "results stay inside their room")
for _, job in tasks do job.fn(table.unpack(job.args)) end
assert(not active.match and last(7,"RoomView").state=="setup", "completed matches tear down and return to ready check")
for _, slot in last(7,"RoomView").slots do assert(not slot.bot and not slot.ready,"rematch resets readiness and bots") end
print("PASS multiplayer: concurrent six/two-player rooms, outsider isolation, 30Hz complete transport, disconnect cancellation, host transfer, bounded presence and bot opt-in")
