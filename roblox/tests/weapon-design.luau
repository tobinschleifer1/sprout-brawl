--!nocheck
-- What the weapon reviews asked of the roster, held as properties of the weapons the game plays
-- (tuned: WeaponTuning.luau, RobloxWeapons.luau). Launch is Knockback.launchSpeed at 100% on a
-- weight-100 fighter, a box's own numbers where it has them.
--
--     lune run tests/weapon-design
local Loader = require("./loader")
local Weapons, Knockback = Loader.load("Weapons"), Loader.load("Knockback")
local function launch(m: any, hb: any?, at: number?): number
	local b = hb or {}
	local damage = b.damage or m.damage
	return Knockback.launchSpeed(b.base or m.base, b.growth or m.growth or 0, damage, (at or 100) + damage, 100)
end
local W = Weapons.BY_ID

-- Round 1: Runebrand made 158 of the Grimoire's 194 KOs, launching 122.
local rune = launch(W.Grimoire.moves.SigSide)
assert(rune <= 90, `Runebrand launches {rune} at 100%, a cash-out every bit as hard as before`)
-- Round 1: Reaper's Arc's handle launched 124 to the tip's 128, so spacing for the tip paid nothing.
local arc = W.Scythe.moves.SigSide
local tip, handle = launch(arc, arc.hitboxes[1]), launch(arc, arc.hitboxes[2])
assert(tip - handle >= 40, `Reaper's Arc's tip launches {tip} and its handle {handle}: the sweet spot is no reward`)
-- Round 1: the Whip's lash launched 7, so anyone inside its tip was safe. It shoves them out to the
-- tip's distance, and the tip stays the reward: more damage, and the harder launch where stocks are
-- taken (the lash's flat shove grows slowly; at 100% the two are close).
for _, id in { "LightNeutral1", "LightNeutral2", "LightNeutral3", "LightSide1", "LightSide2", "LightUp", "LightDown" } do
	local m = W.Whip.moves[id]
	local lash = launch(m, m.hitboxes[2])
	assert(lash >= 15, `the Whip's {id} lash launches {lash}: nothing pushes them out to the tip`)
	local lashLate, crackLate = launch(m, m.hitboxes[2], 150), launch(m, m.hitboxes[1], 150)
	local lashDamage, crackDamage = m.hitboxes[2].damage or m.damage, m.hitboxes[1].damage or m.damage
	assert(crackDamage > lashDamage and crackLate > lashLate,
		`the Whip's {id} tip ({crackDamage} damage, {crackLate} at 150%) is no reward over its lash ({lashDamage}, {lashLate})`)
end
-- Round 1: the Blasters could not finish a stock (median KO 157%); Scattergun is its finisher.
local scatter = launch(W.Blasters.moves.SigDown)
assert(scatter >= 140, `Scattergun launches {scatter} at 100%: the Blasters still cannot finish`)
-- Round 1: the Chakram's ultimate made 60% of its KOs; Orbit Throw launched 28.
local orbit = launch(W.Chakram.moves.SigSide)
assert(orbit >= 60, `Orbit Throw launches {orbit} at 100%: the rings never take a stock`)

-- Round 1: two blurbs said what the numbers do not. A weapon that calls itself the lightest,
-- heaviest, fastest or slowest is.
local function stat(w: any, key: string, default: number): number
	local st = w.stats or {}
	if key == "weight" then return st.set and st.set.weight or default end
	return st.mul and st.mul[key] or default
end
local claims = { lightest = { "weight", 100, -1 }, heaviest = { "weight", 100, 1 }, fastest = { "runSpeed", 1, 1 }, slowest = { "runSpeed", 1, -1 } }
local checked = 0
for _, w in Weapons.LIST do
	local blurb = string.lower((w.blurb or "") .. " " .. (w.tagline or ""))
	for word, c in claims do
		if string.find(blurb, word, 1, true) then
			local mine = stat(w, c[1], c[2]) * c[3]
			for _, other in Weapons.LIST do
				assert(stat(other, c[1], c[2]) * c[3] <= mine, `{w.id} says it is the {word}, but {other.id} is more so`)
			end
			checked += 1
		end
	end
end
print(`PASS weapon design: Runebrand {math.floor(rune)}, Reaper's Arc tip {math.floor(tip)} over handle {math.floor(handle)}, every Whip lash pushes out under its tip, Scattergun {math.floor(scatter)}, Orbit Throw {math.floor(orbit)}; {checked} superlatives in the blurbs true`)
