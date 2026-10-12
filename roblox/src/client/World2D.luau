--!strict
-- The world's things from the server: items, summons, projectiles and bursts - the web entity pass
-- in Canvas2D, with no client simulation of their positions. (Stage hazards are HazardArt's.)
local Canvas = require(script.Parent.Canvas2D)
local Effects = require(script.Parent.Effects)
local UltWorld = require(script.Parent.UltWorld)
local FxArt = require(script.Parent.FxArt)
local DropShapes = require(script.Parent.DropShapes)
local Weapons2D = require(script.Parent.Weapons2D)
local Items = require(game:GetService("ReplicatedStorage").Shared.Data.Items)
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(18, 25, 34)
local HOT = Color3.fromRGB(255, 171, 85)
local World2D = {}
-- The live effects state that orb projectiles trail sparks into; set by the client.
World2D.effects = nil :: any

local function rect(c: any, x: number, y: number, w: number, h: number, col: Color3, alpha: number?)
	Canvas.rect(c, x, y, w, h, col, alpha)
end
local function line(c: any, x: number, y: number, dx: number, dy: number, width: number, col: Color3, alpha: number)
	Canvas.save(c)
	Canvas.translate(c, x, y)
	Canvas.rotate(c, math.atan2(dy, dx))
	rect(c, 0, -width / 2, math.sqrt(dx * dx + dy * dy), width, col, alpha)
	Canvas.restore(c)
end
local function glow(chars: any, owner: number?): Color3
	local char = if owner ~= nil then chars[owner + 1] else nil
	return Canvas.hex(if char then char.weaponPalette.glow else nil, HOT)
end

function World2D.item(c: any, id: string, x: number, y: number, t: number, live: any?)
	local def = Items.BY_ID[id]
	if not def then return end
	local col, accent = Canvas.hex(def.colour, HOT), Canvas.hex(def.accent, WHITE)
	Canvas.save(c)
	Canvas.translate(c, x, y)
	if id == "BlastKeg" then
		rect(c, -0.72, 0, 1.44, 1.1, DARK)
		rect(c, -0.62, 0.08, 1.24, 0.96, col)
		rect(c, -0.72, 0.2, 1.44, 0.12, DARK)
		rect(c, -0.72, 0.8, 1.44, 0.12, DARK)
		rect(c, -0.34, 0.42, 0.68, 0.28, accent)
		rect(c, 0, 1.1, 0.1, 0.35, HOT)
	elseif id == "RivetGun" then
		rect(c, -0.55, 0.42, 1.17, 0.44, col)
		rect(c, 0.55, 0.52, 0.47, 0.22, DARK)
		rect(c, -0.38, 0, 0.36, 0.44, DARK)
		rect(c, -0.48, 0.88, 0.84 * (if live and live.uses then live.uses / 8 else 1), 0.16, accent)
	elseif id == "Bulwark" then
		rect(c, -0.86, 0, 1.72, 2.3, DARK)
		rect(c, -0.72, 0.1, 1.44, 2.1, col)
		rect(c, -0.72, 1.52, 1.44, 0.26, DARK)
		for i = 0, 4 do rect(c, -0.6 + i * 0.3, 0.28, 0.14, 0.14, accent) end
	elseif id == "SpringPlate" then
		local k = if live and live.cd and live.cd > 0 then 0.45 else 1
		rect(c, -1.7, 0, 3.4, 0.16, DARK)
		for _, cx in { -0.85, 0.85 } do
			for i = 0, 2 do rect(c, cx - 0.22, 0.18 + i * 0.18 * k, 0.44, 0.1, accent) end
		end
		rect(c, -1.7, 0.16 + 0.55 * k, 3.4, 0.35 * k, col)
	else
		Canvas.circle(c, 0, 0.55, 0.86 + math.sin(t * 5) * 0.08, accent, 0.28)
		Canvas.circle(c, 0, 0.55, 0.52, col)
		Canvas.circle(c, -0.16, 0.72, 0.13, WHITE, 0.6)
	end
	Canvas.restore(c)
end

-- A weapon drop (weapon drops): the shapes both builds draw (DropShapes, held to the web's
-- dropShapes.js), and a thrown weapon lying there as its own sprite on top.
function World2D.drop(c: any, d: any, frame: number)
	local shapes, sprite = DropShapes.shapes(d, frame)
	for _, sh in shapes do
		local col = Canvas.hex(sh[6], WHITE)
		if sh[1] == "r" then rect(c, sh[2], sh[3], sh[4], sh[5], col, sh[7])
		else Canvas.ellipse(c, sh[2], sh[3], sh[4], sh[5], col, sh[7]) end
	end
	if sprite then
		Canvas.save(c)
		Canvas.translate(c, sprite.x, sprite.y)
		Canvas.rotate(c, sprite.angle)
		Weapons2D.drawSprite(c, sprite.id, sprite.alpha)
		Canvas.restore(c)
	end
end

-- A thrown weapon: its own sprite, tumbling end over end - or point-first along its flight for the
-- two that fly like a spear or a bolt - as renderer2d.js draws it.
function World2D.thrownWeapon(c: any, p: any, t: number)
	local reach = Weapons2D.REACH[p.weapon] or 2
	local dir = if (p.vx or 0) < 0 then -1 else 1
	Canvas.save(c)
	Canvas.translate(c, p.x, p.y)
	Canvas.rotate(c, if p.pierce or p.weapon == "Longbow" then math.atan2(p.vy or 0, p.vx or 1) else -t * 16 * dir)
	Canvas.translate(c, -reach / 2, 0)
	Weapons2D.drawSprite(c, p.weapon, 1)
	Canvas.restore(c)
end

-- A Chakram ring in flight (Roblox only): the silver rim, the dark middle and the teal light the
-- weapon's art has, two notches on the rim spinning with the throw so it reads as a blade, not a
-- disc. The Eclipse Ring wears a teal halo and a cream glint. A few shapes a ring: cheap on Frames.
local RING_RIM, RING_DARK, RING_GLINT = Color3.fromHex("#C0C8D4"), Color3.fromHex("#0F2626"), Color3.fromHex("#F4E8C0")
function World2D.ring(c: any, p: any, t: number, col: Color3)
	local r = p.w / 2
	local eclipse = p.shape == "eclipse"
	if eclipse then
		Canvas.circle(c, p.x, p.y, r * 1.25, col, 0.3)
	end
	Canvas.circle(c, p.x, p.y, r, DARK)
	Canvas.circle(c, p.x, p.y, r * 0.86, RING_RIM)
	Canvas.circle(c, p.x, p.y, r * 0.58, col)
	Canvas.circle(c, p.x, p.y, r * 0.42, RING_DARK)
	local spin = t * 22 * (if (p.vx or 0) < 0 then -1 else 1)
	for k = 0, 1 do
		local a = spin + k * math.pi
		Canvas.save(c)
		Canvas.translate(c, p.x + math.cos(a) * r * 0.72, p.y + math.sin(a) * r * 0.72)
		Canvas.rotate(c, a)
		rect(c, -r * 0.16, -r * 0.16, r * 0.32, r * 0.32, if eclipse then RING_GLINT else WHITE)
		Canvas.restore(c)
	end
end

function World2D.entities(c: any, scene: any, chars: any, states: any, t: number)
	for _, d in scene.drops or {} do
		World2D.drop(c, d, scene.frame or 0)
	end
	for _, it in scene.items or {} do
		local x, y = it.x, it.y
		if it.held ~= nil then
			local st = states[it.held + 1]
			if not st or not st.alive then continue end
			x, y = st.x + st.facing * 1.2, st.y + 2.2
		elseif it.onGround then y += math.sin(t * 3 + x) * 0.12 end
		World2D.item(c, it.id, x, y, t, it)
	end
	for _, s in scene.summons or {} do
		local col = glow(chars, s.owner)
		if s.type == "mine" then
			Canvas.circle(c, s.x, s.y + 0.55, 0.65, DARK)
			Canvas.circle(c, s.x, s.y + 0.55, 0.45, if s.armed <= 0 then col else WHITE)
			if s.armed <= 0 then rect(c, s.x - s.trigger, s.y, s.trigger * 2, 0.14, col, 0.6) end
		elseif s.type == "wall" then rect(c, s.x - s.w / 2, s.y, s.w, s.h, col)
		else Canvas.circle(c, s.x, s.y + 0.6, s.r or 0.6, col, 0.55) end
	end
	for _, p in scene.projectiles or {} do
		local col = glow(chars, p.owner)
		if UltWorld.projectile(c, p, states, chars, t) then
			-- an ultimate's own projectile, drawn as what it is (UltWorld)
		elseif p.weapon then
			World2D.thrownWeapon(c, p, t)
		elseif p.item then
			World2D.item(c, p.item, p.x, p.y - 0.5, t, p)
		elseif p.shape == "ring" or p.shape == "eclipse" then
			World2D.ring(c, p, t, col)
		elseif p.shape == "orb" then
			-- a pulsing core, as renderer2d.js draws it, trailing sparks
			Canvas.circle(c, p.x, p.y, p.w * 0.85, col, 0.35)
			Canvas.circle(c, p.x, p.y, p.w * 0.45 * (0.55 + math.sin(t * 12) * 0.06), col)
			Canvas.circle(c, p.x - 0.1, p.y + 0.1, p.w * 0.18, WHITE)
			if World2D.effects then
				local char = if p.owner ~= nil then chars[p.owner + 1] else nil
				Effects.orbSparks(World2D.effects, p.x, p.y, p.vx or 0, if char then char.weaponPalette.glow else nil, math.random)
			end
		else
			local a = math.atan2(p.vy or 0, p.vx or 1)
			local length = if p.shape == "tracer" then 4.5 else 2.2
			line(c, p.x, p.y, -math.cos(a) * length, -math.sin(a) * length, 0.2, col, 0.6)
			rect(c, p.x - p.w / 2, p.y - p.h / 2, p.w, p.h, WHITE)
		end
	end
	-- A burst is a live circle of damage for a few frames: a pixel shockwave the size of it,
	-- rather than a flat white disc over whoever is standing in it.
	for _, b in scene.bursts or {} do
		local k = math.clamp(b.frames / 3, 0, 1)
		local art = FxArt.get("ring", math.floor((1 - k) * 4), "wind")
		FxArt.draw(c, art, b.x, b.y, b.radius * 2.3 * art.ppu / art.cols, 0, 0.5 + k * 0.5)
	end
end

return World2D
