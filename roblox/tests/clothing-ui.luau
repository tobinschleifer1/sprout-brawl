--!nocheck
-- Clothing on screen (phase 6; Roblox only): the Character Studio offers each category's clothing
-- after its free parts, wearable once owned and shown behind a SHOP lock until then; the Locker sends
-- a clothing card to the Studio instead of a slot; a clothing thumbnail is the default character
-- wearing the piece. The real modules, on the render tool's stub GUI.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Recorder = require("../tools/recorder")
local AvatarKit = Loader.load("AvatarKit")
local Clothing = Loader.load("RobloxClothing")
local KIT = AvatarKit.KIT

local new, made = Recorder.gui(1280, 720)
local enumNames = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
Loader.gui = { Instance = { new = new }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = enumNames }
local codes = setmetatable({}, { __index = function(_, k) return k end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, k) return k end })
local function never() return false end
local services = setmetatable({ ReplicatedStorage = { Shared = shared } }, { __index = function()
	local stub = { GetFocusedTextBox = never, IsKeyDown = never, IsGamepadButtonDown = never }
	stub.InputBegan = { Connect = function() end }
	return stub
end })
local function load(name: string): any
	return luau.load(fs.readFile("src/client/" .. name .. ".luau"), { debugName = name, environment = {
		game = { GetService = function(_, s) return services[s] end },
		script = { Parent = codes },
		require = function(target)
			if type(target) == "string" and fs.isFile("src/client/" .. target .. ".luau") then return Loader.loadFrom("src/client/", target) end
			return Loader.load(target)
		end,
		Instance = { new = new }, Enum = enumNames, Color3 = Rbx.Color3, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Vector2 = Rbx.Vector2,
		Random = { new = function()
			local seed = 7
			local function step() seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646 end
			return { NextInteger = function(_, a, b) return a + math.floor(step() * (b - a + 1)) end, NextNumber = function() return step() end }
		end },
		typeof = function(v) return type(v) end,
	}, injectGlobals = true })()
end
local playerGui = new("PlayerGui")

