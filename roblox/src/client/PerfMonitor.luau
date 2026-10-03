--!strict
-- What the game costs and how the connection is doing, measured where it happens: the client's
-- draw time, the Frames it claims, how evenly snapshots arrive, how often the server corrects our
-- prediction and by how much, the ping, and (from attributes the server sets) its step time and
-- what it sends.
--
-- Two readers. Press F3 for an overlay. And every half second the numbers are written as
-- attributes on the canvas's ScreenGui (`Perf*`), where a Studio session can read them without
-- requiring a module - which Studio's inspection threads are not allowed to do.
--
-- Pure bookkeeping apart from the overlay: tests/perf-monitor.luau feeds it numbers.
local PerfMonitor = {}
PerfMonitor.__index = PerfMonitor

local WINDOW = 120             -- frames of history
local PUBLISH = 0.5            -- seconds between attribute writes

function PerfMonitor.new(): any
	local self = setmetatable({}, PerfMonitor)
	self.draws = {} :: { number }
	self.dts = {} :: { number }
	self.used, self.sprites = 0, 0
	self.arrivals = {} :: { number }
	self.bytes = {} :: { any }
	self.corrections = {} :: { any }
	self.ping = 0
	self.interp = 0
	self.lastPublish = -math.huge
	self.sections = {} :: { [string]: number }
	return self
end

-- How long a named part of the frame took (seconds), smoothed: published as PerfSection<name>.
function PerfMonitor.section(self: any, name: string, seconds: number)
	local was = self.sections[name]
	self.sections[name] = if was then was * 0.9 + seconds * 0.1 else seconds
end

local function push(list: { any }, v: any, cap: number)
	table.insert(list, v)
	if #list > cap then table.remove(list, 1) end
end

-- One rendered frame: its delta time, how long the draw took (seconds), and the canvas's Frame
-- and sprite counts.
function PerfMonitor.frame(self: any, dt: number, draw: number, used: number, sprites: number)
	push(self.dts, dt, WINDOW)
	push(self.draws, draw, WINDOW)
	self.used, self.sprites = used, sprites
end

-- A snapshot (or scene) arrived at `now` carrying `bytes`.
function PerfMonitor.arrival(self: any, now: number, bytes: number)
	push(self.arrivals, now, 64)
	push(self.bytes, { now, bytes }, 256)
end
function PerfMonitor.received(self: any, now: number, bytes: number)
	push(self.bytes, { now, bytes }, 256)
end

-- The server corrected our prediction by `distance` studs at `now`.
function PerfMonitor.correction(self: any, now: number, distance: number)
	push(self.corrections, { now, distance }, 128)
end

local function mean(list: { number }): number
	if #list == 0 then return 0 end
	local s = 0
	for _, v in list do s += v end
	return s / #list
end
local function percentile(list: { number }, p: number): number
	if #list == 0 then return 0 end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[math.clamp(math.ceil(#sorted * p), 1, #sorted)]
end

-- Everything, summarised over the window, at time `now`.
function PerfMonitor.stats(self: any, now: number): any
	local gaps = {}
	for i = 2, #self.arrivals do table.insert(gaps, self.arrivals[i] - self.arrivals[i - 1]) end
	local gap = mean(gaps)
	local var = 0
	for _, g in gaps do var += (g - gap) ^ 2 end
	local jitter = if #gaps > 1 then math.sqrt(var / (#gaps - 1)) else 0
	local bytes = 0
	for _, b in self.bytes do
		if now - b[1] <= 2 then bytes += b[2] end
	end
	local recent, total = 0, 0
	for _, c in self.corrections do
		if now - c[1] <= 2 then recent += 1; total += c[2] end
	end
	local dt = mean(self.dts)
	return {
		fps = if dt > 0 then 1 / dt else 0,
		drawMs = mean(self.draws) * 1000,
		drawP95 = percentile(self.draws, 0.95) * 1000,
		frames = self.used, sprites = self.sprites,
		snapHz = if gap > 0 then 1 / gap else 0,
		jitterMs = jitter * 1000,
		netKBs = bytes / 2 / 1024,
		corrections = recent / 2,
		correctionStuds = if recent > 0 then total / recent else 0,
		pingMs = self.ping * 1000,
		interpMs = self.interp * 1000,
	}
end

local ORDER = { "fps", "drawMs", "drawP95", "frames", "sprites", "snapHz", "jitterMs", "netKBs", "corrections",
	"correctionStuds", "pingMs", "interpMs" }
PerfMonitor.ORDER = ORDER

-- Writes the stats as Perf* attributes on `target` at most every PUBLISH seconds; returns them
-- when it did.
function PerfMonitor.publish(self: any, target: any, now: number): any
	if now - self.lastPublish < PUBLISH then return nil end
	self.lastPublish = now
	local s = self.stats(self, now)
	for _, k in ORDER do
		target:SetAttribute("Perf" .. string.upper(string.sub(k, 1, 1)) .. string.sub(k, 2), math.floor(s[k] * 100 + 0.5) / 100)
	end
	for name, v in self.sections do
		target:SetAttribute("PerfSection" .. name, math.floor(v * 1e5 + 0.5) / 100)
	end
	return s
end

-- The overlay's text.
function PerfMonitor.describe(s: any, server: any?): string
	local lines = {
		string.format("%.0f fps   draw %.2f ms (p95 %.2f)   %d frames, %d sprites", s.fps, s.drawMs, s.drawP95, s.frames, s.sprites),
		string.format("snapshots %.0f Hz, jitter %.1f ms   interp %.0f ms   in %.1f KB/s", s.snapHz, s.jitterMs, s.interpMs, s.netKBs),
		string.format("ping %.0f ms   corrections %.1f/s, %.2f studs", s.pingMs, s.corrections, s.correctionStuds),
	}
	if server then
		table.insert(lines, string.format("server step %.2f ms   out %.1f KB/s a player", server.stepMs or 0, server.outKBs or 0))
	end
	return table.concat(lines, "\n")
end

return PerfMonitor
