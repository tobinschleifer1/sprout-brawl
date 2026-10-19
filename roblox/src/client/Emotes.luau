--!strict
-- Roblox-only pose channels. No sprites, clocks, or simulation writes: taunts sample their
-- stateFrame, podium winners hold their item's key frame. Angles are authored in degrees here,
-- then handed to the same Posture/weapon grip solve as every other fighter pose.
local Shared = game:GetService("ReplicatedStorage").Shared
local Inventory = require(Shared.Inventory)
local Cosmetics = require(Shared.Cosmetics)
local Config = require(Shared.Config)
local Emotes = {}

Emotes.KEY_FRAME = 42
Emotes.STANCE = { front = -25, back = -100, frontExt = 0.9, backExt = 1,
	frontBend = 12, backBend = 12, lean = 4, head = 0, legL = 12, legR = -8,
	kneeL = 0, kneeR = 0, drop = 0 } :: { [string]: number }
local function pose(values: any): any
	local p = table.clone(Emotes.STANCE)
	for k, v in values do p[k] = v end
	return p
end
-- Broad silhouettes survive half-detail. Repeated keys are deliberate holds, not more pictures.
local function keys(a: any, b: any, c: any?): any
	return { { 0 :: any, Emotes.STANCE }, { 24, pose(a) }, { 42, pose(b) }, { 64, pose(c or a) }, { Config.TAUNT_FRAMES :: any, Emotes.STANCE } }
end
Emotes.CLIPS = {
	emote_wave = keys({ back = 115, head = -12 }, { back = 140, head = -10, backBend = 35 }),
	emote_challenge = keys({ front = 10, lean = 16, frontExt = 0.65 }, { front = 5, lean = 20, frontExt = 1, back = -130, head = 12 }),
	emote_cheer = keys({ front = 65, back = 125, legL = 22, legR = -22 }, { front = 80, back = 130, legL = 25, legR = -25, head = -20 }),
	emote_bow = keys({ front = -160, back = -155, lean = 35, head = 25 }, { front = -170, back = -150, lean = 55, head = 35, drop = 0.035 }),
	emote_shrug = keys({ front = 20, back = 160, frontExt = 0.65, backExt = 0.7, frontBend = 75, backBend = 65 },
		{ front = 35, back = 145, frontExt = 0.65, backExt = 0.7, frontBend = 75, backBend = 65, head = 30, lean = -10 }),
	emote_salute = keys({ back = 25, backExt = 0.5, backBend = 100, head = -10 },
		{ back = 110, backExt = 0.55, backBend = 105, front = -75, lean = -5, head = -15, legL = 3, legR = -3 }),
	emote_balance = keys({ front = 0, back = 180, legL = 45, kneeL = 0.6, lean = -10 },
		{ front = 15, back = 170, legL = 65, kneeL = 0.8, lean = -15, head = 20 }),
	emote_disco = keys({ front = -40, back = 135, lean = 12, legL = 30, legR = -25 },
		{ front = 55, back = -145, lean = -18, legL = 30, legR = -25, head = -25 },
		{ front = -45, back = 140, lean = 18, legL = 30, legR = -25 }),
	emote_flex = keys({ front = 35, back = 145, frontExt = 0.6, backExt = 0.6, frontBend = 95, backBend = 95 },
		{ front = 65, back = 115, frontExt = 0.65, backExt = 0.65, frontBend = 110, backBend = 110, legL = 28, legR = -28, head = -15 }),
	emote_crane = keys({ front = 10, back = 170, kneeR = 0.75, legR = -50 },
		{ front = 130, back = 70, kneeR = 0.85, legR = -65, lean = 10, head = -25 }),
	emote_lunge = keys({ front = 5, back = -175, lean = 20, legL = 38, legR = -35, drop = 0.055 },
		{ front = -5, back = 170, lean = 30, legL = 50, legR = -40, drop = 0.08, head = 10 }),
	emote_vip = keys({ front = -55, back = 120, head = -30, lean = -12 },
		{ front = -65, back = 155, head = -35, lean = -18, legL = 25, legR = -5 },
		{ front = -65, back = -15, backExt = 0.4, backBend = 100, lean = 12, head = 20 }),
	pose_champion = keys({ front = 75 }, { front = 85, back = -130, legL = 22, legR = -20, head = -20, lean = -8 }),
	pose_hero = keys({ drop = 0.04 }, { front = 0, back = -155, lean = 25, drop = 0.08, legL = 40, legR = -35, head = -10 }),
	pose_sentinel = keys({ front = 65 }, { front = 70, frontExt = 0.65, frontBend = 55, back = -85, legL = 2, legR = -2, lean = 0, head = 15 }),
	pose_star = keys({ front = 20, back = 160 }, { front = 35, back = 145, legL = 32, legR = -32, head = -30, lean = -5 }),
	pose_thinker = keys({ back = 25, backExt = 0.4 }, { front = -5, frontExt = 0.55, frontBend = 80, back = 110, backExt = 0.55, backBend = 110, head = 40, lean = 15, kneeL = 0.65, legL = 40 }),
	pose_duelist = keys({ front = 15 }, { front = 155, back = -160, lean = -20, head = -35, legL = 30, legR = -15, frontBend = 35 }),
} :: { [string]: any }