-- 1. The Studio: the free parts in order, the category's pieces spread among them (the owner's ask,
-- 2026-11-02: what the packs hold seen among what you have, not in a block at the end), owned ones
-- wearable.
local Editor = load("AvatarEditor")
local ed = Editor.new(playerGui, { send = function() end, weapon = function() return "Sword" end })
ed.gui.AbsoluteSize = Rbx.Vector2.new(1280, 720)
ed:open()
ed:layout(Rbx.Vector2.new(1280, 720))
local top = AvatarKit.category("top")
local opts = ed:optionsOf(top)
local tops = {}
for _, it in Clothing.items do if it.category == "top" then table.insert(tops, it.id) end end
assert(#opts == #top.options + #tops, "the Studio does not offer every top piece")
do
	local freeAt, paidAt = {}, {}
	for i, o in opts do
		if AvatarKit.piece(o.id) then table.insert(paidAt, i); assert(o.layers, `{o.id} is not offered as a drawable option`)
		else table.insert(freeAt, i) end
	end
	for k, o in top.options do assert(opts[freeAt[k]].id == o.id, "the free parts are out of their order") end
	for k, id in tops do assert(opts[paidAt[k]].id == id, "the pieces are out of their order") end
	assert(not AvatarKit.piece(opts[1].id), "a Shop piece is first, before the plain default")
	-- spread: never two pieces together, and no free run longer than an even share and one
	local share = math.ceil(#top.options / (#tops + 1)) + 1
	for k = 2, #paidAt do assert(paidAt[k] - paidAt[k - 1] > 1, "two Shop pieces sit together") end
	assert(paidAt[1] - 1 <= share and #opts - paidAt[#paidAt] <= share, "the Shop pieces are bunched at one end")
	for k = 2, #paidAt do assert(paidAt[k] - paidAt[k - 1] - 1 <= share, "the Shop pieces are not spread evenly") end
	-- and every category: the same, whatever its counts
	for _, c in AvatarKit.KIT.categories do
		local list = ed:optionsOf(c)
		if #list > 0 then assert(not AvatarKit.piece(list[1].id), `{c.id}'s first option is a Shop piece`) end
		for k = 2, #list do
			assert(not (AvatarKit.piece(list[k].id) and AvatarKit.piece(list[k - 1].id)) or #c.options < 2, `{c.id} has two Shop pieces together`)
		end
	end
	local edge = Editor.spread({ "a" }, { "x", "y" })
	assert(#edge == 3 and edge[1] == "a", "spreading two pieces over one free part lost one, or put one first")
	assert(#Editor.spread({}, { "x" }) == 1 and #Editor.spread({ "a", "b" }, {}) == 2, "spreading an empty list lost options")
end
ed:setView({ slots = { { name = "Me", code = AvatarKit.defaultCode() } }, active = 1, max = 8, saving = true, unlocked = {},
	pieces = { "neon_circuit_bomber" } })
assert(ed:wearable("top", "neon_circuit_bomber") and not ed:wearable("top", "frost_rimeguard_coat") and ed:wearable("top", top.options[2].id),
	"wearable does not follow what the server says is owned")
-- an unowned piece is not put on, and says where it is sold
local before = ed:code()
ed:pick("top", "frost_rimeguard_coat")
assert(ed:code() == before, "an unowned piece was put on")
local said = ed.message and ed.message.text or ""
assert(string.find(said, "Rimeguard Coat", 1, true) and string.find(said, "8 R$", 1, true) and string.find(said, "Frostforged", 1, true),
	"an unowned piece does not say where it is sold: " .. said)
ed:pick("top", "neon_circuit_bomber")
assert(string.sub(ed:code(), 1, 2) == "k2" and AvatarKit.decode(ed:code()).parts.top == "neon_circuit_bomber", "an owned piece was not put on")
-- the arrows step onto the owned piece from the wearable option before it, and never stop on an
-- unowned one
do
	local i = 0
	for k, o in opts do if o.id == "neon_circuit_bomber" then i = k end end
	local prev = i - 1
	while prev >= 1 and not ed:wearable("top", opts[prev].id) do prev -= 1 end
	ed:pick("top", opts[prev].id)
	ed:selectCategory("top")
	ed:step(1)
	assert(AvatarKit.decode(ed:code()).parts.top == "neon_circuit_bomber", "the arrows did not reach the owned piece")
	for _ = 1, #opts do
		ed:step(1)
		local on = AvatarKit.decode(ed:code()).parts.top
		assert(not AvatarKit.piece(on) or on == "neon_circuit_bomber", "the arrows stopped on an unowned piece")
	end
end
-- tiles: the unowned piece greyed over and priced, the owned one plain; the free one plain too
ed:rebuildTiles()
do
	local locked, owned = ed.tiles["frost_rimeguard_coat"], ed.tiles["neon_circuit_bomber"]
	local price = locked.button:FindFirstChild("Price")
	assert(locked.veil and locked.veil.Visible ~= false and price and price.Text == "8 R$", "an unowned Shop piece is not greyed and priced")
	assert(string.lower(locked.label.Text) == "rimeguard coat", "an unowned Shop piece's name carries a tag as well as its price")
	assert(not owned.veil and not owned.button:FindFirstChild("Price") and string.lower(owned.label.Text) == "circuit bomber",
		"an owned piece is greyed or priced")
	local free = ed.tiles[top.options[2].id]
	assert(not free.veil and not free.button:FindFirstChild("Price"), "a free part is greyed or priced")
	-- and the studio says which is which, when it has nothing else to say
	ed:loadSlot(ed.editing)                         -- (nothing unsaved)
	ed.message, ed.note = nil, nil
	ed:refreshFooter()
	assert(not ed:dirty() and ed.status.Text == Editor.FREE_NOTE, `the studio does not say what is free and what is greyed: {ed.status.Text}`)
end
-- randomising never hands out an unowned piece
for _ = 1, 20 do
	ed:randomizePart("top")
	local now = AvatarKit.decode(ed:code()).parts.top
	assert(not AvatarKit.piece(now) or now == "neon_circuit_bomber", "randomising put on an unowned piece")
end
-- a purchase arriving in a new view unlocks its tile
ed:setView({ slots = { { name = "Me", code = AvatarKit.defaultCode() } }, active = 1, max = 8, saving = true, unlocked = {},
	pieces = { "neon_circuit_bomber", "frost_rimeguard_coat" } })
ed:rebuildTiles()
assert(ed:wearable("top", "frost_rimeguard_coat") and string.lower(ed.tiles["frost_rimeguard_coat"].label.Text) == "rimeguard coat", "a newly owned piece stayed locked")

-- 2. The Locker: a clothing card goes to the Studio.
local Locker = load("LockerScreen")
local sent, studio = {}, 0
local lk = Locker.new(playerGui, { sendLocker = function(m) table.insert(sent, m) end, sendEconomy = function() end,
	openStudio = function() studio += 1 end, now = os.clock, rand = function() return 0.4 end })
lk:open()
lk:setLocker({ owned = { "neon_circuit_bomber" }, wearing = {} })
lk:setEconomy({ sparks = 0, crates = { scrap = 0, forge = 0 }, keys = { forge = 0 }, meter = 0, guarantees = { scrap = 25, forge = 40 },
	items = { { uid = "u1", id = "neon_circuit_bomber", serial = 3, copies = 120 } } })
local card
for _, c in lk.cardPool do if c.frame.Visible and c.name.Text == "Circuit Bomber" then card = c end end
assert(card and card.primary.Text == "WEAR IN STUDIO", "a clothing card offers a Locker slot")
assert(string.find(card.meta.Text, "#3", 1, true), "a clothing card lost its serial")
card.onPrimary()
assert(studio == 1 and #sent == 0 and not lk.root.Enabled, "WEAR IN STUDIO did not go to the Studio")
assert(Locker.TYPE_LABEL.clothing == "Clothing", "clothing has no label in the Locker")

-- 3. Thumbnails: the default character wearing the piece; head-worn pieces on a head.
local ItemArt = Loader.loadFrom("src/client/", "ItemArt")
for _, it in Clothing.items do
	local kind, arg = ItemArt.plan(it.id)
	local spec = arg and AvatarKit.decode(arg[1])
	assert(kind == "kit" and spec and spec.parts[it.category] == it.id, `{it.id}'s thumbnail does not wear it`)
	local others = AvatarKit.sanitize(nil)
	others.parts[it.category] = it.id
	assert(AvatarKit.encode(others) == arg[1], `{it.id}'s thumbnail wears more than the piece`)
	local head = it.category == "headwear" or it.category == "hair" or it.category == "eyewear"
	assert(arg[2] == (if head then "head" else "figure"), `{it.id}'s thumbnail shows the wrong view`)
end
local _ = made
print(`PASS clothing ui: the Studio offers {#tops} tops after {#top.options} free ones, wears what the server says is owned, says where the rest are sold, steps and randomises past them, spreads them through the free ones greyed and priced, unlocks a purchase; the Locker sends clothing to the Studio; every piece's thumbnail wears it`)
