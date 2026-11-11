--!nocheck
-- Development tool, not a test: every move's frame advantage, from the data the game reads and the
-- engine's own formulas (Knockback.blockstun, Knockback.hitstun, Config.SHIELD.dropFrames).
--   lune run tools/frame-advantage [percent] > table.md
-- On shield: the defender's blockstun against the attacker's frames left after the first active
-- frame ((active - 1) + recovery); negative means the defender acts first, and by more than the
-- shield's drop plus their fastest move means a punish. On hit, at a percent: the victim's hitstun
-- against the same frames left; positive is a frame advantage, the room for a follow-up. Hitlag
-- freezes both sides alike, so it is left out. Projectiles and other moves whose hit is not the
-- attacker's own active frame are marked.
local process = require("@lune/process")
local Loader = require("../tests/loader")
local Weapons, Knockback, Config = Loader.load("Weapons"), Loader.load("Knockback"), Loader.load("Config")
local percent = tonumber(process.args[1] or "60") or 60
local ORDER = { "LightNeutral1", "LightNeutral2", "LightNeutral3", "LightSide1", "LightSide2", "LightUp", "LightDown",
	"SigNeutral", "SigSide", "SigUp", "SigDown", "AirNeutral", "AirForward", "AirUp", "AirDown", "AirBack", "Finisher", "AirFinisher" }
local out = {}
local function p(s: string) table.insert(out, s) end
p(`Frame advantage. On hit at {percent}% (weight 100). Shield drop: {Config.SHIELD.dropFrames} frames.`)
p("")
p("| Weapon | Fastest opener | Safe on shield (of moves) | Worst on shield | Best on hit |")
p("|---|---|---|---|---|")
local detail = {}
for _, w in Weapons.LIST do
	local fastest = math.huge
	for id, m in w.moves do
		if string.sub(id, 1, 5) == "Light" and string.sub(id, -1) ~= "2" and string.sub(id, -1) ~= "3" and m.startup then fastest = math.min(fastest, m.startup) end
	end
	local safe, total, worst, best = 0, 0, { math.huge, "" }, { -math.huge, "" }
	local rows = {}
	for _, id in ORDER do
		local m = w.moves[id]
		if m and m.damage and m.startup then
			local left = (m.active - 1) + m.recovery
			local ranged = m.kind ~= nil and m.kind ~= "melee"
			local block = Knockback.blockstun(m.damage) - left
			local hb = m.hitboxes and m.hitboxes[1] or {}
			local stun = Knockback.hitstun(Knockback.stunSpeed(hb.base or m.base, hb.growth or m.growth or 0, hb.damage or m.damage, percent + m.damage, 100))
			local onHit = stun - left
			if not ranged then
				total += 1
				-- safe: the defender cannot drop shield and start their fastest opener before the attacker recovers
				if -block < Config.SHIELD.dropFrames + fastest then safe += 1 end
				if block < worst[1] then worst = { block, id } end
				if onHit > best[1] then best = { onHit, id } end
			end
			table.insert(rows, string.format("| %s | %s | %d | %d | %+d | %+d |%s", id, m.label or "", m.startup, left, block, onHit, if ranged then " (" .. m.kind .. ")" else ""))
		end
	end
	p(string.format("| %s | %d | %d/%d | %+d (%s) | %+d (%s) |", w.id, fastest, safe, total, worst[1], worst[2], best[1], best[2]))
	table.insert(detail, { w.id, rows })
end
p("")
for _, d in detail do
	p(`### {d[1]}`)
	p("")
	p("| Move | Label | Startup | Frames left after contact | On shield | On hit |")
	p("|---|---|---|---|---|---|")
	for _, r in d[2] do p(r) end
	p("")
end
print(table.concat(out, "\n"))
