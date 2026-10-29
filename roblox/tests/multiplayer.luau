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
local studio = false          -- RunService:IsStudio(): a live server unless a test says otherwise
local run: any = { Heartbeat = signal(), PostSimulation = signal(), IsStudio = function() return studio end,
	PromptGamePassPurchaseFinished = signal(), UserOwnsGamePassAsync = function() return false end,
	GetPolicyInfoForPlayerAsync = function() return { ArePaidRandomItemsRestricted = true } end }
local remotes, messages = {}, {}
-- Lobby presence arrives as a position buffer plus, only when it changed, a roster. Each player
-- keeps the last roster they were sent, as the client does, and the message is recorded decoded -
-- so every presence check below reads what a client would draw. `rosterSent` counts rosters.
local PresenceCodec = Loader.load("PresenceCodec")
local rosters, rosterSent, presenceBytes = {}, {}, {}
-- Fight snapshots arrive as keyframes and deltas (SnapshotCodec): each player decodes against the
-- last one they received, as the client does, and anything they could not decode is counted.
local SnapshotCodec = Loader.load("SnapshotCodec")
local snapBases, snapDropped, keyframes = {}, {}, {}
local function remote(name: string): any
	if not remotes[name] then
		remotes[name] = { OnServerEvent = signal(), FireAllClients = function() error("cross-room broadcast forbidden") end,
			FireClient = function(_, player, data, extra)
				if name == "Match" then
					snapBases[player] = nil          -- the client starts over on a match description
				end
				if name == "HubPresence" then
					assert(typeof(data) == "buffer", "presence positions travel as a buffer")
					if extra then
						rosters[player] = PresenceCodec.index(extra)
						rosterSent[player.UserId] = (rosterSent[player.UserId] or 0) + 1
					end
					presenceBytes[player.UserId] = buffer.len(data)
					data = PresenceCodec.decode(data, rosters[player] or {})
				elseif name == "Snapshot" then
					assert(typeof(data) == "buffer", "snapshots travel as a buffer")
					if SnapshotCodec.isKeyframe(data) then keyframes[player.UserId] = (keyframes[player.UserId] or 0) + 1 end
					local decoded = SnapshotCodec.decode(data, snapBases[player])
					if not decoded then
						snapDropped[player.UserId] = (snapDropped[player.UserId] or 0) + 1
						return
					end
					snapBases[player] = decoded
					data = decoded
				end
				table.insert(messages, { name=name, player=player, data=data })
			end }
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
	if name == "EmoteEvents" or name == "Rooms" or name == "RemoteInput" or name == "AvatarStore" or name == "Cabinets" or name == "ClimbProgress" or name == "ClimbBoards" or name == "Purchases" or name == "Locker" or name == "Mint" or name == "Economy" or name == "Passes" or name == "Shop" then return Loader.loadFrom("src/server/", name) end
	return Loader.load(name)
end
local tasks = {}
-- Paid skips as if every Developer Product were created (ids 9001 on), so the server
-- registers them; ProcessReceipt lands on the MarketplaceService stub (`run`).
local SkipIds = Loader.load("SkipProducts").IDS
for i = 1, #SkipIds do SkipIds[i] = 9000 + i end
local env: any = {
	Enum = { ProductPurchaseDecision = { PurchaseGranted = "PurchaseGranted", NotProcessedYet = "NotProcessedYet" } },
	game={GetService=function(_,name)
		if name == "ReplicatedStorage" then return {Shared=shared} end
		if name == "Players" then return players end
		return run
	end, BindToClose=function() end}, script=setmetatable({Parent=codes}, {__index=function(_,k) return k end}), require=module,
	os={clock=function() return now end, time=function() return math.floor(now) end},
	task={spawn=function(fn, ...) table.insert(tasks,{fn=fn,args={...}}) end, wait=function() end},
}
service = luau.load(fs.readFile("src/server/MatchService.luau"), {environment=env,injectGlobals=true})()
luau.load(fs.readFile("src/server/init.server.luau"), {environment=env,injectGlobals=true})()
local people = {}
local function send(id: number, name: string, data: any?, a: any?, b: any?, c: any?)
	now += 0.11
	remote(name).OnServerEvent:Fire(people[id], data, a, b, c)
