--!strict
-- The character itself: head shape, face, headgear and the mark on the chest.
--
-- A port of web/src/render2d/avatar2d.js. These four choices are everything a fighter owns beyond
-- its five colours, and in the web build they live in one file for one reason: the character
-- creator's preview has to be the SAME drawing as the match. That reason still holds here, and the
-- creator is a later phase, so keeping them together keeps that possible.
--
-- Local space is the head's own: +Y up, one unit = one stud, origin at the neck joint. Every shape
-- reports the box it occupied so the face and the hat can sit on it without knowing which head
-- shape was picked - that is what lets a crown fit a round head and a tall one.
--
-- The curved hood of the JavaScript becomes a stepped one. Canvas2D cannot fill a quadratic and a
-- six-step triangle reads as a triangle on art this blocky; see the note at the top of Weapons2D
-- for the same trade made for the same reason.

local Canvas2D = require(script.Parent.Canvas2D)

local Avatar2D = {}

local EYE = Color3.fromRGB(27, 21, 38)

export type Box = { x0: number, y0: number, w: number, h: number }
export type Pal = { primary: Color3, secondary: Color3, tertiary: Color3, accent: Color3, glow: Color3 }

-- ---------------------------------------------------------------- heads ----
-- Each returns the drawn box, in head-scale units.
local HEADS: { [string]: (any, number, Pal) -> Box } = {
	block = function(c, hs, _p)
		Canvas2D.rect(c, -hs / 2, -hs * 0.15, hs, hs, _p.primary)
		return { x0 = -hs / 2, y0 = -hs * 0.15, w = hs, h = hs }
	end,
	round = function(c, hs, _p)
		Canvas2D.circle(c, 0, hs * 0.35, hs * 0.52, _p.primary)
		return { x0 = -hs * 0.52, y0 = hs * 0.35 - hs * 0.52, w = hs * 1.04, h = hs * 1.04 }
	end,
	tall = function(c, hs, _p)
		Canvas2D.rect(c, -hs * 0.38, -hs * 0.15, hs * 0.76, hs * 1.24, _p.primary)
		return { x0 = -hs * 0.38, y0 = -hs * 0.15, w = hs * 0.76, h = hs * 1.24 }
	end,
	wide = function(c, hs, _p)
		Canvas2D.rect(c, -hs * 0.64, -hs * 0.06, hs * 1.28, hs * 0.82, _p.primary)
		return { x0 = -hs * 0.64, y0 = -hs * 0.06, w = hs * 1.28, h = hs * 0.82 }
	end,
}

-- ---------------------------------------------------------------- faces ----
-- Drawn forward of centre, because every fighter in this game is seen from the side and faces +X.
local FACES: { [string]: (any, Pal, Box) -> () } = {
	dot = function(c, _p, k)
		Canvas2D.rect(c, k.x0 + k.w * 0.52, k.y0 + k.h * 0.52, k.w * 0.20, k.h * 0.20, EYE)
	end,
	pair = function(c, _p, k)
		Canvas2D.rect(c, k.x0 + k.w * 0.56, k.y0 + k.h * 0.54, k.w * 0.16, k.h * 0.18, EYE)
		Canvas2D.rect(c, k.x0 + k.w * 0.28, k.y0 + k.h * 0.54, k.w * 0.13, k.h * 0.16, EYE)
	end,
	visor = function(c, p, k)
		Canvas2D.rect(c, k.x0 + k.w * 0.10, k.y0 + k.h * 0.46, k.w * 0.86, k.h * 0.26, EYE)
		Canvas2D.rect(c, k.x0 + k.w * 0.14, k.y0 + k.h * 0.52, k.w * 0.78, k.h * 0.12, p.glow)
	end,
	shades = function(c, _p, k)
		Canvas2D.rect(c, k.x0 + k.w * 0.44, k.y0 + k.h * 0.48, k.w * 0.34, k.h * 0.22, EYE)
		Canvas2D.rect(c, k.x0 + k.w * 0.14, k.y0 + k.h * 0.48, k.w * 0.24, k.h * 0.20, EYE)
		Canvas2D.rect(c, k.x0 + k.w * 0.36, k.y0 + k.h * 0.58, k.w * 0.10, k.h * 0.06, EYE)  -- the bridge
	end,
	goggles = function(c, p, k)
		Canvas2D.rect(c, k.x0, k.y0 + k.h * 0.50, k.w, k.h * 0.16, p.tertiary)               -- the strap
		Canvas2D.circle(c, k.x0 + k.w * 0.62, k.y0 + k.h * 0.58, k.w * 0.17, p.accent)
		Canvas2D.circle(c, k.x0 + k.w * 0.28, k.y0 + k.h * 0.58, k.w * 0.14, p.accent)
		Canvas2D.circle(c, k.x0 + k.w * 0.62, k.y0 + k.h * 0.58, k.w * 0.10, EYE)
		Canvas2D.circle(c, k.x0 + k.w * 0.28, k.y0 + k.h * 0.58, k.w * 0.08, EYE)
	end,
	blank = function() end,
}

