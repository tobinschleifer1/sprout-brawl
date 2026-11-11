--!nocheck
-- Development tool, not a test: the bot with its Roblox-only layers (BotLayers) against the bot
-- without them, every weapon against itself, sides and avatars alternating, every stage in turn.
--   lune run tools/bot-ab <out.json> [matches per weapon] [level] [shard] [shards]
-- Reports A's (layered) wins, and each side's KOs and self-destructs (KOs nobody is credited with).
-- Side bias is real: run it with both sides plain to know the baseline (BOT_AB_PLAIN=1).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local Match, Loadout, Weapons = Loader.load("Match"), Loader.load("Loadout"), Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST
local out, N, level = process.args[1], tonumber(process.args[2] or "24") or 24, process.args[3] or "hard"
local shard, shards = tonumber(process.args[4] or "1") or 1, tonumber(process.args[5] or "1") or 1
local plain = process.env.BOT_AB_PLAIN == "1"
local BotLayers = Loader.load("BotLayers")
for n in string.gmatch(process.env.BOT_LAYERS_OFF or "", "%d+") do BotLayers.off[tonumber(n)] = true end
local r = { aWins = 0, games = 0, timeouts = 0, a = { kos = 0, sds = 0 }, b = { kos = 0, sds = 0 }, frames = 0, byWeapon = {} }
for wi, w in Weapons.LIST do
	local only = process.env.BOT_AB_WEAPONS
	if (wi - 1) % shards == shard - 1 and (not only or string.find("," .. only .. ",", "," .. w.id .. ",", 1, true)) then
		local ww = 0
		for k = 1, N do
			local seed = 3000 + wi * 97 + k * 31
			local swap = k % 2 == 0
			local fa = { char = Loadout.build(if swap then "Noir" else "Classic", w.id), isBot = true, botLevel = level, team = 0 }
			local fb = { char = Loadout.build(if swap then "Classic" else "Noir", w.id), isBot = true, botLevel = level, team = 1 }
			local m = Match.new({ mode = "StockFFA", stage = Stages[(seed % #Stages) + 1], seed = seed, items = false, stocks = 3, timeLimit = 180,
				fighters = if swap then { fb, fa } else { fa, fb } })
			local aIndex = if swap then 2 else 1
			for i, f in m.fighters do f.noBotLayers = plain or i ~= aIndex end
			m.state = "fight"
			local frames, seen = 0, 0
			while not m.results and frames < 600 * 60 do
				m:step(); frames += 1
				if #m.events < seen then seen = 0 end
				for e = seen + 1, #m.events do
					local ev = m.events[e]
					if ev.type == "ko" then
						local side = if ev.fighter + 1 == aIndex then r.a else r.b
						if ev.by == -1 or ev.by == ev.fighter then side.sds += 1 else side.kos += 1 end
					end
				end
				seen = #m.events
			end
			r.frames += frames
			if not m.results then r.timeouts += 1 else
				r.games += 1
				if m.results.rows[1].index + 1 == aIndex then r.aWins += 1; ww += 1 end
			end
		end
		r.byWeapon[w.id] = ww
	end
end
fs.writeFile(out, serde.encode("json", r))
print(string.format("A (layered%s) won %d of %d; timeouts %d; deaths A %d (%d uncredited), B %d (%d uncredited); avg %.0f s",
	if plain then ", off: baseline" else "", r.aWins, r.games, r.timeouts, r.a.kos + r.a.sds, r.a.sds, r.b.kos + r.b.sds, r.b.sds, r.frames / (r.games + r.timeouts) / 60))
