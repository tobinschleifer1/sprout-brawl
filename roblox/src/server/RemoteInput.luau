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

-- How deep the buffer is allowed to SIT. This is the number that decides felt input latency, and
-- MAX_QUEUED was never it: the client sends one frame per tick and the server drains one per tick,
-- so in-rate equals out-rate and a queue that ever gets deep STAYS deep. Every input after it
-- waits exactly that long, forever, and MAX_QUEUED only capped the damage at six frames - 100ms of
-- standing latency, with the oldest frames dropped outright once it filled.
--
-- Two frames is 33ms: enough to absorb ordinary jitter, shallow enough to feel direct. Anything
-- above it is drained in the same tick by coalescing, so the backlog costs a frame of precision
-- rather than a permanent handicap.
local TARGET_QUEUED = 2

local RemoteInput = {}
RemoteInput.__index = RemoteInput

export type Source = {
	queue: { number },
	last: Input.Frame,
	starved: number,
	-- How many frames this source has had CONSUMED, including ones coalesced away or dropped on
	-- overflow. The client knows how many it has sent, so this one number tells it exactly which
	-- of its inputs the server has already accounted for - which is the whole basis of rollback.
	-- Counting sends rather than consumes would drift the moment the queue overflowed.
	consumed: number,
}

function RemoteInput.new(): any
	local self = setmetatable({}, RemoteInput)
	self.sources = {} :: { [string]: Source }
	self.kb2Active = false
	return self
end

function RemoteInput.register(self: any, source: string)
	self.sources[source] = { queue = {}, last = Input.emptyFrame(), starved = 0, consumed = 0 }
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
		-- Dropped, but the client must still count it as accounted for or its replay would be one
		-- frame long forever after the first overflow.
		s.consumed += 1
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
	s.consumed += 1
	local frame = Net.unpackFrame(n)
	-- Drain anything above the target in this same tick rather than letting it sit. Coalescing
	-- keeps every press and takes the newest axes, so catching up costs precision on one frame
	-- instead of adding permanent latency to every frame after it.
	while #s.queue > TARGET_QUEUED do
		-- The loop condition guarantees a value; the checker cannot see that through table.remove.
		local nxt = table.remove(s.queue, 1) :: number
		s.consumed += 1
		frame = Net.coalesce(frame, Net.unpackFrame(nxt))
	end
	s.starved = 0
	s.last = frame
	return frame
end

-- What the client needs to know to replay: how many of its frames are already in the past.
function RemoteInput.consumedBy(self: any, source: string): number
	local s: Source = self.sources[source]
	return if s then s.consumed else 0
end

return RemoteInput
