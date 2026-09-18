--!nonstrict
-- Hit resolution: the half of the engine that decides what a connection means.
-- Ported from web/src/engine/combat.js.
--
-- PHASE 3a. Projectiles, summons and items are not here yet. Rather than let those paths quietly do
-- nothing - which is how this project keeps growing authored-but-unreachable data - every unported
-- branch calls `later()`, which throws and names what is missing. A move that needs a projectile is
-- therefore loudly unfinished rather than subtly broken.
--
-- What IS here is everything that needs no projectile and no summon: the hitbox scan, resolveHit
-- with all six of its pre-emption branches (reflect, bulwark, counter, armour, shield, command
-- grab), throws, grabs, hazard hits, bursts, and seven of the twelve ultimates.

local Config = require(script.Parent.Config)
local Knockback = require(script.Parent.Knockback)

local FRAME = Config.FRAME
local SHIELD = Config.SHIELD
local GRAB = Config.GRAB
local GROUND_POUND = Config.GROUND_POUND
local LEDGE = Config.LEDGE

local function hypot(x: number, y: number): number
	return math.sqrt(x * x + y * y)
end
local function overlap(a: any, b: any): boolean
	return a.x1 < b.x2 and a.x2 > b.x1 and a.y1 < b.y2 and a.y2 > b.y1
end
local function rectFrom(cx: number, cy: number, w: number, h: number): any
	return { x1 = cx - w / 2, x2 = cx + w / 2, y1 = cy - h / 2, y2 = cy + h / 2, cx = cx, cy = cy, w = w, h = h }
end
local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end
local function sign(v: number): number
	return if v < 0 then -1 else 1
end
-- JavaScript's Math.round: halves go toward +infinity, where math.round sends them away from zero.
local function jsRound(v: number): number
	return math.floor(v + 0.5)
end

local function later(what: string): ()
	error(`Combat: {what} is not ported yet (Phase 3b/3c/3d). It is erroring rather than doing `
		.. `nothing, so the gap cannot be mistaken for working code.`)
end

-- Moves the engine owns rather than the weapon data.
local DIVE_MOVE, LEDGE_ATTACK
do
	local d = GROUND_POUND.dive
	DIVE_MOVE = { id = "GroundPound", label = "Ground Pound", damage = d.damage, base = d.base,
		growth = d.growth, angle = d.angle, heavy = true, kind = "melee",
		hitboxes = { { frames = { 1, 999 }, offset = d.hitbox.offset, size = d.hitbox.size } } }
	local a = LEDGE.options.attack
	LEDGE_ATTACK = { id = "LedgeAttack", label = "Ledge Attack", damage = a.damage, base = a.base,
		growth = a.growth, angle = a.angle, kind = "melee", hitboxes = { a.hitbox } }
end

local Combat = {}

-- `fighters` and `stage` are GETTERS in combat.js, and Fighter reads `ctx.combat.fighters`
-- directly. Defining them as methods here meant Fighter iterated the function itself and called it
-- with no self - so they are computed through __index instead, exactly as Fighter's own getters are,
-- and every call site stays identical to the JavaScript.
local combatMeta = {}
combatMeta.__index = function(self, key)
	if key == "fighters" then
		return self.match.fighters
	elseif key == "stage" then
		return self.match.stage
	end
	return Combat[key]
end

function Combat.new(match: any): any
	local self = setmetatable({}, combatMeta)
	self.match = match
	self.projectiles = {}
	self.summons = {}
	self.bursts = {}
	self.items = {}
	self.plates = {}
	self.events = {}
	self.debugBoxes = {}
	self.itemTimer = 0
	return self
end

function Combat.emit(self, e: any)
	table.insert(self.events, e)
end
function Combat.sameTeam(self, a: any, b: any): boolean
	return a.team == b.team
end
function Combat.enemiesOf(self, f: any): { any }
	local out = {}
	for _, v in self.match.fighters do
		if v ~= f and v.alive and not Combat.sameTeam(self, f, v) then
			table.insert(out, v)
		end
	end
	return out
end

-- Nearest living enemy, by straight-line distance. Every ultimate that picks its own victims wants
-- the same answer, and wants it again later if that victim dies mid-move.
function Combat.nearestEnemy(self, f: any, range: number?, exclude: { any }?): any
	local best, bd = nil, if range == nil then math.huge else range
	for _, v in Combat.enemiesOf(self, f) do
		local skip = v.untouchable
		if not skip and exclude then
			for _, e in exclude do
				if e == v then
					skip = true
					break
				end
			end
		end
		if not skip then
			local d = hypot(v.x - f.x, v.cy - f.cy)
			if d <= bd then
				bd = d
				best = v
			end
		end
	end
	return best
end

function Combat.hitboxRect(self, f: any, hb: any): any
	local rm = f.rangeMul or 1
	return rectFrom(f.x + hb.offset[1] * rm * f.facing, f.y + hb.offset[2], hb.size[1] * rm, hb.size[2])
end

function Combat.activeHitboxes(self, f: any): { any }
	local out = {}
	if f.state == "attack" and f.move then
		local fa = f.moveFrameAbs
		for _, hb in f.move.hitboxes do
			if fa >= hb.frames[1] and fa <= hb.frames[2] then
				table.insert(out, { rect = Combat.hitboxRect(self, f, hb), hb = hb, move = f.move })
			end
		end
	elseif f.state == "groundpound" and f.sf > GROUND_POUND.hang then
		local hb = DIVE_MOVE.hitboxes[1]
		table.insert(out, { rect = Combat.hitboxRect(self, f, hb), hb = hb, move = DIVE_MOVE })
	elseif f.state == "ledgeaction" and f.la and f.la.kind == "attack" then
		local hb = LEDGE_ATTACK.hitboxes[1]
		if f.sf >= hb.frames[1] and f.sf <= hb.frames[2] then
			table.insert(out, { rect = Combat.hitboxRect(self, f, hb), hb = hb, move = LEDGE_ATTACK })
		end
	end
	return out
end

function Combat.step(self)
	self.debugBoxes = {}
	for _, f in self.match.fighters do
		-- Hitlag freezes the attacker, frame counter included. Evaluating hitboxes during it would
		-- let one active frame connect over and over.
		if f.alive and f.hitlag <= 0 then
			for _, b in Combat.activeHitboxes(self, f) do
				table.insert(self.debugBoxes, { rect = b.rect, kind = "hit" })
				local frameKey = if f.state == "attack" then f.mf else f.sf
				for _, v in self.match.fighters do
					if v ~= f and v.alive and not Combat.sameTeam(self, f, v)
						and overlap(b.rect, v.hurtbox) then
						local last = f.hitVictims[v.index]
						if last == nil or (b.hb.rehitEvery and frameKey - last >= b.hb.rehitEvery) then
							f.hitVictims[v.index] = frameKey
							Combat.resolveHit(self, f, v, b.move, b.hb, b.rect, {})
						end
					end
				end
				for _, sm in table.clone(self.summons) do
					if sm.destructible and sm.owner ~= f and not Combat.sameTeam(self, sm.owner, f)
						and overlap(b.rect, sm.rect)
						and (if b.hb.damage ~= nil then b.hb.damage else b.move.damage) >= 4 then
						Combat.destroySummon(self, sm)
					end
				end
				-- A live Blast Keg is a target for EVERYONE, including whoever threw it.
				for _, pr in table.clone(self.projectiles) do
					if pr.volatile and not pr.dead and overlap(b.rect, pr.rect) then
						local at = table.find(self.projectiles, pr)
						if at then
							table.remove(self.projectiles, at)
						end
						Combat.explode(self, pr)
					end
				end
			end
		end
	end
	Combat.stepProjectiles(self)
	Combat.stepSummons(self)
	Combat.stepBursts(self)
	if #self.items > 0 then later("stepItems") end
	if #self.plates > 0 then later("stepPlates") end
