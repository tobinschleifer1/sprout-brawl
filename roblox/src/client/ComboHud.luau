--!strict
-- What the HUD shows about combos (Config.COMBO), worked out from the events and the drawn
-- fighters - pure, so tests/combo-hud.luau can drive it without a ScreenGui. Hud.luau draws it.
--
-- Per attacker, the combo they are running: how many hits (each swing once - the same count the
-- engine scales damage by), the damage it has done, their streak of timed links while it lasts,
-- and whether it ended in a finisher or was broken. It holds on screen for HOLD seconds after the
-- victim gets out, then fades. Per fighter, the combo break: its cooldown, and - for the player
-- being comboed - whether this very freeze is one they can break out of (the prompt).
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local ComboHud = {}
ComboHud.HOLD = 0.9      -- seconds a finished combo stays up before it fades
ComboHud.SHOW_FROM = 2   -- hits before a combo is worth a counter

function ComboHud.new(): any
	return { combos = {} :: { [number]: any } }
end

-- One event, at the moment the drawn picture reaches it.
function ComboHud.event(self: any, e: any, now: number)
	if e.type == "hit" and e.attacker ~= nil and e.attacker >= 0 and e.victim ~= nil then
		local n = e.combo or 1
		local c = self.combos[e.attacker]
		if not c or c.victim ~= e.victim or c.endAt or n < c.hits then
			c = { victim = e.victim, hits = 0, damage = 0, start = now }
			self.combos[e.attacker] = c
		end
		c.hits = math.max(c.hits, n)
		c.damage += e.damage or 0
		if e.finisher then c.finisher = true end
		-- a team combo: an ally's hits are in it too (Combat.teamCombo)
		if e.team then c.team = true end
	elseif e.type == "combobreak" then
		for _, c in self.combos do
			if c.victim == e.fighter and not c.endAt then
				c.broken = true
				c.endAt = now
			end
		end
	end
end

-- What to show this frame: { [attackerIndex] = { hits, damage, perfect, alpha, finisher, broken } }.
-- A combo is over the first frame its victim can act (their combo count is back to 0).
function ComboHud.view(self: any, states: { any }, now: number): { [number]: any }
	local byIndex: { [number]: any } = {}
	for _, st in states do byIndex[st.index] = st end
	local out = {}
	for attacker, c in self.combos do
		if not c.endAt then
			local v = byIndex[c.victim]
			if not v or (v.comboHits or 0) == 0 then c.endAt = now end
		end
		local alpha = if c.endAt then 1 - (now - c.endAt) / ComboHud.HOLD else 1
		if alpha <= 0 then
			self.combos[attacker] = nil
		elseif c.hits >= ComboHud.SHOW_FROM or c.finisher then
			local a = byIndex[attacker]
			out[attacker] = {
				hits = c.hits, damage = math.floor(c.damage + 0.5), alpha = math.min(1, alpha),
				perfect = if not c.endAt and a then (a.perfectStreak or 0) else 0,
				finisher = not not c.finisher, broken = not not c.broken, team = not not c.team,
			}
		end
	end
	return out
end

-- A fighter's combo break: seconds of cooldown left (0 when ready), and whether the freeze they
-- are in right now is one a Dodge breaks (the fourth hit or later, not a finisher, off cooldown).
function ComboHud.breakView(st: any): any
	if not st then return { cooldown = 0, prompt = false } end
	local cd = st.breakCooldown or 0
	return {
		cooldown = cd / 60,
		prompt = st.state == "hitstun" and (st.hitlag or 0) > 0 and (st.comboHits or 0) >= Config.COMBO.breakFrom
			and st.breakable ~= false and cd == 0,
	}
end

return ComboHud
