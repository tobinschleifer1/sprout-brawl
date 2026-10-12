--!nocheck
-- Development tool, not a test: the lowest percent at which a weapon's ultimate KOs a target
-- standing 8 studs in front of the caster at centre stage (binary search, real match).
--   lune run tools/ult-kill <weapon>
-- Crude by design: a multi-hit ultimate (Storm Lash, the Eclipse Ring) racks up its own damage and
-- KOs a fresh target, one that needs a trigger (the Blasters' sniper) never fires, and one whose
-- reach is not 8 studs ahead reads high. Use it to compare like with like, not as a balance target.
local process = require("@lune/process")
local Loader = require("../tests/loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Stages = Loader.load("Data/Stages").LIST
local Remote = Loader.loadFrom("src/server/", "RemoteInput")
local weapon = process.args[1] or "Chakram"
local function kos(pct: number): boolean
	local input = Remote.new(); input:register("a"); input:register("b")
	local m = Match.new({ mode = "StockFFA", stage = Stages[1], seed = 7, items = false, stocks = 3,
		fighters = { { char = Loadout.build("Classic", weapon), team = 0, source = "a" }, { char = Loadout.build("Noir", "Sword"), team = 1, source = "b" } },
		input = input })
	m.state = "fight"
	local f, v = m.fighters[1], m.fighters[2]
	f:reset(0, m.stage.main.top, { state = "idle", invincible = 0 }); f.onGround = true; f.platform = m.stage.main; f.facing = 1
	v:reset(8, m.stage.main.top, { state = "idle", invincible = 0 }); v.onGround = true; v.platform = m.stage.main
	v.percent = pct
	f.ultCharge = 100
	f:startMove("Ultimate")
	for _ = 1, 600 do
		m:step()
		if v.stocks < 3 or not v.alive then return true end
	end
	return false
end
local lo, hi = 0, 400
if not kos(hi) then print(weapon .. ": no KO even at 400%"); return end
while hi - lo > 1 do local mid = (lo + hi) // 2; if kos(mid) then hi = mid else lo = mid end end
print(string.format("%s ultimate KOs a centre-stage target from %d%%", weapon, hi))
