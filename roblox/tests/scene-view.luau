--!strict
-- Live simulations supply every hazard visual, then the shipping renderer paints it through a
-- primitive recorder. This proves threats survive the wire and actually claim visible shapes.
local Loader = require("./loader")
local serde = require("@lune/serde")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Stages = Loader.load("Data/Stages")
local Items = Loader.load("Data/Items")
local Scene = Loader.load("SceneSnapshot")
local Input = Loader.load("Input")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local World = Loader.loadFrom("src/client/", "World2D")
local Stage2D = Loader.loadFrom("src/client/", "Stage2D")
local StageMod = Loader.load("Stage")
local primitive = function(c: any, ...: any)
	local args = { ... }
	for i = 1, 4 do
		local value = args[i]
		if type(value) == "number" then assert(value == value and math.abs(value) < math.huge, "nonfinite drawing geometry") end
	end
	c.used += 1
end
Canvas.rect = primitive
Canvas.circle = primitive
Canvas.ellipse = primitive
-- A sprite is one container Frame moved per draw (an ultimate's projectile, a burst's ring).
Canvas.sprite = function(c: any, _key: string, rects: any, x0: number, y1: number, pw: number, ph: number)
	assert(#rects > 0, "a sprite with no rectangles")
	primitive(c, x0, y1, pw, ph)
end
local function canvas(): any
	return { used = 0, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {}, gui = { AbsoluteSize = { X = 1280, Y = 720 } } }
end
local checked: { [string]: boolean } = {}
local maxFrames = 0
for _, stage in Stages.LIST do
	local chars = { Loadout.build("Classic", "Blasters"), Loadout.build("Noir", "Grimoire") }
	local m = Match.new({ mode = "Training", stage = stage, seed = 1, items = false,
		input = { poll = function() end, get = function() return Input.emptyFrame() end },
		fighters = { { char = chars[1], source = "p1", team = 0 }, { char = chars[2], source = "p2", team = 1 } } })
	-- the realm's sky behind it: a gradient, a sun and four parallax layers (tests/realms.luau
	-- holds the layers to the screen; here, that every stage's sky draws, and draws a bounded amount)
	local background = canvas()
	Stage2D.sky(background, StageMod.new(stage, 1), -100, 0)
	-- 30 gradient strips, the sun's three discs, and at least one tile of each of four layers
	assert(background.used >= 37 and background.used < 120, `background draw must be substantial and bounded ({background.used})`)
	assert(#background.stack == 0, "background stack balance")
	for frame = 1, 2600 do
		m:step()
		if frame % 5 == 0 then
			local packet = Scene.encode(m)
			assert(packet.hazards == m.stage.visual, "authoritative hazard visual must reach the packet")
			for name, v in packet.hazards do
				local c = canvas()
				World.hazards(c, { [name] = v }, m.stage, frame / 60)
				if c.used > 0 then checked[name] = true end
				assert(#c.stack == 0, name .. " leaked a transform")
			end
		end
	end
	for _, def in Items.LIST do m.combat:spawnItem(def, 0, 2) end
	local owner = m.fighters[1]
	local projectile: any = { owner = owner, x = 1, y = 5, vx = 12, vy = 0, w = 0.5, h = 0.3, shape = "slug", life = 20 }
	projectile.self = projectile -- deliberately cyclic engine-only data must never cross the wire
	m.combat.projectiles = { projectile }
	m.combat:spawnBurst(owner, { x = 0, y = 3, size = { 4, 4 }, damage = 0, base = 0, growth = 0, angle = 0 })
	local packet = serde.decode("json", serde.encode("json", Scene.encode(m)))
	assert(#packet.projectiles == 1 and packet.projectiles[1].owner == 0, "projectile and owner identity must survive encoding")
	assert(packet.projectiles[1].x == projectile.x and packet.projectiles[1].w == projectile.w, "projectile position and size must survive encoding")
	assert(#packet.items == #Items.LIST and #packet.bursts == 1, "items and bursts must survive encoding")
	for _, key in { "projectiles", "items", "bursts" } do
		local c = canvas()
		World.entities(c, { [key] = packet[key] }, chars, {}, 1)
		assert(c.used > 0, key .. " must actually draw")
		assert(#c.stack == 0, key .. " leaked transforms")
		maxFrames = math.max(maxFrames, c.used)
	end
end
local count = 0
for _, stage in Stages.LIST do for _, hazard in stage.hazards do assert(checked[hazard.type], "invisible hazard: " .. hazard.type) end end
for _ in checked do count += 1 end
assert(count == 10, "all ten hazards must be exercised")
print(`PASS scene: all {count} hazards draw from live simulations; {#Stages.LIST} backgrounds; serializable projectiles, five items and bursts (peak entity group {maxFrames} Frames)`)
