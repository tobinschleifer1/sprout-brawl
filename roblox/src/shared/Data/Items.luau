--!nocheck
-- GENERATED FILE - DO NOT EDIT.
--
-- Emitted from web/src/data/items.js by roblox/tools/gen-data.mjs, which check.sh runs on every invocation.
-- Edit the JavaScript and re-run; anything typed in here is overwritten without warning.
--
-- `--!nocheck` because this is a literal data table with no logic in it: strict mode would
-- produce thousands of inferred-shape errors and check nothing that tests/data-parity.luau does
-- not already check field by field against the JavaScript.

local ITEMS = {
	{
		id = "BlastKeg",
		name = "Blast Keg",
		kind = "throw",
		uses = 1,
		colour = "#8A5A2B",
		accent = "#E8862E",
		blurb = "Arcs, fuses, and goes off if anyone hits it.",
		throw = {
			vx = 30,
			vy = 30,
			gravity = 115,
			fuse = 110,
			size = { 1.6, 1.8 },
		},
		explode = {
			damage = 16,
			base = 30,
			growth = 3.6,
			angle = 62,
			radius = 5.5,
		},
		volatile = true,
	},
	{
		id = "RivetGun",
		name = "Rivet Gun",
		kind = "shoot",
		uses = 8,
		colour = "#7C8695",
		accent = "#FFD37A",
		blurb = "Eight bolts. Chip and interrupt, no kill.",
		shot = {
			speed = 52,
			lifetime = 26,
			damage = 3,
			base = 6,
			growth = 0.35,
			angle = 20,
			size = { 1, 0.4 },
			cooldown = 7,
			extraHitstun = 6,
		},
		thrown = {
			speed = 42,
			lifetime = 30,
			damage = 7,
			base = 15,
			growth = 1.4,
			angle = 45,
			size = { 1.2, 0.8 },
		},
	},
	{
		id = "Bulwark",
		name = "Bulwark",
		kind = "hold",
		uses = 1,
		colour = "#5A6472",
		accent = "#EDF1F6",
		blurb = "Carry it and the front is covered. Slows you down.",
		guard = {
			hp = 46,
			damageMul = 0.35,
			launchMul = 0.4,
			speedMul = 0.72,
			arc = 0.55,
		},
		bash = {
			label = "Shield Bash",
			startup = 9,
			active = 3,
			recovery = 16,
			damage = 6,
			base = 16,
			growth = 1.4,
			angle = 30,
			shieldDamageMul = 2.6,
			hitboxes = {
				{
					frames = { 10, 12 },
					offset = { 2.2, 2.6 },
					size = { 3.4, 3.6 },
				},
			},
		},
		thrown = {
			speed = 34,
			lifetime = 30,
			damage = 11,
			base = 22,
			growth = 2.2,
			angle = 40,
			size = { 1.8, 2.2 },
		},
	},
	{
		id = "SpringPlate",
		name = "Spring Plate",
		kind = "place",
		uses = 1,
		colour = "#3E8A2E",
		accent = "#A8FF7A",
		blurb = "Anyone who lands on it goes straight up.",
		plate = {
			vy = 88,
			life = 720,
			cooldown = 24,
			size = { 3.4, 0.9 },
		},
		thrown = {
			speed = 30,
			lifetime = 26,
			damage = 6,
			base = 13,
			growth = 1.2,
			angle = 55,
			size = { 1.8, 0.7 },
		},
	},
	{
		id = "Lodestone",
		name = "Lodestone",
		kind = "throw",
		uses = 1,
		colour = "#2B3038",
		accent = "#9AA6FF",
		blurb = "Sticks. They fall like a stone for five seconds.",
		throw = {
			vx = 40,
			vy = 12,
			gravity = 55,
			fuse = 70,
			size = { 1.2, 1.2 },
		},
		stick = {
			frames = 300,
			fallMul = 1.9,
			airMul = 0.45,
			jumpMul = 0.8,
			damage = 2,
		},
	},
}

local BY_ID = {}
for _, i in ITEMS do
	BY_ID[i.id] = i
end

return { LIST = ITEMS, BY_ID = BY_ID }