function Emotes.sample(id: string, frame: number): any
	local clip = Emotes.CLIPS[id] or Emotes.CLIPS.emote_wave
	local f = math.clamp(frame, 0, Config.TAUNT_FRAMES)
	for i = 2, #clip do
		local a, b = clip[i - 1], clip[i]
		if f <= b[1] then
			local u = (f - a[1]) / (b[1] - a[1])
			local k = u * u * (3 - 2 * u)
			local out = {}
			for key, v in a[2] do out[key] = v + (b[2][key] - v) * k end
			return out
		end
	end
	return table.clone(Emotes.STANCE)
end

function Emotes.idFor(worn: any, slot: string): string
	local key = Inventory.EMOTE_SLOTS[slot] or Inventory.EMOTE_SLOTS.neutral
	local id = worn and worn[key]
	local it = id and Cosmetics.get(id)
	return if it and it.type == "emote" then id else (Inventory.DEFAULT_EMOTES[slot] or Inventory.DEFAULT_EMOTES.neutral)
end
function Emotes.poseFor(worn: any): string
	local id = worn and worn.pose
	local it = id and Cosmetics.get(id)
	return if it and it.type == "victory_pose" then id else Inventory.DEFAULT_POSE
end

-- Event identity uses the fighter's clock, not wall time. A late event cannot animate a later
-- taunt, and a predicted cancellation immediately stops drawing without waiting on another event.
function Emotes.For(s: any, char: any, event: any?): any
	if s.state == "victory" then
		return Emotes.sample(s.victoryPose or Emotes.poseFor(char.cosmetics), math.min(Emotes.KEY_FRAME, 24 + s.stateFrame))
	end
	if s.state ~= "taunt" then return nil end
	local slot = "neutral"
	if event and math.abs((s.frameCount - s.stateFrame) - event.start) < 0.01 then slot = event.slot end
	return Emotes.sample(Emotes.idFor(char.cosmetics, slot), s.stateFrame)
end

-- Mutates only freshly computed presentation channels, never the snapshot or the character.
function Emotes.apply(ch: any, wpose: any, p: any, char: any)
	ch.lean, ch.head = math.rad(p.lean), math.rad(p.head)
	local spread = math.max(math.abs(p.legL) * (1 - p.kneeL), math.abs(p.legR) * (1 - p.kneeR))
	ch.bob, ch.sx, ch.sy, ch.spinY, ch.spinZ = -char.height * (p.drop + 0.34 * (1 - math.cos(math.rad(spread)))), 1, 1, 0, 0
	ch.armL.z, ch.armL.x, ch.armL.ext = math.rad(p.back) + math.pi / 2 + ch.lean * 0.35, 0, p.backExt
	ch.armR.z, ch.armR.x, ch.armR.ext = math.rad(p.front) + math.pi / 2, 0, p.frontExt
	ch.legL, ch.legR, ch.kneeL, ch.kneeR = math.rad(p.legL), math.rad(p.legR), p.kneeL, p.kneeR
	ch.emote = p
	wpose.angle, wpose.ox, wpose.oy, wpose.emote = math.rad(p.front), 0, 0, true
	wpose.trail, wpose.drag = nil, nil
end
return Emotes
