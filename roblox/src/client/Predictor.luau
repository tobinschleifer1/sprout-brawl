--!strict
-- Client-side prediction for the local fighter.
--
-- Phase 6a shipped server authority with no prediction on purpose, and the visible cost was that
-- your own fighter answered a round trip late. This removes that: the local fighter is simulated
-- here the instant an input is sampled, and reconciled against the server whenever a snapshot
-- arrives. The server is still the only authority - nothing here changes what is true, only when
-- the player gets to see it.
--
-- WHAT IS PREDICTED, AND WHAT IS NOT. The local fighter's own movement and state machine, and -
-- since combat phase 4 - its own swings connecting (INSTANT HITS, below). Otherwise combat is a
-- silent stub, exactly the shape tests/fighter-parity.luau replays against, so a predicted frame
-- never invents a grab, a pickup or a throw, and never a hit ON the local fighter. Those arrive
-- from the server and land at the next reconcile. A fighter who gets hit mid-prediction will
-- visibly snap; a fighter running, jumping and landing hits will not.
--
-- INSTANT HITS. A swing whose hitbox meets a foe as the client is drawing them (`look`) lands at
-- once on the predicted fighter: the hit freeze the server will give it, the move counted as
-- landed for chaining, the staling memory, the ultimate charge - and a hit event for the sparks.
-- The server judges the same swing against the same view (Combat.hurtboxFor, Config.LAG_COMP: the
-- client sends the frame it was looking at with its inputs), so the two agree unless the foe
-- dodged or shielded since, or the view was further back than the server will rewind. Then the
-- correction takes the freeze back and the swing goes on - a few frames, no teleport. The foe's
-- reaction is never predicted: their flinch and launch are the server's.
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
local Combat = require(game:GetService("ReplicatedStorage").Shared.Combat)
local Knockback = require(game:GetService("ReplicatedStorage").Shared.Knockback)

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
		-- weapon drops: no drop is ever in reach here, so a pickup is the server's to report. A
		-- throw IS predicted - the move plays at once - and the weapon leaving arrives as `armed`.
		dropNear = function() return nil end,
		-- a catch is the server's to decide, like a pickup (Config.TEAM.catch)
		allyToCatch = function() return nil end,
		-- a flung fighter meeting a foe is the server's to decide too (Config.TEAM.fling)
		flingHit = function() return false end,
		takeDrop = function() end,
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

-- `armed` (weapon drops) is { kit = { loadout, loadout }, fists = loadout } when the match has drops:
-- the fighter then carries both weapons and starts on fists, as the server's does.
function Predictor.new(char: any, index: number, stage: any, armed: any?): any
	local self = setmetatable({}, Predictor)
	self.char = char
	self.index = index
	self.stage = stage
	self.fighter = Fighter.new({ index = index, char = char, x = 0, y = 0, stocks = 3,
		kit = if armed then armed.kit else nil, fists = if armed then armed.fists else nil })
	self.ctx = { stage = stage, combat = stubCombat({ self.fighter }), fighters = { self.fighter } }
	-- Both indexed by SEQUENCE, the count of frames ever sampled. inputs[n] is the frame, snaps[n]
	-- is our own full Fighter snapshot taken just after simulating it.
	self.inputs = {} :: { [number]: Input.Frame }
	self.snaps = {} :: { [number]: any }
	self.sent = 0
	self.ready = false
	-- Events from frames simulated for the first time, waiting for the client to show them.
	self.fresh = {} :: { any }
	-- INSTANT HITS: the foes as the client is drawing them (`look`), and by sequence the hits that
	-- were predicted live, so a replay lands them again rather than judging them a second time.
	self.view = nil :: { any }?
	self.viewFrame = nil :: number?
	self.landed = {} :: { [number]: { any } }
	return self
end

