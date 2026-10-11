--!strict
-- Faces that act: a kit character's face reacts to what the fighter is doing. Roblox only (the web
-- build is left as it is, 2026-10-11), so this is tested directly by tests/expressions.luau rather
-- than replayed.
--
-- AN EXPRESSION IS THE PLAYER'S OWN FACE, CHANGED. It swaps the chosen eyes, brows and mouth for
-- catalogue options that carry the feeling - effort is fierce eyes, angry brows and a shout - and
-- everything else stays: skull, colours, hair, nose, beard, eyewear, hat. Where the player chose
-- something distinctive it survives: no brows stays no brows, glowing or anime eyes stay glowing or
-- anime except where the eyes must close. Covered faces change only what shows: behind shades the
-- eyes are left alone, under a knight's helm nothing changes at all. The catalogue has no crossed
-- dizzy eyes and no closed glowing, lashed or anime eyes, so those few are drawn here.
--
-- WHAT IT COSTS. Each expression is its own head picture, composed once per character and cached
-- (bounded), and on screen its own sprite - which Canvas2D keeps, hidden, for ten seconds after it
-- was last drawn, so a face that comes back is a visibility flip, not a rebuild. A face holds for at
-- least HOLD frames (Expressions.held), so a one-frame state cannot flicker it. And an expression
-- whose half-resolution head comes out identical to the neutral one is not drawn as a second
-- picture at half detail: a small fighter never pays for a face nobody can see change.
--
-- Designed with GPT (through Codex) drafting the table and the coverage, checked against the grids.

local AvatarKit = require(game:GetService("ReplicatedStorage").Shared.AvatarKit)
local AvatarCompose = require(script.Parent.AvatarCompose)
local Channels = require(script.Parent.Channels)

local Expressions = {}

Expressions.LIST = { "blink", "focused", "effort", "hurt", "startled", "delighted", "dejected", "smug", "dizzy", "determined" }
Expressions.HOLD = 4          -- frames a face holds before it may change
Expressions.BLINK_EVERY = 210 -- frames between blinks (3.5 s), offset per fighter
Expressions.BLINK_FOR = 5
Expressions.CACHE_MAX = 128   -- composed heads kept, character x expression

-- What each expression makes of the eyes, brows and mouth. "@..." is a layer drawn below.
local TABLE: { [string]: { [string]: string } } = {
	blink = { eyes = "closed" },
	focused = { eyes = "fierce", brows = "angry", mouth = "tight" },
	effort = { eyes = "fierce", brows = "angry", mouth = "shout" },
	hurt = { eyes = "closed", brows = "worried", mouth = "open" },
	startled = { eyes = "wide", brows = "raised", mouth = "oh" },
	delighted = { eyes = "happy", brows = "raised", mouth = "grin" },
	dejected = { eyes = "tired", brows = "worried", mouth = "frown" },
	smug = { eyes = "wink", brows = "arched", mouth = "smirk" },
	dizzy = { eyes = "@dizzy", brows = "worried", mouth = "zigzag" },
	determined = { eyes = "angry", brows = "angry", mouth = "tight" },
}

-- A player's distinctive choices that an expression keeps.
local KEEP_BROWS = { none = true, unibrow = true, scarred = true }
local KEEP_EYES = { glow = true, anime = true, lashes = true }          -- except where eyes close
local KEEP_MOUTH: { [string]: { [string]: boolean } } = {
	fangs = { delighted = true, smug = true, determined = true },
	tongue = { delighted = true },
}

-- Closed versions of the eyes the catalogue never closes, and dizzy eyes. On the head canvas, in the
-- catalogue's own format, at the eyes' layer height so everything that sits over eyes still does.
local function headLayer(x: number, y: number, rows: { string }): { any }
	return { { part = "head", z = 30, x = x, y = y, rows = rows } }
end
local CLOSED: { [string]: { any } } = {
	-- a glow closes to a slit: the open eyes' lower row only (GPT's first draft was the open eyes,
	-- cell for cell - caught by the face sheet, and by tests/expressions.luau since)
	glow = headLayer(9, 11, { "ee..e" }),
	lashes = headLayer(8, 10, { "..kkkk.", ".kk..k." }),
	anime = headLayer(8, 10, { ".kkk.k.", ".kk..k." }),
}
local DIZZY = headLayer(8, 9, { "k.k.k.k", ".e...e.", "k.k.k.k" })

-- What covers the face. Eyewear whose lenses are painted across the eyes hides them; brimmed and
-- knitted hats sit on the brow rows. (A knight's helm needs no rule: it is drawn over the whole face,
-- so no expression shows through it - tests/expressions.luau holds that.)
local COVERS_EYES = { shades = true, goggles = true, visor = true, ["3d"] = true, eyepatch = true }
local COVERS_BROWS = { beanie = true, cap = true, backcap = true, headband = true, beret = true, viking = true }

