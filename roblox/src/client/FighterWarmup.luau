--!strict
-- Spend the countdown building the exact body/weapon slots the first visible frame will reuse.
local Canvas = require(script.Parent.Canvas2D)
local Draw = require(script.Parent.Fighter2D)
local Kicks = require(script.Parent.Kicks)
local KickFx = require(script.Parent.KickFx)
local Shared = game:GetService("ReplicatedStorage").Shared
local Fighter = require(Shared.Fighter)
local Snapshot = require(Shared.Snapshot)
local FighterWarmup = {}
FighterWarmup.BUDGET = 180

function FighterWarmup.new(canvas: any, chars: { any }, ppu: number): any
	local effects, glows, teams, stocks = Draw.effects, Draw.glows, Draw.teamColours, Draw.startStocks
	Draw.effects, Draw.glows, Draw.teamColours, Draw.startStocks = nil, nil, nil, nil
	local ok, queue = pcall(function()
		return Canvas.collectSprites(canvas, function(c)
			local vp = canvas:viewport()
			Canvas.setTransform(c, ppu, 0, 0, -ppu, vp.X / 2, vp.Y / 2)
			for i, original in chars do
				-- Expression holds and secondary followers belong to this disposable loadout,
				-- never the live fighter. Warm neutral heads even for high roster indices.
				local char = table.clone(original)
				local f = Fighter.new({ index = i - 1, char = char, x = 0, y = 0, stocks = 3 })
				f.state, f.sf, f.onGround, f.invincible, f.frameCount = "idle", 0, true, 0, -37 * (i - 1)
				Draw.draw(c, Snapshot.decode(Snapshot.encode(f)), char, 0)
			end
			-- A Rocket Boots kick's blast and exhaust (KickFx) are not in the first frame, but
			-- the first kick would build them mid-fight: one pair for each wearer (a two-legged
			-- kick builds its second pair the first time it is thrown).
			for _, char in chars do
				if Kicks.wears(char) then KickFx.draw(c, 0, 0, 1, 0, 1, false) end
			end
		end)
	end)
	Draw.effects, Draw.glows, Draw.teamColours, Draw.startStocks = effects, glows, teams, stocks
	if not ok then error(queue, 0) end
	local pending: any = queue
	pending.at = 1
	return pending
end

function FighterWarmup.step(canvas: any, queue: any): boolean
	return Canvas.warmSprites(canvas, queue, FighterWarmup.BUDGET)
end

return FighterWarmup
