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

-- A fuller Instance stub for screens built from the UI kit: it tracks parents and children (and
-- FindFirstChild / GetChildren), signals, attributes and property-changed signals, so a module can
-- build and update its tree as in Roblox. Returns `new` and every object made, in creation order.
function Recorder.gui(W: number, H: number): ((string) -> any, { any })
	local made = {}
	local function signal(): any
		local fns = {}
		return { Connect = function(_, fn) table.insert(fns, fn); return { Disconnect = function() end } end,
			Fire = function(_, ...) for _, fn in fns do fn(...) end end }
	end
	local function new(class: string?): any
		local props: any = { ClassName = class or "Frame", Visible = true, Enabled = true, Activated = signal(), FocusLost = signal(),
			Name = class or "Frame", _children = {}, attributes = {} }
		local self: any
		props.Destroy = function()
			props.destroyed = true
			for _, ch in table.clone(props._children) do ch:Destroy() end
		end
		props.ClearAllChildren = function() for _, ch in table.clone(props._children) do ch:Destroy() end end
		props.FindFirstChild = function(_, name) for _, ch in props._children do if ch.Name == name and not ch.destroyed then return ch end end return nil end
		props.GetChildren = function() local out = {} for _, ch in props._children do if not ch.destroyed then table.insert(out, ch) end end return out end
		props.IsA = function(_, c) return props.ClassName == c end
		props.SetAttribute = function(_, k, v) props.attributes[k] = v end
		props.GetPropertyChangedSignal = function() return signal() end
		self = setmetatable({}, { __index = props, __newindex = function(_, k, v)
			props[k] = v
			if k == "Parent" and v and v._children then table.insert(v._children, self) end
		end })
		if class == "ScreenGui" then props.AbsoluteSize = Rbx.Vector2.new(W, H) end
		table.insert(made, self)
		return self
	end
	return new, made
end