end

-- ---------------------------------------------------------------- hit resolution ----
function Combat.resolveHit(self, attacker: any, victim: any, move: any, hb: any, rect: any, opts: any): boolean
	if not victim.alive or victim.untouchable then
		return false
	end
	if victim.state == "grabbed" and move.kind == "grab" then
		return false
	end
	local direct = not opts.projectile and not opts.summon
	local damage = (if hb and hb.damage ~= nil then hb.damage else move.damage)
		+ (if direct then (attacker.bonusDamage or 0) else 0)
	local base = if hb and hb.base ~= nil then hb.base else move.base
	local growth = if hb and hb.growth ~= nil then hb.growth else move.growth
	if direct and attacker.chargeMods and attacker.move == move then
		damage += attacker.chargeMods.damage
		base = attacker.chargeMods.base
		growth = attacker.chargeMods.growth
	end
	local cx = if rect then (rect.x1 + rect.x2) / 2 else victim.x
	local cy = if rect then (rect.y1 + rect.y2) / 2 else victim.cy
	local isMelee = direct and move.kind ~= "grab" and not opts.item

	-- AEGIS. A reflect window converts an incoming hit into an outgoing one, aimed back at whoever
	-- threw it. Checked before everything else a victim can be doing, because for these two seconds
	-- it is the only thing they ARE doing. Grabs are reflected too: light + guardHeld is a grab in
	-- this engine, so without that a defender could shield-grab an Aegis all day and take nothing.
	if victim.reflecting and not opts.reflected and not opts.chip and attacker ~= victim then
		local R = victim.reflecting
		local back = math.max(R.min, jsRound(damage * R.mul))
		Combat.spawnBurst(self, victim, { id = "Aegis", x = attacker.x, y = attacker.cy, damage = back,
			base = R.base, growth = R.growth, angle = R.angle, frames = 4,
			size = { R.radius * 2, R.radius * 2 }, heavy = true, hitsOwner = false,
			shieldDamageMul = R.shieldDamageMul })
		if direct then
			attacker.hitlag = Knockback.hitlag(back, true)
		end
		R.absorbed = (R.absorbed or 0) + damage
		Combat.emit(self, { type = "aegis", x = attacker.x, y = attacker.cy, damage = back, victim = attacker.index })
		return true
	end

	-- BULWARK. A carried shield, checked before everything else because it is a property of the
	-- fighter rather than of what they are doing. It only covers the FRONT.
	local bw = if victim.item and victim.item.def.guard and victim.item.hp > 0 then victim.item else nil
	if bw and move.kind ~= "grab" and not opts.chip and not move.unblockable then
		local from = cx - victim.x
		local facingIt = math.abs(from) < 0.2 or sign(from) == victim.facing
		if facingIt then
			local G = bw.def.guard
			bw.hp -= damage
			damage *= G.damageMul
			base *= G.launchMul
			growth *= G.launchMul
			Combat.emit(self, { type = "bulwark", x = cx, y = cy, victim = victim.index, broke = bw.hp <= 0 })
			if bw.hp <= 0 then
				later("removeItem (a Bulwark breaking)")
			end
		end
	end

	-- Counter window
	if victim.state == "attack" and victim.move and victim.move.kind == "counter"
		and victim.moveActive and move.kind ~= "grab" and not opts.chip then
		victim:triggerCounter(damage)
		if direct then
			attacker.hitlag = 8
		end
		Combat.emit(self, { type = "counter", x = victim.x, y = victim.cy })
		return true
	end
	-- Armour (Barrel Roll)
	if victim.state == "attack" and victim.move and victim.move.armor and victim.moveActive
		and not victim.armorUsed and damage < victim.move.armor then
		victim.armorUsed = true
		victim.percent = math.min(999, victim.percent + damage)
		if direct then
			attacker.hitlag = Knockback.hitlag(damage)
			attacker.moveLanded = true
		end
		Combat.emit(self, { type = "armor", x = cx, y = cy })
		return true
	end
	-- Shield
	if victim.state == "shield" and not move.unblockable and move.kind ~= "grab" and not opts.chip then
		local perfect = victim.sf <= SHIELD.perfectFrames
		-- An ultimate costs 20 landed hits and the whole meter. Holding one button should not be a
		-- clean answer, so they chew through a full shield instead.
		local shieldDmg = damage * ((if hb then hb.shieldDamageMul else nil) or move.shieldDamageMul or 1)
		victim:applyBlock({ damage = shieldDmg,
			facing = if opts.facing ~= nil then opts.facing else attacker.facing, perfect = perfect })
		if direct then
			attacker.hitlag = Knockback.hitlag(damage, move.heavy)
			attacker.moveLanded = true
		end
		Combat.emit(self, { type = "block", x = cx, y = cy, perfect = perfect, victim = victim.index })
		return true
	end
	-- Command grab
	if move.kind == "grab" then
		if not victim.onGround then
			return false
		end
		if victim.state == "holding" then
			victim:releaseHold()
		end
		attacker:startHold(victim, { reel = move.reelFrames or 0,
			throwData = { damage = move.damage + (attacker.bonusDamage or 0), base = base,
				growth = growth, angle = move.angle, behind = not not move.behind },
			tangle = attacker.mech.id == "Tangle" })
		return true
	end
	if opts.chip then
		victim.percent = math.min(999, victim.percent + damage)
		victim.stats.damageTaken += damage
		attacker.stats.damageDealt += damage
		Combat.emit(self, { type = "chip", x = cx, y = cy, damage = damage })
		return true
	end

	local angle = if hb and hb.angle ~= nil then hb.angle else move.angle
	local after = victim.percent + damage
	local own = if direct then (attacker.launchMul or 1) else 1
	local launch = Knockback.launchSpeed(base, growth, damage, after, victim.weight) * own
	-- `stun` is the same hit on the hitstun curve; it travels with the launch into applyHit so that
	-- every multiplier below applies to both.
	local stun = Knockback.stunSpeed(base, growth, damage, after, victim.weight) * own
	if opts.fixedLaunch ~= nil then
		launch = opts.fixedLaunch
		stun = opts.fixedLaunch
	end
	-- An ultimate does not just hit harder in the abstract - it multiplies the knockback the victim
	-- would already have taken, so it stays a finisher at 120% instead of flattening into a fixed
	-- launch the way a raw `base` bump would.
	local kbMul = (if hb and hb.knockbackMul ~= nil then hb.knockbackMul else move.knockbackMul) or 1
	launch *= kbMul
	stun *= kbMul
	local facing = if move.behind then -attacker.facing
		else (if opts.facing ~= nil then opts.facing else attacker.facing)
	local hl = Knockback.hitlag(damage, move.heavy)
	if direct then
		attacker.hitlag = hl
		attacker.moveLanded = true
	elseif opts.projectile and attacker.move == move then
		-- A projectile connecting also counts as the move landing, but only while its owner is
		-- still executing the move that fired it.
		attacker.moveLanded = true
	end
	attacker.stats.damageDealt += damage
	victim:applyHit({ damage = damage, launch = launch, stun = stun, angle = angle, facing = facing,
		attacker = attacker, hitlag = if opts.summon then math.min(hl, 4) else hl,
		extraHitstun = move.extraHitstun or 0, applies = move.applies, pull = move.pullVictim,
		attackerX = attacker.x, trip = move.trip })
	if direct and move.onHit then
		if move.onHit.bounce and not attacker.onGround then
			attacker.vy = move.onHit.bounce
			attacker.fastFalling = false
		end
		if move.onHit.regainJump then
			attacker.jumpsLeft = math.max(attacker.jumpsLeft, 1)
		end
		if move.onHit.regainAirDodge then
			attacker.airDodgeUsed = false
		end
	end
	if direct and move.dragVictim and hb and hb.rehitEvery and victim.pendingLaunch then
		victim.pendingLaunch = { vx = attacker.vx * 0.95, vy = 6 }
	end
	Combat.onHitLanded(self, attacker, victim, move, isMelee)
	if victim.item then
		later("dropItem (a fighter losing their item to a big hit)")
	end
	Combat.emit(self, { type = "hit", x = cx, y = cy, damage = damage, launch = launch,
		heavy = not not move.heavy, weight = victim.weight, attacker = attacker.index,
		victim = victim.index, angle = angle, facing = facing })
	return true
