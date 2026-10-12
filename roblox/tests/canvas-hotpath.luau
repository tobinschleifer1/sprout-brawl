--!nocheck
-- Direct properties of the allocation/write shortcuts, backed by real Instances.
local Probe = require("../tools/perf-probe")
local Rbx = require("@lune/roblox")
local P = Probe.new(800, 600)
local Canvas = P:load("src/client/Canvas2D")
Canvas.IMAGES = false
local c = Canvas.new(P.new("Folder"))
local RED = Rbx.Color3.new(1, 0, 0)

-- The engine receives UDim values, not the higher-precision numbers used for the camera.
local function rect(delta)
	c:screen()
	c:rect(10.1 + delta, 20.1 + delta, 30.1 + delta, 40.1 + delta, RED)
	c:finish()
end
rect(0)
local pos, size = c.pool[1].Position, c.pool[1].Size
P:reset()
rect(0.001)
assert(c.pool[1].Position == pos and c.pool[1].Size == size, "probe requires equal engine UDim values")
assert(P.total.writes == 0, "subpixel arithmetic rewrote equal Position/Size values")
rect(2)
assert(c.pool[1].Position ~= pos and c.pool[1].Size ~= size, "a real move/resize was suppressed")

local ART = { { 0, 0, 2, 1, "#FF0000", 1 }, { 1, 1, 2, 2, "#00FF00", 0.5 } }
local function sprite(facing, cols, rows)
	c:setTransform(facing * 20, 0, 0, -20, 400, 300)
	c:sprite("mirror", ART, -2, 2, 1, 1, cols, rows)
	c:finish()
end
sprite(1, 4, 4)
local sp = c.sprites["mirror#1"]
local kids = table.clone(sp.children)
P:reset()
sprite(-1, 4, 4)
assert(P.total.creates == 0 and P.total.destroys == 0, "turning rebuilt a picture")
assert(P.total.properties.Size == nil, "mirroring rewrote unchanged cell sizes")
assert(P.total.properties.Position == 1, "only the off-centre cell should move when mirrored")
assert(kids[1].Position == Rbx.UDim2.fromScale(0, 3/4), "top row did not mirror to the bottom")
assert(kids[2].Position == Rbx.UDim2.fromScale(1/4, 1/4), "centred cell moved on mirroring")
sprite(1, 4, 4)
assert(kids[1].Position == Rbx.UDim2.fromScale(0, 0), "turning back left a cell mirrored")
sprite(1, 8, 8)
assert(sp.children[1] == kids[1], "canvas dimensions rebuilt the picture")
assert(kids[2].Position == Rbx.UDim2.fromScale(1/8, 1/8) and kids[2].Size == Rbx.UDim2.fromScale(2/8, 2/8),
	"same picture at different canvas dimensions retained stale cell layout")

-- Analytic point after translate -> rotate -> scale. Check both axes, nested alpha and restores;
-- a saved matrix must not be changed by a later transform, even after restore returns it.
local retained = {}
c:screen()
local identity = c.m
for n = 1, 300 do
	c:save()
	assert(c.stack[#c.stack] == identity, "save cloned an immutable matrix unnecessarily")
	c.alpha = 0.25
	c:translate(n/7, -n/11)
	c:rotate(n/13)
	c:scale(-2, 3)
	local a, b = math.cos(n/13), math.sin(n/13)
	local m = c.m
	assert(math.abs(m.a * 5 + m.c * 7 + m.e - (-10*a-21*b+n/7)) < 1e-10, "transform x differs from analytic result")
	assert(math.abs(m.b * 5 + m.d * 7 + m.f - (-10*b+21*a-n/11)) < 1e-10, "transform y differs from analytic result")
	local saved = table.clone(m)
	table.insert(retained, { m, saved })
	c:save()
	assert(c.stack[#c.stack] == m, "nested save cloned an immutable matrix")
	c.alpha = 0
	c:translate(100, 200)
	c:rotate(0.4)
	c:restore()
	for k, v in saved do assert(c.m[k] == v, "nested restore lost " .. k) end
	assert(c.alpha == 0.25, "nested restore lost alpha")
	c:restore()
	assert(c.m.a == 1 and c.m.b == 0 and c.m.c == 0 and c.m.d == 1 and c.m.e == 0 and c.m.f == 0 and c.alpha == 1,
		"outer restore lost its transform/alpha")
end
assert(c.m == identity and #c.stack == 0 and #c.alphaStack == 0, "restore did not return the saved value")
for _, pair in retained do
	for k, v in pair[2] do assert(pair[1][k] == v, "later draw mutated a retained matrix") end
end
-- The specialised translate/rotate/scale must equal the general multiply they replaced, in every
-- order (the analytic check above only ever translates the identity). `mul` is the removed
-- Canvas2D.mul, kept here as the reference.
local function mul(m, n)
	return { a = m.a * n.a + m.c * n.b, b = m.b * n.a + m.d * n.b, c = m.a * n.c + m.c * n.d,
		d = m.b * n.c + m.d * n.d, e = m.a * n.e + m.c * n.f + m.e, f = m.b * n.e + m.d * n.f + m.f }
end
do
	local seed = 7
	local function rnd() seed = (seed * 48271) % 2147483647; return seed / 2147483647 * 4 - 2 end
	c:setTransform(1.5, 0.25, -0.5, 2, 30, -40)
	local want = table.clone(c.m)
	for step = 1, 600 do
		local kind, x, y = step % 3, rnd(), rnd()
		if kind == 0 then
			c:translate(x * 50, y * 50)
			want = mul(want, { a = 1, b = 0, c = 0, d = 1, e = x * 50, f = y * 50 })
		elseif kind == 1 then
			c:rotate(x)
			want = mul(want, { a = math.cos(x), b = math.sin(x), c = -math.sin(x), d = math.cos(x), e = 0, f = 0 })
		else
			c:scale(x, y)
			want = mul(want, { a = x, b = 0, c = 0, d = y, e = 0, f = 0 })
		end
		for k, v in want do assert(c.m[k] == v, `step {step} ({kind}): {k} {c.m[k]} ~= {v}`) end
	end
end
-- Disaster overlays retain the world matrix across screen-space painting.
c:world(3, 7, 18, 1, -1)
local world, saved = c.m, table.clone(c.m)
c:screen()
c:save(); c:translate(100, 20); c:restore()
for k, v in saved do assert(world[k] == v, "screen transform mutated a retained world matrix") end
print("PASS canvas hot path: equal engine values skipped, mirrors/resizes correct, saves share immutable matrices")
