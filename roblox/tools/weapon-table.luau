--!nocheck
-- Development tool, not a test: every weapon's moves as a frame-data table (markdown), for design
-- reviews. Launch is Knockback.launchSpeed at 100% on a weight-100 fighter (the higher, the sooner
-- it kills); reach is the furthest any hitbox extends in front of the fighter, in studs.
--   lune run tools/weapon-table > table.md
local Loader = require("../tests/loader")
local Weapons = Loader.load("Weapons")
local Knockback = Loader.load("Knockback")
local ORDER = { "LightNeutral1", "LightNeutral2", "LightNeutral3", "LightSide1", "LightSide2", "LightUp", "LightDown",
	"SigNeutral", "SigSide", "SigUp", "SigDown", "AirNeutral", "AirSide", "AirUp", "AirDown", "AirBack", "Finisher", "Ultimate" }
local function reach(m: any): number
	local best = 0
	for _, hb in m.hitboxes or {} do
		if hb.offset and hb.size then best = math.max(best, hb.offset[1] + hb.size[1] / 2) end
	end
	return best
end
local out = {}
local function p(s: string) table.insert(out, s) end
p("| Weapon | Archetype | Weight | Run x | Mechanic | Fastest startup | Longest reach | Hardest launch at 100% |")
p("|---|---|---|---|---|---|---|---|")
for _, w in Weapons.LIST do
	local fast, far, hard = { math.huge, "" }, { 0, "" }, { 0, "" }
	for id, m in w.moves do
		if m.startup and m.startup < fast[1] then fast = { m.startup, id } end
		if reach(m) > far[1] then far = { reach(m), id } end
		if m.damage and m.base then
			local l = Knockback.launchSpeed(m.base, m.growth or 0, m.damage, 100 + m.damage, 100)
			if l > hard[1] then hard = { l, id } end
		end
	end
	local st = w.stats or {}
	p(string.format("| %s | %s | %s | %s | %s | %d (%s) | %.1f (%s) | %.0f (%s) |", w.id, w.archetype or "", tostring(st.set and st.set.weight or 100),
		tostring(st.mul and st.mul.runSpeed or 1), w.mechanic and (w.mechanic.label or w.mechanic.id) or "-", fast[1], fast[2], far[1], far[2], hard[1], hard[2]))
end
p("")
for _, w in Weapons.LIST do
	p(`### {w.id} - {w.archetype or ""}`)
	p("")
	p("| Move | Label | Start | Active | Recov | Total | Dmg | Base | Growth | Angle | Launch@100% | Reach | Kind |")
	p("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	local seen = {}
	local ids = {}
	for _, id in ORDER do if w.moves[id] then table.insert(ids, id); seen[id] = true end end
	local rest = {}
	for id in w.moves do if not seen[id] then table.insert(rest, id) end end
	table.sort(rest)
	for _, id in rest do table.insert(ids, id) end
	for _, id in ids do
		local m = w.moves[id]
		local launch = if m.damage and m.base then Knockback.launchSpeed(m.base, m.growth or 0, m.damage, 100 + m.damage, 100) else 0
		p(string.format("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %.0f | %.1f | %s |", id, m.label or "", tostring(m.startup or "-"),
			tostring(m.active or "-"), tostring(m.recovery or "-"), tostring(m.total or "-"), tostring(m.damage or "-"), tostring(m.base or "-"),
			tostring(m.growth or "-"), tostring(m.angle or "-"), launch, reach(m), m.kind or ""))
	end
	p("")
end
print(table.concat(out, "\n"))
