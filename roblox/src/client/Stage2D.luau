--!strict
-- The stage, drawn. A port of `_stage` in web/src/render2d/renderer2d.js.
--
-- Every number here is the JavaScript's number. The solids get a body that runs off the bottom of
-- the screen, a bright cap and a lip on each grabbable corner, because where the ledge is is
-- information the player needs and a flat slab of one colour makes it guesswork. The shelves are
-- drawn thinner and lighter so they read as pass-through at a glance.
--
-- In Roblox every stage has a realm (Realms.luau), and is drawn as a floating island in it by
-- RealmArt; the drawing below is the web's, kept for a stage no realm covers. The ledge banners and
-- the sinking warning are drawn over either, from the Stage, because they are what a player reads.

local Canvas2D = require(script.Parent.Canvas2D)
local BackdropArt = require(script.Parent.BackdropArt)
local RealmArt = require(script.Parent.RealmArt)
local Realms = require(game:GetService("ReplicatedStorage").Shared.Realms)

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local Stage2D = {}

-- What a player must read off the stage, drawn over its art whatever realm it is in: a banner at
-- every grabbable corner (from the stage's ACTUAL ledge list), and the hatching under a shelf that
-- sags. See web/src/render2d/renderer2d.js _stage for why both are information, not decoration.
local INK = Color3.fromRGB(18, 14, 22)
-- A ledge banner: its outer edge on the ledge, its foot on the surface.
local LEDGE_W, LEDGE_H = 0.8, 2.0
Stage2D.LEDGE_W, Stage2D.LEDGE_H = LEDGE_W, LEDGE_H
local function readings(c: any, stage: any, accent: Color3)
	for _, L in stage.ledges do
		local top = L.platform.top
		local x = if L.side < 0 then L.x else L.x - LEDGE_W
		Canvas2D.rect(c, x - 0.1, top - LEDGE_H - 0.2, LEDGE_W + 0.2, LEDGE_H + 0.3, INK, 0.9)
		Canvas2D.rect(c, x, top - LEDGE_H, LEDGE_W, LEDGE_H, accent)
		Canvas2D.rect(c, x, top - 0.45, LEDGE_W, 0.35, WHITE, 0.35)
	end
	for _, pl in stage.platforms do
		if not pl.solid and pl.sinking then
			local th = pl.thickness or 1
			local x = pl.x1 + 1
			while x < pl.x2 - 1 do
				Canvas2D.rect(c, x, pl.top - th - 0.9, 1.2, 0.4, accent, 0.8)
				x += 3
			end
		end
	end
end

function Stage2D.draw(c: any, stage: any)
	local realm = Realms.of(stage.data.id)
	if realm then
		RealmArt.stage(c, stage, realm)
		readings(c, stage, Canvas2D.hex(realm.accent, WHITE))
		return
	end
	local p = stage.data.palette or {}
	local ground = Canvas2D.hex(p.ground, Color3.fromRGB(107, 74, 44))
	local groundTop = Canvas2D.hex(p.groundTop, Color3.fromRGB(95, 191, 75))
	local shelf = Canvas2D.hex(p.platform, Color3.fromRGB(184, 137, 74))
	local accent = Canvas2D.hex(p.accent, Color3.fromRGB(62, 143, 53))

	for _, sp in stage.solids do
		-- The main island runs 60 studs deep so it leaves the bottom of the screen at every zoom;
		-- anything else is only as deep as it actually is.
		local depth = if sp == stage.main then 60 else math.max(sp.thickness or 6, 6)
		local w = sp.x2 - sp.x1
		Canvas2D.rect(c, sp.x1, sp.top - depth, w, depth, ground)
		Canvas2D.rect(c, sp.x1, sp.top - depth, w, math.min(depth, 1.2), BLACK, 0.16)
		Canvas2D.rect(c, sp.x1, sp.top - 1.2, w, 1.2, groundTop)
		Canvas2D.rect(c, sp.x1, sp.top - 1.5, w, 0.3, BLACK, 0.22)
		Canvas2D.rect(c, sp.x1, sp.top - 0.35, w, 0.35, WHITE, 0.22)
	end
	-- Grabbable corners, from the stage's ACTUAL ledge list - see web/src/render2d/renderer2d.js
	-- _stage. Marking both ends of any solid whose `ledges` was not false put a marker at every
	-- inner seam of a split floor, where there is nothing to grab.
	for _, L in stage.ledges do
		Canvas2D.rect(c, if L.side < 0 then L.x else L.x - 0.7, L.platform.top - 2.0, 0.7, 2.0, accent)
	end

	for _, pl in stage.platforms do
		if not pl.solid then
			local th = pl.thickness or 1
			local w = pl.x2 - pl.x1
			Canvas2D.rect(c, pl.x1, pl.top - th, w, th, shelf)
			Canvas2D.rect(c, pl.x1, pl.top - 0.4, w, 0.4, groundTop)
			Canvas2D.rect(c, pl.x1, pl.top - 0.15, w, 0.15, WHITE, 0.24)
			Canvas2D.rect(c, pl.x1, pl.top - th, w, 0.3, BLACK, 0.30)
			Canvas2D.rect(c, pl.x1, pl.top - th, 0.35, th, BLACK, 0.30)
			Canvas2D.rect(c, pl.x2 - 0.35, pl.top - th, 0.35, th, BLACK, 0.30)
			if pl.sinking then
				-- Hatching along the underside: the only warning a player gets that this one sags.
				local x = pl.x1 + 1
				while x < pl.x2 - 1 do
					Canvas2D.rect(c, x, pl.top - th - 0.5, 1.2, 0.4, BLACK, 0.28)
					x += 3
				end
			end
		end
	end
end

-- Shared pixel scenery recipes, with pooled gradient strips and camera-relative parallax.
function Stage2D.sky(c: any, stage: any, camX: number?, t: number?)
	local realm = Realms.of(stage.data.id)
	if realm then
		RealmArt.sky(c, realm, camX or 0, t)
		return
	end
	if BackdropArt.sky(c, stage.data.id or "", camX or 0) then return end
	local p = stage.data.palette or {}
	local vp = Canvas2D.viewport(c)
	Canvas2D.screen(c)
	Canvas2D.rect(c, 0, 0, vp.X, vp.Y, Canvas2D.hex(p.sky, Color3.fromRGB(201, 211, 224)))
end

return Stage2D
