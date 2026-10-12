--!strict
-- Local-player feedback, never implying that an opponent's full meter belongs to you.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Status = {}
-- The ultimate's part alone: CHARGING n/20, ACTIVE, or READY and what is in the way of it. The
-- fight HUD shows it once it begins with READY - the only time there is something to do.
function Status.ultimate(state: any, char: any): string
	local charge = math.min(Config.ULTIMATE.hitsRequired, math.floor(state.ultCharge or 0))
	local ultimate = `CHARGING {charge}/{Config.ULTIMATE.hitsRequired}`
	if state.moveId == "Ultimate" then ultimate = "ACTIVE"
	elseif charge >= Config.ULTIMATE.hitsRequired then
		ultimate = "READY — press O"
		if char.moves.Ultimate.grounded and not state.onGround then ultimate = "READY — land first"
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
function Status.describe(state: any, char: any): string
	local ultimate = Status.ultimate(state, char)
	local shield = if state.state == "shield" then "ACTIVE" else if not state.onGround then "land to shield" else "hold I / Ctrl"
	local rings = Status.rings(state, char)
	local ringPart = if rings then `   |   RINGS: {rings}` else ""
	return `YOU · {char.weapon.name}   |   SHIELD: {shield}{ringPart}   |   ULTIMATE: {ultimate}`
end
function Status.event(event: any): string?
	if event.type == "ultready" then return "YOUR ULTIMATE IS READY — press O" end
	if event.type == "dryfire" and event.rings then
		return if event.rings > 1 then "Halo needs both rings in hand — catch them first." else "No ring in hand — catch one to throw again."
	end
	if event.type == "ultimate" then return "ULTIMATE ACTIVATED" end
	if event.type == "ultdenied" then
		return if event.reason == "grounded" then "This ultimate needs solid ground — land, then press O."
			else "Ultimate is not charged yet — land hits to fill YOUR meter."
	end
	return nil
end
return Status
