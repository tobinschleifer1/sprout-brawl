--!strict
-- World-space threats from the server. A compact Canvas2D port of the web entity/hazard passes:
-- distinct silhouettes, visible warning phases, and no client simulation of hazard positions.
local Canvas = require(script.Parent.Canvas2D)
local Items = require(game:GetService("ReplicatedStorage").Shared.Data.Items)
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(18, 25, 34)
local HOT = Color3.fromRGB(255, 171, 85)
local WATER = Color3.fromRGB(91, 166, 188)
local SAND = Color3.fromRGB(207, 172, 116)
local World2D = {}

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

function World2D.entities(c: any, scene: any, chars: any, states: any, t: number)
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
		if p.item then
			World2D.item(c, p.item, p.x, p.y - 0.5, t, p)
		elseif p.shape == "orb" then
			Canvas.circle(c, p.x, p.y, p.w * 0.85, col, 0.35)
			Canvas.circle(c, p.x, p.y, p.w * 0.45, col)
			Canvas.circle(c, p.x - 0.1, p.y + 0.1, p.w * 0.18, WHITE)
		else
			local a = math.atan2(p.vy or 0, p.vx or 1)
			local length = if p.shape == "tracer" then 4.5 else 2.2
			line(c, p.x, p.y, -math.cos(a) * length, -math.sin(a) * length, 0.2, col, 0.6)
			rect(c, p.x - p.w / 2, p.y - p.h / 2, p.w, p.h, WHITE)
		end
	end
	for _, b in scene.bursts or {} do
		Canvas.circle(c, b.x, b.y, b.radius, WHITE, math.clamp(b.frames / 3, 0, 1) * 0.65)
	end
end

function World2D.hazards(c: any, v: any, stage: any, t: number)
	local top = stage.main.top
	local vents = v.vents
	if vents then
		for _, x in vents.positions do
			rect(c, x - vents.width / 2, top, vents.width, 0.7, DARK)
			local armed = table.find(vents.armed, x) ~= nil
			for i = 0, 4 do rect(c, x - vents.width / 2 + 0.5 + i * (vents.width - 1) / 4, top + 0.1, 0.3, 0.6, HOT, if armed and vents.phase ~= "idle" then 1 else 0.25) end
			if armed and vents.phase ~= "idle" then
				for i = 0, 11 do
					local k = (t * 1.3 + i / 12) % 1
					local height = if vents.phase == "warn" then 4 else 26 * vents.strength
					Canvas.circle(c, x + math.sin(i * 7 + t) * k * 2, top + k * height, 0.45 + k * 2, WHITE, (1 - k) * 0.35)
				end
			end
		end
	end
	if v.slagfall then for _, d in v.slagfall.drops do rect(c, d.x - 0.2, d.y, 0.4 + (d.splash or 0), 0.7, HOT) end end
	local jet = v.sprinkler
	if jet then
		for _, w in jet.wet do rect(c, w.x - 1.5, w.y, 3, 0.16, WATER, w.k * 0.8) end
		if jet.phase == "active" then
			for i = 0, 15 do
				local k = (t * 1.5 + i / 16) % 1
				line(c, jet.x + math.sin(i * 5) * jet.radius, jet.height * k, jet.dir * 0.9, -1.3, 0.13, WATER, 0.7)
			end
		elseif jet.phase == "warn" then rect(c, jet.x - jet.radius, top + 0.2, jet.radius * 2, 0.3, WATER, 0.6 + jet.k * 0.4) end
	end
	local arc = v.antennaarc
	if arc and arc.phase ~= "idle" then
		for i = 0, 11 do
			local dx = (arc.x2 - arc.x1) / 12
			local y = arc.y + (if i % 2 == 0 then -0.5 else 0.5)
			line(c, arc.x1 + i * dx, y, dx, if i % 2 == 0 then 1 else -1, if arc.phase == "active" then 0.35 else 0.1, WATER, if arc.phase == "active" then 1 else 0.5)
		end
	end
	local dust = v.dustdevil
	if dust then
		if dust.active then
			for i = 0, 15 do
				local k = i / 15
				local radius = dust.radius * (0.45 + 0.55 * k)
				Canvas.ellipse(c, dust.x + math.sin(dust.spin + k * 10) * radius * 0.2, top + k * dust.height, radius, 0.75, SAND, 0.35)
			end
		elseif dust.warn then rect(c, dust.from - 2, top + 0.5, 4, 0.4, SAND, 0.5 + dust.warnK * 0.5) end
	end
	local sand = v.sandfall
	if sand and sand.phase ~= "idle" then
		for i = 0, 15 do
			local k = (t * 0.8 + i / 16) % 1
			local y = if sand.phase == "active" then sand.from + (sand.to - sand.from) * k else sand.from - k * 2
			rect(c, sand.x + math.sin(i * 31) * sand.width / 2, y, 0.22, 0.7, SAND, 0.8)
		end
	end
	local tide = v.tide
	if tide then
		for _, edge in { -1, 1 } do
			local x = if edge < 0 then stage.blast.left else tide.edge
			local width = if edge < 0 then -tide.edge - stage.blast.left else stage.blast.right - tide.edge
			rect(c, x, stage.blast.bottom, width, tide.level - stage.blast.bottom, Color3.fromRGB(26, 63, 78), 0.7)
			rect(c, x, tide.level, width, 0.3, WATER, 0.9)
		end
	end
	local wave = v.roguewave
	if wave and (wave.active or wave.warn) then
		local y = if tide then tide.level else top
		if wave.active then
			Canvas.ellipse(c, wave.x, y + wave.crest / 2, wave.width / 2, wave.crest / 2, WATER, 0.7)
			line(c, wave.x - wave.width / 3, y + wave.crest * 0.85, wave.width * 0.6, 0.4, 0.4, WHITE, 0.8)
		else rect(c, stage.main.x1, y + 0.5, stage.main.x2 - stage.main.x1, 0.15, WHITE, 0.6) end
	end
	local wind = v.crosswind
	if wind and wind.phase ~= "calm" then
		for i = 0, 11 do
			local x = stage.main.x1 + ((i * 7 + t * 12 * wind.dir) % (stage.main.x2 - stage.main.x1))
			rect(c, x, top + 3 + i * 1.7, if wind.phase == "warn" then 1 else 4, 0.1, WHITE, 0.35)
		end
	end
	local ember = v.emberdrift
	if ember then
		for _, x in ember.positions do
			for i = 0, 7 do
				local k = (t * 0.3 + i / 8) % 1
				rect(c, x + math.sin(i * 13 + t) * ember.width / 2, ember.from + (ember.to - ember.from) * k, 0.2, 0.3, HOT, ember.pulse)
			end
		end
	end
end
return World2D
