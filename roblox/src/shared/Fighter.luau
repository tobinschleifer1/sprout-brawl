--!nonstrict
-- The fighter state machine, ported 1:1 from web/src/engine/fighter.js.
--
-- tests/fighter-parity.luau replays recorded JavaScript traces through this and fails on the first
-- frame that differs, so this file is checked against its source rather than against a reading of
-- it. Three Luau-specific traps were live while porting it, and all three are invisible on a read:
--
--   * `sign` here is the JavaScript helper, which returns +1 for ZERO. math.sign returns 0.
--   * Luau arrays are 1-INDEXED. Every `inv[0]`/`inv[1]` pair in config became `[1]`/`[2]`, and
--     LEDGE.invinc[min(grabs - 1, 2)] became LEDGE.invinc[min(grabs, 3)].
--   * `pairs` order is unspecified, so the input buffer is walked over a fixed key list rather
--     than iterated. It does not matter for a set of independent decrements; it would matter the
--     first time somebody made one of them depend on another, and by then it is a desync.
--
-- `ctx.combat` is an injected interface, not a require. Combat is Phase 3; the parity trace drives
-- this with a stub on both sides so the state machine is tested in isolation.

local Config = require(script.Parent.Config)
local Knockback = require(script.Parent.Knockback)
local Input = require(script.Parent.Input)

local FRAME = Config.FRAME
local GRAVITY = Config.GRAVITY
local LAUNCH_DRAG = Config.LAUNCH_DRAG
local TUMBLE_THRESHOLD = Config.TUMBLE_THRESHOLD
local MOVE = Config.MOVE
local SHIELD = Config.SHIELD
local LEDGE = Config.LEDGE
local DASH = Config.DASH
local SPOT_DODGE = Config.SPOT_DODGE
local AIR_DODGE = Config.AIR_DODGE
local GROUND_POUND = Config.GROUND_POUND
local GRAB = Config.GRAB
local TECH = Config.TECH
local KNOCKDOWN = Config.KNOCKDOWN
local TAUNT_FRAMES = Config.TAUNT_FRAMES
local RESPAWN = Config.RESPAWN
local INPUT_BUFFER = Config.INPUT_BUFFER
local ULTIMATE = Config.ULTIMATE

-- JavaScript's local helper: sign(0) is +1, NOT 0. math.sign would change facing on a neutral stick.
local function sign(v: number): number
	return if v < 0 then -1 else 1
end

-- See the note in web/src/engine/fighter.js: Math.hypot is avoided on both sides so the two builds
-- compute the same expression rather than two algorithms that differ in the last two bits.
local function hypot(x: number, y: number): number
	return math.sqrt(x * x + y * y)
end

