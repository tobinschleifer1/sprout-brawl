--!strict
-- Observe the finished simulation tick. Input is the frame Fighter actually consumed (including
-- buffered taunts); facing is still the entry facing, since taunt precedes turning in _stepGround.
-- Records live outside Fighter, leaving its snapshots, timing and replay contract untouched.
local EmoteEvents = {}
function EmoteEvents.slot(input: any, facing: number): string
	if input.y > 0.5 then return "up" end
	if input.y < -0.5 then return "down" end
	if input.x * facing > 0.5 then return "forward" end
	return "neutral" -- backward has no fifth slot; vertical wins on a diagonal
end
function EmoteEvents.observe(active: any, match: any)
	for _, f in match.fighters do
		local old = active[f.index]
		if f.state == "taunt" then
			local start = f.frameCount - f.sf
			if not old or old.start ~= start then
				local e = { type = "emote", fighter = f.index, slot = EmoteEvents.slot(f.input, f.facing), start = start, frame = match.frame }
				active[f.index] = e
				table.insert(match.events, e)
			end
		else
			active[f.index] = nil
		end
	end
end
return EmoteEvents
