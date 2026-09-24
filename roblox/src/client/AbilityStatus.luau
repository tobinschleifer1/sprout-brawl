--!strict
-- Local-player feedback, never implying that an opponent's full meter belongs to you.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Status = {}
function Status.describe(state: any, char: any): string
	local charge = math.min(Config.ULTIMATE.hitsRequired, math.floor(state.ultCharge or 0))
	local ultimate = `CHARGING {charge}/{Config.ULTIMATE.hitsRequired}`
	if state.moveId == "Ultimate" then ultimate = "ACTIVE"
	elseif charge >= Config.ULTIMATE.hitsRequired then
		ultimate = "READY — press O"
		if char.moves.Ultimate.grounded and not state.onGround then ultimate = "READY — land first"
		elseif state.state == "shield" then ultimate = "READY — release shield first"
		elseif state.state ~= "idle" and state.state ~= "run" and state.state ~= "air" then ultimate = "READY — finish current action" end
	end
	local shield = if state.state == "shield" then "ACTIVE" else if not state.onGround then "land to shield" else "hold I / Ctrl"
	return `YOU · {char.weapon.name}   |   SHIELD: {shield}   |   ULTIMATE: {ultimate}`
end
function Status.event(event: any): string?
	if event.type == "ultready" then return "YOUR ULTIMATE IS READY — press O" end
	if event.type == "ultimate" then return "ULTIMATE ACTIVATED" end
	if event.type == "ultdenied" then
		return if event.reason == "grounded" then "This ultimate needs solid ground — land, then press O."
			else "Ultimate is not charged yet — land hits to fill YOUR meter."
	end
	return nil
end
return Status
