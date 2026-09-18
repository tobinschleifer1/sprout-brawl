--!strict
-- Loads a shipping ModuleScript outside Roblox, for the Lune tests.
--
-- The modules under src/shared use Roblox-style `require(script.Parent.Foo)` and
-- `require(script.Parent.Data.Weapons)`. Rather than compromise that for testability, this shims
-- `script` and `require`: `script.Parent.Data.Weapons` resolves to the path "Data/Weapons", which
-- the shimmed require turns back into a loaded module from src/shared/Data/Weapons.luau.
--
-- Shared by tests/parity.luau and tests/data-parity.luau, because a subtle test shim maintained in
-- two places is a subtle test shim that disagrees with itself.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SHARED = "src/shared/"

local loaded: { [string]: any } = {}
-- proxy table -> the module path it stands for
local paths: { [any]: string } = {}

local function proxy(prefix: string): any
	local t = setmetatable({}, {
		__index = function(_, key: string): any
			return proxy(if prefix == "" then key else prefix .. "/" .. key)
		end,
	})
	paths[t] = prefix
	return t
end

local Loader = {}

function Loader.load(name: string): any
	if loaded[name] then
		return loaded[name]
	end
	local source = fs.readFile(SHARED .. name .. ".luau")
	local dir = string.match(name, "^(.*)/[^/]*$")     -- a module's Parent is its folder
	local env = {
		script = { Parent = proxy(dir or ""), Name = name },
		require = function(target: any): any
			local p = paths[target]
			if p then
				return Loader.load(p)
			end
			error("test loader: unsupported require target " .. tostring(target))
		end,
	}
	local chunk = luau.load(source, { debugName = name, environment = env, injectGlobals = true })
	loaded[name] = chunk()
	return loaded[name]
end

return Loader