-- The foes in `states` (decoded snapshot fighters) as a swing is judged against them: hurtbox,
-- whether they can be hit at all, and what a shield or a heavy's armour would make of it.
-- `teamOf(index)` and `charOf(index)` - the character in hand - come from the roster.
function Predictor.foes(states: { any }, localIndex: number, teamOf: (number) -> any, charOf: (number) -> any): { any }
	local mine = teamOf(localIndex)
	local out = {}
	for _, st in states do
		local ch = charOf(st.index)
		if st.index ~= localIndex and st.alive and teamOf(st.index) ~= mine and ch then
			table.insert(out, {
				index = st.index, percent = st.percent, weight = ch.weight, char = ch,
				box = { x1 = st.x - ch.radius, x2 = st.x + ch.radius, y1 = st.y, y2 = st.y + ch.height },
				state = st.state, mf = st.moveFrame, se = st.startupEff, moveId = st.moveId,
				-- (the tangle's stacks are not on the wire: a tangled dodge reads as untangled)
				untouchable = Fighter.computed.untouchable({ invincible = st.invincible, state = st.state, sf = st.stateFrame,
					alive = st.alive, techRoll = st.techRoll or 0, effects = { tangle = { stacks = 0 } } }),
			})
		end
	end
	return out
end

-- The view: the snapshot frame the client is drawing other fighters at, and the foes in it.
-- `frame` goes to the server with the inputs sampled while it is the view (Combat.hurtboxFor).
function Predictor.look(self: any, frame: number, foes: { any })
	self.viewFrame = frame
	self.view = foes
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
		if name ~= "index" and name ~= "item" and name ~= "chillStacks" and name ~= "ledgeAction" and name ~= "comboTarget"
			and name ~= "armed" and name ~= "staleMoves" and name ~= "crackMark" and name ~= "crackExpires" and name ~= "rings" and name ~= "fuel" then
			-- Back through the name map: the snapshot calls them stateFrame and moveFrame, the
			-- Fighter calls them sf and mf, and writing the snapshot's names onto a Fighter sets
			-- two fields nothing reads while leaving the two that matter untouched.
			(f :: any)[Snapshot.FROM_FIGHTER[name] or name] = w[name]
		end
	end
	-- `moveId` is a name and `move` is the table the state machine actually reads. Setting one
	-- without the other leaves a fighter executing the move it was doing before the correction,
	-- with the new move's frame counter - which reads as the right attack at the wrong speed.
	-- Weapon drops: the loadout in hand is the server's. `armed` is a number, but what it selects -
	-- size, weight, jumps, the moves - lives on the char, so the fighter is re-equipped, not just
	-- relabelled (writing `armed` alone left it swinging the fists' moves with a sword in hand).
	if f.kit and w.armed ~= nil and w.armed ~= f.armed then
		f.armed = w.armed
		f:equip(if w.armed >= 0 then f.kit[w.armed + 1] else f.fists)
	end
	f.move = Fighter.moveOf(f.char, w.moveId)
	f.effects.chill.stacks = w.chillStacks or 0
	-- the bullwhip's mark (CRACK), whose crack a predicted hit's freeze depends on
	if f.mech.id == "Crack" and w.crackMark ~= nil then f.mech.mark = w.crackMark; f.mech.expires = w.crackExpires or 0 end
	-- the Chakram's rings in hand (RETURN): a predicted throw with none in hand would be refused
	if f.mech.id == "Return" and w.rings ~= nil and w.rings >= 0 then f.mech.rings = w.rings end
	-- Rocket Boots' fuel (THRUST FUEL): a predicted signature without the fuel would be refused
	if f.mech.id == "ThrustFuel" and w.fuel ~= nil and w.fuel >= 0 then f.mech.fuel = w.fuel end
	-- the server's staling memory, which a hit predicted and then taken back left wrong here
	if w.staleMoves ~= nil then
		f.staleMoves = if w.staleMoves == "" then {} else string.split(w.staleMoves, ",")
	end
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
			self.landed[seq] = nil
		end
	end
end

-- ---------------------------------------------------------------- instant hits ----
local function overlap(a: any, b: any): boolean
	return a.x1 < b.x2 and a.x2 > b.x1 and a.y1 < b.y2 and a.y2 > b.y1
end

-- A direct swing's damage before combo scaling, worked out as Combat.resolveHit does - it is what
-- sets the attacker's hit freeze. With the staling multiplier it used. (resolveHit's charge
-- bonus is left out: only a charged beam has one, and a beam is not a swing.)
local function swingDamage(f: any, move: any, hb: any, victim: number): (number, number, boolean)
	local damage = (if hb and hb.damage ~= nil then hb.damage else move.damage) + (f.bonusDamage or 0)
	-- the bullwhip's tip on the fighter it marked cracks (Combat.resolveHit, CRACK) - added after
	-- staling, and only to a hit that lands (the caller adds it for a clean hit)
	local cracks = hb and hb.tip and f.mech.id == "Crack" and f.mech.mark == victim
	local stale = 1
	if move.id ~= "Ultimate" and move.kind ~= "grab" then
		stale = if f.staleSerial == f.moveSerial then f.staleNow else Config.staleMul(f.staleMoves, move.id)
	end
	if stale < 1 then damage = math.max(1, math.floor(damage * stale + 0.5)) end
	return damage, stale, cracks == true
end

-- What the hit will be on the server, from what the view says of the foe: blocked by a shield,
-- shrugged off by a heavy's startup (Combat.resolveHit's armour), or landed.
local function outcome(v: any, move: any): string
	if v.state == "attack" then
		local theirs = Fighter.moveOf(v.char, v.moveId)
		if theirs and theirs.heavy and theirs.id ~= "Ultimate" and v.mf < v.se and not move.heavy
			and move.kind ~= "grab" and move.id ~= "Ultimate" then
			return "armor"
		end
	end
	if v.state == "shield" and not move.unblockable and move.kind ~= "grab" then return "block" end
	return "hit"
