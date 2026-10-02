--!strict
-- The parts of the ultimates that live in the WORLD rather than in the caster's hand: the rune
-- circle every ultimate stands in, the greatsword's burning fissure, the falling sky of Astral
-- Rain and the targets painted under its stars, the anchor and its chain, Aegis's barrier,
-- Deadeye's sight, Exsanguinate's marks over their victims, Rundown's afterimages, and the
-- ultimates' own projectiles.
--
-- These are drawn every frame from state, not spawned, because they are things a player reads
-- and acts on - where the chain is, who is painted, how much the barrier holds - and not
-- decoration. The web renderer's _ultWorld draws the same information (renderer2d.js); this is the
-- Roblox build's pixel-art treatment of it, built from FxArt.
--
-- `under` draws behind the fighters, `over` in front of them.
local Shared = game:GetService("ReplicatedStorage").Shared
local Stage = require(Shared.Stage)
local Canvas2D = require(script.Parent.Canvas2D)
local FxArt = require(script.Parent.FxArt)

local UltWorld = {}

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(18, 14, 22)

local function moveOf(s: any, char: any): any
	if s.moveId ~= "Ultimate" or not char or not char.moves then return nil end
	return char.moves.Ultimate
end

-- windup / active / end, the progress through it, and the frame within the active window.
local function phase(s: any, m: any): (string, number, number)
	local mf, su = s.moveFrame or 0, s.startupEff or m.startup
	if mf <= su then return "windup", mf / math.max(1, su), 0 end
	if mf <= su + m.active then return "active", (mf - su) / math.max(1, m.active), mf - su end
	return "end", math.min(1, (mf - su - m.active) / math.max(1, m.recovery)), mf - su
end
UltWorld.phase = phase

local function glowOf(char: any): string
	local pal = char and (char.weaponPalette or char.palette)
	return pal and (pal.glow or pal.accent) or "#FFFFFF"
end

local function floorUnder(stage: any, x: number, y: number): number
	if not stage then return y end
	local surface = Stage.surfaceUnder(stage, x, y + 0.1)
	return if surface then surface.top else y
end

local function find(states: { any }, index: number?): any
	if index == nil then return nil end
	for _, s in states do
		if s.index == index then return s end
	end
	return nil
end

local function sized(art: any, width: number): number
	return width * art.ppu / art.cols
end

-- How present the caster's ultimate glow is: in over the first frames, out over the recovery.
local function presence(name: string, k: number, mf: number): number
	if name == "end" then return 1 - k end
	return math.min(1, mf / 8)
end

