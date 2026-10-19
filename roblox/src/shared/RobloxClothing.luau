--!strict
-- The clothing catalogue: pieces worn through k2 character codes (AvatarKit), owned as Cosmetics
-- items of type "clothing", sold singly or as a pack (Products.CLOTHING, Shop).
-- `n` is a piece's PERMANENT number: k2 codes carry it, so never renumber or reuse one - a new piece
-- takes the next unused number; a retired piece keeps its number and codes naming it fall back to
-- the category's free option. tests/kit-k2.luau pins every number.
-- Layers use the existing kit's zero-based x/y, z order, clipping and colour ROLES.
-- No literal colours: a/A/u top, b/B trim, c/C bottom, f/F shoes, x/X/y accessory,
-- h/H/i hair. Hats carry trim; every hair layer is marked hair so hats can trim it.
-- Capes occupy neck and the existing torso/pelvis canvases; they are NOT a new rig piece.
-- tools/clothing-sheet.mjs validates and previews this through the shipping Luau kit.
-- See docs/briefs/clothing-catalogue.md for k2 and the future entitlement boundary.

export type Layer = {
	part: string, z: number, x: number, y: number, rows: { string },
	clip: boolean?, hair: boolean?,
}
export type Item = {
	id: string, n: number, category: string, name: string, rarity: string, pack: string,
	priceTier: string, layers: { Layer }, trim: number?,
}
export type Pack = { id: string, name: string, suggestedPriceRobux: number }
export type Catalogue = {
	version: number, priceTiers: { [string]: number }, packs: { Pack }, items: { Item },
}