-- The ceiling on any environmental acceleration, in studs/s^2. See the JavaScript for why it is
-- above gravity: a hazard that cannot beat gravity is not holding you up.
local ENV_MAX = 260
local function clampEnv(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end

local NO_GRAVITY_STATES = {
	ledge = true, grabbed = true, holding = true, frozen = true,
	tether = true, ko = true, respawn = true, ledgeaction = true,
}
local FREE_STATES = { idle = true, run = true, air = true }
local BUFFER_KEYS = { "jump", "light", "heavy", "dodge", "guard", "grab", "taunt", "ult", "pickup" }

local methods = {}
local computed = {}
local meta = { __index = function(self, key)
	local c = computed[key]
	if c then
		return c(self)
	end
	return methods[key]
end }

-- ---------------------------------------------------------------- computed ----
-- The JavaScript uses getters. Routing them through __index keeps every call site identical to the
-- source (`f.cy`, `f.untouchable`) instead of scattering `f:cy()` through a 1:1 port.
computed.hurtbox = function(self)
	return { x1 = self.x - self.r, x2 = self.x + self.r, y1 = self.y, y2 = self.y + self.h }
end
computed.cy = function(self) return self.y + self.h / 2 end
computed.isInvincible = function(self) return self.invincible > 0 end
computed.inHitstun = function(self) return self.state == "hitstun" end
computed.busy = function(self) return not FREE_STATES[self.state] end
computed.ultReady = function(self)
	return self.ultCharge >= ULTIMATE.hitsRequired and self.char.moves.Ultimate ~= nil
end
computed.ultMeter = function(self) return math.min(1, self.ultCharge / ULTIMATE.hitsRequired) end
computed.moveActive = function(self)
	if self.state ~= "attack" or not self.move then
		return false
	end
	return self.mf > self.startupEff and self.mf <= self.startupEff + self.move.active
end
computed.moveFrameAbs = function(self) return self.mf + self.startupShift end
computed.grabActive = function(self)
	return self.state == "grab" and self.sf > GRAB.startup and self.sf <= GRAB.startup + GRAB.active
end
computed.untouchable = function(self)
	return self.invincible > 0 or methods.isDodgeInvincible(self)
		or self.state == "ko" or self.state == "respawn" or not self.alive
end

-- ---------------------------------------------------------------- construction ----
local Fighter = {}

function Fighter.new(opts: any): any
	local self = setmetatable({}, meta)
	self.index = opts.index
	self.char = opts.char
	self.skin = opts.skin or 0
	self.team = if opts.team == nil then opts.index else opts.team
	self.source = opts.source or "bot"
	self.isBot = not not opts.isBot
	self.botLevel = opts.botLevel or "normal"
	self.name = opts.name or self.char.name
	self.r = self.char.radius
	self.h = self.char.height
	self.weight = self.char.weight
	self.stocks = if opts.stocks == nil then 3 else opts.stocks
	self.percent = 0
	self.alive = true
	self.stats = { kos = 0, falls = 0, damageDealt = 0, damageTaken = 0, selfDestructs = 0 }
	self.input = Input.emptyFrame()
	self.buffer = { jump = 0, light = 0, heavy = 0, dodge = 0, guard = 0, grab = 0, taunt = 0, ult = 0, pickup = 0 }
	self.frameCount = 0
	self.item = nil
	self.effects = {
		chill = { stacks = 0, timer = 0 }, tangle = { stacks = 0, timer = 0 },
		grit = { hide = 0, slow = 0 }, slow = 0, frozenBonus = false,
	}
	self.mech = methods._initMechanic(self)
	methods.reset(self, opts.x or 0, opts.y or 0, {})
	return self
end

function methods._initMechanic(self)
	local m = self.char.mechanic
	if not m then
		return {}
	end
	if m.id == "Bloom" then return { id = "Bloom", hits = {}, bloomed = false, timer = 0, cooldown = 0 }
	elseif m.id == "Fruiting" then return { id = "Fruiting", ring = 0 }
	elseif m.id == "Light" then return { id = "Light", segments = 0, still = 0 }
	elseif m.id == "Tangle" then return { id = "Tangle" }
	elseif m.id == "Spines" then return { id = "Spines", spines = m.max, regen = 0 }
	elseif m.id == "Momentum" then return { id = "Momentum", runFrames = 0, ready = false }
	elseif m.id == "Brace" then return { id = "Brace", guardFrames = 0, ready = false }
	elseif m.id == "Network" then return { id = "Network" }
	elseif m.id == "Chill" then return { id = "Chill" }
	end
	return { id = m.id }
end

function methods.reset(self, x: number, y: number, opts: any?)
	local o = opts or {}
	self.x = x; self.y = y; self.prevX = x; self.prevY = y
	self.vx = 0; self.vy = 0
	self.facing = if x < 0 then 1 else -1
	self.onGround = false; self.platform = nil
	self.jumpsLeft = self.char.jumps
	self.airDodgeUsed = false; self.recoveryUsed = false; self.ledgeGrabs = 0; self.fastFalling = false
	self.dropTimer = 0; self.ledgeCooldown = 0
	self.state = o.state or "respawn"; self.sf = 0
	self.shield = SHIELD.max; self.blockstun = 0
	self.hitstun = 0; self.hitlag = 0; self.tumbling = false; self.pendingLaunch = nil
	self.pendingLaunchFrame = nil
	self.invincible = if o.invincible == nil then RESPAWN.invinc else o.invincible
	self.move = nil; self.moveId = nil; self.mf = 0; self.startupEff = 0; self.startupShift = 0
	self.hitVictims = {}; self.moveLanded = false; self.charge = 0; self.armorUsed = false
	self.spawnedActive = false
	self.bonusDamage = 0; self.launchMul = 1
	self.hold = nil; self.holder = nil; self.la = nil; self.lag = 0; self.tether = nil; self.frozenFrames = 0
	self.ledge = nil
	self.di = { x = 0, y = 0 }
	self.techPress = 0; self.techRoll = 0; self.volleyCount = 0; self.rangeMul = 1
	self.chargeMods = nil; self.noGravityFrame = false
	-- Ultimate meter. reset() runs on respawn, so losing a stock wipes the charge.
	self.ultCharge = 0; self.ultActive = 0
	self.ultTarget = nil; self.ultHeld = {}; self.ultShots = 0; self.ultCooldown = 0; self.ultEndAt = 0
	self.ultAnchor = nil
	-- Frames during which this fighter is on the end of a snare, so the carried pull holds instead
	-- of decaying like a gust.
	self.snaredBy = 0
	self.reeling = 0
	self.reflecting = nil   -- Aegis window
	self.marking = nil      -- Exsanguinate window
	self.lastHitBy = nil; self.lastHitFrame = -9999
	self.inWater = false
	-- What the stage is doing to this fighter THIS FRAME. Zeroed by the stage before hazards run,
	-- written by hazards, read by _physics and _friction.
	self.env = { updraft = 0, windX = 0, traction = 1, grip = 1, damp = 1 }
	-- Wind is carried in its OWN velocity, not folded into vx - see the JavaScript for the
	-- measurements. carryX is added at the position step, so drift and wind compose rather than fight.
	self.carryX = 0
	self.effects.chill = { stacks = 0, timer = 0 }
	self.effects.tangle = { stacks = 0, timer = 0 }
	self.effects.grit = { hide = 0, slow = 0 }
	self.effects.slow = 0
	self.effects.frozenBonus = false
	self.effects.lodestone = 0; self.effects.lodestoneDef = nil; self.effects.bleed = 0
	if o.percent ~= nil then
		self.percent = o.percent
	end
	local id = self.mech.id
	if id == "Momentum" then self.mech.runFrames = 0; self.mech.ready = false end
	if id == "Brace" then self.mech.guardFrames = 0; self.mech.ready = false end
	if id == "Light" then self.mech.segments = 0; self.mech.still = 0 end
	if id == "Surge" then self.mech.hits = {}; self.mech.surged = false; self.mech.timer = 0 end
	if id == "Draw" then self.mech.draw = 0; self.mech.ready = false end
	if id == "Snare" then self.mech.snared = nil; self.mech.timer = 0; self.mech.ready = false end
	self.item = nil
	self.events = {}
end

-- ---------------------------------------------------------------- helpers ----
function methods.speedMul(self): number
	local m = 1 - 0.08 * self.effects.chill.stacks
	if self.effects.grit.slow > 0 then m *= 0.9 end
	if self.effects.slow > 0 then m *= 0.8 end
	-- Carrying a Bulwark is slow. That is the cost.
	if self.item and self.item.def.guard and self.item.hp > 0 then m *= self.item.def.guard.speedMul end
	-- Drawing a bow is not something you do while moving.
	if self.mech.id == "Draw" and self.mech.draw > 6 then m *= self.char.mechanic.slowMul end
	if self.reeling > 0 then m *= 0.35 end          -- braced against the chain, not running
	if self.inWater then m *= 0.4 end
	return m
end

function methods.jumpMul(self): number
	local L = if self.effects.lodestone > 0 then self.effects.lodestoneDef else nil
	return (1 - 0.08 * self.effects.chill.stacks) * (if L then L.jumpMul else 1)
end

-- How many stocks this fighter has left, which in a team match is the TEAM's pool rather than
-- their own. match.js patches this onto Fighter.prototype; here it simply lives on Fighter, which
-- is where it always belonged.
function methods.stocksLeft(self): number
	local m = self._match
	return if m then m:stocksLeftFor(self) else self.stocks
end

function methods.setState(self, s: string)
	self.state = s
	self.sf = 0
end

function methods.chargeUltimate(self, n: number?)
	local was = computed.ultReady(self)
	self.ultCharge = math.min(ULTIMATE.hitsRequired, self.ultCharge + (n or 1))
	if not was and computed.ultReady(self) then
		methods.emit(self, { type = "ultready" })
	end
end

function methods.consume(self, b: string): boolean
	if self.buffer[b] > 0 then
		self.buffer[b] = 0
		return true
	end
	return false
end

function methods.emit(self, e: any)
	table.insert(self.events, e)
end

function methods.applyInput(self, frame: any)
	self.input = frame
	for _, b in BUFFER_KEYS do
		if frame[b] then
			self.buffer[b] = INPUT_BUFFER
		end
	end
	-- Teching has its own window (TECH.window = 8), wider than INPUT_BUFFER, so it cannot be
	-- expressed as a guard-buffer threshold.
	if frame.guard then
		self.techPress = TECH.window
	end
end

-- ---------------------------------------------------------------- main step ----
function methods.step(self, ctx: any)
	self.frameCount += 1
	-- DI is re-sampled every frame, hitlag included: the stick held when the freeze ends is the one
	-- that bends the launch angle. See _applyLaunch.
	self.di = { x = self.input.x, y = self.input.y }
	if not self.alive then
		return
	end
	if self.hitlag > 0 then
		-- Buffers deliberately do NOT tick here. Hitlag runs up to HITLAG_CAP (12) frames, longer
		-- than INPUT_BUFFER (6), so ticking during the freeze silently ate every escape input.
		self.hitlag -= 1
		if self.hitlag == 0 and self.pendingLaunch then
			methods._applyLaunch(self)
		end
		return
	end
	for _, k in BUFFER_KEYS do
		if self.buffer[k] > 0 then
			self.buffer[k] -= 1
		end
	end
	methods._tickTimers(self)
	self.sf += 1
	self.prevX = self.x; self.prevY = self.y
	self.noGravityFrame = false
	methods._stepState(self, ctx)
	methods._physics(self, ctx)
	methods._mechanicsFrame(self, ctx)
	-- Ticked last, so a guard pressed on the same frame a landing resolves still counts.
	if self.techPress > 0 then
		self.techPress -= 1
	end
end

function methods._tickTimers(self)
	if self.invincible > 0 then self.invincible -= 1 end
	if self.ledgeCooldown > 0 then self.ledgeCooldown -= 1 end
	if self.dropTimer > 0 then self.dropTimer -= 1 end
	local e = self.effects
	if e.chill.timer > 0 then
		e.chill.timer -= 1
		if e.chill.timer == 0 then e.chill.stacks = 0 end
	end
	if e.tangle.timer > 0 then
		e.tangle.timer -= 1
		if e.tangle.timer == 0 then e.tangle.stacks = 0 end
	end
	if e.grit.hide > 0 then e.grit.hide -= 1 end
	if e.grit.slow > 0 then e.grit.slow -= 1 end
	if e.slow > 0 then e.slow -= 1 end
	if e.lodestone > 0 then
		e.lodestone -= 1
		if e.lodestone == 0 then e.lodestoneDef = nil end
	end
	if self.state ~= "shield" then
		self.shield = math.min(SHIELD.max, self.shield + SHIELD.regenPerSec * FRAME)
	end
end

-- Runs on the frame hitlag ends. The launch vector is built here rather than at hit time so that DI
-- held during the freeze actually counts. Combat overwrites pendingLaunch with a raw {vx, vy} for
-- drag moves; that shape passes through.
function methods._applyLaunch(self)
	local p = self.pendingLaunch
	self.pendingLaunch = nil
	local vx, vy
	if p.vx ~= nil then
		vx = p.vx; vy = p.vy
	else
		local v = Knockback.velocity(p.launch, p.angle, p.facing, self.di)
		vx = v.vx; vy = v.vy
		if self.onGround and vy < 0 then
			vy = -vy * 0.8
		end
	end
	self.vx = vx; self.vy = vy
	if vy > 0.5 or not self.onGround then
		self.onGround = false
		self.platform = nil
	end
end

function methods._stepState(self, ctx)
	local s = self.state
	if s == "idle" or s == "run" then return methods._stepGround(self, ctx)
	elseif s == "jumpsquat" then return methods._stepJumpsquat(self)
	elseif s == "air" or s == "helpless" then return methods._stepAir(self, ctx)
	elseif s == "attack" then return methods._stepAttack(self, ctx)
	elseif s == "landing" then
		if self.sf > self.lag then methods.setState(self, "idle") end
		methods._friction(self); return
	elseif s == "dash" then return methods._stepDash(self, ctx)
	elseif s == "spotdodge" then
		methods._friction(self)
		if self.sf > SPOT_DODGE.frames then methods.setState(self, "idle") end
		return
	elseif s == "airdodge" then return methods._stepAirDodge(self)
	elseif s == "shield" then return methods._stepShield(self, ctx)
	elseif s == "shielddrop" then
		methods._friction(self)
		if self.sf > SHIELD.dropFrames then methods.setState(self, "idle") end
		return
	elseif s == "stunned" then
		methods._friction(self)
		if self.sf > SHIELD.breakStun then methods.setState(self, "idle") end
		return
	elseif s == "hitstun" then return methods._stepHitstun(self)
	elseif s == "knockdown" then
		methods._friction(self)
		if self.sf > KNOCKDOWN.frames then methods.setState(self, "idle") end
		return
	elseif s == "tech" then return methods._stepTech(self)
	elseif s == "ledge" then return methods._stepLedge(self, ctx)
	elseif s == "ledgeaction" then return methods._stepLedgeAction(self, ctx)
	elseif s == "grab" then return methods._stepGrab(self, ctx)
	elseif s == "holding" then return methods._stepHolding(self, ctx)
	elseif s == "grabbed" then return
	elseif s == "groundpound" then return methods._stepGroundPound(self)
	elseif s == "recovery" then
		if self.sf > 18 then methods.setState(self, "helpless") end
		return
	elseif s == "tether" then return methods._stepTether(self, ctx)
	elseif s == "frozen" then return methods._stepFrozen(self)
	elseif s == "taunt" then
		methods._friction(self)
		if self.sf > TAUNT_FRAMES or (self.sf > 10 and self.input.anyPress) then
			methods.setState(self, "idle")
		end
		return
	elseif s == "respawn" then return methods._stepRespawn(self)
	elseif s == "ko" then return
	end
	return
end

-- ---------------------------------------------------------------- ground ----
function methods._stepGround(self, ctx)
	local inp = self.input
	if inp.downTap and self.platform and self.platform.soft then
		methods.dropThrough(self); return
	end
	if methods.consume(self, "jump") then methods.setState(self, "jumpsquat"); return end
	if self.item then
		if methods.consume(self, "light") then ctx.combat:useItem(self, "light"); return end
		if methods.consume(self, "heavy") then ctx.combat:useItem(self, "heavy"); return end
	end
	if methods.consume(self, "grab") or (self.buffer.light > 0 and inp.guardHeld) then
		self.buffer.light = 0
		methods._startGrab(self); return
	end
	if methods.consume(self, "light") then methods._startGroundLight(self, inp); return end
	if methods.consume(self, "heavy") then methods._startGroundHeavy(self, inp, ctx); return end
	if methods.consume(self, "dodge") then
		if math.abs(inp.x) > 0.5 then methods._startDash(self, sign(inp.x))
		else methods.setState(self, "spotdodge") end
		return
	end
	-- Pick up / drop. `pickup` is its own button; guard still works, because that is what anyone
	-- who learned it the old way will press.
	if methods.consume(self, "pickup") or methods.consume(self, "guard") then
		if self.item and inp.y < -0.5 then ctx.combat:dropItem(self, false); return end
		local it = ctx.combat:itemNear(self)
		if it and not self.item then ctx.combat:pickupItem(self, it); return end
	end
	if inp.guardHeld then methods.setState(self, "shield"); return end
	if methods._tryUltimate(self, ctx) then return end
	if methods.consume(self, "taunt") then methods.setState(self, "taunt"); return end
	methods._groundMove(self, inp)
end

function methods._groundMove(self, inp)
	local run = math.abs(inp.x) >= 0.5
	local walk = math.abs(inp.x) > 0.15
	local speed = (if run then self.char.runSpeed else self.char.walkSpeed) * methods.speedMul(self)
	-- env.grip is the slick's effect on ACCELERATION, as distinct from env.traction which is its
	-- effect on stopping. Floored at 0.3: a stage may make you clumsy, never helpless.
	local accel = (self.char.runSpeed / MOVE.groundAccelFrames) * math.max(0.3, self.env.grip)
	if walk then
		self.facing = sign(inp.x)
		local target = sign(inp.x) * speed
		if self.vx < target then
			self.vx = math.min(target, self.vx + accel)
		elseif self.vx > target then
			self.vx = math.max(target, self.vx - accel)
		end
		self.state = if run then "run" else "idle"
	else
		methods._friction(self)
		self.state = if math.abs(self.vx) > 0.5 then self.state else "idle"
		if self.state == "run" then
			self.state = "idle"
		end
	end
end

function methods._friction(self)
	if not self.onGround then
		return
	end
	-- Traction floors at 0.25: a slick surface should cost you your stop, never your agency.
	local decel = (self.char.runSpeed / MOVE.groundStopFrames) * math.max(0.25, self.env.traction)
	if math.abs(self.vx) <= decel then
		self.vx = 0
	else
		self.vx -= sign(self.vx) * decel
	end
end

function methods._airDrift(self, inp, mul: number?)
	local m = mul or 1
	-- A stuck Lodestone takes most of your air control away.
	local L = if self.effects.lodestone > 0 then self.effects.lodestoneDef else nil
	local target = inp.x * self.char.airSpeed * m * (if L then L.airMul else 1) * methods.speedMul(self)
	local accel = self.char.airSpeed / MOVE.airAccelFrames
	if math.abs(inp.x) > 0.15 then
		if self.vx < target then
			self.vx = math.min(target, self.vx + accel)
		elseif self.vx > target then
			self.vx = math.max(target, self.vx - accel)
		end
	else
		self.vx *= MOVE.airDrag
	end
end

function methods.dropThrough(self)
	if not self.platform or not self.platform.soft then
		return
	end
	self.dropTimer = 10; self.onGround = false; self.platform = nil; self.vy = -2
	if self.state == "idle" or self.state == "run" then
		methods.setState(self, "air")
	end
end

function methods._stepJumpsquat(self)
	methods._friction(self)
	if self.sf >= MOVE.jumpsquat then
		self.vy = self.char.jumpVelocity * methods.jumpMul(self)
		if not self.input.jumpHeld then
			self.vy *= MOVE.shortHopMul
		end
		self.onGround = false; self.platform = nil
		self.jumpsLeft = self.char.jumps - 1
		self.fastFalling = false
		methods.setState(self, "air")
		methods.emit(self, { type = "jump" })
	end
end

function methods._startGroundLight(self, inp)
	if inp.y < -0.5 then return methods.startMove(self, "LightDown") end
	-- Up + Light. Without this the up-light was reachable only as a chain link.
	if inp.y > 0.5 and self.char.moves.LightUp then return methods.startMove(self, "LightUp") end
	if math.abs(inp.x) > 0.5 then
		self.facing = sign(inp.x)
		return methods.startMove(self, "LightSide1")
	end
	return methods.startMove(self, "LightNeutral1")
end

function methods._startGroundHeavy(self, inp, ctx)
	if inp.y < -0.5 then
		if self.mech.id == "Fruiting" and self.mech.ring >= self.char.mechanic.ringMax
			and ctx.combat:hasFruit(self) then
			ctx.combat:fruiting(self)
			return
		end
		return methods.startMove(self, "SigDown")
	end
	if math.abs(inp.x) > 0.5 then
		self.facing = sign(inp.x)
		return methods.startMove(self, "SigSide")
	end
	-- Neutral Heavy is its own signature when the loadout defines one, else it reuses the side sig.
	return methods.startMove(self, if self.char.moves.SigNeutral then "SigNeutral" else "SigSide")
end

function methods._startDash(self, dir: number)
	self.facing = dir
	self.vx = dir * self.char.runSpeed * DASH.speedMul * methods.speedMul(self)
	methods.setState(self, "dash")
	methods.emit(self, { type = "dash" })
end

function methods._stepDash(self, ctx)
	local inp = self.input
	self.vx = self.facing * self.char.runSpeed * DASH.speedMul * methods.speedMul(self)
	if self.sf >= 4 and methods.consume(self, "jump") then methods.setState(self, "jumpsquat"); return end
	if self.sf >= DASH.cancelLightFrom then
		if methods.consume(self, "light") then methods._startGroundLight(self, inp); return end
		if methods.consume(self, "heavy") then methods._startGroundHeavy(self, inp, ctx); return end
	end
	if self.sf >= DASH.cancelShieldFrom and inp.guardHeld then methods.setState(self, "shield"); return end
	if self.mech.id == "Momentum" then self.mech.runFrames += 1 end
	if self.sf > DASH.frames then
		self.vx = self.facing * self.char.runSpeed * methods.speedMul(self)
		methods.setState(self, "run")
	end
end

-- ---------------------------------------------------------------- air ----
function methods._stepAir(self, ctx)
	local inp = self.input
	if self.state == "helpless" then
		methods._airDrift(self, inp, 0.6)
		if methods.consume(self, "dodge") and not self.airDodgeUsed then
			methods._startAirDodge(self, inp)
		end
		return
	end
	if self.jumpsLeft > 0 and methods.consume(self, "jump") then
		self.jumpsLeft -= 1
		self.vy = self.char.jumpVelocity * methods.jumpMul(self)
		self.fastFalling = false; self.tumbling = false
		if math.abs(inp.x) > 0.5 then self.facing = sign(inp.x) end
		methods.emit(self, { type = "doublejump" })
	end
	if methods._tryUltimate(self, ctx) then return end
	if methods.consume(self, "light") then methods._startAerial(self, inp); return end
	if methods.consume(self, "heavy") then
		if inp.y < -0.5 then methods._startGroundPound(self) else methods._startRecovery(self, ctx) end
		return
	end
	if methods.consume(self, "dodge") and not self.airDodgeUsed then
		methods._startAirDodge(self, inp); return
	end
	if (inp.downTap or (inp.y < -0.5 and self.vy < 0 and self.vy > -6))
		and self.vy <= 0 and not self.fastFalling then
		self.fastFalling = true
		methods.emit(self, { type = "fastfall" })
	end
	methods._airDrift(self, inp)
end

-- Spending the meter is all-or-nothing: the whole bar goes, and the move gets a short window of
-- invincibility on startup so an ultimate cannot be poked out of the air the frame it starts.
function methods._tryUltimate(self, ctx): boolean
	if self.buffer.ult <= 0 then
		return false
	end
	if not computed.ultReady(self) then
		self.buffer.ult = 0
		methods.emit(self, { type = "ultdenied" })
		return false
	end
	-- A slam that opens the floor has to be standing on one.
	if self.char.moves.Ultimate.grounded and not self.onGround then
		methods.emit(self, { type = "ultdenied" })
		return false
	end
	self.buffer.ult = 0
	self.ultCharge = 0
	self.ultActive = 1
	-- Everyone freezes, the CASTER INCLUDED - a beat of theatre, not an advantage. Freezing only
	-- the victims would make every ultimate unavoidable.
	if ctx and ctx.combat then
		for _, v in ctx.combat.fighters do
			v.hitlag = math.max(v.hitlag, ULTIMATE.freezeFrames)
		end
	end
	self.invincible = math.max(self.invincible, ULTIMATE.invincibleFrames)
	methods.emit(self, { type = "ultimate", move = "Ultimate", label = self.char.moves.Ultimate.label,
		weapon = if self.char.weapon then self.char.weapon.id else nil,
		fighter = self.index, x = self.x, y = computed.cy(self) })
	methods.startMove(self, "Ultimate")
	return true
end

function methods._startAerial(self, inp)
	self.tumbling = false
	if inp.y < -0.5 then return methods.startMove(self, "AirDown") end
	if inp.y > 0.5 and self.char.moves.AirUp then return methods.startMove(self, "AirUp") end
	if math.abs(inp.x) > 0.5 then
		self.facing = sign(inp.x)
		return methods.startMove(self, "AirForward")
	end
	return methods.startMove(self, "AirNeutral")
end

function methods._startAirDodge(self, inp)
	self.airDodgeUsed = true; self.tumbling = false; self.fastFalling = false
	local len = hypot(inp.x, inp.y)
	if len > 0.3 then
		self.vx = (inp.x / len) * 36
		self.vy = (inp.y / len) * 36
	else
		self.vx = 0; self.vy = 0
	end
	methods.setState(self, "airdodge")
	methods.emit(self, { type = "dodge" })
end

function methods._stepAirDodge(self)
	if self.sf <= 10 then
		self.vx *= 0.85; self.vy *= 0.85
		self.noGravityFrame = true
	end
	if self.sf > AIR_DODGE.frames then methods.setState(self, "air") end
end

function methods._startGroundPound(self)
	self.tumbling = false; self.fastFalling = false; self.vx = 0; self.vy = 0
	self.hitVictims = {}
	methods.setState(self, "groundpound")
end

function methods._stepGroundPound(self)
	if self.sf <= GROUND_POUND.hang then
		self.vy = 0; self.vx *= 0.8; self.noGravityFrame = true
	else
		self.vy = -GROUND_POUND.speed; self.noGravityFrame = true
	end
end

function methods._startRecovery(self, ctx)
	if self.recoveryUsed then
		return
	end
	self.recoveryUsed = true; self.tumbling = false; self.fastFalling = false
	local rec = self.char.recovery
	local inp = self.input
	local dir = if math.abs(inp.x) > 0.3 then sign(inp.x) else self.facing
	local stage = ctx.stage
	methods.emit(self, { type = "recovery", kind = rec.kind })
	if rec.kind == "tether" then
		local res = stage:nearestLedge(self.x, computed.cy(self))
		local ledge, dist = res.ledge, res.dist
		local outside = ledge ~= nil
			and ((self.x - ledge.x) * ledge.side > -2 or self.y < ledge.y - 2)
		if ledge and dist <= rec.range and outside and self.ledgeGrabs < LEDGE.maxGrabs then
			self.tether = { ledge = ledge, tx = ledge.x + ledge.side * LEDGE.hangOffsetX,
				ty = ledge.y + LEDGE.hangOffsetY, speed = rec.speed }
			self.vx = 0; self.vy = 0; self.facing = -ledge.side
			methods.setState(self, "tether")
			return
		end
		self.vy = rec.hopVy
		self.vx = (if stage.main.cx > self.x then 1 else -1) * self.char.airSpeed
		self.facing = sign(self.vx)
		methods.setState(self, "recovery"); return
	end
	if rec.kind == "teleport" then
		local node = ctx.combat:nearestNode(self, rec.range)
		if node then
			ctx.combat:removeSummon(node)
			self.x = node.x; self.y = node.y + 0.1; self.vx = 0; self.vy = 6
			methods.emit(self, { type = "teleport", x = node.x, y = node.y })
			methods.setState(self, "recovery"); return
		end
		self.vy = rec.puffVy; self.vx = dir * rec.puffVx
		methods.setState(self, "recovery"); return
	end
	if rec.kind == "puff" then
		self.vy = rec.vy; self.vx = dir * rec.vx
		methods.setState(self, "recovery"); return
	end
	-- hop
	self.vy = rec.vy * methods.jumpMul(self); self.vx = dir * rec.vx; self.facing = dir
	methods.setState(self, "recovery")
end

function methods._stepTether(self, ctx)
	local t = self.tether
	local dx, dy = t.tx - self.x, t.ty - self.y
	local d = hypot(dx, dy)
	local stepLen = t.speed * FRAME
	self.noGravityFrame = true; self.vx = 0; self.vy = 0
	if d <= stepLen then
		self.x = t.tx; self.y = t.ty; self.tether = nil
		methods.grabLedge(self, t.ledge)
		return
	end
	self.x += (dx / d) * stepLen
	self.y += (dy / d) * stepLen
	if self.sf > 60 then
		self.tether = nil
		methods.setState(self, "helpless")
	end
end

-- ---------------------------------------------------------------- attacks ----
function methods.startMove(self, moveOrId: any, opts: any?)
	local move = if type(moveOrId) == "string" then self.char.moves[moveOrId] else moveOrId
	if not move then
		return
	end
	if move.ammo and self.mech.id == "Spines" then
		if (self.mech.spines or 0) < move.ammo then
			methods.emit(self, { type = "dryfire" })
			return
		end
		self.mech.spines -= move.ammo
	end
	self.move = move; self.moveId = move.id; self.mf = 0
	self.moveLanded = false; self.hitVictims = {}
	self.charge = 0; self.armorUsed = false; self.volleyCount = 0; self.spawnedActive = false
	-- per-ultimate scratch: who the sniper painted, who the vortex is holding, shots left
	self.ultTarget = nil; self.ultHeld = {}; self.ultShots = 0; self.ultCooldown = 0; self.ultEndAt = 0
	self.bonusDamage = 0; self.launchMul = 1; self.rangeMul = 1; self.tumbling = false
	self.startupEff = move.startup
	-- mechanic modifiers on move start
	local M = self.char.mechanic
	local id = self.mech.id
	-- BRACE (Warpike): banked by holding shield, spent by a signature. The mirror of Momentum -
	-- one weapon is paid for moving, the other for refusing to.
	if id == "Brace" and self.mech.ready and move.heavy then
		self.bonusDamage += M.bonusDamage
		self.launchMul *= M.launchMul
		self.mech.ready = false; self.mech.guardFrames = 0
		methods.emit(self, { type = "momentum" })
	end
	if id == "Surge" and self.mech.surged then
		if M.startupCut then
			self.startupEff = math.max(2, self.startupEff - M.startupCut)
		end
		if move.heavy then
			self.bonusDamage += M.bonusDamage
			self.launchMul *= M.launchMul
			self.mech.surged = false; self.mech.hits = {}
			methods.emit(self, { type = "momentum" })
		end
	end
	if id == "Draw" and self.mech.ready and move.heavy then
		self.bonusDamage += M.bonusDamage; self.launchMul *= M.launchMul
		self.mech.ready = false; self.mech.draw = 0
		methods.emit(self, { type = "momentum" })
	end
	if id == "Momentum" and self.mech.ready and move.heavy then
		self.bonusDamage += M.bonusDamage; self.launchMul *= M.launchMul
		self.mech.ready = false; self.mech.runFrames = 0
		methods.emit(self, { type = "momentum" })
	elseif id == "Momentum" then
		self.mech.runFrames = 0     -- spent by signatures only; a light does not burn it
	end
	if id == "Bloom" and self.mech.bloomed and move.heavy then
		self.bonusDamage += M.bonusDamage; self.rangeMul = M.rangeMul
		self.mech.bloomed = false; self.mech.cooldown = M.cooldownFrames
		methods.emit(self, { type = "bloomspend" })
	end
	if id == "Light" and move.kind == "beam" and self.mech.segments > 0 then
		self.startupEff = math.max(4, move.startup - M.windupPerSegment * self.mech.segments)
		self.mech.segments = 0
	end
	self.startupShift = move.startup - self.startupEff
	methods.setState(self, "attack")
	methods.emit(self, { type = "movestart", move = move.id, heavy = not not move.heavy })
end

function methods._stepAttack(self, ctx)
	local m = self.move
	local inp = self.input
	if not m then
		methods.setState(self, if self.onGround then "idle" else "air")
		return
	end
	-- Charge holds at the last startup frame.
	if m.charge and self.mf == self.startupEff and inp.heavyHeld and self.charge < m.charge.maxHold then
		self.charge += 1
		if m.kind == "burst" and self.mech.id == "Light" and self.charge % m.charge.lightEvery == 0 then
			self.mech.segments = math.min(self.char.mechanic.segments, self.mech.segments + 1)
		end
		if self.onGround then methods._friction(self) end
		return
	end
	self.mf += 1
	local active = computed.moveActive(self)
	local total = self.startupEff + m.active + m.recovery
	if m.stall and self.mf <= m.stall then
		self.vy = 0; self.noGravityFrame = true
	end
	-- A GROUNDED lunge only drives while there is ground under it. See the JavaScript for the
	-- self-destruct this fixed: a signature thrown near an edge used to carry its full drive speed
	-- off the stage with no friction and no drift.
	local groundLunge = m.lunge and m.grounded ~= false
	if m.lunge and active and (self.onGround or not groundLunge) then
		self.vx = self.facing * (m.lunge / m.active) / FRAME
		-- ...and it stops at the ledge. A lunge is the fighter stepping into their own swing,
		-- which is not something anyone does off the side of a stage.
		if groundLunge and self.onGround and self.platform then
			local pf = self.platform
			local nx = self.x + self.vx * FRAME
			if nx > pf.x2 - 0.1 then
				self.vx = math.max(0, (pf.x2 - 0.1 - self.x) / FRAME)
			elseif nx < pf.x1 + 0.1 then
				self.vx = math.min(0, (pf.x1 + 0.1 - self.x) / FRAME)
			end
		end
	-- A move can declare that it is a STANCE rather than a swing, and keep partial ground control
	-- while it is live. Deadeye needs this.
	elseif m.walkSpeed and active and self.onGround then
		local target = inp.x * self.char.runSpeed * m.walkSpeed * methods.speedMul(self)
		self.vx += (target - self.vx) * 0.22
	elseif self.onGround then
		-- A lunge is a STEP, not a shove. Stop the drive with the swing that produced it; the
		-- recovery is the fighter planted, which is what the animation shows.
		if m.lunge and self.mf > self.startupEff + m.active then
			self.vx = 0
		end
		methods._friction(self)
	else
		if groundLunge then
			local cap = self.char.airSpeed * 1.2
			if math.abs(self.vx) > cap then
				self.vx = sign(self.vx) * cap
			end
		end
		methods._airDrift(self, inp, 0.7)
	end
	if m.fastFallActive and active and not self.onGround then
		self.vy = math.min(self.vy, -self.char.fallSpeed * MOVE.fastFallMul)
	end
	if methods._chainInto(self, m, inp) then return end
	if self.mf == self.startupEff + 1 and not self.spawnedActive then
		self.spawnedActive = true
		ctx.combat:onMoveActive(self, m)
	end
	if active then ctx.combat:onMoveActiveFrame(self, m) end
	if self.mf > total then methods.endMove(self) end
end

-- Combo strings. Once a move has connected and its active frames are done, the follow-up is chosen
-- by the direction held: `chains` keyed by up/side/down/neutral, with `chainsTo` as the fallback.
-- `chainsHeavy` lets a light string cash out into a signature.
function methods._chainInto(self, m, inp): boolean
	if not self.moveLanded or self.mf < self.startupEff + m.active then
		return false
	end
	local dir = if inp.y > 0.5 then "up"
		elseif inp.y < -0.5 then "down"
		elseif math.abs(inp.x) > 0.5 then "side"
		else "neutral"
	local function go(id: any, buf: string): boolean
		if not id or not self.char.moves[id] then
			return false
		end
		self.buffer[buf] = 0
		if dir == "side" then self.facing = sign(inp.x) end
		methods.startMove(self, id)
		return true
	end
	if self.buffer.heavy > 0 and m.chainsHeavy then
		local id = if type(m.chainsHeavy) == "string" then m.chainsHeavy else m.chainsHeavy[dir]
		if go(id, "heavy") then return true end
	end
	if self.buffer.light > 0 then
		local id = (if m.chains then m.chains[dir] else nil) or m.chainsTo
		if go(id, "light") then return true end
	end
	return false
end

function methods.endMove(self)
	if self.moveId == "Ultimate" then
		self.ultActive = 0; self.ultTarget = nil; self.ultHeld = {}; self.ultAnchor = nil
	end
	-- The two sustained ultimate windows close with the move that opened them. Leaving either set
	-- would hand a fighter a permanent reflect or a permanent mark.
	self.reflecting = nil; self.marking = nil
	self.move = nil; self.moveId = nil
	methods.setState(self, if self.onGround then "idle" else "air")
end

-- Counter (Spine Guard) triggered: replace the move with a burst.
function methods.triggerCounter(self, incomingDamage: number)
	local m = self.move
	local c = m.counter
	-- JavaScript's Math.round rounds halves toward +infinity; Luau's math.round rounds them away
	-- from zero. floor(x + 0.5) is the JavaScript behaviour, and damage can be fractional.
	local dmg = math.max(c.minDamage, math.floor(incomingDamage * c.multiplier + 0.5))
	local burst = {
		id = "CounterBurst", label = "Spine Burst", startup = 0, active = c.burstFrames,
		recovery = c.burstRecovery, damage = dmg, base = m.base, growth = m.growth, angle = m.angle,
		heavy = true, kind = "melee", total = c.burstFrames + c.burstRecovery,
		hitboxes = { { frames = { 1, c.burstFrames }, offset = c.hitbox.offset, size = c.hitbox.size } },
	}
	methods.startMove(self, burst)
	if self.mech.id == "Spines" then
		self.mech.spines = self.char.mechanic.max
	end
	methods.emit(self, { type = "counter" })
end

-- ---------------------------------------------------------------- shield ----
function methods._stepShield(self, ctx)
	local inp = self.input
	methods._friction(self)
	self.shield -= SHIELD.drainPerSec * FRAME
	if self.shield <= 0 then methods.breakShield(self); return end
	if self.blockstun > 0 then self.blockstun -= 1; return end
	if methods.consume(self, "jump") then methods.setState(self, "jumpsquat"); return end
	if methods.consume(self, "grab") or methods.consume(self, "light") then methods._startGrab(self); return end
	if methods.consume(self, "dodge") then methods.setState(self, "spotdodge"); return end
	if not inp.guardHeld then methods.setState(self, "shielddrop"); return end
end

function methods.breakShield(self)
	self.shield = SHIELD.resetHp; self.blockstun = 0
	methods.setState(self, "stunned")
	methods.emit(self, { type = "shieldbreak" })
end

function methods.applyBlock(self, o: any)
	local stun = Knockback.blockstun(o.damage)
	self.blockstun = if o.perfect then math.floor(stun / 2) else stun
	if not o.perfect then
		self.shield -= o.damage * SHIELD.damageMul
	end
	self.vx = o.facing * (o.damage / 5) * 10
	if self.shield <= 0 then methods.breakShield(self) end
end

-- ---------------------------------------------------------------- hits ----
-- hit: { damage, launch, stun, angle, facing, attacker, hitlag, extraHitstun, applies, pull, trip }
function methods.applyHit(self, hit: any)
	if self.holder then methods.releaseHold(self.holder) end
	if self.hold then methods.releaseHold(self) end
	self.percent = math.min(999, self.percent + hit.damage)
	self.stats.damageTaken += hit.damage
	self.lastHitBy = hit.attacker or nil
	self.lastHitFrame = self.frameCount
	self.hitlag = hit.hitlag
	if hit.applies then methods._applyEffects(self, hit.applies) end
	local id = self.mech.id
	if id == "Light" then self.mech.segments = math.max(0, self.mech.segments - 1) end
	if id == "Momentum" then self.mech.runFrames = 0; self.mech.ready = false end
	if id == "Brace" then self.mech.guardFrames = 0; self.mech.ready = false end
	-- Surge and Draw are wiped by being hit, the same way Momentum and Brace are: every one of
	-- these mechanics is a reward for pressure, and taking a hit is the opposite of pressure.
	if id == "Surge" then self.mech.hits = {}; self.mech.surged = false end
	if id == "Draw" then self.mech.draw = 0; self.mech.ready = false end
	self.move = nil; self.hold = nil; self.tether = nil; self.la = nil
	if hit.trip and self.percent < hit.trip and self.onGround then
		methods.setState(self, "knockdown")
		self.sf = 6; self.vx = 0
		return
	end
	local launch = hit.launch
	-- How long they cannot act is its own curve - see KNOCKBACK in Config. Everything that scales
	-- the launch scales the stun with it, so water and a frozen victim still change hitstun.
	local stun = if hit.stun ~= nil then hit.stun else hit.launch
	if self.effects.frozenBonus then
		launch *= 1.2; stun *= 1.2
		self.effects.frozenBonus = false
	end
	-- Deep water eats knockback.
	if self.env.damp < 1 then
		launch *= self.env.damp; stun *= self.env.damp
	end
	self.hitstun = Knockback.hitstun(stun) + (hit.extraHitstun or 0)
	if hit.pull then
		local ax = if hit.attackerX ~= nil then hit.attackerX else self.x
		self.x += -hit.facing * math.min(hit.pull, math.abs(self.x - ax))
	end
	-- Two hitboxes can land on the SAME frame. Taking the last one meant the weaker of the pair
	-- decided where the victim went. The bigger hit wins; both still do damage.
	if not (self.pendingLaunch and self.pendingLaunchFrame == self.frameCount
		and self.pendingLaunch.launch >= launch) then
		self.pendingLaunch = { launch = launch, angle = hit.angle, facing = hit.facing }
		self.pendingLaunchFrame = self.frameCount
	end
	if self.hitlag <= 0 then methods._applyLaunch(self) end
	-- Tumble is about whether they are helpless, not how far they go, so it reads the stun curve.
	self.tumbling = stun >= TUMBLE_THRESHOLD
	self.fastFalling = false
	methods.setState(self, "hitstun")
end

function methods._applyEffects(self, applies: any)
	local M = self.effects
	if applies.chill then
		M.chill.stacks = math.min(3, M.chill.stacks + applies.chill)
		M.chill.timer = 300
	end
	if applies.grit then M.grit.hide = 180; M.grit.slow = 120 end
	if applies.tangle then
		M.tangle.stacks = math.min(2, M.tangle.stacks + 1)
		M.tangle.timer = 600
	end
	if applies.slow then M.slow = math.max(M.slow, applies.slow) end
end

function methods._stepHitstun(self)
	self.hitstun -= 1
	if self.hitstun <= 0 then
		methods.setState(self, if self.onGround then "idle" else "air")
	end
end

function methods.launchNoStun(self, vx: number, vy: number)
	self.vy = vy; self.vx += vx; self.onGround = false; self.platform = nil
	local s = self.state
	if s == "idle" or s == "run" or s == "shield" or s == "shielddrop" then
		methods.setState(self, "air")
	end
	methods.emit(self, { type = "vent" })
end

function methods.freeze(self, frames: number)
	self.frozenFrames = frames; self.vx = 0; self.vy = 0; self.move = nil; self.tumbling = false
	methods.setState(self, "frozen")
	self.effects.frozenBonus = true
	methods.emit(self, { type = "frozen" })
end

function methods._stepFrozen(self)
	self.vx = 0; self.vy = 0; self.noGravityFrame = true
	if self.input.anyPress then
		self.frozenFrames = math.max(self.frozenFrames - 2, 0)
	end
	self.frozenFrames -= 1
	if self.frozenFrames <= 0 or self.sf > 40 then
		methods.setState(self, if self.onGround then "idle" else "air")
	end
end

-- ---------------------------------------------------------------- physics ----
function methods._physics(self, ctx)
	local stage = ctx.stage
	local noGravity = NO_GRAVITY_STATES[self.state] or self.noGravityFrame
	-- Environmental forces, applied as accelerations rather than velocity sets, so they compose
	-- with gravity and never yank a fighter out of a trajectory they were reading.
	if self.env.windX ~= 0 and not self.onGround then
		self.carryX += clampEnv(self.env.windX, -ENV_MAX, ENV_MAX) * FRAME
	end
	-- A gust dies the moment you are back on the ground; a rope does not.
	local roped = self.snaredBy > 0
	self.carryX *= if roped then 0.97 else (if self.onGround then 0.80 else 0.97)
	if self.snaredBy > 0 then self.snaredBy -= 1 end
	if self.reeling > 0 then self.reeling -= 1 end
	if math.abs(self.carryX) < 0.05 then self.carryX = 0 end

	if not self.onGround and not noGravity then
		self.vy -= GRAVITY * FRAME
		local term = self.char.fallSpeed * (if self.fastFalling then MOVE.fastFallMul else 1)
		if self.effects.lodestone > 0 and self.effects.lodestoneDef then
			term *= self.effects.lodestoneDef.fallMul
		end
		if self.inWater then term *= 0.5 end
		if self.state == "hitstun" or self.tumbling then term = math.max(term, 80) end
		-- An updraft lowers your terminal fall speed and a downdraft raises it - that is what
		-- terminal velocity IS. Without this, lift below gravity did nothing at all at terminal
		-- speed: the clamp re-ran every frame and ate it.
		if self.env.updraft < 0 then
			term *= 1 + math.min(1.2, -self.env.updraft / GRAVITY)
		elseif self.env.updraft > 0 and self.vy < 0 then
			term *= math.max(0.22, 1 - self.env.updraft / GRAVITY)
		end
		if self.vy < -term then self.vy = -term end
	end
	-- Applied AFTER the clamp, so lift is never silently erased.
	if not self.onGround and self.env.updraft ~= 0 then
		self.vy += clampEnv(self.env.updraft, -ENV_MAX, ENV_MAX) * FRAME
	end
	if self.state == "hitstun" and not self.onGround then self.vx *= LAUNCH_DRAG end
	local s = self.state
	if s == "grabbed" or s == "ledge" or s == "ko" or s == "respawn" then
		return
	end
	local nx = self.x + (self.vx + self.carryX) * FRAME
	local ny = self.y + self.vy * FRAME
	if self.onGround and self.platform then
		nx += self.platform.dx
		ny = self.platform.top
	end
	local res = stage:collide(self, self.x, self.y, nx, ny)
	self.x = res.x; self.y = res.y
	if res.wall then
		if self.tumbling and self.techPress > 0 and math.abs(self.vx) > 20 then
			-- Wall tech: kill the tumble, bounce off with control instead of sliding down the wall.
			self.techPress = 0; self.buffer.guard = 0; self.tumbling = false
			self.hitstun = 0; self.techRoll = 0
			self.vx = -sign(self.vx) * 18
			self.vy = math.max(self.vy, 8)
			methods.setState(self, "tech")
			methods.emit(self, { type = "tech", wall = true })
		elseif self.state == "hitstun" and math.abs(self.vx) > 40 then
			self.vx = -self.vx * 0.5
		else
			self.vx = 0
		end
	end
	if res.bumped then self.vy = 0 end
	if res.landed and not self.onGround then
		methods._land(self, res.landed, ctx)
	elseif res.landed then
		self.platform = res.landed
	end
	if self.onGround and not stage:supported(self) then
		self.onGround = false; self.platform = nil
		local st = self.state
		if st == "idle" or st == "run" or st == "dash" then methods.setState(self, "air") end
		if st == "shield" or st == "shielddrop" then methods.setState(self, "air") end
	end
	local st2 = self.state
	if not self.onGround and (st2 == "air" or st2 == "helpless" or st2 == "recovery") then
		local L = stage:ledgeFor(self, self.buffer.guard > 0)
		if L then
			self.buffer.guard = 0
			methods.grabLedge(self, L)
		end
	end
	if self.state == "holding" and self.hold then methods._positionHeld(self) end
end

function methods._land(self, p: any, ctx: any)
	self.onGround = true; self.platform = p; self.vy = 0
	self.jumpsLeft = self.char.jumps; self.airDodgeUsed = false; self.recoveryUsed = false
	self.ledgeGrabs = 0; self.fastFalling = false; self.dropTimer = 0
	local s = self.state
	methods.emit(self, { type = "land", hard = s == "groundpound" })
	if s == "attack" and self.move and self.move.grounded == false then
		local ended = self.mf > self.startupEff + self.move.active
		self.lag = if ended then 4 else (self.move.landingLag or 8)
		self.move = nil
		methods.setState(self, "landing")
		return
	end
	if s == "attack" then return end -- grounded move keeps going (lunges off/on platforms)
	if s == "groundpound" then
		local shock = GROUND_POUND.shock
		ctx.combat:spawnBurst(self, {
			damage = shock.damage, base = shock.base, growth = shock.growth, angle = shock.angle,
			radius = shock.radius, x = self.x, y = self.y + 1, frames = shock.frames,
			size = { shock.radius * 2, 3 },
		})
		self.lag = GROUND_POUND.landingLag
		methods.setState(self, "landing")
		methods.emit(self, { type = "shock" })
		return
	end
	if s == "hitstun" or (s == "air" and self.tumbling) then
		if self.tumbling then
			if self.techPress > 0 then
				self.techPress = 0; self.buffer.guard = 0; self.tumbling = false
				self.techRoll = if math.abs(self.input.x) > 0.5 then sign(self.input.x) else 0
				methods.setState(self, "tech")
				methods.emit(self, { type = "tech" })
				return
			end
			self.tumbling = false; self.hitstun = 0
			methods.setState(self, "knockdown")
			return
		end
		-- Landing does NOT end hitstun. Zeroing it here let a launched fighter act the instant they
		-- touched ground, which silently cut every ground-to-ground combo short.
		if self.hitstun > 0 then
			self.hitstun = math.ceil(self.hitstun * 0.5)
			self.vx *= 0.5
			methods.setState(self, "hitstun")
			return
		end
		methods.setState(self, "idle")
		return
	end
	if s == "helpless" or s == "recovery" then self.lag = 8; methods.setState(self, "landing"); return end
	if s == "airdodge" then self.lag = 8; methods.setState(self, "landing"); return end
	if s == "frozen" then return end
	methods.setState(self, "idle")
end

function methods._stepTech(self)
	local cfg = if self.techRoll ~= 0 then TECH.roll else TECH.inPlace
	if self.techRoll ~= 0 and self.sf <= 20 then
		self.vx = self.techRoll * (cfg.distance / 20) / FRAME
	else
		methods._friction(self)
	end
	if self.sf > cfg.frames then methods.setState(self, "idle") end
end

-- Config's inv pairs are [start, end]; Luau indexes them 1 and 2 where the JavaScript uses 0 and 1.
function methods.isDodgeInvincible(self): boolean
	local t = self.effects.tangle.stacks
	local s = self.state
	if s == "spotdodge" then
		return self.sf >= SPOT_DODGE.inv[1] and self.sf <= SPOT_DODGE.inv[2] - 3 * t
	end
	if s == "airdodge" then
		return self.sf >= AIR_DODGE.inv[1] and self.sf <= AIR_DODGE.inv[2] - 4 * t
	end
	if s == "tech" then
		local cfg = if self.techRoll ~= 0 then TECH.roll else TECH.inPlace
		return self.sf >= cfg.inv[1] and self.sf <= cfg.inv[2]
	end
	if s == "knockdown" then
		return self.sf <= KNOCKDOWN.getupInv[2]
	end
	if s == "ledgeaction" and self.la then
		local o = LEDGE.options[self.la.kind]
		return self.sf >= o.inv[1] and self.sf <= o.inv[2]
	end
	return false
end

-- ---------------------------------------------------------------- ledge ----
function methods.grabLedge(self, L: any)
	self.ledgeGrabs += 1
	-- JS: LEDGE.invinc[Math.min(this.ledgeGrabs - 1, 2)] on a 0-indexed array.
	local inv = LEDGE.invinc[math.min(self.ledgeGrabs, 3)]
	self.invincible = math.max(self.invincible, inv)
	self.ledge = L
	self.x = L.x + L.side * LEDGE.hangOffsetX
	self.y = L.y + LEDGE.hangOffsetY
	self.facing = -L.side; self.vx = 0; self.vy = 0
	self.onGround = false; self.platform = nil
	self.airDodgeUsed = false; self.recoveryUsed = false; self.fastFalling = false
	self.tumbling = false; self.move = nil
	methods.setState(self, "ledge")
	methods.emit(self, { type = "ledge" })
end

function methods._stepLedge(self, ctx)
	local inp = self.input
	local L = self.ledge
	local toward = inp.x * -L.side
	if self.sf > LEDGE.hangMax then methods._ledgeDrop(self); return end
	if self.sf < 4 then return end
	if methods.consume(self, "jump") or inp.y > 0.5 then
		self.x = L.x - L.side * 1.2
		self.y = L.y + 0.5
		self.vy = self.char.jumpVelocity * methods.jumpMul(self)
		self.vx = -L.side * 6
		self.jumpsLeft = self.char.jumps - 1
		methods.setState(self, "air")
		methods.emit(self, { type = "jump" })
		return
	end
	if inp.y < -0.5 then methods._ledgeDrop(self); return end
	if methods.consume(self, "light") or methods.consume(self, "heavy") then
		methods._startLedgeAction(self, "attack"); return
	end
	if methods.consume(self, "dodge") or methods.consume(self, "guard") then
		methods._startLedgeAction(self, "roll"); return
	end
	if toward > 0.5 then methods._startLedgeAction(self, "getup"); return end
end

function methods._ledgeDrop(self)
	self.y -= 0.5; self.ledgeCooldown = 14
	self.jumpsLeft = self.char.jumps - 1
	self.invincible = 0
	methods.setState(self, "air")
end

function methods._startLedgeAction(self, kind: string)
	self.la = { kind = kind, L = self.ledge }
	self.hitVictims = {}
	methods.setState(self, "ledgeaction")
end

function methods._stepLedgeAction(self, ctx)
	local kind, L = self.la.kind, self.la.L
	local o = LEDGE.options[kind]
	local onFrame = if kind == "roll" then 6 elseif kind == "attack" then 8 else 10
	if self.sf == onFrame then
		self.x = L.x - L.side * 1.6
		self.y = L.y
	end
	if kind == "roll" and self.sf > onFrame and self.sf <= 24 then
		self.x += -L.side * (o.distance - 1.6) / 18
	end
	if self.sf > o.frames then
		self.x = L.x - L.side * o.distance
		self.y = L.y
		self.onGround = true; self.platform = ctx.stage.main
		self.vx = 0; self.vy = 0
		self.la = nil; self.invincible = 0
		methods.setState(self, "idle")
	end
end

-- ---------------------------------------------------------------- grabs ----
function methods._startGrab(self)
	methods.setState(self, "grab")
	methods.emit(self, { type = "grab" })
end

function methods._stepGrab(self, ctx)
	methods._friction(self)
	if self.sf > GRAB.startup and self.sf <= GRAB.startup + GRAB.active then
		ctx.combat:checkGrab(self)
	end
	if self.sf > GRAB.startup + GRAB.active + GRAB.whiffRecovery then
		methods.setState(self, "idle")
	end
end

function methods.startHold(self, victim: any, data: any)
	self.hold = { victim = victim, reel = data.reel or 0, frames = 0,
		throwData = data.throwData or nil, tangle = not not data.tangle, dir = "forward",
		startX = victim.x, startY = victim.y }
	victim.holder = self; victim.move = nil; victim.hold = nil; victim.tumbling = false
	victim.vx = 0; victim.vy = 0
	methods.setState(victim, "grabbed")
	self.vx = 0
	methods.setState(self, "holding")
	methods.emit(self, { type = "grabhit", x = victim.x, y = computed.cy(victim) })
end

function methods.releaseHold(self)
	if not self.hold then
		return
	end
	local v = self.hold.victim
	v.holder = nil
	if v.state == "grabbed" then
		methods.setState(v, "air")
		v.vy = 12; v.vx = self.facing * 8
		v.onGround = false; v.platform = nil
	end
	self.hold = nil
	if self.state == "holding" then
		self.lag = 8
		methods.setState(self, "landing")
	end
end

function methods._positionHeld(self)
	local h = self.hold
	local v = h.victim
	local tx = self.x + self.facing * (self.r + v.r + 0.4)
	local ty = self.y
	if h.reel > 0 then
		local k = 1 / math.max(1, h.reel)
		v.x += (tx - v.x) * k
		v.y += (ty - v.y) * k
		h.reel -= 1
	else
		v.x = tx; v.y = ty
	end
	v.facing = -self.facing; v.onGround = self.onGround; v.vx = 0; v.vy = 0
end

function methods._stepHolding(self, ctx)
	local h = self.hold
	if not h then methods.setState(self, "idle"); return end
	local inp = self.input
	if h.reel > 0 then return end
	h.frames += 1
	if inp.y > 0.5 then h.dir = "up"
	elseif inp.y < -0.5 then h.dir = "down"
	elseif inp.x * self.facing < -0.5 then h.dir = "back"
	elseif math.abs(inp.x) > 0.5 then h.dir = "forward" end
	if h.frames >= GRAB.holdFrames then
		local td = h.throwData or GRAB.throws[h.dir]
		ctx.combat:resolveThrow(self, h.victim, td, h.tangle)
		h.victim.holder = nil
		self.hold = nil
		self.lag = 10
		methods.setState(self, "landing")
	end
end

-- ---------------------------------------------------------------- respawn / ko ----
function methods.knockOut(self)
	self.alive = false
	self.stats.falls += 1
	if self.hold then methods.releaseHold(self) end
	if self.holder then methods.releaseHold(self.holder) end
	methods.setState(self, "ko")
end

function methods.respawn(self, x: number, opts: any?)
	local o = opts or {}
	self.alive = true
	methods.reset(self, x, RESPAWN.height,
		{ state = "respawn", percent = o.percent or 0, invincible = RESPAWN.invinc })
	self.facing = if x < 0 then 1 else -1
end

function methods._stepRespawn(self)
	self.vx = 0; self.vy = 0; self.noGravityFrame = true
	if self.sf > 12 and (self.input.anyPress or math.abs(self.input.x) > 0.5 or self.sf > 180) then
		self.invincible = math.max(self.invincible, 60)
		methods.setState(self, "air")
	end
end

-- ---------------------------------------------------------------- mechanics ----
function methods._mechanicsFrame(self, ctx)
	local M = self.char.mechanic
	local m = self.mech
	if not M then
		return
	end
	if m.id == "Bloom" then
		local now = self.frameCount
		local kept = {}
		for _, t in m.hits do
			if now - t <= M.windowFrames then table.insert(kept, t) end
		end
		m.hits = kept
		if m.cooldown > 0 then m.cooldown -= 1 end
		if m.bloomed then
			m.timer -= 1
			if m.timer <= 0 then m.bloomed = false; m.cooldown = M.cooldownFrames end
		end
		if not m.bloomed and m.cooldown == 0 and #m.hits >= M.hitsRequired then
			m.bloomed = true; m.timer = M.durationFrames; m.hits = {}
			methods.emit(self, { type = "bloom" })
		end
	elseif m.id == "Light" then
		if self.state == "idle" and self.onGround and math.abs(self.vx) < 0.5 then
			m.still += 1
			if m.still >= M.fillFrames then
				m.still = 0
				if m.segments < M.segments then
					m.segments += 1
					methods.emit(self, { type = "light" })
				end
			end
		else
			m.still = 0
		end
	elseif m.id == "Spines" then
		if m.spines < M.max then
			m.regen += 1
			if m.regen >= M.regenFrames then m.regen = 0; m.spines += 1 end
		end
	elseif m.id == "Momentum" then
		if self.state == "run" then
			m.runFrames += 1
		elseif self.state ~= "dash" and self.state ~= "jumpsquat" and self.state ~= "air" then
			m.runFrames = 0
		end
		if not m.ready and m.runFrames >= M.runFrames then
			m.ready = true
			methods.emit(self, { type = "momentumready" })
		end
	elseif m.id == "Surge" then
		-- SURGE, shared by the Gauntlets (Overdrive) and the Daggers (Bloodrush). Consecutive
		-- CONNECTED hits inside a window bank it; while banked, startup is cut and the next heavy
		-- spends the damage bonus.
		local now = self.frameCount
		local kept = {}
		for _, t in (m.hits or {}) do
			if now - t <= M.windowFrames then table.insert(kept, t) end
		end
		m.hits = kept
		if m.surged then
			m.timer -= 1
			if m.timer <= 0 then m.surged = false; m.hits = {} end
		end
		if not m.surged and #m.hits >= M.hitsRequired then
			m.surged = true; m.timer = M.durationFrames
			methods.emit(self, { type = "momentumready" })
		end
	elseif m.id == "Draw" then
		-- DRAW is banked by HOLDING heavy, grounded and near-still. You cannot kite and draw.
		if self.input.heavyHeld and self.onGround and math.abs(self.vx) < 2 then
			m.draw = math.min(M.drawFrames, (m.draw or 0) + 1)
		else
			m.draw = math.max(0, (m.draw or 0) - 3)
		end
		local was = m.ready
		m.ready = m.draw >= M.drawFrames
		if m.ready and not was then methods.emit(self, { type = "momentumready" }) end
	elseif m.id == "Snare" then
		-- SNARE holds whoever the chain is attached to and reels one of you toward the other
		-- depending on which way the stick is held.
		if m.snared then
			local v = m.snared
			local gone = (not v.alive) or v.state == "ko" or v.state == "respawn"
				or math.abs(v.x - self.x) > M.range * 1.6
			m.timer -= 1
			if gone or m.timer <= 0 then
				m.snared = nil; m.timer = 0
			else
				-- THE PULL RIDES `carryX`, NOT `vx`. Written to vx it was a complete no-op in both
				-- directions: _groundMove and _friction rewrite vx from the stick every frame.
				local toward = if v.x - self.x < 0 then -1 elseif v.x - self.x > 0 then 1 else 1
				local pull = M.pullSpeed * FRAME
				if self.input.x * toward > 0.4 then
					self.carryX += toward * pull
					self.snaredBy = 2
				elseif self.input.x * toward < -0.4 then
					v.carryX -= toward * pull * 1.2
					v.snaredBy = 2
					-- Reeling them in and running away are the same stick direction, so without
					-- this the pull and your own run cancel.
					self.reeling = 3
				end
			end
		end
		m.ready = m.snared ~= nil
	elseif m.id == "Brace" then
		-- Banked only while actually holding shield, and dropped the moment the shield does.
		if self.state == "shield" then
			m.guardFrames += 1
		elseif self.state ~= "shielddrop" then
			m.guardFrames = 0
		end
		if not m.ready and m.guardFrames >= M.guardFrames then
			m.ready = true
			methods.emit(self, { type = "momentumready" })
		end
	end
end

-- ---------------------------------------------------------------- snapshot ----
-- Save and restore the whole simulation state of one fighter.
--
-- This exists for client-side prediction: predict forward from the last authoritative frame, and
-- when the server's version of that frame arrives, restore and re-simulate. Retrofitting it into a
-- finished state machine is a rewrite - every field you forget is a desync that only shows up
-- under packet loss - so the list below is exhaustive and the parity test proves it, by snapshotting
-- mid-trace, running on, restoring, and replaying the same inputs against the same expected frames.
--
-- Fighter-OWNED state is copied. Externally-owned objects (the platform, the ledge, a move table,
-- another fighter) are kept BY REFERENCE, deliberately: a platform's own position is the stage's to
-- roll back, move tables are read-only, and a fighter reference must still point at that fighter.

local SCALARS = {
	"x", "y", "prevX", "prevY", "vx", "vy", "facing", "state", "sf", "onGround",
	"jumpsLeft", "airDodgeUsed", "recoveryUsed", "ledgeGrabs", "fastFalling", "dropTimer",
	"ledgeCooldown", "shield", "blockstun", "hitstun", "hitlag", "tumbling", "invincible",
	"moveId", "mf", "startupEff", "startupShift", "moveLanded", "charge", "percent", "carryX",
	"snaredBy", "reeling", "techPress", "techRoll", "ultCharge", "ultActive", "ultShots",
	"ultCooldown", "ultEndAt", "ultEscape", "frozenFrames", "lag", "alive", "stocks", "spawnedActive",
	"armorUsed", "bonusDamage", "launchMul", "rangeMul", "noGravityFrame", "frameCount",
	"volleyCount", "inWater", "lastHitFrame", "skin", "team", "index", "r", "h", "weight",
	"pendingLaunchFrame",
	-- Identity rather than simulation state: these never change during a match, so restoring them
	-- is a no-op. They are here because a snapshot that cannot rebuild the whole fighter is a
	-- snapshot somebody will eventually use for something else and be wrong about.
	"name", "source", "isBot", "botLevel",
	-- Written onto the fighter by Match rather than by Fighter itself, but they are simulation
	-- state all the same: a rollback that forgot koTimer would respawn somebody at the wrong frame.
	"koTimer", "eliminatedAt",
}
-- Kept by reference; see above.
local REFS = { "platform", "ledge", "move", "holder", "lastHitBy", "char", "reflecting", "marking",
	"ultTarget", "ultAnchor", "chargeMods", "item",
	-- The match this fighter belongs to. A reference, never copied.
	"_match" }

local function shallow(t: any): any
	return if t == nil then nil else table.clone(t)
end

function methods.snapshot(self): any
	local s: any = {}
	for _, k in SCALARS do
		s[k] = self[k]
	end
	for _, k in REFS do
		s[k] = self[k]
	end
	s.buffer = table.clone(self.buffer)
	s.di = table.clone(self.di)
	s.env = table.clone(self.env)
	s.input = table.clone(self.input)
	s.stats = table.clone(self.stats)
	s.hitVictims = table.clone(self.hitVictims)
	s.ultHeld = table.clone(self.ultHeld)
	s.pendingLaunch = shallow(self.pendingLaunch)
	s.hold = shallow(self.hold)          -- carries a victim REFERENCE, which stays a reference
	s.la = shallow(self.la)
	s.tether = shallow(self.tether)
	s.events = table.clone(self.events)
	local e = self.effects
	s.effects = {
		chill = table.clone(e.chill), tangle = table.clone(e.tangle), grit = table.clone(e.grit),
		slow = e.slow, frozenBonus = e.frozenBonus, lodestone = e.lodestone,
		lodestoneDef = e.lodestoneDef, bleed = e.bleed,
	}
	-- The bot's own scratch state. Fighter-owned, written by Ai, and a rollback that dropped it
	-- would hand the bot a fresh plan and a cleared chain mid-decision.
	if self.ai then
		s.ai = table.clone(self.ai)
		if self.ai.chain then
			s.ai.chain = table.clone(self.ai.chain)
		end
	end
	s.mech = table.clone(self.mech)
	-- mech.hits is a list of frame numbers and is the one nested table in there
	if self.mech.hits then
		s.mech.hits = table.clone(self.mech.hits)
	end
	return s
end

function methods.restore(self, s: any)
	for _, k in SCALARS do
		self[k] = s[k]
	end
	for _, k in REFS do
		self[k] = s[k]
	end
	self.buffer = table.clone(s.buffer)
	self.di = table.clone(s.di)
	self.env = table.clone(s.env)
	self.input = table.clone(s.input)
	self.stats = table.clone(s.stats)
	self.hitVictims = table.clone(s.hitVictims)
	self.ultHeld = table.clone(s.ultHeld)
	self.pendingLaunch = shallow(s.pendingLaunch)
	self.hold = shallow(s.hold)
	self.la = shallow(s.la)
	self.tether = shallow(s.tether)
	self.events = table.clone(s.events)
	local e = s.effects
	self.effects = {
		chill = table.clone(e.chill), tangle = table.clone(e.tangle), grit = table.clone(e.grit),
		slow = e.slow, frozenBonus = e.frozenBonus, lodestone = e.lodestone,
		lodestoneDef = e.lodestoneDef, bleed = e.bleed,
	}
	if s.ai then
		self.ai = table.clone(s.ai)
		if s.ai.chain then
			self.ai.chain = table.clone(s.ai.chain)
		end
	else
		self.ai = nil
	end
	self.mech = table.clone(s.mech)
	if s.mech.hits then
		self.mech.hits = table.clone(s.mech.hits)
	end
end

Fighter.methods = methods
Fighter.computed = computed
Fighter.meta = meta

return Fighter
