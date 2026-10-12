--!nocheck
-- Dev/test boundary probe. Every proxy owns a REAL @lune/roblox Instance: assignments are
-- forwarded, not simulated. Count all assignments (including equal values), and recursively
-- count Destroy's descendants. Lune has no GUI layout, so only AbsoluteSize and UI input are
-- supplied. Production modules run unmodified with Roblox value types and a deterministic clock.
local fs, luau, Rbx = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local process = require("@lune/process")
local Probe = {}
Probe.__index = Probe

local function counters()
	return { writes = 0, creates = 0, destroys = 0, ms = 0, properties = {} }
end

function Probe.new(width, height, native, sourceRef)
	local self = setmetatable({ width = width, height = height, now = 0, section = "Setup",
		groups = {}, live = {}, owners = {}, raw = {}, proxies = {}, loaded = {}, native = native, sourceRef = sourceRef }, Probe)
	self.total = counters()
	local seed = 811
	self.math = table.clone(math)
	self.math.random = function(lo, hi)
		seed = (seed * 48271) % 2147483647
		local unit = seed / 2147483647
		if lo == nil then return unit end
		if hi == nil then hi, lo = lo, 1 end
		return lo + math.floor(unit * (hi - lo + 1))
	end
	local function count(key, property, amount)
		amount = amount or 1
		local group = self.groups[self.section]
		if not group then group = counters(); self.groups[self.section] = group end
		for _, c in { self.total, group } do
			c[key] += amount
			if property then c.properties[property] = (c.properties[property] or 0) + amount end
		end
	end
	local function new(class)
		local real = Rbx.Instance.new(class)
		-- There is no viewport/layout engine in Lune; never count this harness-only assignment.
		if class == "ScreenGui" or class == "Frame" then real.AbsoluteSize = Rbx.Vector2.new(width, height) end
		if native then return real end
		count("creates")
		self.live[real] = class
		self.owners[real] = self.section
		local proxy = setmetatable({}, {
			__index = function(_, k)
				if k == "Destroy" then return function()
					if not self.live[real] then return end
					local descendants = real:GetDescendants()
					for _, child in descendants do
						if self.live[child] then count("destroys"); self.live[child], self.owners[child] = nil, nil end
					end
					count("destroys"); self.live[real], self.owners[real] = nil, nil
					real:Destroy()
				end end
				if k == "GetChildren" or k == "GetDescendants" then return function()
					local out = {}
					for i, child in real[k](real) do out[i] = self.proxies[child] end
					return out
				end end
				if k == "FindFirstChild" then return function(_, name)
					return self.proxies[real:FindFirstChild(name)]
				end end
				if k == "Parent" then return self.proxies[real.Parent] end
				local value = real[k]
				if type(value) == "function" then return function(_, ...) return value(real, ...) end end
				return value
			end,
			__newindex = function(_, k, v)
				count("writes", k)
				real[k] = self.raw[v] or v
			end,
		})
		self.raw[proxy], self.proxies[real] = real, proxy
		return proxy
	end
	self.new = new
	return self
end

function Probe:load(path)
	if self.loaded[path] then return self.loaded[path] end
	local function proxy(prefix)
		return setmetatable({ path = prefix }, { __index = function(_, k) return proxy(prefix .. "/" .. k) end })
	end
	local directory = string.match(path, "^(.*)/[^/]+$")
	local env = {
		Instance = { new = self.new }, Color3 = Rbx.Color3, Vector2 = Rbx.Vector2,
		UDim2 = Rbx.UDim2, UDim = Rbx.UDim, Enum = Rbx.Enum,
		math = self.math,
		os = setmetatable({ clock = function() return self.now end }, { __index = os }),
		game = { GetService = function(_, name)
			if name == "ReplicatedStorage" then return { Shared = proxy("src/shared") } end
			if name == "UserInputService" then return {
				GetFocusedTextBox = function() return nil end, IsKeyDown = function() return false end,
			} end
			error("perf probe: no service " .. name)
		end },
		script = { Parent = proxy(directory) },
		require = function(target) return self:load(target.path) end,
	}
	local source
	if self.sourceRef then
		-- Read a baseline without checking it out or touching another worktree. No shell expansion.
		local result = process.exec("git", { "show", self.sourceRef .. ":roblox/" .. path .. ".luau" })
		assert(result.ok, result.stderr)
		source = result.stdout
	else
		source = fs.readFile(path .. ".luau")
	end
	local module = luau.load(source, { debugName = path, environment = env, injectGlobals = true })()
	self.loaded[path] = module
	return module
end

function Probe:reset()
	self.total, self.groups = counters(), {}
end

function Probe:frames()
	local count = 0
	for _, class in self.live do if class == "Frame" then count += 1 end end
	return count
end

function Probe:frameOwners()
	local out = {}
	for real, class in self.live do
		if class == "Frame" then local owner = self.owners[real]; out[owner] = (out[owner] or 0) + 1 end
	end
	return out
end

-- Non-overlapping draw entry points: attribution changes only in the dev process.
function Probe:wrap(module, method, section)
	local fn = module[method]
	module[method] = function(...)
		local before, start = self.section, os.clock()
		self.section = section
		local out = table.pack(fn(...))
		local group = self.groups[section]
		if not group then group = counters(); self.groups[section] = group end
		group.ms += (os.clock() - start) * 1000
		self.section = before
		return table.unpack(out, 1, out.n)
	end
end

return Probe
