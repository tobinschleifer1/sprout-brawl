--!strict
-- The HUD's palette, and the one piece of it that is arithmetic.
--
-- Split out of the HUD itself because web/src/ui/hud.js is a DOM tree - divs, CSS classes and
-- innerHTML - and none of that ports. What DOES port is this: the per-player colours, the marks
-- that tell four identical tiles apart, and the ramp that turns a damage percent into a colour.
-- That ramp is the only part a reader cannot check by looking at the screen, so it is the only
-- part held to the JavaScript by a test.

local HudColors = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

HudColors.PLAYER = {
	rgb(62, 138, 46), rgb(222, 98, 28), rgb(63, 127, 214), rgb(154, 95, 200),
	rgb(214, 76, 140), rgb(47, 163, 154), rgb(201, 162, 39), rgb(138, 90, 43),
}
-- A shape per player as well as a colour: at tile size, and for anyone who cannot separate the
-- green from the orange, the colour alone is not a distinction.
HudColors.MARKS = { "●", "■", "▲", "◆", "✿", "★", "⬢", "❋" }
HudColors.TEAM = { rgb(62, 138, 46), rgb(222, 98, 28) }

-- Damage, as a colour. Bone white through yellow and orange into a deep red, and it stops mattering
-- past 200 because everything above that is equally lethal.
local RAMP: { { any } } = {
	{ 0, { 246, 248, 241 } },
	{ 50, { 243, 217, 92 } },
	{ 100, { 242, 162, 60 } },
	{ 150, { 232, 98, 42 } },
	{ 200, { 180, 35, 30 } },
}

function HudColors.percent(p: number): Color3
	local v = math.min(200, p)
	for i = 2, #RAMP do
		if v <= RAMP[i][1] then
			local a, ca = RAMP[i - 1][1], RAMP[i - 1][2]
			local b, cb = RAMP[i][1], RAMP[i][2]
			local k = (v - a) / (b - a)
			-- math.floor(x + 0.5), not math.round: the JavaScript rounds halves toward +infinity
			-- and Luau rounds them away from zero, and the two disagree on a negative half. A
			-- percent below zero is not reachable today, but a colour ramp that is only correct
			-- for reachable inputs is a trap for whoever makes it reachable.
			local c = {}
			for j = 1, 3 do
				c[j] = math.floor(ca[j] + (cb[j] - ca[j]) * k + 0.5)
			end
			return rgb(c[1], c[2], c[3])
		end
	end
	return rgb(180, 35, 30)
end

return HudColors
