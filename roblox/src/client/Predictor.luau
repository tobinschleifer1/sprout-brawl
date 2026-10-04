--!strict
-- Client-side prediction for the local fighter.
--
-- Phase 6a shipped server authority with no prediction on purpose, and the visible cost was that
-- your own fighter answered a round trip late. This removes that: the local fighter is simulated
-- here the instant an input is sampled, and reconciled against the server whenever a snapshot
-- arrives. The server is still the only authority - nothing here changes what is true, only when
-- the player gets to see it.
--
-- WHAT IS PREDICTED, AND WHAT IS NOT. Only the local fighter's own movement and state machine.
-- Combat is a silent stub, exactly the shape tests/fighter-parity.luau replays against, so a
-- predicted frame never invents a hit, a grab, a pickup or a throw. Those arrive from the server
-- and land at the next reconcile. A fighter who gets hit mid-prediction will visibly snap; a
-- fighter running and jumping will not, and that is the trade this is built around.
--
-- RECONCILIATION IS LOSSY, AND HAS TO BE. Fighter:snapshot() carries object references - the
-- platform, a grab victim - that cannot cross a network, so the server sends the wire fields and
-- those are written onto the predicted fighter. Everything else - input buffers, hit victims, the
-- weapon mechanic's scratch state - keeps its predicted value. That is sound because every wire
-- field is re-anchored on every snapshot, so an error in one cannot compound; and it is the reason
-- `move` is repaired from moveId by hand below rather than left to drift.

local Fighter = require(game:GetService("ReplicatedStorage").Shared.Fighter)
local Input = require(game:GetService("ReplicatedStorage").Shared.Input)
local Snapshot = require(game:GetService("ReplicatedStorage").Shared.Snapshot)
local Stage = require(game:GetService("ReplicatedStorage").Shared.Stage)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Predictor = {}
Predictor.__index = Predictor

-- The combat stub. Every method is a no-op that answers "nothing here": no item within reach, no
-- fruit, no node. Silent, unlike the test harness's, which logs for comparison.
local function stubCombat(fighters: { any }): any
	return {
		fighters = fighters,
		useItem = function() end,
		dropItem = function() end,
		itemNear = function() return nil end,
		pickupItem = function() end,
		hasFruit = function() return false end,
		fruiting = function() end,
		nearestNode = function() return nil end,
		removeSummon = function() end,
		onMoveActive = function() end,
		onMoveActiveFrame = function() end,
		spawnBurst = function() end,
		checkGrab = function() end,
		resolveThrow = function() end,
	}
end

function Predictor.new(char: any, index: number, stage: any): any
	local self = setmetatable({}, Predictor)
	self.char = char
	self.index = index
	self.stage = stage
	self.fighter = Fighter.new({ index = index, char = char, x = 0, y = 0, stocks = 3 })
	self.ctx = { stage = stage, combat = stubCombat({ self.fighter }), fighters = { self.fighter } }
	-- Both indexed by SEQUENCE, the count of frames ever sampled. inputs[n] is the frame, snaps[n]
	-- is our own full Fighter snapshot taken just after simulating it.
	self.inputs = {} :: { [number]: Input.Frame }
	self.snaps = {} :: { [number]: any }
	self.sent = 0
	self.ready = false
	-- Events from frames simulated for the first time, waiting for the client to show them.
	self.fresh = {} :: { any }
	return self
end

-- How far back we keep history. Two seconds: past that the connection is gone rather than slow,
-- and replaying a hundred frames to catch up would cost more than snapping.
local HISTORY = 120

