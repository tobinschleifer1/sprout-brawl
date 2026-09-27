--!strict
-- A fighter standing still in `state`, in the shape Fighter2D reads (Snapshot's field names), built
-- from a real Fighter so every field the pose code reads exists - the web does the same with
-- render2d/preview.js posedFighter. Used by the results podium and the character studio's preview.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fighter = require(ReplicatedStorage.Shared.Fighter)
local Snapshot = require(ReplicatedStorage.Shared.Snapshot)

local PosedFighter = {}

function PosedFighter.posed(char: any, index: number, state: string, sf: number): any
	local f: any = Fighter.new({ index = index, char = char, x = 0, y = 0, stocks = 1 })
	f.state, f.sf, f.frameCount, f.onGround = state, sf, sf, true
	local out: any = {}
	for _, pair in Snapshot.FIELDS do
		local name = pair[1]
		out[name] = f[Snapshot.FROM_FIGHTER[name] or name]
	end
	out.index, out.chillStacks = index, 0
	return out
end

return PosedFighter
