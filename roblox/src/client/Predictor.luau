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
		if name ~= "index" and name ~= "item" and name ~= "chillStacks" and name ~= "ledgeAction" then
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
	-- `platform` is a reference the wire cannot carry. Grounded fighters get the stage's main
	-- platform, which is what Fighter itself does when it needs a floor and has none.
	if w.onGround and not f.platform then
		f.platform = self.stage.main
	elseif not w.onGround then
		f.platform = nil
	end
end

local function prune(self: any)
	local cutoff = self.sent - HISTORY
	if cutoff < 1 then
		return
	end
	for seq in pairs(self.snaps) do
		if seq < cutoff then
			self.snaps[seq] = nil
			self.inputs[seq] = nil
		end
	end
end

local function simulate(self: any, seq: number)
	local frame = self.inputs[seq]
	if not frame then
		return
	end
	self.fighter:applyInput(frame)
	self.fighter:step(self.ctx)
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
		simulate(self, self.sent)
	end
	prune(self)
end

-- A snapshot arrived describing the state after the server consumed `consumed` of our frames.
-- Roll back to our own state at that frame, overwrite it with what the server actually says, and
-- replay everything since. This is the whole of rollback netcode; the rest is bookkeeping.
function Predictor.reconcile(self: any, w: any, consumed: number)
	if self.ready then
		-- Our own full snapshot from that frame, if we still hold it. Without this the non-wire
		-- state is whatever prediction left it as, and the replay below applies inputs the fighter
		-- has already seen.
		local snap = self.snaps[consumed]
		if snap then
			self.fighter:restore(snap)
		end
	end
	self:applyWire(w)
	self.ready = true

	for seq = consumed + 1, self.sent do
		simulate(self, seq)
	end
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
	out.item = if f.item then f.item.id else nil
	out.chillStacks = f.effects.chill.stacks
	out.ledgeAction = if f.la then f.la.kind else nil
	return out
end

return Predictor
