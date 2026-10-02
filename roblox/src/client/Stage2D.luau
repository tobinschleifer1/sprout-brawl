--!strict
-- The stage, drawn: its realm's islands, platforms and sky (RealmArt), and over them what a player
-- reads off a stage to play it - a banner at every grabbable corner and the warning under a shelf
-- that sags. Positions all come from the Stage; the art only dresses them.
--
-- Every stage is in a realm (Realms.luau; tests/realms.luau fails a stage that is not). The web's
-- flat drawing of `_stage` (renderer2d.js) used to live here as the fallback for one that was not,
-- and was removed once nothing could reach it.

local Canvas2D = require(script.Parent.Canvas2D)
local RealmArt = require(script.Parent.RealmArt)
local Realms = require(game:GetService("ReplicatedStorage").Shared.Realms)

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

-- The realm `stage` is drawn in: its own, or the first realm's for a stage without one, so a stage
-- added to the web data before Roblox has dressed it still draws (and tests/realms.luau says so).
local function realmOf(stage: any): any
	return Realms.of(stage.data and stage.data.id) or Realms.LIST[1]
end

function Stage2D.draw(c: any, stage: any)
	local realm = realmOf(stage)
	RealmArt.stage(c, stage, realm)
	readings(c, stage, Canvas2D.hex(realm.accent, WHITE))
end

function Stage2D.sky(c: any, stage: any, camX: number?, t: number?)
	RealmArt.sky(c, realmOf(stage), camX or 0, t)
end

return Stage2D
