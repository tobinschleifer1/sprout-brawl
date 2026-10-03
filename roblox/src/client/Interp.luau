--!strict
-- How far in the past to draw other fighters, from how evenly their snapshots actually arrive.
--
-- Interpolating between two snapshots needs the next one to have arrived before the drawing gets
-- there; draw too close to the newest and every late packet is a stall ("opponents jitter"), draw
-- too far back and everyone else lags behind what you see of yourself. A fixed 4 frames (67ms) was
-- both: too long on a steady connection at 60Hz, and not enough on a ragged one. This keeps the
-- delay at about one and a half snapshot gaps plus twice the arrival jitter, measured as it goes,
-- and eases toward a new value rather than jumping, because a delay that changes suddenly moves
-- every remote fighter at once.
local Interp = {}
Interp.__index = Interp

Interp.MIN = 2 / 60
Interp.MAX = 9 / 60
Interp.EASE = 0.05             -- of the way to the target per snapshot
Interp.PAUSE = 0.25            -- a gap longer than this is a pause, not the connection

function Interp.new(frame: number): any
	local self = setmetatable({}, Interp)
	self.frame = frame
	self.delay = 4 * frame     -- where the fixed delay was, until there is something to measure
	self.gap = 2 * frame
	self.jitter = 0
	self.last = nil :: number?
	return self
end

-- A snapshot arrived at `now`.
function Interp.arrive(self: any, now: number)
	if self.last then
		local gap = now - self.last
		if gap > Interp.PAUSE then
			-- a pause (the window lost focus, a hitch) is not jitter: start measuring again from here
			self.last = now
			return
		end
		local err = math.abs(gap - self.gap)
		self.gap += (gap - self.gap) * 0.1
		self.jitter += (err - self.jitter) * 0.1
		local target = math.clamp(self.gap * 1.5 + self.jitter * 2, Interp.MIN, Interp.MAX)
		self.delay += (target - self.delay) * Interp.EASE
	end
	self.last = now
end

return Interp