local catalogue: Catalogue = {
	version = 1,
	priceTiers = {
		accent = 3,
		standard = 5,
		statement = 8
	},
	packs = {
		{
			id = "neon_night",
			name = "Neon Night",
			suggestedPriceRobux = 24
		},
		{
			id = "frostforged",
			name = "Frostforged",
			suggestedPriceRobux = 26
		},
		{
			id = "candy_club",
			name = "Candy Club",
			suggestedPriceRobux = 22
		},
		{
			id = "void_court",
			name = "Void Court",
			suggestedPriceRobux = 24
		}
	},
	items = {
		{
			id = "neon_circuit_bomber",
			n = 1,
			category = "top",
			name = "Circuit Bomber",
			rarity = "Rare",
			pack = "neon_night",
			priceTier = "statement",
			layers = {
				{
					part = "torso",
					z = 20,
					x = 1,
					y = 0,
					rows = { "BBBBbbbbbbbbbb", "BBBBbbbbbbbbbb", "AAaaaaaaabbaaa", "AAbbaaaaabbaaa", "AAbbbbaaabbaaa", "AAaabbbbabbaaa", "AAaaaabbbbbbaa", "AAaaaaaabbbbaa", "AAaaaaaaabbaaa", "AAaaaaaaabbaaa", "AAaaaaaaabbaaa", "AAaaaaaaabbaaa", "AAaaaaaaabbaaa", "AAaaaaaaabbaaa", "AAaaaaaaabbaaa", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "BBBBBBBBBBBBBB" },
					clip = true
				},
				{
					part = "arm",
					z = 20,
					x = 1,
					y = 0,
					rows = { "Aaaa", "Aaaa", "Aaaa", "bbbb", "bbbb", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "bbbb", "bbbb" },
					clip = true
				}
			}
		},
		{
			id = "neon_sideband_joggers",
			n = 2,
			category = "bottom",
			name = "Sideband Joggers",
			rarity = "Common",
			pack = "neon_night",
			priceTier = "standard",
			layers = {
				{
					part = "pelvis",
					z = 20,
					x = 1,
					y = 0,
					rows = { "BBBBBBBBBBBB", "Ccccccccccbb", "Ccccccccccbb", "Ccccccccccbb", "Ccccccccccbb" }
				},
				{
					part = "leg",
					z = 20,
					x = 1,
					y = 0,
					rows = { "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "Ccbb", "BBBB", "BBBB" }
				}
			}
		},
		{
			id = "neon_signal_cap",
			n = 3,
			category = "headwear",
			name = "Signal Cap",
			rarity = "Uncommon",
			pack = "neon_night",
			priceTier = "standard",
			layers = {
				{
					part = "head",
					z = 60,
					x = 2,
					y = 3,
					rows = { "...xxxxxx.......", "..Xxxxxxxx......", ".XXxxbbxxxx.....", "XXXxxbbxxxx.....", "XXXXXXXXXXyyyyyy", "XXXXXXXXXXyyyyyy" }
				}
			},
			trim = 7
		},
		{
			id = "neon_voltage_sweep",
			n = 4,
			category = "hair",
			name = "Voltage Sweep",
			rarity = "Uncommon",
			pack = "neon_night",
			priceTier = "standard",
			layers = {
				{
					part = "head",
					z = 50,
					x = 2,
					y = 1,
					rows = { "...........hh...", "........hhhii...", "......hhhiiiH...", "....hhhiiiHH....", "..hhhiiiHHHHH...", ".hhhiiiHHHhhhH..", "HhhhiiHHhhhhhhH.", "HhhhhHHhhh......", "HHhhh...........", "HHhh............" },
					hair = true
				}
			}
		},
		{
			id = "neon_pulse_gloves",
			n = 5,
			category = "gloves",
			name = "Pulse Gloves",
			rarity = "Common",
			pack = "neon_night",
			priceTier = "accent",
			layers = {
				{
					part = "arm",
					z = 30,
					x = 1,
					y = 9,
					rows = { "bbbb", "bbbb", "Xxxx", "Xxxy", "Xxxy", ".XX." }
				}
			}
		},
		{
			id = "neon_nightstep_hightops",
			n = 6,
			category = "shoes",
			name = "Nightstep Hightops",
			rarity = "Uncommon",
			pack = "neon_night",
			priceTier = "standard",
			layers = {
				{
					part = "leg",
					z = 30,
					x = 1,
					y = 11,
					rows = { "ffff..", "fbbf..", "fbbf..", "Ffff..", "Ffffff", "bbbbbb" }
				}
			}
		},
		{
			id = "frost_rimeguard_coat",
			n = 7,
			category = "top",
			name = "Rimeguard Coat",
			rarity = "Rare",
			pack = "frostforged",
			priceTier = "statement",
			layers = {
				{
					part = "torso",
					z = 20,
					x = 1,
					y = 0,
					rows = { "bbbbbbbbbbbbbb", "bbbbbbbbbbbbbb", "bbbbbbbbbbbbbb", "bbbbbbbbbbbbbb", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "AAaaaaabbaaauu", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "AAAAAAAAAAAAAA", "AAAAAAAAAAAAAA" },
					clip = true
				},
				{
					part = "arm",
					z = 20,
					x = 1,
					y = 0,
					rows = { "bbbb", "bbbb", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "Aaaa", "bbbb", "bbbb" },
					clip = true
				}
			}
		},
		{
			id = "frost_ridgeguard_trousers",
			n = 8,
			category = "bottom",
			name = "Ridgeguard Trousers",
			rarity = "Common",
			pack = "frostforged",
			priceTier = "standard",
			layers = {
				{
					part = "pelvis",
					z = 20,
					x = 1,
					y = 0,
					rows = { "BBBBBBBBBBBB", "Cccccccccccc", "Cccccccccccc", "Cccccccccccc", "Cccccccccccc" }
				},
				{
					part = "leg",
					z = 20,
					x = 1,
					y = 0,
					rows = { "Cccc", "Cccc", "Cccc", "Cccc", "Cccc", "Cccc", "BBBB", "bbbb", "bbbb", "Cccc", "Cccc", "Cccc", "Cccc", "Cccc" }
				}
			}
		},
		{
			id = "frost_snowline_beanie",
			n = 9,
			category = "headwear",
			name = "Snowline Beanie",
			rarity = "Uncommon",
			pack = "frostforged",
			priceTier = "standard",
			layers = {
				{
					part = "head",
					z = 60,
					x = 2,
					y = 0,
					rows = { ".....bbb......", ".....bbb......", "...xxxxxxx....", "..Xxxxxxxxx...", ".XXxxxxxxxxx..", "XXXxxxxxxxxxx.", "XXXxxxxxxxxxx.", "bbbbbbbbbbbbbb", "BBBBBBBBBBBBBB" }
				}
			},
			trim = 8
		},
		{
			id = "frost_whiteout_halfcape",
			n = 10,
			category = "neck",
			name = "Whiteout Halfcape",
			rarity = "Rare",
			pack = "frostforged",
			priceTier = "statement",
			layers = {
				{
					part = "torso",
					z = 30,
					x = 0,
					y = 0,
					rows = { "..bbbbbbbbbbbb..", "bbbbbbbbbbbbbb..", "BBb.........bb..", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "BBb.............", "xxb.............", "xxb.............", "xxb............." }
				},
				{
					part = "pelvis",
					z = 27,
					x = 0,
					y = 0,
					rows = { "BBb..", "BBb..", "BBb..", "BBbb.", "BBbb.", "BBbb.", "BBbbb", "BBbbb", "xxxxx", "XXXXX" }
				}
			}
		},
		{
			id = "frost_icebreak_mitts",
			n = 11,
			category = "gloves",
			name = "Icebreak Mitts",
			rarity = "Common",
			pack = "frostforged",
			priceTier = "accent",
			layers = {
				{
					part = "arm",
					z = 30,
					x = 1,
					y = 9,
					rows = { "XXXX", "xxxx", "bbbb", "bbbb", "Bbbb", ".BB." }
				}
			}
		},
		{
			id = "frost_snowdrift_boots",
			n = 12,
			category = "shoes",
			name = "Snowdrift Boots",
			rarity = "Uncommon",
			pack = "frostforged",
			priceTier = "standard",
			layers = {
				{
					part = "leg",
					z = 30,
					x = 1,
					y = 9,
					rows = { "bbbb..", "bbbb..", "Ffff..", "Ffff..", "Ffff..", "Ffff..", "Ffffff", "BBBBBB" }
				}
			}
		},
		{
			id = "candy_sugarstripe_tee",
			n = 13,
			category = "top",
			name = "Sugarstripe Tee",
			rarity = "Common",
			pack = "candy_club",
			priceTier = "statement",
			layers = {
				{
					part = "torso",
					z = 20,
					x = 1,
					y = 0,
					rows = { "BBBBbbbbbbbbbb", "AAaaaaaaaaaaaa", "AAaaaaaaaaaaaa", "AAaaaaaaaaaaaa", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "AAaaaaaaaaaaaa", "AAaaaaaaaaaaaa", "AAaaaaaaaaaaaa", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "AAaaaaaaaaaaaa", "AAaaaaaaaaaaaa", "AAaaaaaaaaaaaa", "AAAAAAAAAAAAAA", "AAAAAAAAAAAAAA" },
					clip = true
				},
				{
					part = "arm",
					z = 20,
					x = 1,
					y = 0,
					rows = { "Aaaa", "Aaaa", "Aaaa", "bbbb", "bbbb" },
					clip = true
				}
			}
		},
		{
			id = "candy_bonbon_shorts",
			n = 14,
			category = "bottom",
			name = "Bonbon Shorts",
			rarity = "Common",
			pack = "candy_club",
			priceTier = "standard",
			layers = {
				{
					part = "pelvis",
					z = 20,
					x = 1,
					y = 0,
					rows = { "BBBBBBBBBBBB", "Cccccccccccc", "Cccccccccccc", "Cccccccccccc", "Cccccccccccc" }
				},
				{
					part = "leg",
					z = 20,
					x = 1,
					y = 0,
					rows = { "Cccc", "Cccc", "Cccc", "Cccc", "bbbb", "bbbb" }
				}
			}
		},
		{
			id = "candy_sundae_beret",
			n = 15,
			category = "headwear",
			name = "Sundae Beret",
			rarity = "Uncommon",
			pack = "candy_club",
			priceTier = "standard",
			layers = {
				{
					part = "head",
					z = 60,
					x = 1,
					y = 1,
					rows = { "........bb......", "........bb......", "....xxxxxxxx....", "..Xxxxxxxxxxxx..", ".XXxxxxxxxxxxxx.", "XXXxxxxxxxxxxx..", "XXXxxxxxxxxxx...", "..BBBBBBBBBBB..." }
				}
			},
			trim = 7
		},
		{
			id = "candy_softserve_swirl",
			n = 16,
			category = "hair",
			name = "Softserve Swirl",
			rarity = "Rare",
			pack = "candy_club",
			priceTier = "standard",
			layers = {
				{
					part = "head",
					z = 50,
					x = 2,
					y = 0,
					rows = { "......hh......", ".....hiiH.....", "....hiiiHH....", "..hhhiiHHH....", ".hhiiHHhhhh...", "hhiiiHhhhiiH..", "hhiiHHhhiiiHH.", "HhhhhhhhiiHHH.", "HHhhhhhhhhHH..", "HHhh.........." },
					hair = true
				}
			}
		},
		{
			id = "candy_sugarstar_specs",
			n = 17,
			category = "eyewear",
			name = "Sugarstar Specs",
			rarity = "Uncommon",
			pack = "candy_club",
			priceTier = "accent",
			layers = {
				{
					part = "head",
					z = 55,
					x = 2,
					y = 8,
					rows = { ".......x....x..", "......xyx..xyx.", "xxxxxxxyyyyyyyx", "......xyx..xyx.", ".......x....x.." }
				}
			}
		},
		{
			id = "candy_taffy_trainers",
			n = 18,
			category = "shoes",
			name = "Taffy Trainers",
			rarity = "Common",
			pack = "candy_club",
			priceTier = "standard",
			layers = {
				{
					part = "leg",
					z = 30,
					x = 1,
					y = 12,
					rows = { "ffff..", "ffbb..", "Ffbbb.", "Ffffff", "bbbbbb" }
				}
			}
		},
		{
			id = "void_eventide_vest",
			n = 19,
			category = "top",
			name = "Eventide Vest",
			rarity = "Uncommon",
			pack = "void_court",
			priceTier = "statement",
			layers = {
				{
					part = "torso",
					z = 20,
					x = 1,
					y = 0,
					rows = { "AAbbaaaaaabbaa", "AAabbaaaabbaaa", "AAabbbaabbbaaa", "AAaabbbbbbbaaa", "AAaaabbbbbaaaa", "AAaaaabbbaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "AAaaaaabaaaaaa", "BBbbbbbbbbbbbb", "BBbbbbbbbbbbbb", "AAAAAAAAAAAAAA", "AAAAAAAAAAAAAA" },
					clip = true
				}
			}
		},
		{
			id = "void_rift_pleats",
			n = 20,
			category = "bottom",
			name = "Rift Pleats",
			rarity = "Uncommon",
			pack = "void_court",
			priceTier = "standard",
			layers = {
				{
					part = "pelvis",
					z = 26,
					x = 0,
					y = 0,
					rows = { ".BBBBBBBBBBBB.", ".CCccCCccCCcc.", ".CCccCCccCCcc.", ".CCccCCccCCcc.", "CCCccCCccCCccc", "CCCccCCccCCccc", "CCCccCCccCCccc", "CCCccCCccCCccc", "BBBbbbbbbbbbbb" }
				}
			}
		},
		{
			id = "void_comet_tail",
			n = 21,
			category = "hair",
			name = "Comet Tail",
			rarity = "Rare",
			pack = "void_court",
			priceTier = "standard",
			layers = {
				{
					part = "head",
					z = 10,
					x = 0,
					y = 5,
					rows = { ".HHh.", "HHhhi", "HHhhi", "HHhhi", "HHhhi", "HHhhi", "HHhhi", ".HHhi", ".HHhi", "..Hhi", "..Hhi", "...Hi", "...HH" },
					hair = true
				},
				{
					part = "head",
					z = 50,
					x = 3,
					y = 3,
					rows = { "..hhhhhhhh....", ".Hhhiiiiihhh..", "HHhiiiiihhhhH.", "HHhhhhhhhhhhhH", "HHhhh.........", "HHhh.........." },
					hair = true
				}
			}
		},
		{
			id = "void_eclipse_mantle",
			n = 22,
			category = "neck",
			name = "Eclipse Mantle",
			rarity = "Epic",
			pack = "void_court",
			priceTier = "statement",
			layers = {
				{
					part = "torso",
					z = 30,
					x = 0,
					y = 0,
					rows = { "..Xxxxxxxxxxbb..", ".XXxxxxxxxxbyb..", "XXX........bbb..", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "XXx.............", "Xbb.............", "Xbb.............", "Xbb.............", "Xbb............." }
				},
				{
					part = "pelvis",
					z = 27,
					x = 0,
					y = 0,
					rows = { "XXxx..", "XXxx..", "XXxx..", "XXxx..", "XXxxx.", "XXxxx.", "XXxxxx", "Xbbxxx", "bbbxxx", ".BB..." }
				}
			}
		},
		{
			id = "void_orbit_cuffs",
			n = 23,
			category = "gloves",
			name = "Orbit Cuffs",
			rarity = "Uncommon",
			pack = "void_court",
			priceTier = "accent",
			layers = {
				{
					part = "arm",
					z = 30,
					x = 1,
					y = 7,
					rows = { "bbbb", "bbbb", "Xxxx", "Xxxx", "bbbb", "bbbb" }
				}
			}
		},
		{
			id = "void_null_visor",
			n = 24,
			category = "eyewear",
			name = "Null Visor",
			rarity = "Rare",
			pack = "void_court",
			priceTier = "accent",
			layers = {
				{
					part = "head",
					z = 55,
					x = 3,
					y = 8,
					rows = { "XXXXXXXXXXXXX", "XxxxxyyyyyyyX", "XxxxxyyyyyyyX", "XXXXXXXXXXXXX" }
				}
			}
		}
	}
}

return catalogue