end

function Combat.onHitLanded(self, attacker: any, victim: any, move: any, isMelee: boolean)
	-- One landed hit, one point of ultimate charge - regardless of damage, so a fast light string
	-- charges as fast as a signature and pressure is what fills the bar.
	if attacker.chargeUltimate and move.id ~= "Ultimate" then
		attacker:chargeUltimate(1)
	end
	-- A mark, not a launch. While Exsanguinate is live every connection stacks on the victim and
	-- the knockback is held back until the window closes.
	if attacker.marking then
		victim.effects.bleed = math.min(attacker.marking.max, (victim.effects.bleed or 0) + 1)
		Combat.emit(self, { type = "bleedmark", x = victim.x, y = victim.cy,
			marks = victim.effects.bleed, victim = victim.index })
	end
	if attacker.mech.id == "Bloom" then
		table.insert(attacker.mech.hits, attacker.frameCount)
	end
	-- Surge counts the same way Bloom does: only CONNECTED hits, so the counter is a record of
	-- pressure rather than of button presses.
	if attacker.mech.id == "Surge" then
		attacker.mech.hits = attacker.mech.hits or {}
		table.insert(attacker.mech.hits, attacker.frameCount)
	end
	if victim.mech.id == "Spines" and isMelee then
		attacker.percent = math.min(999, attacker.percent + victim.char.mechanic.recoil)
		Combat.emit(self, { type = "recoil", x = attacker.x, y = attacker.cy })
	end
end

function Combat.resolveThrow(self, attacker: any, victim: any, td: any, tangle: boolean?)
	local damage = td.damage + (attacker.bonusDamage or 0)
	local facing = attacker.facing
	if td.behind then
		facing = -attacker.facing
		if not td.keepFacing and not attacker.move then
			attacker.facing = facing
		end
	end
	victim.x = attacker.x + facing * (attacker.r + victim.r + 0.5)
	victim.y = attacker.y + 0.3
	victim.holder = nil
	local mul = attacker.launchMul or 1
	local after = victim.percent + damage
	local launch = Knockback.launchSpeed(td.base, td.growth, damage, after, victim.weight) * mul
	local stun = Knockback.stunSpeed(td.base, td.growth, damage, after, victim.weight) * mul
	victim.onGround = false
	victim.platform = nil
	victim:applyHit({ damage = damage, launch = launch, stun = stun, angle = td.angle,
		facing = facing, attacker = attacker, hitlag = Knockback.hitlag(damage, true) })
	victim.hitlag = 2
	if tangle then
		victim:_applyEffects({ tangle = 1 })
	end
	attacker.stats.damageDealt += damage
	Combat.emit(self, { type = "hit", x = victim.x, y = victim.cy, damage = damage, launch = launch,
		heavy = true, weight = victim.weight, attacker = attacker.index, victim = victim.index,
		angle = td.angle, facing = facing, throw = true })
end

local UNGRABBABLE = { grabbed = true, holding = true, ko = true, respawn = true, ledge = true }
-- You can only catch a thrown explosive out of a state you could catch anything from.
local CATCHABLE_STATES = { air = true, idle = true, run = true }

function Combat.checkGrab(self, f: any)
	local rect = Combat.hitboxRect(self, f, GRAB.hitbox)
	table.insert(self.debugBoxes, { rect = rect, kind = "grab" })
	for _, v in self.match.fighters do
		if v ~= f and v.alive and not Combat.sameTeam(self, f, v) and v.onGround and not v.untouchable
			and not UNGRABBABLE[v.state] and overlap(rect, v.hurtbox) then
			if v.hold then
				v:releaseHold()
			end
			f:startHold(v, { tangle = f.mech.id == "Tangle" })
			return
		end
	end
end

function Combat.hazardHit(self, f: any, p: any)
	if f.untouchable then
		return
	end
	local d = f.x - p.x
	local facing = sign(if d ~= 0 then d else 1)
	f:applyHit({ damage = p.damage, launch = p.launch, angle = p.angle, facing = facing,
		attacker = nil, hitlag = 6 })
	Combat.emit(self, { type = "hit", x = f.x, y = f.cy, damage = p.damage, launch = p.launch,
		heavy = false, weight = f.weight, attacker = -1, victim = f.index, angle = p.angle, facing = facing })
end

-- ---------------------------------------------------------------- bursts ----
function Combat.spawnBurst(self, owner: any, b: any): any
	local burst = {
		owner = owner, x = b.x, y = b.y, frames = b.frames or 3,
		move = { id = b.id or "Burst", damage = b.damage, base = b.base, growth = b.growth,
			angle = b.angle, heavy = not not b.heavy, kind = "melee", applies = b.applies,
			knockbackMul = b.knockbackMul, shieldDamageMul = b.shieldDamageMul,
			unblockable = b.unblockable },
		hitVictims = {}, rect = rectFrom(b.x, b.y, b.size[1], b.size[2]),
		hitsOwner = not not b.hitsOwner,
	}
	table.insert(self.bursts, burst)
	return burst
end

