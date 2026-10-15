--!nocheck
-- Controlled pre-launch pressure followed by real bot recovery, across both ledges/seeds.
local Loader = require("./loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local stage = Loader.load("Data/Stages").LIST[1]

return function()
	local recovered, cases, fuels = 0, 0, {}
	for side = -1, 1, 2 do
		for seed = 1, 8 do
			local m = Match.new({ mode = "Training", stage = stage, seed = seed, items = false, fighters = {
				{ char = Loadout.build("Classic", "RocketBoots"), isBot = true, botLevel = "hard", team = 0 },
				{ char = Loadout.build("Noir", "Sword"), isBot = true, botLevel = "dummy", team = 1 },
			} })
			m.state = "fight"
			local f, foe = m.fighters[1], m.fighters[2]
			local main = m.stage.main
			local edge = if side < 0 then main.x1 else main.x2
			f:reset(edge - side * 6, main.top, { state = "idle", invincible = 0 })
			f.onGround, f.platform, f.facing, f.mech.fuel = true, main, side, 60
			foe:reset(edge - side * 2, main.top, { state = "idle", invincible = 0 })
			foe.onGround, foe.platform, foe.percent = true, main, 160
			-- Hold the spacing while the bot commits real attacks and pays their real fuel costs.
			for _ = 1, 180 do
				m:step()
				f.x, f.y, f.onGround, f.platform = edge - side * 6, main.top, true, main
				foe:reset(edge - side * 2, main.top, { state = "idle", invincible = 0 })
				foe.onGround, foe.platform, foe.percent = true, main, 160
			end
			local fuel = f.mech.fuel
			table.insert(fuels, fuel)
			-- Fix the post-launch position/velocity, retaining exactly the fuel the bot kept.
			f:reset(edge + side * (9 + seed * 0.4), main.top - 8 - seed * 0.8, { state = "air", invincible = 0 })
			f.mech.fuel, f.jumpsLeft, f.vx, f.vy = fuel, 0, side * 12, -12
			foe:reset(0, main.top, { state = "idle", invincible = 0 })
			foe.onGround, foe.platform = true, main
			local success = false
			for _ = 1, 240 do
				m:step()
				if f.state == "ledge" or (f.onGround and f.alive) then success = true; break end
				if not f.alive then break end
			end
			cases += 1
			if success then recovered += 1 end
		end
	end
	return { recovered = recovered, cases = cases, fuels = fuels }
end
