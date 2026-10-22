-- Every cosmetic and crate picture draws, inside its tile, at every tile size the game uses, with no
-- NaN rects and no magenta "missing colour" (tools/sweep-art.luau does the drawing; this runs it).
-- Found in the 2026-10-22 bug hunt: titles drew nothing; Ghost Rise drew 349 px past its tile.
require("../tools/sweep-art")
print("PASS item art: every cosmetic and crate draws, inside its tile, at every tile size")