function Combat.stepBursts(self)
	for i = #self.bursts, 1, -1 do
		local b = self.bursts[i]
		table.insert(self.debugBoxes, { rect = b.rect, kind = "burst" })
		for _, v in self.match.fighters do
			if v.alive and not b.hitVictims[v.index]
				and not (v == b.owner and not b.hitsOwner)
				and not (v ~= b.owner and Combat.sameTeam(self, b.owner, v))
				and overlap(b.rect, v.hurtbox) then
				b.hitVictims[v.index] = true
				local d = v.x - b.x
				Combat.resolveHit(self, b.owner, v, b.move, nil, b.rect,
					{ summon = true, facing = sign(if d ~= 0 then d else b.owner.facing) })
			end
		end
		for _, sm in table.clone(self.summons) do
			if sm.destructible and sm.owner ~= b.owner and overlap(b.rect, sm.rect) then
				Combat.destroySummon(self, sm)
			end
		end
		b.frames -= 1
		if b.frames <= 0 then
			table.remove(self.bursts, i)
		end
	end
end

function Combat.surfaceUnder(self, x: number, yMax: number): any
	local best = nil
	for _, p in self.match.stage.platforms do
		if not (x < p.x1 or x > p.x2 or p.top > yMax + 0.5) then
			if best == nil or p.top > best.top then
				best = p
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------- move triggers ----
-- Fighter calls both of these every frame of every attack. In Phase 3a only a plain melee swing is
-- supported; every kind that needs a projectile, a summon or one of the twelve ultimate branches
-- refuses by name. `counter` has no trigger of its own - it resolves inside resolveHit - so it
-- falls through here exactly as it does in the JavaScript.
-- `pulse` is the only trigger kind left unported: it fires a burst at each of the caster's NODES,
-- and no weapon in the roster spawns nodes. See spawnSummon.
local ACTIVE_KINDS = { pulse = true }
local FRAME_KINDS = {}

function Combat.onMoveActive(self, f: any, m: any)
	if m.kind == "beam" and m.charge then
		local k = math.min(1, f.charge / m.charge.maxHold)
		local function lerp(a: number, b: number): number
			return a + (b - a) * k
		end
		f.chargeMods = { damage = jsRound(lerp(m.damage, m.charge.damage)) - m.damage,
			base = lerp(m.base, m.charge.base), growth = lerp(m.growth, m.charge.growth) }
		Combat.emit(self, { type = "beam", x = f.x, y = f.y + 3.6, facing = f.facing, charge = k,
			frames = m.active })
		return
	end
	f.chargeMods = nil
	if m.kind == "projectile" then
		Combat.spawnProjectile(self, f, m, {})
		return
	end
	if m.kind == "summon" then
		Combat.spawnSummon(self, f, m)
		return
	end
	-- The sniper stance is the one ultimate that is not a single committed swing: it paints a
	-- target and waits for the player to pull the trigger, so the target is chosen the moment the
	-- stance opens rather than the moment a bullet leaves.
	if m.kind == "sniper" then
		f.ultTarget = Combat.nearestEnemy(self, f, m.sniper.range)
		f.ultShots = m.sniper.shots
		f.ultCooldown = 0
		f.ultEndAt = 0
		Combat.emit(self, { type = "mark", x = f.x, y = f.cy,
			victim = if f.ultTarget then f.ultTarget.index else -1 })
		return
	end
	if m.kind == "burst" then
		Combat.emit(self, { type = "burst", x = f.x, y = f.y + 3, radius = 7, frames = m.active })
		return
	end
	-- Exsanguinate opens its marking window the moment it becomes active; the `bleed` branch in
	-- onMoveActiveFrame collects on the last frame.
	if m.kind == "bleed" then
		f.marking = { max = m.bleed.maxMarks }
		return
	end
	if m.kind == "freeze" then
		local M = f.char.mechanic
		for _, v in Combat.enemiesOf(self, f) do
			if not v.untouchable and v.effects.chill.stacks >= 3
				and hypot(v.x - f.x, v.cy - f.cy) <= m.freeze.range then
				v.percent = math.min(999, v.percent + m.damage)
				v.stats.damageTaken += m.damage
				f.stats.damageDealt += m.damage
				v.effects.chill.stacks = 0
				v:freeze(M.freezeFrames)
				f.moveLanded = true
				Combat.emit(self, { type = "freeze", x = v.x, y = v.cy, victim = v.index })
				break
			end
		end
		return
	end
	if ACTIVE_KINDS[m.kind] then
		later(`onMoveActive for kind "{m.kind}"`)
	end
end

