--!strict
-- Where the touch controls go (Roblox only; the owner's ask, 2026-11-02: phones and tablets play
-- with buttons on the screen, laid out for each device, and moved and resized in Settings the way
-- Fortnite's mobile HUD editor does).
--
-- Pure: a screen's size in, every control's circle out. Everything is measured in M, one main
-- button's diameter, which is a share of the screen's SHORT side (clamped), so one layout is right
-- on a 568x320 phone and a 2732x2048 tablet alike: the thumb, not the screen, sets the size. A
-- phone (short side under TABLET_FROM) and a tablet keep separate customisations, as their hands
-- sit differently. tests/touch-layout holds every default on screen, apart and big enough to hit
-- at sizes from the smallest phone to the largest tablet.
local TouchLayout = {}

TouchLayout.TABLET_FROM = 600           -- short side, in Roblox's logical pixels
TouchLayout.MIN_TOUCH = 44              -- the smallest thing a thumb can hit reliably (px)

-- The controls. `action`: what it presses (Bindings' action ids); the stick moves. `size`: its
-- diameter in M. `x`, `y`: its centre in M from its corner (`side`: "left" from the bottom-left,
-- "right" from the bottom-right; up and inward are positive). `lobby`: shown in the lobby too
-- (walking and jumping; everything else there is a button already).
TouchLayout.CONTROLS = {
	{ id = "stick", side = "left", x = 1.75, y = 1.75, size = 2.3, lobby = true },
	{ id = "light", action = "light", side = "right", x = 1.3, y = 1.2, size = 1.15, label = "ATTACK" },
	{ id = "heavy", action = "heavy", side = "right", x = 2.75, y = 0.8, size = 0.95, label = "HEAVY" },
	-- (in the lobby JUMP sits low, just over the lobby's buttons: `lobbyY`)
	{ id = "jump", action = "jump", side = "right", x = 1.05, y = 2.7, size = 0.95, label = "JUMP", lobby = true, lobbyY = 0.6 },
	{ id = "dodge", action = "dodge", side = "right", x = 2.45, y = 2.1, size = 0.8, label = "DODGE" },
	{ id = "guard", action = "guard", side = "right", x = 3.75, y = 1.5, size = 0.8, label = "SHIELD" },
	{ id = "grab", action = "grab", side = "right", x = 4.0, y = 0.55, size = 0.8, label = "GRAB" },
	-- (the fan stops at 3.73 M: an iPhone SE's 320 px leaves 3.8 under the HUD's top band)
	{ id = "ult", action = "ult", side = "right", x = 2.0, y = 3.3, size = 0.85, label = "ULT" },
	{ id = "pickup", action = "pickup", side = "right", x = 3.45, y = 2.75, size = 0.8, label = "PICK UP" },
} :: { any }
local BY_ID: { [string]: any } = {}
for _, c in TouchLayout.CONTROLS do BY_ID[c.id] = c end
TouchLayout.BY_ID = BY_ID

TouchLayout.SCALE_MIN, TouchLayout.SCALE_MAX = 0.6, 1.6
TouchLayout.OPACITY_MIN, TouchLayout.OPACITY_MAX, TouchLayout.OPACITY = 0.2, 1, 0.65

-- "phone" or "tablet", by the screen's short side.
function TouchLayout.class(w: number, h: number): string
	return if math.min(w, h) >= TouchLayout.TABLET_FROM then "tablet" else "phone"
end
-- M, a main button's diameter in px: 17% of the short side, kept between 56 and 96 (a tablet's
-- buttons a little smaller for their screen than a phone's, as its hands rest further in).
function TouchLayout.unit(w: number, h: number): number
	local short = math.min(w, h)
	local share = if TouchLayout.class(w, h) == "tablet" then 0.13 else 0.17
	return math.clamp(short * share, 56, 96)
end
-- The margin kept from every edge.
function TouchLayout.margin(w: number, h: number): number
	return math.max(10, math.floor(math.min(w, h) * 0.03))
end

local function finite(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v then return nil end
	return math.clamp(v, lo, hi)
end
-- A player's changes as they may be stored: { phone = { [id] = { dx, dy, s } }, tablet = ..., opacity }.
-- dx and dy are in M from the control's default place, s its size multiplier.
function TouchLayout.sanitize(raw: any): any
	local src = if type(raw) == "table" then raw else {}
	local out = { opacity = finite(src.opacity, TouchLayout.OPACITY_MIN, TouchLayout.OPACITY_MAX) or TouchLayout.OPACITY }
	for _, class in { "phone", "tablet" } do
		local mine = {}
		local given = if type(src[class]) == "table" then src[class] else {}
		for _, c in TouchLayout.CONTROLS do
			local e = given[c.id]
			if type(e) == "table" then
				local dx, dy = finite(e.dx, -40, 40) or 0, finite(e.dy, -40, 40) or 0
				local s = finite(e.s, TouchLayout.SCALE_MIN, TouchLayout.SCALE_MAX) or 1
				if dx ~= 0 or dy ~= 0 or s ~= 1 then mine[c.id] = { dx = dx, dy = dy, s = s } end
			end
		end
		out[class] = mine
	end
	return out
end

-- Every control's circle on a w x h screen: { [id] = { x, y (centre, px from the top-left), r } }.
-- `custom`: TouchLayout.sanitize's table (nil: the defaults). `lift`: px kept clear along the
-- bottom on the right (the lobby's own button row, at its bottom right). A circle is always kept
-- wholly on screen, inside the margin.
function TouchLayout.layout(w: number, h: number, custom: any?, lift: number?): { [string]: any }
	local m = TouchLayout.unit(w, h)
	local margin = TouchLayout.margin(w, h)
	local mine = (custom and custom[TouchLayout.class(w, h)]) or {}
	local out = {}
	for _, c in TouchLayout.CONTROLS do
		local e = mine[c.id]
		local r = c.size * m * (if e then e.s else 1) / 2
		local cx = (c.x + (if e then e.dx else 0)) * m
		local cy = ((if lift and c.lobbyY then c.lobbyY else c.y) + (if e then e.dy else 0)) * m
		local x = if c.side == "left" then margin + cx else w - margin - cx
		local y = h - margin - (if c.side == "right" then lift or 0 else 0) - cy
		x = math.clamp(x, margin + r, w - margin - r)
		y = math.clamp(y, margin + r, h - margin - r)
		out[c.id] = { x = x, y = y, r = r }
	end
	return out
end

-- Where a control dragged to (x, y) on screen would be stored, as an offset from its default in M
-- (the editor's drag). Kept inside the screen, as layout keeps it.
function TouchLayout.offsetFor(w: number, h: number, id: string, x: number, y: number, lift: number?): (number, number)
	local c = BY_ID[id]
	local m = TouchLayout.unit(w, h)
	local margin = TouchLayout.margin(w, h)
	local cy = (h - margin - (if c.side == "right" then lift or 0 else 0) - y) / m
	local cx = if c.side == "left" then (x - margin) / m else (w - margin - x) / m
	return cx - c.x, cy - (if lift and c.lobbyY then c.lobbyY else c.y)
end

-- What a touch screen calls an action's control (the tutorial's cards): its button's word, or the
-- stick for a direction.
local STICK = { left = "STICK LEFT", right = "STICK RIGHT", up = "STICK UP", down = "STICK DOWN" }
function TouchLayout.labelFor(action: string): string
	if STICK[action] then return STICK[action] end
	for _, c in TouchLayout.CONTROLS do
		if c.action == action then return c.label or string.upper(action) end
	end
	return string.upper(action)
end
-- Pairs of controls whose circles overlap (the editor warns; the defaults never do).
function TouchLayout.overlaps(placed: { [string]: any }): { { string } }
	local out = {}
	for i, a in TouchLayout.CONTROLS do
		for j = i + 1, #TouchLayout.CONTROLS do
			local b = TouchLayout.CONTROLS[j]
			local p, q = placed[a.id], placed[b.id]
			if p and q and math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2) < p.r + q.r then table.insert(out, { a.id, b.id }) end
		end
	end
	return out
end

return TouchLayout