-- ------------------------------------------------------------------ under ----
function UltWorld.under(c: any, states: { any }, chars: { any }, scene: any, stage: any, t: number)
	for _, s in states do
		local char = chars[s.index + 1]
		local m = moveOf(s, char)
		if not m or not s.alive then continue end
		local name, k, ak = phase(s, m)
		local glow = glowOf(char)
		local h = char.height
		local floor = floorUnder(stage, s.x, s.y)
		local here = presence(name, k, s.moveFrame or 0)

		-- Every ultimate: a rune circle turning on the floor under the caster.
		if here > 0 and s.onGround then
			local rune = FxArt.get("rune", 0, glow)
			-- Lying on the floor it cannot turn - a Frame can be squashed or rotated, not both - so it
			-- breathes instead.
			local breathe = 1 + math.sin(t * 4) * 0.04
			FxArt.draw(c, rune, s.x, floor + 0.08, sized(rune, h * 1.7 * (0.6 + 0.4 * here) * breathe), 0, 0.85 * here, 0.26)
		end

		if m.kind == "starfall" and name ~= "windup" then
			-- The sky goes dark from the top down, stars come out, and a great circle opens behind
			-- the caster. World-space bands wide enough to cover any framing of the fight.
			local dark = if name == "active" then math.min(1, ak / 10) else 1 - k
			local deep = Color3.fromRGB(26, 14, 72)
			local violet = Color3.fromRGB(96, 52, 200)
			Canvas2D.rect(c, s.x - 160, floor - 40, 320, 46, deep, dark * 0.28)
			for band = 0, 5 do
				local y0 = floor + 6 + band * 9
				Canvas2D.rect(c, s.x - 160, y0, 320, 9, deep, dark * (0.3 + band * 0.07))
			end
			Canvas2D.rect(c, s.x - 160, floor + 60, 320, 80, deep, dark * 0.7)
			-- the glow where the orbs come from, a violet band across the top of the sky
			Canvas2D.rect(c, s.x - 160, floor + 22, 320, 3, violet, dark * 0.35)
			Canvas2D.rect(c, s.x - 160, floor + 26, 320, 6, violet, dark * 0.18)
			for i = 0, 13 do
				local sx = s.x + (FxArt.hash(i, 1, s.index) - 0.5) * 80
				local sy = floor + 12 + FxArt.hash(i, 2, s.index) * 30
				local tw = math.floor(t * 5 + i * 1.7) % 4
				FxArt.draw(c, FxArt.get("star", tw, "star"), sx, sy, 0.6 + FxArt.hash(i, 3, s.index) * 0.5, 0, dark)
			end
			local big = FxArt.get("rune", 0, "star", nil, 2)
			FxArt.draw(c, big, s.x, s.y + h * 0.75, sized(big, h * 1.9), -t * 0.7, 0.55 * dark)
		end

		if m.kind == "slam" and name ~= "windup" then
			-- The greatsword's crater: a burning split racing outward to the reach the crater
			-- schedule has got to (renderer2d.js drives it the same way), flames at each burst.
			local C = m.crater
			local span = C.every * (C.count - 1)
			local reachK = math.clamp(((s.moveFrame or 0) - (s.startupEff or m.startup) - 1) / math.max(1, span), 0, 1)
			local reach = C.step * (C.count - 1) * reachK
			local fade = if name == "end" then 1 - k else 1
			if reach > 0.5 then
				local art = FxArt.get("fissure", math.floor(t * 10) % 2, glow, nil, s.index + 1)
				local sc = sized(art, reach)
				local sy = 1.4 * art.ppu / (art.rows * sc)
				for _, dir in { -1, 1 } do
					FxArt.draw(c, art, s.x + dir * reach / 2, floor + 0.1, sc, if dir < 0 then math.pi else 0, fade, sy)
				end
			end
			-- a flame where each burst went off, flaring as it is reached and burning down after
			local su = s.startupEff or m.startup
			for i = 1, C.count - 1 do
				local age = (s.moveFrame or 0) - (su + 1 + C.every * i)
				if age < 0 then break end
				local life = 1 - age / 26
				if life > 0 then
					local f = math.floor(t * 12 + i) % 6
					local fl = FxArt.get("flame", f, glow, nil, i)
					local size = (0.9 + (C.count - i) * 0.22) * (0.45 + 0.55 * life)
					for _, dir in { -1, 1 } do
						FxArt.draw(c, fl, s.x + dir * C.step * i, floor, sized(fl, size), 0, math.min(1, life * 1.6))
					end
				end
			end
		end

		if char.weapon and char.weapon.id == "Pike" and m.kind == "melee" and name == "active" then
			-- Lance Charge: every thrust drives a lance of light down the lane its hitbox owns, out to
			-- the far end of that box, so the player sees exactly the line they must not stand in.
			local per = m.active / 5
			local q = (ak % per) / per
			local punch = if q < 0.35 then (q / 0.35) ^ 2 else 1 - (q - 0.35) / 0.65
			local box = m.hitboxes[math.clamp(math.floor(ak / per) + 1, 1, #m.hitboxes)]
			if box and punch > 0.12 then
				local y = s.y + box.offset[2]
				local x0 = s.x + s.facing * 1.6
				local reach = (box.offset[1] + box.size[1] / 2 - 1.6) * math.min(1, punch * 1.6)
				local art = FxArt.get("lance", math.floor(t * 20) % 3, glow, nil, 2)
				local sc = sized(art, reach)
				local tall = box.size[2] * 1.5
				FxArt.draw(c, art, x0, y, sc, if s.facing < 0 then math.pi else 0, math.min(1, punch * 1.5), tall * art.ppu / (art.rows * sc))
				if punch > 0.75 then
					local pop = FxArt.get("pop", math.floor((1 - punch) * 16) % 5, glow, nil, 3)
					FxArt.draw(c, pop, x0 + s.facing * reach, y, sized(pop, 1.6 + box.size[2]), 0, 1)
				end
			end
		end

		if m.kind == "upheaval" and name == "active" then
			-- The hammer holds the ground open: cracks out from the head, pulsing with each column.
			local U = m.upheaval
			local beat = if U then 1 - (ak % U.every) / U.every else 0.5
			local hx = s.x + s.facing * 2.6
			local art = FxArt.get("fissure", if beat > 0.6 then 0 else 1, glow, nil, 4)
			local sc = sized(art, 7)
			FxArt.draw(c, art, hx, floor + 0.1, sc, 0, 0.6 + beat * 0.4, 1.3 * art.ppu / (art.rows * sc))
		end

		if m.kind == "melee" and char.weapon and char.weapon.id == "Axe" and name == "active" then
			-- Reave: a cyclone wound up around the axe-wielder, banding faster as the spin speeds.
			local f = math.floor(t * 14 + ak * 0.5) % 4
			local cy = FxArt.get("cyclone", f, glow, nil, 3)
			local w = 3.2 * (m.weaponScale or 1.35) * 2.1
			FxArt.draw(c, cy, s.x, floor, sized(cy, w), 0, 0.42 + 0.3 * k)
		end
	end

	-- Astral Rain's orbs paint where they will land: a target turning on the floor under each.
	if scene and scene.projectiles then
		for _, p in scene.projectiles do
			local owner = find(states, p.owner)
			local char = if owner then chars[owner.index + 1] else nil
			local m = if owner then moveOf(owner, char) else nil
			if m and m.kind == "starfall" and p.shape == "orb" then
				local floor = floorUnder(stage, p.x, p.y)
				local near = math.clamp(1 - (p.y - floor) / 22, 0.2, 1)
				local art = FxArt.get("reticle", 0, glowOf(char))
				FxArt.draw(c, art, p.x, floor + 0.1, sized(art, 2.2 + near * 2.2), 0, 0.4 + near * 0.6, 0.32)
			end
		end
	end
end

-- ------------------------------------------------------------------ over ----
-- Rundown's afterimages need where the fighter has just been; the client keeps a short history.
local trails: { [number]: { any } } = {}

local function bodyGhost(c: any, x: number, y: number, char: any, colour: Color3, alpha: number)
	local r, h = char.radius, char.height
	Canvas2D.rect(c, x - r * 0.8, y + h * 0.06, r * 1.6, h * 0.66, colour, alpha)
	Canvas2D.rect(c, x - r * 0.55, y + h * 0.72, r * 1.1, h * 0.26, colour, alpha)
end

local function chain(c: any, ax: number, ay: number, hx: number, hy: number, char: any, glow: string, strain: number, t: number)
	local pal = char.weaponPalette or {}
	local dark = Canvas2D.hex(pal.tertiary, Color3.fromRGB(35, 28, 34))
	local mid = Canvas2D.hex(pal.secondary, Color3.fromRGB(58, 48, 56))
	local lite = Canvas2D.hex(pal.accent, Color3.fromRGB(200, 206, 216))
	local g = Canvas2D.hex(glow, WHITE)
	local dx, dy = hx - ax, hy - ay
	local span = math.sqrt(dx * dx + dy * dy)
	local a = math.atan2(dy, dx)
	-- the glow under the links brightens as the slack runs out: the snap is telegraphed
	Canvas2D.line(c, ax, ay, hx, hy, 0.5 + strain * 0.4, g, 0.12 + strain * 0.4)
	local links = math.max(3, math.floor(span / 0.75 + 0.5))
	for i = 0, links do
		local u = i / links
		local x, y = ax + dx * u, ay + dy * u
		Canvas2D.save(c)
		Canvas2D.translate(c, x, y)
		Canvas2D.rotate(c, a)
		if i % 2 == 0 then
			Canvas2D.rect(c, -0.42, -0.24, 0.84, 0.48, INK)
			Canvas2D.rect(c, -0.34, -0.16, 0.68, 0.32, mid)
			Canvas2D.rect(c, -0.2, -0.06, 0.4, 0.12, dark)
			Canvas2D.rect(c, -0.3, 0.08, 0.4, 0.08, lite, 0.6)
		else
			Canvas2D.rect(c, -0.4, -0.08, 0.8, 0.16, INK)
			Canvas2D.rect(c, -0.32, -0.04, 0.64, 0.08, mid)
		end
		Canvas2D.restore(c)
	end
	-- the chain crackles once it is close to snapping
	if strain > 0.55 then
		local seg = math.floor(t * 16)
		for i = 0, 1 do
			local u = FxArt.hash(seg, i, 3) * 0.8 + 0.1
			local art = FxArt.get("bolt", (seg + i) % 4, glow, nil, seg % 5 + 1)
			FxArt.draw(c, art, ax + dx * u, ay + dy * u, sized(art, 2.4 + strain * 1.6), a + (i - 0.5) * 0.5, strain)
		end
	end
	-- the head, buried in the floor: a spiked iron ball in the circle it cracked open
	local primary = Canvas2D.hex(pal.primary, Color3.fromRGB(110, 118, 132))
	Canvas2D.circle(c, ax, ay, 0.86, INK)
	Canvas2D.circle(c, ax, ay, 0.74, primary)
	Canvas2D.circle(c, ax - 0.22, ay + 0.22, 0.24, lite, 0.7)
	for i = 0, 5 do
		local sa = (i / 6) * math.pi * 2 + 0.3
		Canvas2D.save(c)
		Canvas2D.translate(c, ax + math.cos(sa) * 0.8, ay + math.sin(sa) * 0.8)
		Canvas2D.rotate(c, sa)
		Canvas2D.rect(c, -0.1, -0.14, 0.42, 0.28, INK)
		Canvas2D.rect(c, -0.04, -0.08, 0.32, 0.16, lite)
		Canvas2D.restore(c)
	end
	if strain > 0.8 and math.floor(t * 20) % 2 == 0 then
		Canvas2D.circle(c, ax, ay, 1.2, g, 0.5)
	end
end

function UltWorld.over(c: any, states: { any }, chars: { any }, scene: any, stage: any, t: number)
	local ults: { [number]: any } = {}
	if scene and scene.ults then
		for _, u in scene.ults do ults[u.i] = u end
	end
	local seen: { [number]: boolean } = {}
	for _, s in states do
		local char = chars[s.index + 1]
		local m = moveOf(s, char)
		if not m or not s.alive then continue end
		local name, k = phase(s, m)
		local glow = glowOf(char)
		local h = char.height
		local here = presence(name, k, s.moveFrame or 0)
		local u = ults[s.index]

		-- Every ultimate: motes of the caster's light rising round them.
		if here > 0 then
			for i = 0, 4 do
				local cyc = (t * 1.1 + FxArt.hash(i, 0, s.index)) % 1
				local x = s.x + (FxArt.hash(i, 1, s.index) - 0.5) * char.radius * 3.2 + math.sin(t * 3 + i) * 0.3
				local y = s.y + cyc * h * 1.2
				local f = if cyc < 0.15 then 0 elseif cyc < 0.7 then 1 elseif cyc < 0.85 then 2 else 3
				FxArt.draw(c, FxArt.get("star", f, glow), x, y, 0.5, 0, here)
			end
		end

		if m.kind == "anchor" and u and u.ax then
			local hx, hy = s.x + s.facing * 0.8, s.y + h * 0.46
			local span = math.sqrt((hx - u.ax) ^ 2 + (hy - u.ay) ^ 2)
			local strain = math.min(1, span / (m.anchor.maxLength * 0.85))
			local rune = FxArt.get("rune", 0, glow, nil, 5)
			FxArt.draw(c, rune, u.ax, u.ay - 0.6, sized(rune, 4.2 + math.sin(t * 6) * 0.2), 0, 0.8, 0.28)
			chain(c, u.ax, u.ay, hx, hy, char, glow, strain, t)
		end

		if m.kind == "reflect" and u and u.abs ~= nil and name == "active" then
			-- Aegis: a barrier of light in front of the shield, filling as it soaks damage, and
			-- crackling with it once it holds enough to hurt.
			local stored = math.min(1, u.abs / 40)
			local R = m.reflect.radius * (0.9 + stored * 0.25)
			local cx, cy = s.x + s.facing * 1.4, s.y + 2.8
			local dome = FxArt.get("dome", 0, glow)
			local sc = R * 2 * dome.ppu / dome.rows
			FxArt.draw(c, dome, cx, cy, sc, 0, 0.5 + stored * 0.4 + math.sin(t * 9) * 0.08)
			if stored > 0.35 then
				local seg = math.floor(t * 14)
				for i = 0, if stored > 0.7 then 2 else 1 do
					local a = FxArt.hash(seg, i, s.index) * math.pi * 2
					local bolt = FxArt.get("bolt", (seg + i) % 4, glow, nil, seg % 3 + 1)
					FxArt.draw(c, bolt, cx + math.cos(a) * R * 0.2, cy + math.sin(a) * R * 0.4,
						sized(bolt, R * 0.9), a, stored)
				end
			end
		end

		if m.kind == "sniper" and u and u.tgt ~= nil then
			local v = find(states, u.tgt)
			local vc = if v then chars[v.index + 1] else nil
			if v and v.alive and vc then
				local vx, vy = v.x, v.y + vc.height * 0.5
				local pulse = 0.55 + 0.45 * math.sin(t * 11)
				local red = Canvas2D.hex("#FF4A4A", WHITE)
				-- the sight line, through anything in between, and a bead of light running down it
				local mx, my = s.x + s.facing * 2.6, s.y + 3.5
				Canvas2D.line(c, mx, my, vx, vy, 0.1, red, 0.25 + 0.2 * pulse)
				for i = 0, 2 do
					local q = (t * 1.8 + i / 3) % 1
					Canvas2D.rect(c, mx + (vx - mx) * q - 0.12, my + (vy - my) * q - 0.12, 0.24, 0.24, red, 0.8)
				end
				local ret = FxArt.get("reticle", 0, "red")
				FxArt.draw(c, ret, vx, vy, sized(ret, 3.4 + (1 - pulse) * 0.8), t * 1.5, 0.95)
				-- corner brackets closing in on the mark
				local bw, bh = vc.radius + 0.7 + (1 - pulse) * 0.3, vc.height * 0.5 + 0.6 + (1 - pulse) * 0.3
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						local x, y = vx + sx * bw, vy + sy * bh
						Canvas2D.rect(c, x - (if sx > 0 then 0.9 else 0), y - 0.08, 0.9, 0.16, red, 0.9)
						Canvas2D.rect(c, x - 0.08, y - (if sy > 0 then 0.9 else 0), 0.16, 0.9, red, 0.9)
					end
				end
			end
		end

		if m.kind == "rundown" and name == "active" then
			-- Afterimages along the path the fighter has just covered between targets.
			local list = trails[s.index] or {}
			trails[s.index] = list
			table.insert(list, { x = s.x, y = s.y, t = t })
			while #list > 0 and t - list[1].t > 0.22 do table.remove(list, 1) end
			while #list > 12 do table.remove(list, 1) end
			local g = Canvas2D.hex(glow, WHITE)
			for i = 1, #list - 1, 3 do
				local p = list[i]
				local d = (s.x - p.x) ^ 2 + (s.y - p.y) ^ 2
				if d > 1.5 then
					bodyGhost(c, p.x, p.y, char, g, 0.12 + 0.3 * (i / #list))
				end
			end
			seen[s.index] = true
		end
	end
	for index in trails do
		if not seen[index] then trails[index] = nil end
	end

	-- Exsanguinate's marks, over whoever carries them: a drop of blood and a pip per mark.
	if scene and scene.bleed then
		local blood = Canvas2D.hex("#FF4A6A", WHITE)
		for _, b in scene.bleed do
			local v = find(states, b.i)
			local vc = if v then chars[v.index + 1] else nil
			if v and v.alive and vc then
				local top = v.y + vc.height + 1.1 + math.sin(t * 4 + b.i) * 0.12
				local art = FxArt.get("sigil", 0, "blood")
				FxArt.draw(c, art, v.x, top, sized(art, 1.3), 0, 1)
				local n = math.min(12, b.n)
				for i = 0, n - 1 do
					local row, col = math.floor(i / 6), i % 6
					local cols = math.min(6, n - row * 6)
					Canvas2D.rect(c, v.x + (col - (cols - 1) / 2) * 0.36 - 0.13, top - 1.2 - row * 0.36, 0.26, 0.26, INK)
					Canvas2D.rect(c, v.x + (col - (cols - 1) / 2) * 0.36 - 0.09, top - 1.16 - row * 0.36, 0.18, 0.18, blood)
				end
			end
		end
	end
end

-- An ultimate's own projectile, drawn as what it is: Deadeye's rounds as tracers, Astral Rain's
-- orbs as falling stars, Heartseeker as a lance of light. Returns false for anything else, which
-- World2D then draws as before.
function UltWorld.projectile(c: any, p: any, states: { any }, chars: { any }, t: number): boolean
	local owner = find(states, p.owner)
	local char = if owner then chars[owner.index + 1] else nil
	local m = if owner then moveOf(owner, char) else nil
	if not m or p.item then return false end
	local glow = glowOf(char)
	local a = math.atan2(p.vy or 0, p.vx or 1)
	local f = math.floor(t * 20) % 3
	if m.kind == "starfall" then
		local art = FxArt.get("comet", f, "star", nil, 2)
		FxArt.draw(c, art, p.x, p.y, sized(art, 5.5), a)
		local core = FxArt.get("orb", math.floor(t * 12) % 4, glow)
		FxArt.draw(c, core, p.x, p.y, sized(core, p.w * 2.4), 0)
		return true
	elseif m.kind == "sniper" then
		local art = FxArt.get("comet", f, glow, nil, 5)
		FxArt.draw(c, art, p.x, p.y, sized(art, 4.6), a)
		return true
	elseif m.kind == "pierce" then
		local art = FxArt.get("lance", f, glow, nil, 3)
		local sc = sized(art, 7)
		FxArt.draw(c, art, p.x - math.cos(a) * 5.6, p.y - math.sin(a) * 5.6, sc, a, 1, 1.3 * art.ppu / (art.rows * sc) * 1.4)
		local head = FxArt.get("orb", math.floor(t * 16) % 4, glow)
		FxArt.draw(c, head, p.x, p.y, sized(head, 2.2), 0)
		return true
	end
	return false
end

return UltWorld