function Combat.onMoveActiveFrame(self, f: any, m: any)
	if m.kind == "volley" then
		local p = m.projectile
		local k = f.mf - f.startupEff - 1
		if k % p.every == 0 and f.volleyCount < p.count and f.mech.spines > 0 then
			f.mech.spines -= 1
			f.volleyCount += 1
			Combat.spawnProjectile(self, f, m, { yJitter = (f.volleyCount - 3) * (p.spread or 0.35) })
		end
		return
	end
	local k = f.mf - f.startupEff - 1

	if m.kind == "slam" then
		-- COLOSSUS. The blade's own hitbox is authored in the move; what happens HERE is the
		-- impact: a crater that walks outward along the ground in both directions, so the kill zone
		-- is the floor around the landing point and not just the arc of the swing.
		local C = m.crater
		if k < C.frame or (k - C.frame) % C.every ~= 0 then
			return
		end
		local step = math.floor((k - C.frame) / C.every)
		if step >= C.count then
			return
		end
		local surf = Combat.surfaceUnder(self, f.x, f.y + 1.5)
		local y = (if surf then surf.top else f.y) + 1.0
		local fade = 1 - step / C.count             -- the shockwave loses bite as it travels
		for _, dir in { -1, 1 } do
			if not (step == 0 and dir == -1) then  -- one crater at the centre, not two
				local x = f.x + dir * C.step * step
				Combat.spawnBurst(self, f, { id = "Crater", x = x, y = y,
					-- `C.minDamage or 1`: without the fallback a crater that omits the optional
					-- floor computed max(nil, n), wrote a bad number into the victim's percent, and
					-- corrupted the match silently.
					damage = if step == 0 then C.damage
						else math.max(C.minDamage or 1, jsRound(C.damage * fade)),
					base = C.base, growth = C.growth, frames = 4, knockbackMul = C.knockbackMul,
					shieldDamageMul = C.shieldDamageMul,
					-- The epicentre throws along the BLADE's angle, the outward steps pop upward.
					angle = if step == 0 then (if C.centreAngle ~= nil then C.centreAngle else C.angle)
						else C.angle,
					size = { C.radius * 2, C.radius * (if step == 0 then 3.0 else 2.2) }, heavy = true })
				Combat.emit(self, { type = "crater", x = x, y = y,
					radius = C.radius * (if step == 0 then 1.5 else 1), first = step == 0 })
			end
		end

	elseif m.kind == "vortex" then
		-- SOUL HARVEST. Reach out, take hold of the two closest fighters, drag them into one point,
		-- and detonate it. The pull is the move: the damage is trivial until the ball closes.
		local V = m.vortex
		local ox, oy = f.x + f.facing * V.orbOffset[1], f.y + V.orbOffset[2]
		if k == 0 then
			f.ultHeld = {}
			for _ = 1, V.targets do
				local v = Combat.nearestEnemy(self, f, V.range, f.ultHeld)
				if not v then
					break
				end
				table.insert(f.ultHeld, v)
			end
			if #f.ultHeld > 0 then
				local idx = {}
				for _, v in f.ultHeld do
					table.insert(idx, v.index)
				end
				Combat.emit(self, { type = "soulgrab", x = ox, y = oy, victims = idx })
			end
			-- The Chain Flail's Snare is the same reach-and-hold, except it does not crush: it
			-- ATTACHES, and hands the pull to the mechanic.
			if f.mech.id == "Snare" and #f.ultHeld > 0 then
				f.mech.snared = f.ultHeld[1]
				f.mech.timer = f.char.mechanic.holdFrames
				Combat.emit(self, { type = "snare", x = ox, y = oy, victim = f.ultHeld[1].index })
			end
		end
		local held = f.ultHeld or {}
		if k < V.holdFrames then
			for i = #held, 1, -1 do
				local v = held[i]
				-- A dodge started AFTER the grab used to be cancelled by the forced hitstun state,
				-- so no timing beat this. Invincibility frees you.
				if not v.alive or v.untouchable then
					table.remove(held, i)
					if v.alive then
						Combat.emit(self, { type = "soulescape", x = v.x, y = v.cy, victim = v.index })
					end
				else
					-- Mashing buys distance back. Twenty-two frames with no agency at all, ending
					-- in a kill, is not a thing a fighting game should contain.
					if v.buffer.jump > 0 or v.buffer.dodge > 0 or v.buffer.light > 0 then
						v.ultEscape = math.min(V.escapeCap, (v.ultEscape or 0) + V.escapePerPress)
						v.buffer.jump = 0; v.buffer.dodge = 0; v.buffer.light = 0
					end
					-- Hard drag, but the victim's stick still bends where in the ball they end up.
					local dx, dy = ox - v.x, oy - v.cy
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					-- Enough mashing turns the pull negative and the victim drifts back out.
					local rate = (V.pullSpeed - (v.ultEscape or 0) * V.escapeBite) * FRAME
					local stepLen = if rate >= 0 then math.min(d, rate) else rate
					v.x += (dx / d) * stepLen + v.input.x * V.diPerFrame
					v.y += (dy / d) * stepLen + v.input.y * V.diPerFrame
					v.vx = 0; v.vy = 0; v.onGround = false; v.platform = nil
					v.hitstun = math.max(v.hitstun, 3)
					if v.state ~= "hitstun" then
						v:setState("hitstun")
					end
					f.moveLanded = true
					-- Only a victim who has fought their way out is released: the check cannot fire
					-- on frame one, when everyone the scythe reached for is still standing where
					-- the grab found them and is legitimately outside the ball.
					if (v.ultEscape or 0) > 0 and hypot(ox - v.x, oy - v.cy) > V.burst.radius * 1.6 then
						table.remove(held, i)
						v.ultEscape = 0
						Combat.emit(self, { type = "soulescape", x = v.x, y = v.cy, victim = v.index })
					end
				end
			end
			Combat.emit(self, { type = "soulorb", x = ox, y = oy, k = k / V.holdFrames, held = #held })
		elseif k == V.holdFrames then
			local B = V.burst
			Combat.spawnBurst(self, f, { id = "Ultimate", x = ox, y = oy, damage = B.damage,
				base = B.base, growth = B.growth, angle = B.angle, frames = 4,
				size = { B.radius * 2, B.radius * 2 }, heavy = true,
				knockbackMul = B.knockbackMul, shieldDamageMul = B.shieldDamageMul })
			Combat.emit(self, { type = "soulburst", x = ox, y = oy, radius = B.radius })
			f.ultHeld = {}
		end

	elseif m.kind == "sniper" then
		-- DEADEYE. One bullet per trigger pull, three in the magazine. The stance holds until the
		-- player spends them, which is why this reads the input buffer directly.
		local S = m.sniper
		if not f.ultTarget or not f.ultTarget.alive then
			f.ultTarget = Combat.nearestEnemy(self, f, S.range)
		end
		if f.ultTarget then
			f.facing = sign(f.ultTarget.x - f.x)
		end
		if f.ultCooldown > 0 then
			f.ultCooldown -= 1
		end
		if f.ultEndAt ~= 0 then
			if f.mf >= f.ultEndAt then
				f.mf = f.startupEff + m.active
			end
			return
		end
		if f.buffer.ult > 0 and f.ultShots > 0 and f.ultCooldown <= 0 then
			f.buffer.ult = 0
			f.ultShots -= 1
			f.ultCooldown = S.reload
			local P = S.projectile
			local pr: any = {
				owner = f, move = m, x = f.x + P.spawnOffset[1] * f.facing, y = f.y + P.spawnOffset[2],
				vx = f.facing * P.speed, vy = 0, w = P.size[1], h = P.size[2], life = P.lifetime,
				shape = "tracer", grounded = false, gravity = 0, hitVictims = {}, facing = f.facing,
				item = false,
				ghost = true,                          -- a painted target is not saved by cover
				-- Only the LAST round in the magazine launches. Three equal rounds killed from 25%.
				knockbackMul = if f.ultShots == 0 then m.knockbackMul
					else (if S.setupMul ~= nil then S.setupMul else 1) * m.knockbackMul,
				homing = { target = f.ultTarget, turn = P.turn, speed = P.speed,
					expireAfter = P.expireAfter, dropOnHitstun = true },
			}
			pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h)
			table.insert(self.projectiles, pr)
			Combat.emit(self, { type = "snipe", x = pr.x, y = pr.y, facing = f.facing, shotsLeft = f.ultShots })
			if f.ultShots <= 0 then
				f.ultEndAt = f.mf + S.holdAfterLast
			end
		end

	elseif m.kind == "starfall" then
		-- ASTRAL RAIN. Two orbs for everyone, aimed at where each enemy IS.
		local S = m.starfall
		if k % S.every ~= 0 then
			return
		end
		local wave = k / S.every
		if wave >= S.perTarget then
			return
		end
		for _, v in Combat.enemiesOf(self, f) do
			if not v.untouchable then
				local jitter = (self.match.stage.rng() - 0.5) * S.jitter
					+ (if wave ~= 0 then v.vx * 0.18 else 0)
				local pr: any = {
					owner = f, move = m, x = v.x + jitter, y = v.cy + S.height,
					vx = 0, vy = -S.speed, w = S.size, h = S.size, life = 200, shape = "orb",
					grounded = false, gravity = 0, hitVictims = {}, facing = 1, item = false,
					falling = true,
					homing = { target = v, turn = S.turn, speed = S.speed, axis = "x" },
					explode = { id = "Ultimate", damage = S.damage, base = S.base, growth = S.growth,
						angle = S.angle, radius = S.radius, knockbackMul = S.knockbackMul,
						shieldDamageMul = S.shieldDamageMul,
						-- The first wave is the shield check; the second punishes you for still
						-- being in it. Two blockable orbs left a full shield at 16/50.
						unblockable = wave > 0, hitsOwner = false, fx = "star" },
				}
				pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h)
				table.insert(self.projectiles, pr)
				Combat.emit(self, { type = "starfall", x = pr.x, y = pr.y, target = v.index })
			end
		end

	elseif m.kind == "rundown" then
		-- RUNDOWN. The ultimate does not happen where you are standing: it PURSUES. Nothing else in
		-- the game moves the ATTACKER to the target.
		local R = m.rundown
		if k % R.every ~= 0 then
			return
		end
		local step = math.floor(k / R.every)
		if step >= R.count then
			return
		end
		local target = Combat.nearestEnemy(self, f, R.range)
		if not target then
			return
		end
		local side = sign(f.x - target.x)
		f.x = target.x + side * R.standoff
		f.y = target.y
		f.facing = -side
		f.vx = 0; f.vy = 0
		f.onGround = target.onGround
		f.platform = target.platform
		Combat.spawnBurst(self, f, { id = "Rundown", x = target.x, y = target.cy, damage = R.damage,
			base = R.base, growth = R.growth, angle = R.angle, frames = 3,
			size = { R.radius * 2, R.radius * 2 }, heavy = true, hitsOwner = false,
			knockbackMul = if step == R.count - 1 then R.finalMul else 1,
			shieldDamageMul = R.shieldDamageMul })
		Combat.emit(self, { type = "rundown", x = target.x, y = target.cy, step = step,
			last = step == R.count - 1, victim = target.index })

	elseif m.kind == "upheaval" then
		-- UPHEAVAL. The floor attacks, and it attacks where THEY are standing. NOT filtered to
		-- grounded fighters: the first version was, and the move countered itself.
		local U = m.upheaval
		if k % U.every ~= 0 then
			return
		end
		local step = math.floor(k / U.every)
		if step >= U.count then
			return
		end
		local targets = Combat.enemiesOf(self, f)
		local v = targets[(step % math.max(1, #targets)) + 1]
		if not v then
			return
		end
		local surf = Combat.surfaceUnder(self, v.x, v.y + 1.5)
		local y = (if surf then surf.top else v.y) + 1.0
		-- The last column is the finisher, the same way Rundown's sixth punch is. Without it this
		-- was the only ultimate in the game that could not KO at any percent up to 400.
		local last = step == U.count - 1
		Combat.spawnBurst(self, f, { id = "Upheaval", x = v.x, y = y, damage = U.damage,
			base = U.base, growth = U.growth, angle = U.angle, frames = 5,
			size = { U.width, U.height }, heavy = true, hitsOwner = false,
			knockbackMul = if last then (if U.finalMul ~= nil then U.finalMul else U.knockbackMul)
				else U.knockbackMul,
			shieldDamageMul = U.shieldDamageMul })
		Combat.emit(self, { type = "upheaval", x = v.x, y = y, step = step, last = last, victim = v.index })

	elseif m.kind == "pierce" then
		-- HEARTSEEKER. One arrow. It does not stop at the first thing it hits, it cannot be
		-- blocked, and it crosses the entire stage. Every other ultimate is a duration; this is a
		-- single frame of commitment with a two-second wind-up in front of it.
		if k ~= 0 then
			return
		end
		local P = m.pierce
		local shot = table.clone(m)
		shot.kind = "melee"
		shot.unblockable = true
		local pr: any = {
			owner = f, move = shot,
			x = f.x + f.facing * 2.2, y = f.y + P.height, vx = f.facing * P.speed, vy = 0,
			w = P.size[1], h = P.size[2], life = P.lifetime, gravity = 0, hitVictims = {},
			facing = f.facing, shape = "heartseeker", ghost = true, pierce = true,
		}
		pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h)
		table.insert(self.projectiles, pr)
		Combat.emit(self, { type = "heartseeker", x = pr.x, y = pr.y, facing = f.facing })

	elseif m.kind == "anchor" then
		-- ANCHOR. The head is thrown into the ground and stays there. The chain between the fighter
		-- and that point is live for the whole ultimate, and the fighter can still move.
		local A = m.anchor
		if k == 0 then
			local surf = Combat.surfaceUnder(self, f.x + f.facing * A.throwDistance, f.y + 1.5)
			f.ultAnchor = { x = f.x + f.facing * A.throwDistance,
				y = (if surf then surf.top else f.y) + 0.6 }
			Combat.emit(self, { type = "anchorset", x = f.ultAnchor.x, y = f.ultAnchor.y })
		end
		-- THE SNAP-BACK. On the last active frame the head is torn out of the ground and comes home
		-- along the chain, and everything on that line comes with it.
		if f.ultAnchor and k >= m.active - 1 then
			local ax, ay = f.ultAnchor.x, f.ultAnchor.y
			local steps = 6
			for i = 0, steps do
				local u = i / steps
				Combat.spawnBurst(self, f, { id = "Snapback", x = ax + (f.x - ax) * u,
					y = ay + (f.y + 2.4 - ay) * u, damage = A.snapDamage, base = A.snapBase,
					growth = A.snapGrowth, angle = A.snapAngle, frames = 5,
					size = { A.thickness * 2.4, A.thickness * 2.4 }, heavy = true, hitsOwner = false,
					knockbackMul = 1.35, shieldDamageMul = A.shieldDamageMul * 2 })
			end
			Combat.emit(self, { type = "anchorsnap", x = ax, y = ay })
			f.ultAnchor = nil
			return
		end
		if not f.ultAnchor or k % A.every ~= 0 then
			return
		end
		-- The chain is a line: sample it and hit anything standing on it.
		local ax, ay = f.ultAnchor.x, f.ultAnchor.y
		local hx, hy = f.x, f.y + 2.4
		local span = hypot(hx - ax, hy - ay)
		if span > A.maxLength then
			f.ultAnchor = nil
			Combat.emit(self, { type = "anchorsnap", x = ax, y = ay })
			return
		end
		-- ONE hit per fighter per tick. Sampling the line into overlapping bursts caught a victim
		-- standing on the chain with three or four at once: the ultimate dealt 124% where every
		-- other one deals between 18 and 55.
		for _, v in Combat.enemiesOf(self, f) do
			local dx, dy = hx - ax, hy - ay
			local len2 = dx * dx + dy * dy
			if len2 == 0 then
				len2 = 1
			end
			local t = math.max(0, math.min(1, ((v.x - ax) * dx + (v.cy - ay) * dy) / len2))
			local px, py = ax + dx * t, ay + dy * t
			if hypot(v.x - px, v.cy - py) <= A.thickness + v.r then
				Combat.spawnBurst(self, f, { id = "Chain", x = px, y = py, damage = A.damage,
					base = A.base, growth = A.growth, angle = A.angle, frames = 2,
					size = { A.thickness * 2, A.thickness * 2 }, heavy = false, hitsOwner = false,
					shieldDamageMul = A.shieldDamageMul })
			end
		end
		Combat.emit(self, { type = "chainline", ax = ax, ay = ay, hx = hx, hy = hy })

	elseif m.kind == "reflect" then
		-- AEGIS. Their damage becomes yours. The counter mechanic does this for one hit on one
		-- frame; this is the same idea held open for two seconds.
		if not f.reflecting then
			f.reflecting = { mul = m.reflect.multiplier, min = m.reflect.minDamage,
				radius = m.reflect.radius, angle = m.reflect.angle, base = m.reflect.base,
				growth = m.reflect.growth, shieldDamageMul = m.reflect.shieldDamageMul, absorbed = 0 }
		end
		-- THE DISCHARGE. Without it Aegis is blanked completely by an opponent who holds shield or
		-- walks away - the whole meter spent on nothing.
		if k >= m.active - 1 then
			local D = m.reflect
			local stored = f.reflecting.absorbed
			Combat.spawnBurst(self, f, { id = "AegisBreak", x = f.x + f.facing * 2.2, y = f.y + 2.8,
				damage = D.dischargeMin + jsRound(stored * D.dischargeShare),
				base = D.base, growth = D.growth, angle = D.angle, frames = 5,
				size = { D.dischargeRadius * 2, D.dischargeRadius * 1.7 }, heavy = true,
				hitsOwner = false, knockbackMul = 1.3, shieldDamageMul = D.shieldDamageMul })
			Combat.emit(self, { type = "aegisbreak", x = f.x, y = f.cy, stored = stored })
		end

	elseif m.kind == "bleed" then
		-- EXSANGUINATE. Mark now, collect later. The finisher is not a number in a data file, it is
		-- the combo you just did.
		local B = m.bleed
		if k < m.active - 1 then
			return
		end
		for _, v in Combat.enemiesOf(self, f) do
			local marks = v.effects.bleed or 0
			if marks ~= 0 then
				v.effects.bleed = 0
				Combat.spawnBurst(self, f, { id = "Exsanguinate", x = v.x, y = v.cy,
					damage = B.perMark * marks, base = B.base + B.basePerMark * marks,
					growth = B.growth, angle = B.angle, frames = 4,
					size = { B.radius * 2, B.radius * 2 }, heavy = true, hitsOwner = false,
					knockbackMul = B.knockbackMul, shieldDamageMul = B.shieldDamageMul })
				Combat.emit(self, { type = "exsanguinate", x = v.x, y = v.cy, marks = marks, victim = v.index })
			end
		end

	elseif FRAME_KINDS[m.kind] then
		later(`onMoveActiveFrame for kind "{m.kind}"`)
	end
end

-- ---------------------------------------------------------------- projectiles ----
function Combat.spawnProjectile(self, f: any, m: any, extra: any): any
	local p = m.projectile
	local rm = f.rangeMul or 1
	local pr: any = {
		owner = f, move = m,
		x = f.x + p.spawnOffset[1] * f.facing,
		y = f.y + p.spawnOffset[2] + (extra.yJitter or 0),
		vx = f.facing * p.speed, vy = 0, w = p.size[1], h = p.size[2],
		life = jsRound(p.lifetime * rm), shape = p.shape or "bolt",
		grounded = not not p.grounded, gravity = 0, hitVictims = {}, facing = f.facing,
		item = false, bloom = rm > 1,
	}
	pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h)
	table.insert(self.projectiles, pr)
	Combat.emit(self, { type = "projectile", shape = pr.shape, x = pr.x, y = pr.y })
	return pr
end

function Combat.stepProjectiles(self)
	for i = #self.projectiles, 1, -1 do
		local p = self.projectiles[i]
		-- `px` is unused here exactly as it is in the JavaScript; `py` is the landing check below.
		local _px, py = p.x, p.y
		if p.gravity ~= 0 then
			p.vy -= p.gravity * FRAME
		end
		-- Homing. A tracked round steers toward its mark at a fixed turn rate rather than snapping
		-- to it, so it still reads as a bullet in flight and can be walked out of at range.
		if p.homing and p.homing.target then
			local tg = p.homing.target
			if p.homing.expireAfter ~= nil then
				p.homing.expireAfter -= 1
			end
			if p.homing and p.homing.expireAfter ~= nil and p.homing.expireAfter <= 0 then
				p.homing = nil
			elseif not tg.alive then
				p.homing = nil
			-- A tracked round does not chase a fighter who is already flying. Chasing made a
			-- landed round a guaranteed edgeguard rather than a hit.
			elseif p.homing.dropOnHitstun and (tg.state == "hitstun" or tg.hitstun > 0) then
				p.homing = nil
			else
				local H = p.homing
				if H.axis == "x" then
					p.vx += clamp((tg.x - p.x) * H.turn, -H.speed * 0.6, H.speed * 0.6) - p.vx * 0.12
				else
					local dx, dy = tg.x - p.x, tg.cy - p.y
					local d = hypot(dx, dy)
					if d == 0 then
						d = 1
					end
					local wx, wy = (dx / d) * H.speed, (dy / d) * H.speed
					local blend = math.min(1, H.turn * FRAME)
					p.vx += (wx - p.vx) * blend
					p.vy += (wy - p.vy) * blend
				end
			end
		end
		p.x += p.vx * FRAME
		p.y += p.vy * FRAME
		p.life -= 1
		p.rect = rectFrom(p.x, p.y, p.w, p.h)
		table.insert(self.debugBoxes, { rect = p.rect, kind = "proj" })
		local dead = p.life <= 0
		-- Stage body: every solid stops a shot, not just the main floor. This is what makes a
		-- tower or a mesa actual cover instead of scenery.
		if not p.grounded and not p.ghost then
			for _, sp in self.match.stage.solids do
				if p.x > sp.x1 and p.x < sp.x2 and p.y < sp.top and p.y > sp.bottom then
					dead = true
					if p.falling then
						p.y = sp.top + 0.6                  -- burst ON the floor, not inside it
					end
					if p.explode then
						Combat.explode(self, p)
					else
						Combat.emit(self, { type = "projectilebreak", x = p.x, y = p.y })
					end
					break
				end
			end
		end
		-- Landing for lobbed items. Falling orbs are deliberately NOT in here: a drop-through
		-- shelf is not something energy from the sky stops on.
		if p.gravity ~= 0 and p.vy <= 0 then
			for _, pl in self.match.stage.platforms do
				if p.x > pl.x1 and p.x < pl.x2 and py >= pl.top - 0.2 and p.y < pl.top + 0.2 then
					dead = true
					if p.explode then
						Combat.explode(self, p)
					end
					break
				end
			end
		end
		for _, sm in self.summons do
			if sm.type == "wall" and sm.owner ~= p.owner and not Combat.sameTeam(self, sm.owner, p.owner)
				and overlap(p.rect, sm.rect) then
				dead = true
				Combat.emit(self, { type = "projectilebreak", x = p.x, y = p.y })
			end
			if sm.destructible and sm.owner ~= p.owner and not Combat.sameTeam(self, sm.owner, p.owner)
				and overlap(p.rect, sm.rect) and p.move.damage >= 4 then
				Combat.destroySummon(self, sm)
				dead = true
			end
		end
		if not dead then
			for _, v in self.match.fighters do
				if v ~= p.owner and v.alive and not Combat.sameTeam(self, p.owner, v)
					and not v.untouchable and not p.hitVictims[v.index]
					and overlap(p.rect, v.hurtbox) then
					-- Catching a keg out of the air. Timing a shield press on an incoming
					-- explosive takes it out of the air and puts it in your hands.
					--
					-- The state check is load-bearing and was missing here at first: without it
					-- this fired for a victim who was HOLDING shield, whose state is "shield" and
					-- who therefore cannot catch anything, and a starfall orb into a raised guard
					-- aborted the whole trace on a branch the JavaScript never takes.
					if p.explode and v.buffer.guard > 0 and not v.item
						and CATCHABLE_STATES[v.state] then
						later("giveItem (catching a thrown keg out of the air)")
					end
					p.hitVictims[v.index] = true
					if p.stick then
						later("the Lodestone's stick effect, which is an item")
					end
					if p.explode then
						Combat.explode(self, p)
						dead = true
						break
					end
					-- `p.knockbackMul` lets a move give one round in a magazine a different launch
					-- from the others - see the sniper stance, whose setup rounds must not launch
					-- hard enough for the NEXT round to chase the victim off the stage.
					local hit = Combat.resolveHit(self, p.owner, v, p.move,
						{ angle = p.move.angle, knockbackMul = p.knockbackMul }, p.rect,
						{ projectile = true, facing = sign(p.vx), item = p.item })
					-- A piercing shot keeps going; hitVictims already stops it hitting the same
					-- fighter twice, so it crosses the stage taking everyone on the line.
					if hit and not p.pierce then
						dead = true
						break
					end
				end
			end
		end
		if p.y < self.match.stage.blast.bottom - 10 or math.abs(p.x) > 200 then
			dead = true
		end
		if dead then
			table.remove(self.projectiles, i)
		end
	end
end

function Combat.explode(self, p: any)
	local e = p.explode
	Combat.spawnBurst(self, p.owner, { id = e.id, x = p.x, y = p.y, damage = e.damage, base = e.base,
		growth = e.growth, angle = e.angle, frames = 3, size = { e.radius * 2, e.radius * 2 },
		heavy = true, hitsOwner = e.hitsOwner ~= false, knockbackMul = e.knockbackMul,
		shieldDamageMul = e.shieldDamageMul, unblockable = e.unblockable })
	Combat.emit(self, { type = "explosion", x = p.x, y = p.y, radius = e.radius, kind = e.fx or nil })
end

-- ---------------------------------------------------------------- summons ----
-- Only `mine` is ported. No weapon in the roster uses `wall`, `cloud` or `node`, which also makes
-- WALL_MOVE, CLOUD_MOVE, NODE_MOVE, the `pulse` move kind, the `teleport` recovery and nearestNode
-- unreachable. They are refused rather than carried, the same way `field` was.
function Combat.spawnSummon(self, f: any, m: any)
	local s = m.summon
	-- rangeMul scales a wall's height and a cloud's radius, neither of which is ported.
	local _rm = f.rangeMul or 1
	if s.type ~= "mine" then
		later(`summon type "{s.type}", which no weapon uses`)
	end
	local mine: any = { type = "mine", owner = f, x = f.x + s.offset[1] * f.facing, y = f.y,
		hp = s.hp, life = s.lifetime, trigger = s.trigger, radius = s.radius, armed = 20,
		destructible = true,
		blast = { damage = 12, base = 26, growth = 4.0, angle = 70 } }
	for k, v in (s.blast or {}) do
		mine.blast[k] = v
	end
	local surf = Combat.surfaceUnder(self, mine.x, f.y + 1)
	if surf then
		mine.y = surf.top
	end
	mine.rect = rectFrom(mine.x, mine.y + 0.8, 1.6, 1.6)
	local owned = {}
	for _, q in self.summons do
		if q.type == "mine" and q.owner == f then
			table.insert(owned, q)
		end
	end
	if #owned >= s.max then
		Combat.removeSummon(self, owned[1])
	end
	table.insert(self.summons, mine)
	if f.mech.id == "Fruiting" then
		later("the Fruiting mechanic's ring, which no weapon has")
	end
	Combat.emit(self, { type = "summon", kind = s.type, x = f.x, y = f.y })
end

function Combat.stepSummons(self)
	for i = #self.summons, 1, -1 do
		local s = self.summons[i]
		s.life -= 1
		if s.type ~= "mine" then
			later(`stepSummons for type "{s.type}"`)
		end
		table.insert(self.debugBoxes, { rect = s.rect, kind = "summon" })
		if s.armed > 0 then
			s.armed -= 1
		else
			for _, v in Combat.enemiesOf(self, s.owner) do
				if not v.untouchable
					and hypot(v.x - s.x, v.cy - (s.y + 1)) <= s.trigger + v.r then
					local b: any = { x = s.x, y = s.y + 1, frames = 3,
						size = { s.radius * 2, s.radius * 2 }, heavy = true }
					for k, bv in s.blast do
						b[k] = bv
					end
					b.x = s.x; b.y = s.y + 1; b.frames = 3
					b.size = { s.radius * 2, s.radius * 2 }; b.heavy = true
					Combat.spawnBurst(self, s.owner, b)
					Combat.emit(self, { type = "explosion", x = s.x, y = s.y + 1, radius = s.radius })
					Combat.removeSummon(self, s)
					break
				end
			end
		end
		if s.life <= 0 and self.summons[i] == s then
			table.remove(self.summons, i)
		end
	end
end

function Combat.nodesOf(self, f: any): { any }
	return {}                                   -- no weapon spawns nodes; see spawnSummon
end
function Combat.hasFruit(self, f: any): boolean
	for _, s in self.summons do
		if (s.type == "cloud" or s.type == "mine") and s.owner == f then
			return true
		end
	end
	return false
end
function Combat.nearestNode(self, f: any, range: number): any
	return nil                                  -- no weapon spawns nodes, and none recovers by teleport
end
function Combat.removeSummon(self, s: any)
	local i = table.find(self.summons, s)
	if i then
		table.remove(self.summons, i)
	end
end
function Combat.destroySummon(self, s: any)
	Combat.removeSummon(self, s)
	Combat.emit(self, { type = "summonbreak", kind = s.type, x = s.x, y = s.y })
end

-- ---------------------------------------------------------------- item stubs ----
-- Fighter calls into these; with nothing spawning items in Phase 3b they are correctly empty,
-- which is why these can answer honestly rather than throw.
function Combat.itemNear(self, f: any): any
	return nil
end
function Combat.useItem(self, f: any, button: string)
	later("useItem")
end
function Combat.dropItem(self, f: any, knocked: boolean?)
	later("dropItem")
end
function Combat.pickupItem(self, f: any, it: any)
	later("pickupItem")
end
function Combat.fruiting(self, f: any)
	-- The Fruiting mechanic is not on any weapon in the roster, so this cannot be reached: Fighter
	-- only calls it when mech.id == "Fruiting". Not ported for the same reason `field` was deleted.
	later("fruiting, which no weapon's mechanic uses")
end

return Combat