-- ---------------------------------------------------------------- hats ----
local HATS: { [string]: (any, Pal, Box) -> () } = {
	none = function() end,
	cap = function(c, p, k)
		Canvas2D.rect(c, k.x0 + k.w * 0.06, k.y0 + k.h * 0.80, k.w * 0.88, k.h * 0.26, p.secondary)  -- dome
		Canvas2D.rect(c, k.x0 + k.w * 0.55, k.y0 + k.h * 0.74, k.w * 0.62, k.h * 0.10, p.secondary)  -- brim
		Canvas2D.rect(c, k.x0 + k.w * 0.06, k.y0 + k.h * 0.98, k.w * 0.88, k.h * 0.06, p.accent)
	end,
	horns = function(c, p, k)
		for _, dir in { -1, 1 } do
			local x = k.x0 + k.w * (if dir < 0 then 0.18 else 0.82)
			Canvas2D.tri(c,
				x + dir * k.w * 0.22, k.y0 + k.h * 1.30,
				x - k.w * 0.09, k.y0 + k.h * 0.86,
				x + k.w * 0.09, k.y0 + k.h * 0.86, p.accent)
		end
	end,
	crown = function(c, p, k)
		-- Four points on a band. The JavaScript draws it as one polygon; four triangles on a bar is
		-- the same silhouette and is four shapes a Frame can actually be.
		Canvas2D.rect(c, k.x0 + k.w * 0.08, k.y0 + k.h * 0.86, k.w * 0.84, k.h * 0.10, p.glow)
		for i = 0, 3 do
			local u = k.x0 + k.w * (0.08 + (i + 0.5) * 0.21)
			Canvas2D.tri(c, u, k.y0 + k.h * 1.24,
				u - k.w * 0.05, k.y0 + k.h * 0.94,
				u + k.w * 0.105, k.y0 + k.h * 0.94, p.glow)
		end
	end,
	antenna = function(c, p, k)
		Canvas2D.rect(c, k.x0 + k.w * 0.46, k.y0 + k.h * 0.84, k.w * 0.08, k.h * 0.42, p.tertiary)
		Canvas2D.circle(c, k.x0 + k.w * 0.50, k.y0 + k.h * 1.32, k.w * 0.13, p.glow)
	end,
	hood = function(c, p, k)
		-- Over the head and open toward the front, so the face still reads. The JavaScript's
		-- quadratic becomes a back panel and a stepped shoulder.
		Canvas2D.rect(c, k.x0 - k.w * 0.10, k.y0 + k.h * 0.16, k.w * 0.40, k.h * 0.70, p.secondary)
		Canvas2D.rect(c, k.x0 - k.w * 0.10, k.y0 + k.h * 0.84, k.w * 0.72, k.h * 0.22, p.secondary)
		Canvas2D.tri(c, k.x0 + k.w * 0.92, k.y0 + k.h * 1.02,
			k.x0 + k.w * 0.30, k.y0 + k.h * 1.06,
			k.x0 + k.w * 0.62, k.y0 + k.h * 0.84, p.secondary)
	end,
}

-- ---------------------------------------------------------------- torso ----
-- x runs -r*0.8 .. r*0.8, y runs 0 (hip) .. len (shoulder).
local TORSOS: { [string]: (any, Pal, number, number) -> () } = {
	belt = function(c, p, r, len)
		Canvas2D.rect(c, -r * 0.80, len * 0.42, r * 1.60, len * 0.22, p.accent)
	end,
	sash = function(c, p, r, len)
		-- A band running shoulder to hip. Drawn as its own rotated rectangle rather than the
		-- JavaScript's parallelogram: a Frame IS a rotated rectangle, so this one is exact.
		local dx, dy = r * 1.60, len * 0.54
		local ang = math.atan2(dy, dx)
		Canvas2D.save(c)
		Canvas2D.translate(c, 0, len * 0.56)
		Canvas2D.rotate(c, ang)
		Canvas2D.rect(c, -math.sqrt(dx * dx + dy * dy) / 2, -len * 0.11,
			math.sqrt(dx * dx + dy * dy), len * 0.22, p.accent)
		Canvas2D.restore(c)
	end,
	emblem = function(c, p, r, len)
		local function diamond(rw: number, rh: number, colour: Color3)
			Canvas2D.tri(c, 0, len * 0.54 + rh, -rw, len * 0.54, rw, len * 0.54, colour)
			Canvas2D.tri(c, 0, len * 0.54 - rh, -rw, len * 0.54, rw, len * 0.54, colour)
		end
		diamond(r * 0.52, len * 0.24, p.accent)
		diamond(r * 0.26, len * 0.14, p.glow)
	end,
	plain = function() end,
}

Avatar2D.HEAD_IDS = { "block", "round", "tall", "wide" }
Avatar2D.FACE_IDS = { "dot", "pair", "visor", "shades", "goggles", "blank" }
Avatar2D.HAT_IDS = { "none", "cap", "horns", "crown", "antenna", "hood" }
Avatar2D.TORSO_IDS = { "belt", "sash", "emblem", "plain" }

local DEFAULTS = { head = "block", face = "dot", hat = "none", torso = "belt" }

-- `featuresOf` in web/src/data/avatars.js: the defaults, with whatever the avatar overrides.
function Avatar2D.features(avatar: any): { [string]: string }
	local out = table.clone(DEFAULTS)
	if avatar and avatar.features then
		for key, value in avatar.features do
			out[key] = value
		end
	end
	return out
end

-- Head, face and hat, in that order: the hat is allowed to sit over the skull, the face is not
-- allowed to sit over the hat.
function Avatar2D.drawHead(c: any, pal: Pal, hs: number, feat: { [string]: string }): Box
	local head = HEADS[feat.head] or HEADS.block
	local face = FACES[feat.face] or FACES.dot
	local hat = HATS[feat.hat] or HATS.none
	local box = head(c, hs, pal)
	face(c, pal, box)
	hat(c, pal, box)
	return box
end

function Avatar2D.drawTorsoMark(c: any, pal: Pal, r: number, len: number, feat: { [string]: string })
	local mark = TORSOS[feat.torso] or TORSOS.belt
	mark(c, pal, r, len)
end

return Avatar2D
