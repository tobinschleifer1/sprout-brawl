--!strict
-- The results podium's layout, ported from web/src/render2d/podium.js - read that file for the
-- design. Pure: tests/podium-parity.luau holds it to the JavaScript. PodiumView draws it.
local Podium = {}

local function pair(...: any): { any }
	return { ... }
end
Podium.STATS = {
	pair("Score", "score"), pair("KOs", "kos"), pair("Falls", "falls"), pair("Accidents", "sds"),
	pair("Dmg Done", "damage"), pair("Dmg Taken", "taken"),
}

function Podium.ordinal(n: number): string
	local t = n % 100
	if t >= 11 and t <= 13 then
		return `{n}th`
	end
	local u = n % 10
	return `{n}{if u == 1 then "st" elseif u == 2 then "nd" elseif u == 3 then "rd" else "th"}`
end

function Podium.places(rows: { any }, teams: boolean?): { number }
	local out: { number } = {}
	for i, row in rows do
		if teams and i > 1 and row.team == rows[i - 1].team then
			out[i] = out[i - 1]
		else
			out[i] = if i == 1 then 1 else out[i - 1] + 1
		end
	end
	return out
end

-- Whole numbers, rounded as JavaScript's Math.round does (halves toward +infinity).
function Podium.statValue(row: any, field: string): number
	local v = row[field]
	return if v == nil then 0 else math.floor(v + 0.5)
end

function Podium.layout(n: number, W: number, H: number): { any }
	local margin = W * 0.04
	local colW = (W - margin * 2) / math.max(1, n)
	local step = if n > 1 then math.min(H * 0.045, (H * 0.2) / (n - 1)) else 0
	local figureH = math.min(colW * 0.6, H * 0.24)
	local cardW = math.min(colW * 0.9, H * 0.52)
	local slots = {}
	for i = 1, n do
		local cx = margin + colW * (i - 0.5)
		local top = H * 0.5 + step * (i - 1)
		local cardY = top + H * 0.06
		local cardH = math.max(0, H - cardY - H * 0.03)
		slots[i] = {
			cx = cx, top = top, colW = colW, figureH = figureH,
			pillar = { x = cx - colW * 0.42, y = top, w = colW * 0.84, h = H - top },
			cap = { x = cx - colW * 0.46, y = top - H * 0.012, w = colW * 0.92, h = H * 0.024 },
			card = { x = cx - cardW / 2, y = cardY, w = cardW, h = cardH },
			rowH = cardH / (#Podium.STATS + 2.2),
		}
	end
	return slots
end

return Podium
