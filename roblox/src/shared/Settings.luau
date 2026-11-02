--!strict
-- A player's settings (Roblox only; the owner's ask, 2026-11-02): their own keys, music and sound
-- volume, screen shake, and the hints. Saved in their record (AvatarStore) so they follow them to
-- any device; the server keeps only what `sanitize` rebuilds, the client applies them (Audio,
-- Bindings, the camera).
--
-- Keys: each action has its keys (Bindings.keyboard). Rebinding sets an action's FIRST key; the
-- rest of its keys stay unless another action now has them. An action whose first key that was is
-- given this action's old one - a swap, so nothing is ever keyless - unless the two shipped sharing
-- it (Jump and Aim up both have W): then it simply keeps its other keys, and Jump to W leaves Aim up
-- its arrow and Jump its Space, rather than moving Space to Aim up.
local Settings = {}

Settings.DEFAULTS = { music = 0.6, sfx = 0.8, shake = true, hints = true }

-- The actions a player may rebind, in the order the menu lists them.
Settings.ACTIONS = { "left", "right", "up", "down", "jump", "light", "heavy", "dodge", "guard", "grab", "pickup", "ult", "taunt" }
Settings.NAMES = { left = "Move left", right = "Move right", up = "Aim up", down = "Aim down / drop", jump = "Jump",
	light = "Light attack", heavy = "Heavy attack", dodge = "Dodge", guard = "Shield", grab = "Grab",
	pickup = "Pick up / throw", ult = "Ultimate", taunt = "Taunt" }

-- Keys that may be bound. Not Escape (Roblox's menu), Slash (chat), Tab (the player list), Backquote
-- or the F keys (Roblox's and the game's own: F3 is the performance overlay), nor H (the fight's
-- COMBOS guide, Hud.COMBO_KEY).
local ALLOWED: { [string]: boolean } = {}
for c = string.byte("A"), string.byte("Z") do
	if string.char(c) ~= "H" then ALLOWED[string.char(c)] = true end
end
for _, k in { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Space", "LeftShift",
	"RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt", "Up", "Down", "Left", "Right", "Semicolon", "Quote",
	"Comma", "Period", "LeftBracket", "RightBracket", "Minus", "Equals", "BackSlash", "Return", "Backspace" } do
	ALLOWED[k] = true
end
Settings.ALLOWED = ALLOWED
local ACTION: { [string]: boolean } = {}
for _, a in Settings.ACTIONS do ACTION[a] = true end

local function volume(v: any, default: number): number
	if type(v) ~= "number" or v ~= v then return default end
	return math.clamp(math.floor(v * 20 + 0.5) / 20, 0, 1)       -- (in steps of 5%)
end

-- Settings as they may be stored or sent: rebuilt, never trusted.
function Settings.sanitize(raw: any): any
	local src = if type(raw) == "table" then raw else {}
	local binds = {}
	if type(src.binds) == "table" then
		local used: { [string]: boolean } = {}
		for _, a in Settings.ACTIONS do
			local k = src.binds[a]
			-- (one first key per action, and never one key first for two)
			if type(k) == "string" and ALLOWED[k] and not used[k] then binds[a] = k; used[k] = true end
		end
	end
	return {
		music = volume(src.music, Settings.DEFAULTS.music),
		sfx = volume(src.sfx, Settings.DEFAULTS.sfx),
		shake = if type(src.shake) == "boolean" then src.shake else Settings.DEFAULTS.shake,
		hints = if type(src.hints) == "boolean" then src.hints else Settings.DEFAULTS.hints,
		binds = binds,
	}
end

-- The keyboard map these settings make from `defaults` (Bindings.keyboard's shape: action -> keys).
function Settings.keyboard(s: any, defaults: { [string]: { string } }): { [string]: { string } }
	local binds = (s and s.binds) or {}
	-- a key someone made an action's first key is that action's alone
	local claimed: { [string]: string } = {}
	for a, k in binds do claimed[k] = a end
	local out: { [string]: { string } } = {}
	for action, keys in defaults do
		local list: { string } = {}
		local first = binds[action]
		if first then table.insert(list, first) end
		for _, k in keys do
			if (claimed[k] == nil or claimed[k] == action) and not table.find(list, k) then table.insert(list, k) end
		end
		out[action] = list
	end
	-- An action whose only keys were all taken gets its default first key back, unless that too is
	-- someone's first key (then `bind`'s swap had already given it one).
	for action, list in out do
		if #list == 0 and defaults[action][1] and not claimed[defaults[action][1]] then list[1] = defaults[action][1] end
	end
	return out
end

-- The first key an action has now.
function Settings.first(s: any, defaults: { [string]: { string } }, action: string): string?
	return Settings.keyboard(s, defaults)[action][1]
end

-- Bind `key` as `action`'s first key. Returns new settings, and the action it was swapped with (or
-- nil), or nil and why not.
function Settings.bind(s: any, defaults: { [string]: { string } }, action: string, key: string): (any, string?)
	if not ACTION[action] then return nil, "That cannot be rebound." end
	if not ALLOWED[key] then return nil, "That key is kept for Roblox. Choose another." end
	local out = Settings.sanitize(s)
	local before = Settings.keyboard(out, defaults)
	local old = before[action][1]
	if old == key then return out, nil end
	-- (a binding elsewhere to the same key is given up: the key is this action's first now)
	for other, k in out.binds do
		if other ~= action and k == key then out.binds[other] = nil end
	end
	out.binds[action] = key
	-- whoever had the key FIRST gets the old key (a swap), unless both shipped with it and they have
	-- another key left
	local swapped = nil
	local after = Settings.keyboard(out, defaults)
	for other, keys in before do
		if other ~= action and keys[1] == key then
			local shared = table.find(defaults[other], key) ~= nil and table.find(defaults[action], key) ~= nil
			if old and (not shared or #after[other] == 0) then
				swapped = other
				out.binds[other] = old
			end
		end
	end
	return Settings.sanitize(out), swapped
end

-- Every key back to how the game ships.
function Settings.resetKeys(s: any): any
	local out = Settings.sanitize(s)
	out.binds = {}
	return out
end

-- How a key is written in the menu.
local NAMES = { LeftControl = "L Ctrl", RightControl = "R Ctrl", LeftShift = "L Shift", RightShift = "R Shift",
	LeftAlt = "L Alt", RightAlt = "R Alt", Up = "↑", Down = "↓", Left = "←", Right = "→", Zero = "0", One = "1", Two = "2",
	Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Semicolon = ";", Quote = "'",
	Comma = ",", Period = ".", LeftBracket = "[", RightBracket = "]", Minus = "-", Equals = "=", BackSlash = "\\",
	Return = "Enter", Backspace = "Bksp" }
function Settings.keyName(key: string?): string
	if not key then return "—" end
	return NAMES[key] or key
end

return Settings
