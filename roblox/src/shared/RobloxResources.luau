--!strict
-- Self-only resource changes at ignition, shared by authoritative combat and local prediction.
-- Projectiles, catches and hits remain authoritative. No web move uses either of these fields.
local RobloxResources = {}

function RobloxResources.ignite(f: any, move: any): boolean
	if move.fuelCost and f.mech and f.mech.id == "ThrustFuel" then
		f.mech.fuel = math.max(0, f.mech.fuel - move.fuelCost)
		f.mech.grounded = 0
		return true
	end
	return false
end

function RobloxResources.throwRing(f: any, rings: number)
	if f.mech and f.mech.id == "Return" then
		f.mech.rings = math.max(0, (f.mech.rings or 0) - rings)
	end
end

return RobloxResources