-- The parts an expression draws for this character, and the layers to override (or nil).
function Expressions.specFor(spec: AvatarKit.Spec, expr: string): (AvatarKit.Spec, { [string]: { any } }?)
	local want = TABLE[expr]
	local parts = table.clone(spec.parts)
	local out: AvatarKit.Spec = { parts = parts, colours = spec.colours }
	if not want then
		return out, nil
	end
	local override: { [string]: { any } }? = nil
	local eyes = want.eyes
	if eyes and not COVERS_EYES[parts.eyewear] then
		local own = parts.eyes
		if eyes == "@dizzy" then
			override = { eyes = DIZZY }
		elseif eyes == "closed" and CLOSED[own] then
			override = { eyes = CLOSED[own] }
		elseif eyes ~= "closed" and KEEP_EYES[own] then
			-- the player's glowing, anime or lashed eyes stay themselves
		else
			parts.eyes = eyes
		end
	end
	if want.brows and not KEEP_BROWS[parts.brows] and not COVERS_BROWS[parts.headwear] then
		parts.brows = want.brows
	end
	if want.mouth and not (KEEP_MOUTH[parts.mouth] and KEEP_MOUTH[parts.mouth][expr]) then
		parts.mouth = want.mouth
	end
	return out, override
end

local function sameRects(a: { any }, b: { any }): boolean
	if #a ~= #b then
		return false
	end
	for i, r in a do
		local q = b[i]
		for j = 1, 6 do
			if r[j] ~= q[j] then
				return false
			end
		end
	end
	return true
end

-- The head this character makes with this expression: { full, half, sameFull, sameHalf }, where
-- `same*` says the picture is identical to the neutral head at that resolution (draw the neutral
-- one instead). Cached, least recently used first out.
local cache: { [string]: any } = {}
local order: { string } = {}
function Expressions.head(code: string, expr: string): any
	local key = code .. "|" .. expr
	local hit = cache[key]
	if hit then
		return hit
	end
	local spec = AvatarKit.decode(code) or AvatarKit.sanitize(nil)
	local exprSpec, override = Expressions.specFor(spec, expr)
	local neutral = AvatarCompose.sprites(code).head
	local g = AvatarCompose.compose(exprSpec, override).head
	local full = AvatarCompose.piece(g)
	local half = AvatarCompose.piece(AvatarCompose.halve(g))
	local made = { full = full, half = half, sameFull = sameRects(full, neutral.full), sameHalf = sameRects(half, neutral.half) }
	cache[key] = made
	table.insert(order, key)
	if #order > Expressions.CACHE_MAX then
		cache[table.remove(order, 1) :: string] = nil
	end
	return made
end
function Expressions.cacheSize(): number
	return #order
end

-- What the fighter's face is doing this frame, from its state alone (nil: their own face).
-- `small`: drawn at half detail, where only every third blink happens.
function Expressions.of(s: any, move: any, small: boolean): string?
	local st = s.state
	if st == "victory" then
		return "delighted"
	elseif st == "defeat" then
		return "dejected"
	elseif st == "stunned" then
		return "dizzy"
	elseif (s.tumbling and (st == "air" or st == "hitstun")) or st == "flung" then
		return "startled"
	elseif st == "hitstun" or st == "knockdown" or st == "grabbed" or st == "frozen" then
		return "hurt"
	elseif st == "attack" and move then
		if move.id == "Ultimate" then
			return "effort"
		end
		local w = Channels.swing(s, move)
		if w.phase == "wind" then
			return "focused"
		end
		-- the strike's face carries into the first third of the recovery, so a two-frame active
		-- window still shows effort for long enough to read
		if w.phase == "strike" or w.k < 0.35 then
			return "effort"
		end
	elseif st == "groundpound" then
		return if s.stateFrame <= 8 then "focused" else "effort"
	elseif st == "taunt" then
		return "smug"
	end
	-- an otherwise neutral face: determined on the last stock, and blinking
	local fc = (s.frameCount or 0) + 37 * (s.index or 0)
	local cycle = fc // Expressions.BLINK_EVERY
	if fc % Expressions.BLINK_EVERY < Expressions.BLINK_FOR and (not small or cycle % 3 == 0) then
		return "blink"
	end
	return if s.stocks == 1 then "determined" else nil
end

-- The face actually shown: a new expression is taken only once the last one has held HOLD frames
-- (victory and defeat at once). One small record per fighter, per loadout - a preview and a match
-- never share one - forgotten when the loadout is, and started afresh when the frame count jumps
-- (a replay, a new match, a preview posing an arbitrary frame).
local holds: { [any]: { [number]: { expr: string?, from: number, at: number } } } = setmetatable({} :: any, { __mode = "k" })
function Expressions.held(char: any, s: any, expr: string?): string?
	local per = holds[char]
	if not per then
		per = {}
		holds[char] = per
	end
	local i, fc = s.index or 0, s.frameCount or 0
	local h = per[i]
	if not h or fc < h.at or fc > h.at + 30 then
		per[i] = { expr = expr, from = fc, at = fc }
		return expr
	end
	h.at = fc
	if expr ~= h.expr and (fc - h.from >= Expressions.HOLD or expr == "delighted" or expr == "dejected") then
		h.expr, h.from = expr, fc
	end
	return h.expr
end

return Expressions
