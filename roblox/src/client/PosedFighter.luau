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
	-- A new Fighter has just "respawned" and carries spawn invincibility, which the pose code draws
	-- as a blink - 55% opacity three frames in six. Posed afresh every frame, every lobby character
	-- and podium winner flickered at 10Hz, re-tinting every rectangle of its sprites each time.
	f.invincible = 0
	-- Nested mechanics and wire encodings belong to Snapshot too. A field-name copy silently
	-- omitted rings/fuel and exposed the raw stale-move table instead of the decoded string.
	return Snapshot.decode(Snapshot.encode(f))
end

return PosedFighter
