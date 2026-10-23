-- The matches that found fighters inside solid ground (the 2026-10-22 bug hunt), replayed with
-- tools/fuzz-matches' every-frame checks, which must all hold. Each seed is one way in:
--   2     a rising fighter passed up through a solid: the ceiling check missed by a rounding error
--   131   a grab placed its victim inside Saltflat's bunker (before the later fixes changed its course)
--   285   the same: a grabbed fighter held inside a solid
--   137   falling past a block's top corner, into the band beside it, and on into it
--   244   Redline Reversal (Rocket Boots' ultimate) ran through the bunker
--   1016  an ultimate's vortex dragged its victim through the bunker (found it)
--   1311  the same, still needing the vortex fix after the others
--   1254  a whip's pull put a victim stepping off an edge back over the island just under its surface,
--         where no landing catches you: they fell through the floor
local process = require("@lune/process")
local r = process.exec("lune", { "run", "tools/fuzz-matches" }, { env = { FUZZ_SEEDS = "2,131,137,244,285,1016,1311,1254", FUZZ_STRICT = "1" } })
print(r.stdout)
if not r.ok then error("fuzzed matches found fighters inside solid ground (or another broken invariant):\n" .. r.stdout .. r.stderr, 0) end
print("PASS solid ground: eight matches that found ways into solids, replayed with every invariant checked each frame")
