--!nocheck
-- Development tools' shared half: a Canvas2D that RECORDS what it is asked to draw instead of
-- drawing it, and the Instance stub the UI modules need outside Roblox. The game renders into a
-- ScreenGui, so Studio's screenshot is empty; render-fight, render-hub and render-climb turn a real
-- draw into JSON with this, for fight-png.mjs (pixels) or hub-svg.mjs (with the text labels).
--
-- A shape is { "p", corner, corner, corner, corner, hex, alpha } for a rectangle under any
-- transform, or { "e", cx, cy, rx, ry, hex, alpha } for an ellipse, in screen pixels.
local Rbx = require("@lune/roblox")
local Recorder = {}

local function hex(c: any): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
Recorder.hex = hex

-- Points Canvas's primitives at a list, and returns the list (cleared by the caller between frames).
-- A sprite is recorded as its rectangles, each in the sprite's transform and at the sprite's alpha.
function Recorder.install(Canvas: any): { any }
	local shapes = {}
	Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
		local m = c.m
		local function P(u: number, v: number) return { m.a * u + m.c * v + m.e, m.b * u + m.d * v + m.f } end
		table.insert(shapes, { "p", P(x, y), P(x + w, y), P(x + w, y + h), P(x, y + h), hex(colour), (alpha or 1) * c.alpha })
	end
	-- an ellipse under a rotation is still recorded axis-aligned; good enough to look at
	Canvas.ellipse = function(c: any, x: number, y: number, rx: number, ry: number, colour: any, alpha: number?)
		local m = c.m
		local sx, sy = math.sqrt(m.a * m.a + m.b * m.b), math.sqrt(m.c * m.c + m.d * m.d)
		table.insert(shapes, { "e", m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f, math.abs(rx * sx), math.abs(ry * sy), hex(colour),
			(alpha or 1) * c.alpha })
	end
	Canvas.circle = function(c: any, x: number, y: number, r: number, colour: any, alpha: number?)
		Canvas.ellipse(c, x, y, r, r, colour, alpha)
	end
	Canvas.sprite = function(c: any, _key: string, rects: any, x0: number, y1: number, pw: number, ph: number, _cols, _rows, alpha: number?)
		Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, h, hx, a)
			Canvas.rect(c, x, y, w, h, Rbx.Color3.fromHex(hx), a * (alpha or 1))
		end)
	end
	return shapes
end

-- A W x H canvas to draw into.
function Recorder.canvas(Canvas: any, W: number, H: number): any
	return setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
		gui = { AbsoluteSize = { X = W, Y = H } }, finish = function() end }, { __index = Canvas })
end

-- Instance.new for UI modules run outside Roblox: every object it makes is kept in `made`, so the
-- text labels can be read back afterwards (Recorder.texts).
function Recorder.instances(): ((...any) -> any, { any })
	local made = {}
	local function new(): any
		local obj: any = { attributes = {}, Visible = true }
		table.insert(made, obj)
		obj.Destroy = function() obj.destroyed = true end
		obj.Activated = { Connect = function(_, fn) obj.activate = fn end }
		obj.SetAttribute = function(_, key, value) obj.attributes[key] = value end
		return obj
	end
	return new, made
end

-- The visible text labels among `made`, as { x, y, w, h, text, colour, size, background? } in a
-- W x H screen.
function Recorder.texts(made: { any }, W: number, H: number): { any }
	local texts = {}
	for _, t in made do
		if t.Text and t.Text ~= "" and t.Visible ~= false and not t.destroyed and t.Position then
			local p, s = t.Position, t.Size
			local x = p.X.Scale * W + p.X.Offset
			local y = p.Y.Scale * H + p.Y.Offset
			local w = (s and (s.X.Scale * W + s.X.Offset)) or 200
			local h = (s and (s.Y.Scale * H + s.Y.Offset)) or 20
			if t.AnchorPoint then x -= t.AnchorPoint.X * w; y -= t.AnchorPoint.Y * h end
			table.insert(texts, { x, y, w, h, t.Text, if t.TextColor3 then hex(t.TextColor3) else "#e7e3d1", t.TextSize or 14,
				t.BackgroundTransparency ~= nil and t.BackgroundTransparency < 1 and t.BackgroundColor3 and hex(t.BackgroundColor3) or nil })
		end
	end
	return texts
end

return Recorder
