--!strict
-- The object Match asks for input, backed by packets instead of a keyboard.
--
-- Match calls `input:get(source)` exactly once per fighter per tick and expects a frame to exist.
-- The network does not work like that: packets arrive early, late, in bursts, or never. So each
-- source gets a small queue and this drains it at one frame per tick, which is the only rate the
-- simulation can consume. The queue is the whole jitter buffer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(ReplicatedStorage.Shared.Input)

-- Past this, a client is running ahead of the server or spamming, and the extra frames are
-- dropped oldest-first. Six frames is 100ms of slack: enough to ride out ordinary jitter, short
-- enough that a client cannot bank a second of inputs and replay them in a burst.
local MAX_QUEUED = 6

local RemoteInput = {}
RemoteInput.__index = RemoteInput

export type Source = {
	queue: { number },
	last: Input.Frame,
	starved: number,
}

function RemoteInput.new(): any
	local self = setmetatable({}, RemoteInput)
	self.sources = {} :: { [string]: Source }
	self.kb2Active = false
	return self
end

function RemoteInput.register(self: any, source: string)
	self.sources[source] = { queue = {}, last = Input.emptyFrame(), starved = 0 }
end

-- Called from the remote handler. `packed` is a list of frames the client sampled since its last
-- send, oldest first.
function RemoteInput.push(self: any, source: string, packed: { number })
	local s: Source = self.sources[source]
	if not s then
		return
	end
	for _, n in packed do
		if type(n) == "number" and n % 1 == 0 and n >= 0 and n < Net.MAX_PACKED then
			table.insert(s.queue, n)
		end
	end
	while #s.queue > MAX_QUEUED do
		table.remove(s.queue, 1)
	end
end

function RemoteInput.get(self: any, source: string): Input.Frame
	local s: Source = self.sources[source]
	if not s then
		return Input.emptyFrame()
	end
	local n = table.remove(s.queue, 1)
	if n == nil then
		-- Nothing arrived for this tick. Keep what is held, fire nothing new.
		s.starved += 1
		return Net.holdOnly(s.last)
	end
	s.starved = 0
	s.last = Net.unpackFrame(n)
	return s.last
end

return RemoteInput
