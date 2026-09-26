--!nocheck
-- GENERATED FILE - DO NOT EDIT.
--
-- Emitted from web/src/data/rules.js by roblox/tools/gen-data.mjs, which check.sh runs on every invocation.
-- Edit the JavaScript and re-run; anything typed in here is overwritten without warning.
--
-- `--!nocheck` because this is a literal data table with no logic in it: strict mode would
-- produce thousands of inferred-shape errors and check nothing that tests/data-parity.luau does
-- not already check field by field against the JavaScript.

return {
	modes = {
		{
			id = "stock",
			name = "Stock",
			hint = "Last one with lives left wins.",
		},
		{
			id = "timed",
			name = "Timed",
			hint = "Most KOs when the clock runs out.",
		},
	},
	stocks = { 1, 2, 3, 4, 5 },
	times = { 120, 180, 240, 300 },
	disasters = { "off", "stage", "chaos" },
	mapChoices = { "host", "vote", "random" },
	mapSets = { "all", "ranked" },
	presets = {
		{
			id = "tournament",
			name = "Tournament 1v1",
			hint = "3 lives, no items or disasters, ranked maps by vote.",
			rules = {
				mode = "stock",
				stocks = 3,
				time = 180,
				items = false,
				disasters = "off",
				mapChoice = "vote",
				mapSet = "ranked",
			},
		},
		{
			id = "casual",
			name = "Casual",
			hint = "3 lives, items on, each map brings its own disaster.",
			rules = {
				mode = "stock",
				stocks = 3,
				time = 180,
				items = true,
				disasters = "stage",
				mapChoice = "host",
				mapSet = "all",
			},
		},
		{
			id = "chaos",
			name = "Chaos",
			hint = "Three minutes on the clock, every disaster, a random map.",
			rules = {
				mode = "timed",
				stocks = 3,
				time = 180,
				items = true,
				disasters = "chaos",
				mapChoice = "random",
				mapSet = "all",
			},
		},
	},
}
