--!nocheck
-- GENERATED FILE - DO NOT EDIT.
--
-- Emitted from web/src/data/avatars.js by roblox/tools/gen-data.mjs, which check.sh runs on every invocation.
-- Edit the JavaScript and re-run; anything typed in here is overwritten without warning.
--
-- `--!nocheck` because this is a literal data table with no logic in it: strict mode would
-- produce thousands of inferred-shape errors and check nothing that tests/data-parity.luau does
-- not already check field by field against the JavaScript.

local AVATARS = {
	{
		id = "Classic",
		name = "Classic",
		rig = "avatar",
		features = {
			head = "block",
			face = "dot",
			hat = "none",
			torso = "belt",
		},
		palette = {
			primary = "#F2C94C",
			secondary = "#4A90D9",
			tertiary = "#2E5F8A",
			accent = "#FFF3D0",
			glow = "#8ED8FF",
		},
	},
	{
		id = "Noir",
		name = "Noir",
		rig = "avatar",
		features = {
			head = "block",
			face = "shades",
			hat = "none",
			torso = "sash",
		},
		palette = {
			primary = "#E8E8EC",
			secondary = "#23232B",
			tertiary = "#3A3A46",
			accent = "#FFFFFF",
			glow = "#9AA6FF",
		},
	},
	{
		id = "Ember",
		name = "Ember",
		rig = "avatar",
		features = {
			head = "round",
			face = "pair",
			hat = "horns",
			torso = "belt",
		},
		palette = {
			primary = "#F2994A",
			secondary = "#8A2E1F",
			tertiary = "#4A1B14",
			accent = "#FFE0C0",
			glow = "#FF7A3C",
		},
	},
	{
		id = "Moss",
		name = "Moss",
		rig = "avatar",
		features = {
			head = "wide",
			face = "pair",
			hat = "hood",
			torso = "plain",
		},
		palette = {
			primary = "#8FBF6A",
			secondary = "#3E6B3A",
			tertiary = "#294B2A",
			accent = "#E4F3D6",
			glow = "#A8FF7A",
		},
	},
	{
		id = "Vapor",
		name = "Vapor",
		rig = "avatar",
		features = {
			head = "tall",
			face = "visor",
			hat = "antenna",
			torso = "emblem",
		},
		palette = {
			primary = "#F49AC2",
			secondary = "#6C63C7",
			tertiary = "#3E3A78",
			accent = "#FFE4F1",
			glow = "#FF6BD6",
		},
	},
	{
		id = "Steel",
		name = "Steel",
		rig = "avatar",
		features = {
			head = "block",
			face = "goggles",
			hat = "cap",
			torso = "emblem",
		},
		palette = {
			primary = "#B8C0CC",
			secondary = "#5A6472",
			tertiary = "#333A45",
			accent = "#EDF1F6",
			glow = "#7FD4FF",
		},
	},
}

-- The stat line every fighter starts from, before the weapon's set/mul overrides. See Loadout.
local BASE = {
	weight = 100,
	runSpeed = 23,
	walkSpeed = 12,
	airSpeed = 18,
	jumps = 2,
	jumpVelocity = 63,
	fallSpeed = 38,
	height = 5.2,
	radius = 1.1,
}

local BY_ID = {}
for _, a in AVATARS do
	BY_ID[a.id] = a
end

return { LIST = AVATARS, BY_ID = BY_ID, BASE = BASE, DEFAULT_ID = "Classic" }