-- Write the server's wire fields onto the predicted fighter. Anything the wire does not carry is
-- left alone deliberately; see the note at the top.
function Predictor.applyWire(self: any, w: any)
	local f = self.fighter
	for _, pair in Snapshot.FIELDS do
		local name = pair[1]
		if name ~= "index" and name ~= "item" and name ~= "chillStacks" and name ~= "ledgeAction" and name ~= "comboTarget" then
			-- Back through the name map: the snapshot calls them stateFrame and moveFrame, the
			-- Fighter calls them sf and mf, and writing the snapshot's names onto a Fighter sets
			-- two fields nothing reads while leaving the two that matter untouched.
			(f :: any)[Snapshot.FROM_FIGHTER[name] or name] = w[name]
		end
	end
	-- `moveId` is a name and `move` is the table the state machine actually reads. Setting one
	-- without the other leaves a fighter executing the move it was doing before the correction,
	-- with the new move's frame counter - which reads as the right attack at the wrong speed.
	f.move = if w.moveId then self.char.moves[w.moveId] else nil
	f.effects.chill.stacks = w.chillStacks or 0
	-- The fighter we last hit, for the chase: the server sends an index, and the only stand-in we
	-- have is that fighter as the same snapshot describes them (`others`, from reconcile). It does
	-- not move during the replay - it is where the chase aims, which is all the chase reads.
	f.comboTarget = if w.comboTarget ~= nil and self.others then self.others[w.comboTarget] else nil
	-- A rollback's old platform reference can point to a different island or shelf. Resolve
	-- every grounded correction against its actual contact, using Stage.supported's footprint.
	-- Assuming the main floor teleported shelf fighters down and erased shields as "air".
	f.platform = nil
	if w.onGround then
		local distance = 0.5
		for _, platform in self.stage.platforms do
			local dy = math.abs(w.y - platform.top)
			if dy < distance and w.x + f.r * 0.6 > platform.x1 and w.x - f.r * 0.6 < platform.x2 then
				f.platform, distance = platform, dy
			end
		end
	end
end

local function prune(self: any)
	local cutoff = self.sent - HISTORY
	if cutoff < 1 then
		return
	end
	for seq in pairs(self.inputs) do
		if seq < cutoff then
			self.snaps[seq] = nil
			self.inputs[seq] = nil
		end
	end
end

