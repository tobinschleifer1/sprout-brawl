--!strict
-- UI launch acknowledgement is not success: only a first complete snapshot is playable.
local LaunchState = {}
LaunchState.__index = LaunchState
LaunchState.TIMEOUT = 8
function LaunchState.new(): any
	return setmetatable({ phase = "lobby", since = 0 }, LaunchState)
end
function LaunchState.begin(self: any, now: number): boolean
	if self.phase == "requesting" or self.phase == "loading" then return false end
	self.phase, self.since = "requesting", now
	return true
end
function LaunchState.accept(self: any, now: number)
	self.phase, self.since = "loading", now
end
function LaunchState.ready(self: any)
	self.phase = "playing"
end
function LaunchState.reset(self: any)
	self.phase = "lobby"
end
function LaunchState.expired(self: any, now: number): boolean
	if (self.phase == "requesting" or self.phase == "loading") and now - self.since >= LaunchState.TIMEOUT then
		self.phase = "error"
		return true
	end
	return false
end
return LaunchState
