--!strict
-- Local-player feedback, never implying that an opponent's full meter belongs to you.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Status = {}
-- The ultimate's part alone: CHARGING n/20, ACTIVE, or READY and what is in the way of it. The
-- fight HUD shows it once it begins with READY - the only time there is something to do.
function Status.ultimate(state: any, char: any): string
	local move = char.moves.Ultimate
	if not move then return "UNARMED — pick up a weapon" end
	local charge = math.min(Config.ULTIMATE.hitsRequired, math.floor(state.ultCharge or 0))
	local ultimate = `CHARGING {charge}/{Config.ULTIMATE.hitsRequired}`
	if state.moveId == "Ultimate" then ultimate = "ACTIVE"
	elseif charge >= Config.ULTIMATE.hitsRequired then
		ultimate = "READY — press O"
		if move.rings and char.mechanic and char.mechanic.id == "Return" and state.rings ~= nil and state.rings < move.rings then
			ultimate = "READY — catch a ring first"
		elseif move.grounded and not state.onGround then ultimate = "READY — land first"
		elseif state.state == "shield" then ultimate = "READY — release shield first"
		elseif state.state ~= "idle" and state.state ~= "run" and state.state ~= "air" then ultimate = "READY — finish current action" end
	end
	return ultimate
end
-- The Chakram's rings in hand (Roblox only; Snapshot `rings`, -1 for any other weapon), and what
-- that leaves you: Halo throws both, every other throw one.
function Status.rings(state: any, char: any): string?
	local n = state.rings
	if not char.mechanic or char.mechanic.id ~= "Return" or n == nil or n < 0 then return nil end
	local max = char.mechanic.rings
	if n >= max then return `{n}/{max}` end
	if n > 0 then return `{n}/{max} — Halo needs both` end
	return `0/{max} — catch a ring to throw again`
end
-- Rocket Boots' thrust fuel (Roblox only; Snapshot `fuel`, -1 for any other weapon), and which
-- signatures it still pays for.
function Status.fuel(state: any, char: any): string?
	local n = state.fuel
	if not char.mechanic or char.mechanic.id ~= "ThrustFuel" or n == nil or n < 0 then return nil end
	local tank = `{math.floor(n)}/{char.mechanic.max}`
	local short = {}
	for _, id in { "SigSide", "SigDown", "SigNeutral" } do
		local m = char.moves[id]
		if m and m.fuelCost and n < m.fuelCost then table.insert(short, m.label) end
	end
	if #short == 0 then return tank end
	if #short == 3 then return `{tank} — stand on the ground to refuel` end
	return `{tank} — not enough for {table.concat(short, ", ")}`
end
function Status.describe(state: any, char: any): string
	local ultimate = Status.ultimate(state, char)
	local shield = if state.state == "shield" then "ACTIVE" else if not state.onGround then "land to shield" else "hold I / Ctrl"
	local rings = Status.rings(state, char)
	local ringPart = if rings then `   |   RINGS: {rings}` else ""
	local fuel = Status.fuel(state, char)
	if fuel then ringPart ..= `   |   FUEL: {fuel}` end
	return `YOU · {char.weapon.name}   |   SHIELD: {shield}{ringPart}   |   ULTIMATE: {ultimate}`
end
function Status.event(event: any): string?
	if event.type == "ultready" then return "YOUR ULTIMATE IS READY — press O" end
	if event.type == "dryfire" and event.fuel then
		return `Not enough fuel ({event.fuel} needed) — stand on the ground to refuel.`
	end
	if event.type == "dryfire" and event.rings then
		return if event.rings > 1 then "Halo needs both rings in hand — catch them first." else "No ring in hand — catch one to throw again."
	end
	if event.type == "ultimate" then return "ULTIMATE ACTIVATED" end
	if event.type == "ultdenied" then
		return if event.reason == "grounded" then "This ultimate needs solid ground — land, then press O."
			elseif event.reason == "unarmed" then "Pick up a weapon to use your ultimate."
			else "Ultimate is not charged yet — land hits to fill YOUR meter."
	end
	return nil
end
return Status
