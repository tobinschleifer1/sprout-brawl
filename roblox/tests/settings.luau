--!nocheck
-- SETTINGS (the owner's ask, 2026-11-02): what may be set and how it is kept (shared/Settings), the
-- sound it controls (client/Audio), the menu (client/SettingsMenu) and the record it is saved in
-- (AvatarStore).
--     lune run tests/settings
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Settings = Loader.load("Settings")
local Bindings = Loader.loadFrom("src/client/", "Bindings")
local Audio = Loader.loadFrom("src/client/", "Audio")

local function fail(msg: string): never error(msg, 0) end
local SHIPPED = {}
for a, keys in Bindings.keyboard do SHIPPED[a] = table.clone(keys) end
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end

-- 1. What is kept: defaults for anything missing or wrong; volumes 0..1 in 5% steps; only keys
-- Roblox leaves to games, and never one key first for two actions.
do
	local d = Settings.sanitize(nil)
	if d.music ~= 0.6 or d.sfx ~= 0.8 or d.shake ~= true or d.hints ~= true or next(d.binds) ~= nil then fail("the defaults are wrong") end
	local s = Settings.sanitize({ music = 7, sfx = -1, shake = "no", hints = false, binds = { light = "Q", heavy = "Q", guard = "Escape",
		grab = "Slash", ult = "Tab", taunt = "F3", fly = "E", jump = 5, dodge = "Return" } })
	if s.music ~= 1 or s.sfx ~= 0 or s.shake ~= true or s.hints ~= false then fail("volumes or switches were kept out of range") end
	if s.binds.light ~= "Q" or s.binds.heavy ~= nil then fail("one key was kept first for two actions") end
	for _, bad in { "guard", "grab", "ult", "taunt", "fly", "jump" } do
		if s.binds[bad] ~= nil then fail(`a bind for {bad} to {tostring(s.binds[bad])} was kept`) end
	end
	if s.binds.dodge ~= "Return" then fail("an allowed key was dropped") end
	if Settings.sanitize({ music = 0.333 }).music ~= 0.35 or Settings.sanitize({ sfx = 0 / 0 }).sfx ~= 0.8 then fail("volumes are not kept in 5% steps") end
	-- the actions are exactly the keyboard's
	for _, a in Settings.ACTIONS do if not SHIPPED[a] then fail(`{a} is offered for rebinding but is not a key the game reads`) end end
	for a in SHIPPED do if not table.find(Settings.ACTIONS, a) then fail(`{a} has keys but cannot be rebound`) end end
end

-- 2. The keyboard settings make: unchanged without binds; a new first key; a swap; a secondary
-- key taken; keys Roblox keeps refused; and after any run of rebinds every action still has a key
-- and no key is first for two.
do
	local kb = Settings.keyboard(Settings.sanitize(nil), SHIPPED)
	for a, keys in SHIPPED do if not same(kb[a], keys) then fail(`with no binds, {a} is {table.concat(kb[a], ",")}`) end end
	-- light to K: Heavy had K first, so Heavy takes Light's old J
	local s, swapped = Settings.bind(nil, SHIPPED, "light", "K")
	kb = Settings.keyboard(s, SHIPPED)
	if swapped ~= "heavy" or kb.light[1] ~= "K" or kb.heavy[1] ~= "J" then fail(`light to K: light {table.concat(kb.light, ",")}, heavy {table.concat(kb.heavy, ",")}`) end
	-- grab to Left Ctrl: Shield's second key; Shield keeps I and loses Left Ctrl
	s = Settings.bind(nil, SHIPPED, "grab", "LeftControl")
	kb = Settings.keyboard(s, SHIPPED)
	if kb.grab[1] ~= "LeftControl" or table.find(kb.guard, "LeftControl") or kb.guard[1] ~= "I" then fail("taking a second key did not move it alone") end
	-- jump to Q keeps W and Up as jumps too (the second keys stay)
	s = Settings.bind(nil, SHIPPED, "jump", "Q")
	kb = Settings.keyboard(s, SHIPPED)
	if not same(kb.jump, { "Q", "Space", "W", "Up" }) then fail(`jump to Q gave {table.concat(kb.jump, ",")}`) end
	for _, kept in { "Escape", "Slash", "Tab", "F3", "Backquote", "F9", "LeftSuper" } do
		local out, why = Settings.bind(nil, SHIPPED, "light", kept)
		if out or not why then fail(`{kept} could be bound`) end
	end
	if Settings.bind(nil, SHIPPED, "fly", "Q") then fail("an action that does not exist was bound") end
	-- a long run of rebinds, every key and action, in a fixed pseudo-random order
	local keys = {}
	for k in Settings.ALLOWED do table.insert(keys, k) end
	table.sort(keys)
	local seed = 7
	local function rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
	s = Settings.sanitize(nil)
	for i = 1, 2000 do
		local a = Settings.ACTIONS[rand(#Settings.ACTIONS)]
		local k = keys[rand(#keys)]
		s = Settings.bind(s, SHIPPED, a, k)
		if not s then fail(`binding {a} to {k} was refused`) end
		kb = Settings.keyboard(s, SHIPPED)
		if Settings.first(s, SHIPPED, a) ~= k then fail(`after binding {a} to {k}, its first key is {tostring(kb[a][1])}`) end
		local firsts = {}
		for act, list in kb do
			if #list == 0 then fail(`after {i} rebinds {act} has no key`) end
			if firsts[list[1]] then fail(`after {i} rebinds {list[1]} is first for {firsts[list[1]]} and {act}`) end
			firsts[list[1]] = act
		end
		-- and what is kept is what was made (sanitize changes nothing)
		local again = Settings.keyboard(Settings.sanitize(s), SHIPPED)
		for act, list in kb do if not same(list, again[act]) then fail("a saved and reloaded set of keys came back different") end end
	end
	local back = Settings.keyboard(Settings.resetKeys(s), SHIPPED)
	for a, list in SHIPPED do if not same(back[a], list) then fail("RESET KEYS did not put every key back") end end
	if Settings.keyName("LeftControl") ~= "L Ctrl" or Settings.keyName("Q") ~= "Q" or Settings.keyName(nil) ~= "—" then fail("key names read wrong") end
end

-- 3. Sound: which event makes which sound; never more than one of a sound per GAP or PER_FRAME
-- sounds a frame; silent at zero volume; three voices a sound at most; only the client's own sounds.
do
	if Audio.forEvent({ type = "hit", heavy = false, launch = 10 }) ~= "hit" or Audio.forEvent({ type = "hit", heavy = true }) ~= "hitheavy"
		or Audio.forEvent({ type = "hit", launch = 80 }) ~= "hitheavy" or Audio.forEvent({ type = "movestart", heavy = true }) ~= "whiffheavy"
		or Audio.forEvent({ type = "movestart" }) ~= "whiff" or Audio.forEvent({ type = "ko" }) ~= "ko" or Audio.forEvent({ type = "grabhit" }) ~= "grab"
		or Audio.forEvent({ type = "respawn" }) ~= nil or Audio.forEvent(nil) ~= nil then
		fail("a match event makes the wrong sound")
	end
	for name, def in Audio.SOUNDS do
		if string.sub(def.id, 1, 18) ~= "rbxasset://sounds/" then fail(`{name} is not one of the Roblox client's own sounds: {def.id}`) end
		if def.volume <= 0 or def.volume > 1 or def.speed - def.spread <= 0 then fail(`{name}'s volume or speed is out of range`) end
	end
	local now, made, played = 0, 0, {}
	local a = Audio.new({ clock = function() return now end, rand = function() return 0.5 end, make = function(name)
		made += 1
		return { Play = function() table.insert(played, name) end }
	end })
	a:setVolumes(0.5, 0.7)
	if not a:play("hit") or a:play("hit") then fail("a sound played twice in one moment") end
	now = Audio.GAP
	if not a:play("hit") then fail("a sound could not play again after its gap") end
	now = 1
	local n = 0
	for _, name in { "jump", "land", "whiff", "block", "chip", "dodge", "dash", "grab", "ko" } do
		if a:play(name) then n += 1 end
	end
	if n ~= Audio.PER_FRAME then fail(`{n} sounds started in one frame, not at most {Audio.PER_FRAME}`) end
	for i = 1, 20 do now = 2 + i; a:play("hit") end
	local hits = 0
	for _, s in a.pool.hit do if type(s) == "table" then hits += 1 end end
	if hits ~= 3 then fail(`the hit sound has {hits} voices, not 3`) end
	if a:play("nope") then fail("an unknown sound played") end
	a:setVolumes(0.5, 0)
	now = 100
	if a:play("jump") then fail("a sound played with the effects volume at zero") end
	local g = { music = { Volume = 1 }, sfx = { Volume = 1 } }
	local b = Audio.new({ groups = g, make = function() return nil end })
	b:setVolumes(2, -1)
	if g.music.Volume ~= 1 or g.sfx.Volume ~= 0 then fail("the groups' volumes were not set and clamped") end
end

-- 4. The menu: - and +, the switches, a key chosen (and a swap said), Escape cancelling, RESET KEYS,
-- and every change handed on as kept settings.
do
	local function signal()
		local fns = {}
		return { Connect = function(_, fn) table.insert(fns, fn) end, Fire = function() for _, fn in fns do fn() end end }
	end
	local function instance(class: string): any
		local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), Text = "", _children = {} }
		local self: any
		props.GetChildren = function() return table.clone(props._children) end
		props.FindFirstChild = function(_, name)
			for _, c in props._children do if c.Name == name then return c end end
			return nil
		end
		self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
			if key == "Parent" and value then table.insert(value._children, self) end
			props[key] = value
		end })
		return self
	end
	local codes = setmetatable({}, { __index = function(_, name) return name end })
	Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
	local Menu = Loader.loadFrom("src/client/", "SettingsMenu")
	local changes, tutorials = {}, 0
	local root = instance("Folder")
	local menu = Menu.new(root, SHIPPED, { onChange = function(s) table.insert(changes, s) end, onTutorial = function() tutorials += 1 end })
	local function find(node, name)
		for _, c in node._children do
			if c.Name == name then return c end
			local d = find(c, name)
			if d then return d end
		end
		return nil
	end
	local function press(row, button) find(find(root, row), button).Activated:Fire() end
	menu:open()
	press("Volume_music", "Down")
	if #changes ~= 1 or changes[1].music ~= 0.5 or find(find(root, "Volume_music"), "Value").Text ~= "50%" then fail("Music - did not turn it down 10%") end
	for _ = 1, 8 do press("Volume_sfx", "Up") end
	if changes[#changes].sfx ~= 1 or find(find(root, "Volume_sfx"), "Value").Text ~= "100%" then fail("Sound effects + went past 100% or not up") end
	press("Switch_shake", "Toggle")
	if changes[#changes].shake ~= false or find(find(root, "Switch_shake"), "Toggle").Text ~= "OFF" then fail("the shake switch did not turn it off") end
	-- a key: press Light's box, then K - Heavy had K, and the menu says so
	press("Key_light", "Bind")
	if find(find(root, "Key_light"), "Bind").Text ~= "press a key…" then fail("the key box does not ask for a key") end
	local before = #changes
	if not menu:key("K") then fail("the menu did not take the key it asked for") end
	local s = changes[#changes]
	if #changes ~= before + 1 or s.binds.light ~= "K" or s.binds.heavy ~= "J" then fail("choosing K for Light did not swap Heavy to J") end
	if not string.find(find(root, "KeyNote").Text, "Heavy attack", 1, true) then fail(`the swap was not said: {find(root, "KeyNote").Text}`) end
	if string.sub(find(find(root, "Key_light"), "Bind").Text, 1, 1) ~= "K" then fail("Light's box does not show K") end
	-- a key Roblox keeps: refused, said, nothing changed
	press("Key_guard", "Bind")
	before = #changes
	menu:key("Slash")
	if #changes ~= before or not string.find(find(root, "KeyNote").Text, "Roblox", 1, true) then fail("a kept key was not refused with a reason") end
	-- Escape cancels; a key with nothing asked is not the menu's
	press("Key_guard", "Bind")
	menu:key("Escape")
	if #changes ~= before or menu.listening or not string.find(find(root, "KeyNote").Text, "Press a key box", 1, true) then
		fail(`Escape did not cancel choosing a key quietly: {find(root, "KeyNote").Text}`)
	end
	if menu:key("Q") then fail("the menu took a key nobody asked it for") end
	press("ResetKeys", "Reset")
	if next(changes[#changes].binds) ~= nil then fail("RESET KEYS kept a binding") end
	press("Tutorial", "StartTutorial")
	if tutorials ~= 1 or menu:isOpen() then fail("PLAY TUTORIAL did not close the menu and start it") end
	-- whatever the menu hands on is already kept as it would be stored
	for _, c in changes do
		local kept = Settings.sanitize(c)
		if kept.music ~= c.music or kept.sfx ~= c.sfx or kept.shake ~= c.shake then fail("the menu handed on settings that would not be kept") end
	end
end

-- 5. The record: settings and the tutorial's flag survive a save and a hand edit; a change from
-- the menu is kept as sanitize rebuilds it and marks the record to save.
do
	local Store = Loader.loadFrom("src/server/", "AvatarStore")
	local rec = Store.sanitize({ settings = { music = 0.2, binds = { light = "Q", heavy = "Escape" } }, tutorial = true })
	if rec.settings.music ~= 0.2 or rec.settings.binds.light ~= "Q" or rec.settings.binds.heavy ~= nil or rec.tutorial ~= true then
		fail("a record's settings or tutorial flag did not survive being read")
	end
	if Store.sanitize({ tutorial = "yes" }).tutorial ~= false then fail("a tutorial flag that is not true was kept") end
	local store = Store.new(nil, function() return 5 end)
	store:setSettings(9, { sfx = 0.25, shake = false, binds = { grab = "Tab" } })
	local v = store:view(9)
	if v.settings.sfx ~= 0.25 or v.settings.shake ~= false or v.settings.binds.grab ~= nil or store:load(9).settings.binds.grab ~= nil
		or not store.dirty[9] then
		fail("settings from the menu were not kept as sanitized, or not marked to save")
	end
	if v.tutorial ~= false then fail("a new player's view says the tutorial is done") end
	store.dirty[9] = nil
	store:finishTutorial(9)
	if not store:view(9).tutorial or not store.dirty[9] then fail("finishing the tutorial was not kept") end
end

print("PASS settings: volumes in 5% steps, switches, keys Roblox leaves to games; a rebind swaps or takes a second key, 2000 rebinds leave every action a key")
print("  and no key first twice; RESET KEYS; sounds by event (the client's own), gapped, six a frame, three voices, silent at zero; the menu; the record")
