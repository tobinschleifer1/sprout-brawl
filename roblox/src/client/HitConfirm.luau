--!strict
-- The local player's hits, drawn twice by nobody.
--
-- A swing that meets a foe on screen sets off its sparks at once, from the prediction (Predictor,
-- INSTANT HITS). The server's own event for the same hit arrives a round trip and an interpolation
-- later; drawn as well, every hit would spark twice. So each predicted hit is remembered here, and
-- the server's event that confirms it - same victim, same kind - is drawn only for what the
-- prediction could not know: whether it was the kill hit, which gets its flash and burst then.
-- A predicted hit the server never confirms (the foe dodged first) is forgotten after WINDOW; its
-- sparks were the price of answering at once.
local HitConfirm = {}
HitConfirm.__index = HitConfirm

-- Seconds a predicted hit waits for its confirmation: past the 150ms rewind cap, an interpolation
-- delay and a slow round trip.
HitConfirm.WINDOW = 1.0

function HitConfirm.new(): any
	return setmetatable({ shown = {} :: { any } }, HitConfirm)
end

-- A predicted hit (`e.predicted`) was drawn at `now`.
function HitConfirm.drawn(self: any, e: any, now: number)
	table.insert(self.shown, { victim = e.victim, kind = e.type, t = now })
end

-- The server's event `e`, released at `now`: true if a prediction already drew it. A hit, an
-- armour clank or the bullwhip's mark and crack name their attacker; a block does not, so any
-- predicted block on that victim is it.
function HitConfirm.confirms(self: any, e: any, localIndex: number?, now: number): boolean
	local shown = self.shown
	for i = #shown, 1, -1 do
		if now - shown[i].t > HitConfirm.WINDOW then table.remove(shown, i) end
	end
	if localIndex == nil then return false end
	if e.type == "hit" or e.type == "armor" or e.type == "crack" or e.type == "crackmark" then
		if e.attacker ~= localIndex then return false end
	elseif e.type ~= "block" then
		return false
	end
	for i, p in shown do
		if p.victim == e.victim and p.kind == e.type then
			table.remove(shown, i)
			return true
		end
	end
	return false
end

return HitConfirm
