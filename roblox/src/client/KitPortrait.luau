--!strict
-- Still pictures of kit characters: the creator's option tiles, its slot chips, anything that
-- shows a character without animating one.
--
-- Uses the fight's posture, joint art and body draw order at a fixed, unarmed idle frame.
-- Neutral means the player's chosen face (the same composed head the fight uses between
-- expressions), never a blink or a match's last-stock face.

local Canvas2D = require(script.Parent.Canvas2D)
local PostureArt = require(script.Parent.PostureArt)
local KitBody = require(script.Parent.KitBody)
local Posture = require(script.Parent.Posture)
local Channels = require(script.Parent.Channels)
local Shared = game:GetService("ReplicatedStorage").Shared
local Loadout = require(Shared.Loadout)
local Fighter = require(Shared.Fighter)
local Snapshot = require(Shared.Snapshot)
local KIT: any = require(game:GetService("ReplicatedStorage").Shared.Data.AvatarKit)

local KitPortrait = {}

local char = Loadout.build("Classic", "Fists")
char.weapon = nil -- private presentation loadout, with relaxed, unarmed hands
local fighter = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
fighter.state, fighter.sf, fighter.invincible, fighter.onGround = "idle", 0, 0, true
local snapshot = Snapshot.decode(Snapshot.encode(fighter))
local ch = Channels.For(snapshot, char, nil, 0)
local pose = Posture.For(ch, snapshot, char, { angle = 0 }, nil, 0)
local H, R = char.height, char.radius
local PW = R * 1.15 / 12
KitPortrait.HEIGHT = H

local function piece(c: any, code: string, art: any, id: string, ph: number, far: boolean?, half: boolean?)
	local P, a = PostureArt.parts[id], art[id]
	local k = if half then 2 else 1
	local list = if far then (if half then a.farHalf else a.farFull) else (if half then a.half else a.full)
	Canvas2D.sprite(c, `{code}|{id}|{if far then "f" else ""}{if half then "h" else ""}`, list,
		-P.ox * PW, P.oy * ph, PW * k, ph * k, math.ceil(P.w / k), math.ceil(P.h / k))
end

-- Full detail on editor tiles; the offline sheet can also inspect the fight's half-detail body.
function KitPortrait.figure(c: any, code: string, x: number, y: number, k: number, half: boolean?)
	local art = PostureArt.sprites(code)
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	Canvas2D.scale(c, k, k)
	Canvas2D.translate(c, 0, ch.bob)
	KitBody.draw(c, H, PW, ch, pose, half == true, function(id, ph, far)
		piece(c, code, art, id, ph, far, half)
	end)
	Canvas2D.restore(c)
end

-- The player's neutral head, its neck joint at (x, y).
function KitPortrait.head(c: any, code: string, x: number, y: number, k: number, half: boolean?)
	local art = PostureArt.sprites(code)
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	Canvas2D.scale(c, k, k)
	piece(c, code, art, "head", PW, false, half)
	Canvas2D.restore(c)
end

-- Where to put a picture so it fills a w x h screen box (y down, like every GUI): the transform to
-- install and the feet or neck point to draw at. A figure is framed on its full height plus
-- headroom for a tall hat; a head on its 18 x 20 canvas.
function KitPortrait.frame(c: any, view: string, w: number, h: number)
	if view == "head" then
		local P = KIT.parts.head
		local k = math.min(w / (P.w * PW), h / (P.h * PW)) * 0.92
		Canvas2D.setTransform(c, k, 0, 0, -k, w / 2, h / 2 + (P.h / 2 - (P.h - P.oy)) * PW * k)
		return
	end
	local k = h / (H + 1.4) * 0.94
	Canvas2D.setTransform(c, k, 0, 0, -k, w / 2, h - 0.35 * k)
end

-- A tile's whole draw: frame, picture, finish (purging what the previous picture left).
function KitPortrait.draw(c: any, code: string, view: string, w: number, h: number)
	KitPortrait.frame(c, view, w, h)
	if view == "head" then
		KitPortrait.head(c, code, 0, 0, 1)
	else
		KitPortrait.figure(c, code, 0, 0, 1)
	end
	Canvas2D.finish(c, true)
end

return KitPortrait