end
local function last(id: number, name: string): any
	for i=#messages,1,-1 do local msg=messages[i]; if msg.player==people[id] and msg.name==name then return msg.data end end
	return nil
end
local function edit(id: number, action: string, value: any?, slot: number?)
	local view=last(id,"RoomView")
	send(id,"RoomAction",{id=view.id,revision=view.revision,action=action,value=value,slot=slot})
end
-- After everyone is ready the room votes its map, then its rules, and the fight starts itself.
local function votes(ids: { number })
	for _, id in ids do assert(last(id,"RoomView").phase=="map","everyone ready did not open the map vote") end
	for _, id in ids do edit(id,"vote","FoundryFloor") end
	for _, id in ids do assert(last(id,"RoomView").phase=="rules","everyone voting did not open the rules vote") end
	for _, id in ids do edit(id,"rule","current") end
end
for i=1,9 do
	people[i]={UserId=i,Name=`P{i}`,DisplayName=`P{i}`}
	send(i,"Hello")
end
-- Characters: every player is told their wardrobe on arrival. There is no DataStore here, so it is
-- session-only and says so rather than pretending to save.
local AvatarKit = Loader.load("AvatarKit")
local KNIGHT = AvatarKit.KIT.presets[2].code
for i=1,9 do
	local w = last(i,"AvatarView")
	assert(w and #w.slots==1 and w.slots[1].code==AvatarKit.defaultCode(), "every player starts wearing the default character")
	assert(w.saving==false and type(w.note)=="string", "a server with no DataStore says saving is off")
	local b = last(i,"ClimbBoards")
	assert(b and b.offline==true and #b.speed==0, "and is shown the climb's leaderboards, offline here")
end
-- The leaderboard job runs from the server's clock without taking it down, offline or not.
for _ = 1, 4 do run.Heartbeat:Fire(10) end
for _, t in tasks do t.fn(table.unpack(t.args)) end
table.clear(tasks)
send(9,"Avatar",{action="save",slot=1,code="k1" .. string.upper(string.sub(KNIGHT, 3)),name="<b>Sir</b> Knight"})
assert(last(9,"AvatarView").slots[1].code==KNIGHT and last(9,"AvatarView").slots[1].name=="bSirb Knight", "a saved character comes back canonical, its name cleaned")
run.Heartbeat:Fire(0.1)
local worn = nil
for _, peer in last(1,"HubPresence") do if peer.userId==9 then worn = peer.avatar end end
assert(worn==KNIGHT, "everyone in the concourse sees the character a player put on")
-- The roster goes only when it changes: another tick with nobody changing sends positions alone.
local sentBefore = rosterSent[1]
run.Heartbeat:Fire(0.1)
assert(rosterSent[1] == sentBefore and #last(1,"HubPresence") == 9, "an unchanged lobby re-sends positions, not who everyone is")
assert(presenceBytes[1] == 10 + 9 * PresenceCodec.ENTRY, `nine people's positions are {10 + 9 * PresenceCodec.ENTRY} bytes, sent {presenceBytes[1]}`)
-- A client that loads again (Hello) has no roster: it is sent one on the next tick, without anyone
-- else in the lobby changing. The reload is a second later, past Hello's rate limit.
now += 1.1
send(1,"Hello")
run.Heartbeat:Fire(0.1)
assert(rosterSent[1] == sentBefore + 1 and #last(1,"HubPresence") == 9, "a reloaded client is sent the roster again")
send(9,"Avatar",{action="save",slot=1,code="k1<script>",name="x"})
send(9,"Avatar",{action="save",slot=7,code=KNIGHT})
send(9,"Avatar",{action="wear",slot=0})
assert(#last(9,"AvatarView").slots==1 and type(last(9,"AvatarView").error)=="string", "a bad slot or a skipped slot is refused")
-- PLAY's queue: four of six wait in the lobby; the fifth forms the room and the sixth takes its open place
for i=1,4 do send(i,"RoomAction",{action="queue",format="Triples"}) end
assert(last(4,"QueueView").queued and last(4,"QueueView").waiting == 4 and not last(1,"RoomView"), "four of six wait in the queue")
assert(last(1,"QueueView").waiting == 4, "everyone queued is told the new count")
for i=5,6 do send(i,"RoomAction",{action="queue",format="Triples"}) end
assert(last(1,"RoomView") and last(1,"RoomView").id == last(6,"RoomView").id, "the queue seats all six in one room")
send(7,"RoomAction",{action="join",format="Doubles"})
assert(last(7,"RoomView").left and string.find(last(7,"RoomView").error or "", "PLAY"), "the old gates' join is refused")
-- Changing character inside a room updates your place in it and un-readies no-one.
edit(2,"ready")
local before = last(3,"RoomView").revision
send(3,"Avatar",{action="save",slot=1,code=KNIGHT})
local after = last(3,"RoomView")
assert(after.revision==before and after.slots[3].avatar==KNIGHT and after.slots[2].ready, "a character change is not a rules change")
edit(2,"ready")
for i=7,8 do send(i,"RoomAction",{action="queue",format="Duel"}) end
for i=1,8 do edit(i,"ready") end
votes({1,2,3,4,5,6})
votes({7,8})
assert(#last(1,"Match").fighters==6 and #last(7,"Match").fighters==2)
local knights = 0
for _, f in last(1,"Match").fighters do if f.avatar==KNIGHT then knights += 1 end end
assert(knights==1, "the character a player saved is the one they fight in")
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
	assert(count==300, "complete 60Hz snapshots for every participant")
	assert(not snapDropped[id], `player {id} could not decode {snapDropped[id]} snapshots`)
	-- Mostly deltas: a keyframe at the start and one a second, 300 frames here.
	assert(keyframes[id] and keyframes[id] >= 5 and keyframes[id] <= 7, `player {id}: {keyframes[id]} keyframes in five seconds`)
end
assert(not last(9,"Snapshot") and not last(9,"Events") and not last(9,"Scene"))
-- A fighter whose client reloads mid-fight (Hello again) is sent the match and starts over with no
-- base: the next snapshot has to be a keyframe for them. 20 frames in, far from a periodic one.
for _=1,20 do now+=1/60; run.PostSimulation:Fire(1/60) end
now += 1.1
send(5,"Hello")
local keysBefore = keyframes[5]
now+=1/30; run.PostSimulation:Fire(1/30)
assert(keyframes[5] == keysBefore + 1 and not snapDropped[5], "a rejoined fighter gets a keyframe next, and decodes it")
-- and the scene likewise (SceneCodec): with no base, a delta would be undrawable
assert(last(5, "Scene") and last(5, "Scene").k, "a rejoined fighter's next scene is a keyframe")
local six=instances[1]
local before=six.input:consumedBy("p1")
send(9,"Input",{0},six.generation,0)
send(1,"Input",{0},instances[2].generation,0)
run.PostSimulation:Fire(1/60)
assert(six.input:consumedBy("p1")==before,"outsider/wrong-match packets do not feed a fighter")
send(1,"Input",{0},six.generation,0)
run.PostSimulation:Fire(1/60)
assert(six.input:consumedBy("p1")==before+1,"own-room input reaches own fighter")
-- Lag compensation (Config.LAG_COMP): the snapshot frame a client was drawing comes up with its
-- input, through the real entry point, and that fighter's swings are judged that far back.
do
	local m6 = six.match
	local me = nil
	for _, f in m6.fighters do if f.source == "p1" then me = f end end
	local sent = m6.frame - 5
	send(1,"Input",{0},six.generation,0,sent)
	run.PostSimulation:Fire(1/60)
	assert(six.input:viewOf("p1") == sent, `the view a client sent reached the server as {tostring(six.input:viewOf("p1"))}, not {sent}`)
	assert(me and m6.combat.rewindOf(me) == m6.frame - sent and m6.frame - sent >= 5, "a fighter's swings are judged at the frame they were drawing")
	send(1,"Input",{0},six.generation,0,"soon")
	run.PostSimulation:Fire(1/60)
	assert(six.input:viewOf("p1") == nil and m6.combat.rewindOf(me) == 0, "a view that is not a frame number is judged as now")
end
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
-- Poses: somewhere a player could stand on the scene's floor (Plaza.walkable), or ignored.
local PLAZA = Loader.load("Plaza").DATA
send(9,"HubPose",{area=0,x=12,z=5,y=-20,facing=-1,moving=true,userId=7})
run.Heartbeat:Fire(0.1)
local presence=last(9,"HubPresence")
local seen={}
for _, peer in presence do seen[peer.userId]=peer end
assert(not seen[1] and not seen[7] and not seen[8], "left/playing people excluded from shared hub")
assert(seen[9].x==12 and seen[9].z==5 and seen[9].y==0 and seen[9].facing==-1, "a pose on the floor is taken, its hop clamped, sender identity preserved")
assert(#presence==1 and seen[9], "preparation-room members must not appear in the market")
local roomPresence=last(2,"HubPresence")
assert(#roomPresence==5, "only the five remaining teammates/opponents occupy this preparation room")
for _, peer in roomPresence do assert(peer.userId>=2 and peer.userId<=6 and peer.area==returnedRoom.id, "room presence isolation") end
local lounge = PLAZA.rooms[returnedRoom.format]
send(2,"HubPose",{area=0,x=10,z=8,y=0})
run.Heartbeat:Fire(0.1)
for _, peer in last(2,"HubPresence") do
	if peer.userId==2 then assert(peer.x==lounge.spawn.x and peer.z==lounge.spawn.z, "a stale or forged area cannot move a room avatar") end
end
send(2,"HubPose",{area=returnedRoom.id,x=1e20,z=8,y=0})
send(2,"HubPose",{area=returnedRoom.id,x=10,z=40,y=0})
run.Heartbeat:Fire(0.1)
for _, peer in last(2,"HubPresence") do
	if peer.userId==2 then assert(peer.x==lounge.spawn.x, "a pose off the lounge floor is ignored") end
end
send(9,"HubPose",{area=0,x=0,z=14,y=0})          -- inside the square's kiosk
send(9,"HubPose",{area=0,x=0/0,z=8,y=10})
send(9,"HubPose",{area=0,x=-90,z=3,y=0})          -- over the gap beside a bridge
run.Heartbeat:Fire(0.1)
for _, peer in last(9,"HubPresence") do
	assert(peer.x==12 and peer.z==5, "inside the kiosk, NaN and over the gap are all refused; the last good pose stands")
end
-- Explicit bot match can finish and cleanly return; completion targets no other room.
-- FILL WITH BOTS: alone in the 1v1 queue, into a room at once with a hard bot
send(9,"RoomAction",{action="queue",format="Duel"})
assert(last(9,"QueueView").queued and not last(9,"RoomView"), "one 1v1 player waits")
send(9,"RoomAction",{action="fill"})
assert(last(9,"RoomView") and last(9,"RoomView").slots[2].bot == "hard", "FILL WITH BOTS seats a hard bot")
assert(not last(9,"QueueView").queued, "and takes the player out of the queue")
edit(9,"ready"); votes({9})
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
-- three more in the lobby, for the climb
for i=10,12 do
	people[i]={UserId=i,Name=`P{i}`,DisplayName=`P{i}`}
	now += 1.1
	send(i,"Hello")
end
-- The Skyline Climb: entering takes you off the floor and shows in the member list; a checkpoint
-- claimed too fast is ignored; leaving puts you back.
do
	now += 1
	send(12,"Climb",{action="enter",from=0})
	assert(last(12,"ClimbView") and last(12,"ClimbView").start == 0, "entering the climb starts at the bottom")
	run.Heartbeat:Fire(0.1)
	for _, peer in last(9,"HubPresence") or {} do assert(peer.userId ~= 12, "a climber is not on the lobby floor") end
	local mark = #messages
	now += 0.3
	send(12,"Climb",{action="checkpoint",index=3})
	for k = mark + 1, #messages do assert(messages[k].name ~= "ClimbView", "a checkpoint claimed in a second is ignored") end
	now += 30
	send(12,"Climb",{action="checkpoint",index=3})
	assert(last(12,"ClimbView").best == 3, "a believable checkpoint is kept")
	-- A paid skip: moved one checkpoint on, told to move now, saved as progress but not as climbed.
	local function buy(purchase: string, product: number, userId: number?): string
		return run.ProcessReceipt({ PurchaseId = purchase, PlayerId = userId or 12, ProductId = product })
	end
	assert(buy("s1", 9004) == "PurchaseGranted", "the skip into checkpoint 4 is granted")
	local v = last(12,"ClimbView")
	assert(v.skipTo == 4 and v.best == 4 and v.climbed == 3, "the climber is moved to 4, which is saved but not climbed")
	local mark2 = #messages
	assert(buy("s1", 9004) == "PurchaseGranted", "the same receipt again is acknowledged")
	for k = mark2 + 1, #messages do assert(messages[k].name ~= "ClimbView", "and not applied a second time") end
	assert(buy("s2", 9000 + #SkipIds) == "PurchaseGranted" and last(12,"ClimbView").skipTo == 5, "a tampered prompt for the Summit moves one checkpoint on, no more")
	assert(buy("s3", 9006, 4242) == "NotProcessedYet", "a buyer not in this server waits")
	assert(buy("s4", 1234) == "NotProcessedYet", "a product that is not a skip is not granted")
	-- The free Studio skip: nothing on a live server; in Studio, one checkpoint on, like a purchase.
	local markS = #messages
	now += 1
	send(12,"Climb",{action="studioSkip"})
	for k = markS + 1, #messages do assert(messages[k].name ~= "ClimbView", "a free skip on a live server does nothing") end
	studio = true
	now += 1
	send(12,"Climb",{action="studioSkip"})
	studio = false
	local sv = last(12,"ClimbView")
	assert(sv.skipTo == 6 and sv.best == 6 and sv.climbed == 3, "in Studio it moves you one checkpoint on, saved but not climbed")
	-- A reward at the top: claimed where it lies, by a climber who climbed there; its part unlocks.
	local PK = Loader.load("Data/Parkour")
	local crown = PK.course.rewards[1]
	local mark3 = #messages
	send(12,"Climb",{action="reward",id=crown.id})
	for k = mark3 + 1, #messages do assert(messages[k].name ~= "ClimbView", "a reward claimed from checkpoint 5 is ignored") end
	now += 100
	send(12,"Climb",{action="checkpoint",index=crown.checkpoint})
	assert(last(12,"ClimbView").best == crown.checkpoint, "climbed to Crown Perch")
	now += 1
	send(12,"Climb",{action="reward",id=crown.id})
	assert(last(12,"ClimbView").earned == crown.id, "the crown is granted")
	assert(table.find(last(12,"AvatarView").unlocked, crown.id), "and the creator is told it is unlocked")
	local mark4 = #messages
	now += 1
	send(12,"Climb",{action="reward",id=crown.id})
	send(12,"Climb",{action="reward",id=PK.course.rewards[2].id})
	for k = mark4 + 1, #messages do assert(messages[k].name ~= "AvatarView", "no second crown, and no mantle from Crown Perch") end
	now += 1
	send(12,"Climb",{action="leave"})
	run.Heartbeat:Fire(0.1)
	local back = false
	for _, peer in last(9,"HubPresence") or {} do if peer.userId == 12 then back = true end end
	assert(back, "leaving the climb puts you back on the floor")
end
-- One service, two matches in a row (a rematch on the same machine): the second match's first
-- snapshot is a keyframe, never a delta against the first match's last one.
do
	local viewer = { UserId = 90, Name = "V", DisplayName = "V" }
	local svc = service.new({ viewer }, 500)
	local bots = { { avatar = "Classic", weapon = "Sword" }, { avatar = "Classic", weapon = "Axe" } }
	svc:start(bots, { stage = "FoundryFloor" })
	for _ = 1, 20 do svc:tick(1/60) end
	svc:start(bots, { stage = "FoundryFloor" })
	local k = keyframes[90] or 0
	svc:tick(1/30)
	assert(keyframes[90] == k + 1 and not snapDropped[90], "a new match on the same service starts with a keyframe")
	svc:stop()
end
print("PASS multiplayer: concurrent six/two-player rooms, outsider isolation, 60Hz complete transport, disconnect cancellation, host transfer, bounded presence, bot opt-in, saved characters worn in the hub, the room and the fight; rooms through PLAY's queue and FILL WITH BOTS; the climb")