-- Every visible Frame, label, button and text box among `made`, resolved to its absolute rectangle
-- through its parents, with its corner radius, border, text outline, padding and text - for
-- tools/gui-svg.mjs. Ordered as Roblox draws them: by their ScreenGui's DisplayOrder, then made.
local BOXES = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ScrollingFrame = true }
function Recorder.nodes(made: { any }, W: number, H: number): { any }
	-- a box's height: its Size, or with AutomaticSize Y and a UIGridLayout, as tall as its cells
	local height: (any, number, number) -> number
	function height(o: any, pw: number, ph: number): number
		local sz = o.Size or Rbx.UDim2.new(1, 0, 1, 0)
		local h = ph * sz.Y.Scale + sz.Y.Offset
		if not string.find(tostring(o.AutomaticSize or ""), "Y") then return h end
		for _, g in o._children or {} do
			if g.ClassName == "UIGridLayout" and not g.destroyed then
				local cs, gap = g.CellSize or Rbx.UDim2.fromOffset(100, 100), g.CellPadding or Rbx.UDim2.fromOffset(4, 4)
				local w = pw * sz.X.Scale + sz.X.Offset
				local cw, ch = w * cs.X.Scale + cs.X.Offset, cs.Y.Offset
				local n = 0
				for _, c in o._children do if BOXES[c.ClassName] and not c.destroyed and c.Visible ~= false then n += 1 end end
				local cols = math.max(1, math.floor((w + gap.X.Offset) / (cw + gap.X.Offset)))
				local rows = math.ceil(n / cols)
				return math.max(h, rows * ch + math.max(0, rows - 1) * gap.Y.Offset)
			end
			if g.ClassName == "UIListLayout" and not g.destroyed and not string.find(tostring(g.FillDirection or ""), "Horizontal") then
				-- a vertical list grows to the sum of its visible boxes and the gaps between them
				local w, total, n = pw * sz.X.Scale + sz.X.Offset, 0, 0
				local pad = g.Padding and g.Padding.Offset or 0
				for _, c in o._children do
					if BOXES[c.ClassName] and not c.destroyed and c.Visible ~= false then
						total += height(c, w, h); n += 1
					end
				end
				return math.max(h, total + math.max(0, n - 1) * pad)
			end
		end
		return h
	end
	local function rect(o: any): (number, number, number, number)
		local p = o.Parent
		local px, py, pw, ph = 0, 0, W, H
		if p and BOXES[p.ClassName] then px, py, pw, ph = rect(p) end
		local pos, sz = o.Position or Rbx.UDim2.new(), o.Size or Rbx.UDim2.new(1, 0, 1, 0)
		-- a UIListLayout or UIGridLayout in the parent places its boxes in LayoutOrder, as Roblox does
		local layout = nil
		if p and p._children then
			for _, ch in p._children do
				if (ch.ClassName == "UIListLayout" or ch.ClassName == "UIGridLayout") and not ch.destroyed then layout = ch end
			end
		end
		if layout then
			local sibs = {}
			for _, ch in p._children do if BOXES[ch.ClassName] and not ch.destroyed then table.insert(sibs, ch) end end
			table.sort(sibs, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
			local at = table.find(sibs, o) or 1
			local x, y = 0, 0
			if layout.ClassName == "UIGridLayout" then
				local cs, gap = layout.CellSize or Rbx.UDim2.fromOffset(100, 100), layout.CellPadding or Rbx.UDim2.fromOffset(4, 4)
				local cw, ch = pw * cs.X.Scale + cs.X.Offset, ph * cs.Y.Scale + cs.Y.Offset
				local inner = pw
				for _, c in p._children do
					if c.ClassName == "UIPadding" then inner -= (c.PaddingLeft and c.PaddingLeft.Offset or 0) + (c.PaddingRight and c.PaddingRight.Offset or 0) end
				end
				local cols = math.max(1, math.floor((inner + gap.X.Offset) / (cw + gap.X.Offset)))
				local pad = 0
				for _, c in p._children do if c.ClassName == "UIPadding" then pad = c.PaddingLeft and c.PaddingLeft.Offset or 0 end end
				x = pad + ((at - 1) % cols) * (cw + gap.X.Offset)
				y = pad + math.floor((at - 1) / cols) * (ch + gap.Y.Offset)
				return px + x, py + y, cw, ch
			end
			local horizontal = string.find(tostring(layout.FillDirection or ""), "Horizontal") ~= nil
			local padPx = layout.Padding and layout.Padding.Offset or 0
			for k = 1, at - 1 do
				local sz2 = sibs[k].Size or Rbx.UDim2.new()
				if horizontal then x += pw * sz2.X.Scale + sz2.X.Offset + padPx
				elseif sibs[k].Visible ~= false then y += height(sibs[k], pw, ph) + padPx end
			end
			return px + x, py + y, pw * sz.X.Scale + sz.X.Offset, height(o, pw, ph)
		end
		local w, h = pw * sz.X.Scale + sz.X.Offset, ph * sz.Y.Scale + sz.Y.Offset
		for _, ch in o._children do
			if ch.ClassName == "UISizeConstraint" and ch.MaxSize then w, h = math.min(w, ch.MaxSize.X), math.min(h, ch.MaxSize.Y) end
		end
		local x, y = px + pw * pos.X.Scale + pos.X.Offset, py + ph * pos.Y.Scale + pos.Y.Offset
		if o.AnchorPoint then x -= o.AnchorPoint.X * w; y -= o.AnchorPoint.Y * h end
		return x, y, w, h
	end
	local function root(o: any): any
		local cur = o
		while cur and cur.ClassName ~= "ScreenGui" do cur = cur.Parent end
		return cur
	end
	local function shown(o: any): boolean
		local cur = o
		while cur do
			if cur.destroyed or cur.Visible == false or (cur.ClassName == "ScreenGui" and cur.Enabled == false) then return false end
			cur = cur.Parent
		end
		return true
	end
	local list = {}
	for i, o in made do
		local cls = o.ClassName
		if BOXES[cls] and shown(o) then
			local x, y, w, h = rect(o)
			local node: any = { x = x, y = y, w = w, h = h }
			if o.BackgroundTransparency == nil or o.BackgroundTransparency < 1 then
				node.bg, node.bgAlpha = hex(o.BackgroundColor3 or Rbx.Color3.new(0.6, 0.6, 0.6)), 1 - (o.BackgroundTransparency or 0)
			end
			for _, ch in o._children do
				if ch.destroyed then continue end
				if ch.ClassName == "UICorner" then node.radius = ch.CornerRadius.Offset end
				if ch.ClassName == "UIGradient" and ch.Color and ch.Color.Keypoints and ch.Enabled ~= false then
					-- top to bottom (Rotation 90) or left to right
					local k = ch.Color.Keypoints
					node.gradient = { from = hex(k[1].Value), to = hex(k[#k].Value), vertical = (ch.Rotation or 0) == 90 }
				end
				if ch.ClassName == "UIStroke" and ch.Enabled ~= false then
					if tostring(ch.ApplyStrokeMode) == "ApplyStrokeMode.Border" or tostring(ch.ApplyStrokeMode) == "Border" then
						node.stroke, node.strokeW = hex(ch.Color), ch.Thickness
					elseif cls ~= "Frame" then
						node.textStroke, node.textStrokeW = hex(ch.Color or Rbx.Color3.new()), ch.Thickness
					end
				end
				if ch.ClassName == "UIPadding" then
					node.padL = ch.PaddingLeft and ch.PaddingLeft.Offset or 0
					node.padR = ch.PaddingRight and ch.PaddingRight.Offset or 0
				end
			end
			if (cls == "TextLabel" or cls == "TextButton" or cls == "TextBox") and o.Text and o.Text ~= "" and (o.TextTransparency or 0) < 1 then
				local txt = o.Text
				if o.RichText then txt = string.gsub(txt, "<[^>]+>", "") end
				node.text, node.colour, node.size = txt, hex(o.TextColor3 or Rbx.Color3.new(1, 1, 1)), o.TextSize or 14
				node.font = tostring(o.Font or "")
				node.wrap = o.TextWrapped == true
				local a = tostring(o.TextXAlignment or "")
				node.align = if string.find(a, "Left") then "start" elseif string.find(a, "Right") then "end" else "middle"
			end
			-- a ScrollingFrame, or a box with ClipsDescendants, cuts off what it holds, as in Roblox
			local cur = o.Parent
			while cur and BOXES[cur.ClassName] do
				if cur.ClassName == "ScrollingFrame" or cur.ClipsDescendants == true then
					local cx, cy, cw, chh = rect(cur)
					local c = node.clip
					if c then
						local x0, y0 = math.max(c[1], cx), math.max(c[2], cy)
						node.clip = { x0, y0, math.max(0, math.min(c[1] + c[3], cx + cw) - x0), math.max(0, math.min(c[2] + c[4], cy + chh) - y0) }
					else
						node.clip = { cx, cy, cw, chh }
					end
				end
				cur = cur.Parent
			end
			local r = root(o)
			table.insert(list, { order = (r and r.DisplayOrder or 0), i = i, node = node })
		end
	end
	table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.i < b.i end)
	local nodes = {}
	for _, e in list do table.insert(nodes, e.node) end
	return nodes
end

return Recorder
