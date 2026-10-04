--!strict
-- The local player's combo routes, in words, read straight off their weapon's data (Config.COMBO)
-- so the guide can never drift from the game: the light string to the finisher, and the air string
-- to the air finisher. Shown in the HUD under the controls. Pure; tests/combo-hud.luau checks it.
local ComboGuide = {}

local DIR_WORD = { neutral = "", side = "→ ", up = "↑ ", down = "↓ " }

-- The neutral light chain from LightNeutral1 to the move that holds the Finisher branch, then the
-- finisher: { ids }, or nil if the weapon has none.
function ComboGuide.finisherRoute(moves: any): { string }?
	local from
	for id, m in moves do
		if m.finishers and m.finishers.neutral == "Finisher" then from = id end
	end
	if not from or not moves.LightNeutral1 then return nil end
	local path = { "LightNeutral1" }
	while path[#path] ~= from do
		local m = moves[path[#path]]
		local nextId = m.chains and m.chains.neutral
		if not nextId or table.find(path, nextId) then return nil end
		table.insert(path, nextId)
	end
	table.insert(path, "Finisher")
	return path
end

-- The longest chain of aerials into the one holding the AirFinisher branch, then the air finisher,
-- as { { id, dir } } - the direction each link is pressed with.
function ComboGuide.airRoute(moves: any): { any }?
	local last
	for id, m in moves do
		if m.finishers and m.finishers.neutral == "AirFinisher" then last = id end
	end
	if not last then return nil end
	local function into(id: string): { any }
		local out = {}
		for p, m in moves do
			if string.sub(p, 1, 3) == "Air" and m.chains then
				for _, d in { "neutral", "side", "up", "down" } do
					if m.chains[d] == id then table.insert(out, { p, d }); break end
				end
			end
		end
		table.sort(out, function(a, b) return a[1] < b[1] end)   -- a fixed order: tables have none
		return out
	end
	local function longest(id: string, seen: { [string]: boolean }): { any }
		local best = { { id, "neutral" } }
		for _, pd in into(id) do
			if not seen[pd[1]] then
				local s2 = table.clone(seen); s2[pd[1]] = true
				local l = longest(pd[1], s2)
				local withMe = table.clone(l)
				table.insert(withMe, { id, pd[2] })            -- reached from its predecessor with this press
				if #withMe > #best then best = withMe end
			end
		end
		return best
	end
	local path = longest(last, { [last] = true })
	table.insert(path, { "AirFinisher", "neutral" })
	return path
end

-- The two lines the HUD shows.
function ComboGuide.lines(char: any): { string }
	local out = {}
	local moves = char and char.moves
	if not moves then return out end
	local fin = ComboGuide.finisherRoute(moves)
	if fin then
		local labels = {}
		for _, id in fin do table.insert(labels, moves[id].label) end
		table.insert(out, `Finisher: {table.concat(labels, " › ")}  (press Light as each hit lands)`)
	end
	local air = ComboGuide.airRoute(moves)
	if air then
		local labels = {}
		for i, pd in air do table.insert(labels, (if i > 1 then DIR_WORD[pd[2]] or "" else "") .. moves[pd[1]].label) end
		table.insert(out, `Air: {table.concat(labels, " › ")}  (timed links chase)`)
	end
	return out
end

return ComboGuide