end

-- What a landed hit does to the attacker (Combat.resolveHit, `direct`): the freeze, and for a
-- clean hit the chain, the chase target, the staling memory, the move's own on-hit and the charge.
-- A touch that landed nothing (`kind` nil: the foe was dodging) does nothing here.
local function land(self: any, c: any)
	local f = self.fighter
	if not c.kind then return end
	f.hitlag = c.hitlag
	f.moveLanded = true
	if c.kind ~= "hit" then return end
	local move = c.move
	f.comboTarget = if self.others then self.others[c.victim] else nil
	if move.id ~= "Ultimate" and move.kind ~= "grab" and f.staleSerial ~= f.moveSerial then
		f.staleSerial = f.moveSerial; f.staleNow = c.stale
		table.insert(f.staleMoves, move.id)
		if #f.staleMoves > Config.STALE.memory then table.remove(f.staleMoves, 1) end
	end
	if move.onHit then
		if move.onHit.bounce and not f.onGround then f.vy = move.onHit.bounce; f.fastFalling = false end
		if move.onHit.regainJump then f.jumpsLeft = math.max(f.jumpsLeft, 1) end
		if move.onHit.regainAirDodge then f.airDodgeUsed = false end
	end
	if move.id ~= "Ultimate" then
		f:chargeUltimate(if f.linkPerfect and f.move == move then Config.COMBO.perfectCharge else 1)
	end
	-- a tip that landed marks its victim, or cracks and spends the mark (CRACK)
	if c.tip and f.mech.id == "Crack" then
		if c.cracks then f.mech.mark = -1; f.mech.expires = 0
		else f.mech.mark = c.victim; f.mech.expires = f.frameCount + f.char.mechanic.markFrames end
	end
end