local function simulate(self: any, seq: number, live: boolean)
	local frame = self.inputs[seq]
	if not frame then
		return
	end
	self.fighter:applyInput(frame)
	self.fighter:step(self.ctx)
	-- Take this frame's events out before the snapshot. Left in, the list was never emptied and
	-- was cloned into every frame's snapshot - a copy growing all match, sixty times a second.
	-- Only a frame's first simulation is shown: a replay re-emits events the player already saw.
	local f = self.fighter
	local events = f.events
	f.events = {}
	if live then
		for _, e in events do
			table.insert(self.fresh, table.clone(e))
			local last = self.fresh[#self.fresh]
			last.fighter, last.x, last.y = self.index, last.x or f.x, last.y or (f.y + f.h / 2)
		end
	end
	-- Our own full state, for the rollback that a correction to this frame will need. The wire
	-- cannot carry input buffers, hit victims or the weapon mechanic's scratch state, so they are
	-- restored from here rather than left to be re-derived - replaying a frame onto a fighter that
	-- already consumed it counts every buffered press twice.
	self.snaps[seq] = self.fighter:snapshot()
end

-- A sampled input: simulate it now, and remember it in case it has to be replayed.
function Predictor.push(self: any, frame: Input.Frame)
	self.sent += 1
	self.inputs[self.sent] = frame
	if self.ready then
		simulate(self, self.sent, true)
	end
	prune(self)
end

-- A snapshot arrived describing the state after the server consumed `consumed` of our frames.
-- Roll back to our own state at that frame, overwrite it with what the server actually says, and
-- replay everything since. This is the whole of rollback netcode; the rest is bookkeeping.
-- SMOOTHING. A correction moves the predicted fighter, and drawing it where it now is made every
-- correction a visible jump - "the controls feel late", "I teleport back". The simulation snaps
-- (it must: it is the truth the next inputs act on); only the DRAWING eases. The gap between where
-- we drew the fighter and where the correction puts it is kept as an offset that decays to nothing
-- in about 70ms (Predictor.visual). A gap larger than SNAP_STUDS - a respawn, a grab, a warp - is
-- not a mistake to ease over, so it is drawn at once.
Predictor.SMOOTH_RATE = 30     -- per second: e^(-30 * 0.07) is about an eighth left after 70ms
Predictor.SNAP_STUDS = 6

-- `others`, if given, is every fighter in the same snapshot as { [index] = { index, x, y, vx, vy,
-- h, alive, comboHits, onGround, hitlag } }: what a predicted chase aims at, and whether its combo
-- is still going.
function Predictor.reconcile(self: any, w: any, consumed: number, platforms: any?, others: any?)
	local beforeX, beforeY = self.fighter.x, self.fighter.y
	self.others = others
	local wasReady = self.ready
	if self.ready then
		-- Our own full snapshot from that frame, if we still hold it. Without this the non-wire
		-- state is whatever prediction left it as, and the replay below applies inputs the fighter
		-- has already seen.
		local snap = self.snaps[consumed]
		if snap then
			self.fighter:restore(snap)
		end
	end
	Stage.applyDynamicState(self.stage, platforms)
	-- Packet displacement is already included in w.x/w.y. Reusing it as a per-tick velocity
	-- would carry the fighter a whole snapshot interval again on every replayed input.
	for _, platform in self.stage.platforms do platform.dx, platform.dy = 0, 0 end
	self:applyWire(w)
	self.ready = true

	-- The other fighters move on while we replay: carry each stand-in forward along what the
	-- snapshot says of it - frozen while its hit freeze lasts, otherwise its velocity under
	-- gravity - so a chase predicted a few frames on aims near where they will be. Copies, so the
	-- caller's table is not changed. Their launch out of a freeze is not on the wire, so a chase
	-- straight out of one can still be a correction.
	if others then
		local moving = {}
		for i, o in others do moving[i] = table.clone(o) end
		self.others = moving
		local f = self.fighter
		if f.comboTarget then f.comboTarget = moving[f.comboTarget.index] end
	end
	for seq = consumed + 1, self.sent do
		simulate(self, seq, false)
		for _, o in self.others or {} do
			if (o.hitlag or 0) > 0 then
				o.hitlag -= 1
			else
				o.x += (o.vx or 0) * Config.FRAME
				o.y += (o.vy or 0) * Config.FRAME
				if not o.onGround then o.vy = (o.vy or 0) - Config.GRAVITY * Config.FRAME end
			end
		end
	end
	-- how far the correction moved the fighter we are drawing
	local dx, dy = beforeX - self.fighter.x, beforeY - self.fighter.y
	self.lastCorrection = if wasReady then math.sqrt(dx * dx + dy * dy) else 0
	if wasReady and self.lastCorrection < Predictor.SNAP_STUDS then
		self.offsetX = (self.offsetX or 0) + dx
		self.offsetY = (self.offsetY or 0) + dy
	else
		self.offsetX, self.offsetY = 0, 0
	end
end

-- The predicted fighter as it should be DRAWN after `dt` seconds: its state, eased from where the
-- last correction found it (see SMOOTHING above).
function Predictor.visual(self: any, dt: number): any
	local out = self:state()
	local keep = math.exp(-Predictor.SMOOTH_RATE * dt)
	self.offsetX = (self.offsetX or 0) * keep
	self.offsetY = (self.offsetY or 0) * keep
	if math.abs(self.offsetX) < 1e-3 then self.offsetX = 0 end
	if math.abs(self.offsetY) < 1e-3 then self.offsetY = 0 end
	out.x += self.offsetX
	out.y += self.offsetY
	return out
end

-- The events of newly predicted frames since the last call, stamped with where the fighter was.
function Predictor.drain(self: any): { any }
	local out = self.fresh
	self.fresh = {}
	return out
end

-- The predicted fighter in the shape everything downstream of Snapshot.decode reads.
function Predictor.state(self: any): any
	local f = self.fighter
	local out = {}
	for _, pair in Snapshot.FIELDS do
		local name = pair[1]
		out[name] = (f :: any)[Snapshot.FROM_FIGHTER[name] or name]
	end
	out.index = self.index
	out.item = if f.item then f.item.def.id else nil
	out.chillStacks = f.effects.chill.stacks
	out.ledgeAction = if f.la then f.la.kind else nil
	out.comboTarget = if f.comboTarget then f.comboTarget.index else nil
	return out
end

return Predictor
