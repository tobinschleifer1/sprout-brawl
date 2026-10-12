--!nocheck
-- Read the actual GUI properties AFTER a draw. No Canvas caches or input draw commands are
-- consulted. This lets before/after runs compare ordered output, not just performance counters.
local serde = require("@lune/serde")
local Output = {}
local function dim(v) return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
local function colour(v) return { v.R, v.G, v.B } end
local function hex(v)
	return string.format("#%02x%02x%02x", math.floor(v.R*255+0.5), math.floor(v.G*255+0.5), math.floor(v.B*255+0.5))
end
local function children(root)
	local sorted = {}
	for i, child in root:GetChildren() do
		if child:IsA("GuiObject") then table.insert(sorted, { child, i }) end
	end
	table.sort(sorted, function(a, b)
		if a[1].ZIndex == b[1].ZIndex then return a[2] < b[2] end
		return a[1].ZIndex < b[1].ZIndex
	end)
	return sorted
end

function Output.tree(root)
	local out = {}
	for _, pair in children(root) do
		local f = pair[1]
		if not f.Visible then continue end
		local row = { f.ClassName, dim(f.Position), dim(f.Size), { f.AnchorPoint.X, f.AnchorPoint.Y },
			f.Rotation, f.BackgroundTransparency, colour(f.BackgroundColor3), f.ZIndex }
		local corner = f:FindFirstChildWhichIsA("UICorner")
		if corner then table.insert(row, { corner.CornerRadius.Scale, corner.CornerRadius.Offset }) else table.insert(row, false) end
		local stroke = f:FindFirstChildWhichIsA("UIStroke")
		if stroke then table.insert(row, { stroke.Enabled, stroke.Thickness, stroke.Transparency, colour(stroke.Color), tostring(stroke.ApplyStrokeMode) })
		else table.insert(row, false) end
		if f:IsA("TextLabel") then
			table.insert(row, { f.Text, f.TextSize, f.TextTransparency, colour(f.TextColor3), tostring(f.Font), f.RichText,
				tostring(f.TextXAlignment), tostring(f.TextYAlignment), f.TextWrapped, f.TextScaled })
		else table.insert(row, false) end
		table.insert(row, Output.tree(f))
		table.insert(out, row)
	end
	return out
end

function Output.capture(scene)
	local P = scene.probe
	return { Output.tree(P.raw[scene.canvas.layer]), Output.tree(P.raw[scene.hud.gui]) }
end

function Output.hash(scene)
	return serde.hash("sha256", serde.encode("json", Output.capture(scene)))
end

-- Flatten the actual Frame hierarchy to fight-png's shapes. Sprite children inherit their
-- container's rotation and axis scales; no shearing or stale AbsolutePosition is involved.
function Output.shapes(scene)
	local shapes = {}
	local function draw(root, width, height, a, b, c, d, e, g)
		for _, pair in children(root) do
			local f = pair[1]
			if not f.Visible then continue end
			local p, s, anchor = f.Position, f.Size, f.AnchorPoint
			local w, h = s.X.Scale * width + s.X.Offset, s.Y.Scale * height + s.Y.Offset
			local x = p.X.Scale * width + p.X.Offset + (0.5 - anchor.X) * w
			local y = p.Y.Scale * height + p.Y.Offset + (0.5 - anchor.Y) * h
			local co, si = math.cos(math.rad(f.Rotation)), math.sin(math.rad(f.Rotation))
			local A, B, C, D = a*co+c*si, b*co+d*si, -a*si+c*co, -b*si+d*co
			local E, G = a*x+c*y+e - A*w/2-C*h/2, b*x+d*y+g - B*w/2-D*h/2
			local function point(u,v) return { A*u+C*v+E, B*u+D*v+G } end
			if f.BackgroundTransparency < 1 then
				local corner = f:FindFirstChildWhichIsA("UICorner")
				if corner and corner.CornerRadius.Scale == 0.5 then
					local centre = point(w/2,h/2)
					table.insert(shapes, { "e", centre[1], centre[2], w/2, h/2, hex(f.BackgroundColor3), 1-f.BackgroundTransparency })
				else table.insert(shapes, { "p", point(0,0), point(w,0), point(w,h), point(0,h), hex(f.BackgroundColor3), 1-f.BackgroundTransparency }) end
			end
			draw(f,w,h,A,B,C,D,E,G)
		end
	end
	draw(scene.probe.raw[scene.canvas.layer], scene.probe.width, scene.probe.height, 1,0,0,1,0,0)
	return shapes
end
return Output