-- Combat.step's hitbox scan for the local fighter, against the view: the same once-per-victim
-- bookkeeping (hitVictims, rehitEvery), the same skip while frozen. Returns every foe it touched -
-- a dodging one is touched too, and not hit again by the same swing, exactly as on the server -
-- each with the hit it landed, if it landed one.
local function predictHits(self: any): { any }?
	local f = self.fighter
	local foes = self.view
	if not foes or not f.alive or f.hitlag > 0 then return nil end
	local out = nil
	for _, b in Combat.activeHitboxes(Combat, f) do
		local frameKey = if f.state == "attack" then f.mf else f.sf
		for _, v in foes do
			if overlap(b.rect, v.box) then
				local last = f.hitVictims[v.index]
				if last == nil or (b.hb.rehitEvery and frameKey - last >= b.hb.rehitEvery) then
					f.hitVictims[v.index] = frameKey
					local c: any = { victim = v.index, frameKey = frameKey, serial = f.moveSerial }
					out = out or {}
					table.insert(out, c)
					if not v.untouchable then
						local move, hb = b.move, b.hb
						local damage, stale, crackable = swingDamage(f, move, hb, v.index)
						local kind = outcome(v, move)
						-- a crack only on a clean hit: a blocked or armoured tip neither cracks nor spends the mark
						local cracks = crackable and kind == "hit"
						if cracks then damage += f.char.mechanic.bonusDamage end
						c.kind, c.move, c.hitlag, c.stale = kind, move, Knockback.hitlag(damage, move.heavy), stale
						c.tip, c.cracks = hb.tip == true, cracks
						land(self, c)
						-- the sparks: where the server puts them, as hard as the launch is likely to be
						local base = if hb.base ~= nil then hb.base else move.base
						local growth = if hb.growth ~= nil then hb.growth else move.growth
						local kb = (if hb.knockbackMul ~= nil then hb.knockbackMul else move.knockbackMul) or 1
						table.insert(self.fresh, {
							type = c.kind, predicted = true, attacker = self.index, victim = v.index, fighter = self.index,
							x = (b.rect.x1 + b.rect.x2) / 2, y = (b.rect.y1 + b.rect.y2) / 2,
							damage = damage, heavy = not not move.heavy, finisher = not not move.finisher, weight = v.weight,
							launch = Knockback.launchSpeed(base, growth, damage, v.percent + damage, v.weight) * (f.launchMul or 1) * kb
								* (if cracks then f.char.mechanic.launchMul else 1),
						})
						-- and the whip's mark or crack, which the server sends after its hit event
						if c.kind == "hit" and c.tip and f.mech.id == "Crack" then
							table.insert(self.fresh, { type = if cracks then "crack" else "crackmark", predicted = true,
								attacker = self.index, victim = v.index, fighter = self.index,
								x = (b.rect.x1 + b.rect.x2) / 2, y = (b.rect.y1 + b.rect.y2) / 2 })
						end
					end
				end
			end
		end
	end
	return out
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
		-- After the step, as Combat.step runs after the fighters' - and before the snapshot below,
		-- which a rollback to this frame restores.
		self.landed[seq] = predictHits(self)
	else
		-- A replay touches and lands what was predicted live, on the same swing, rather than judging
		-- it again against a view that has moved on since. Leaving out a touch that landed nothing
		-- let the swing's next active frame "hit" a foe the server had already passed over.
		for _, c in self.landed[seq] or {} do
			if f.moveSerial == c.serial then
				f.hitVictims[c.victim] = c.frameKey
				land(self, c)
			end
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
	out.staleMoves = table.concat(f.staleMoves, ",")
	out.crackMark = if f.mech.id == "Crack" then f.mech.mark else -1
	out.crackExpires = if f.mech.id == "Crack" then f.mech.expires else 0
	out.rings = if f.mech.id == "Return" then f.mech.rings else -1
	out.fuel = if f.mech.id == "ThrustFuel" then f.mech.fuel else -1
	return out
end

return Predictor
