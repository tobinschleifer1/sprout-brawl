--!strict
-- The loading screen (Roblox only; the owner's ask, 2026-11-02). It runs from ReplicatedFirst, the
-- first thing a client runs, so it is up before anything else is - which is also why it needs
-- nothing from ReplicatedStorage and draws itself: the game's UI kit has not arrived yet.
--
-- Behind the title two bots fight (LoadingFight, the owner's ask, 2026-11-04): it lives with the
-- client's modules, so it starts once they arrive, and until then - or if it fails - the screen is
-- the falling blocks it always was.
--
-- It replaces Roblox's own, holds while the game loads, and goes when the game says it is ready
-- (the main client sets the player's BlockfallReady attribute once the lobby is up), or after
-- GIVE_UP seconds whatever happens - a loading screen must never be what stops someone playing.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GIVE_UP = 25
local TIPS = {
	"Press jump again in the air to jump twice - it is how you get back to the stage.",
	"Hold up or down as you attack to swing that way.",
	"Heavy attacks send a damaged fighter flying further.",
	"Hold your shield to block. Let go and it recovers.",
	"A grab gets through a shield.",
	"Hits fill your ultimate meter. Press Ultimate when it is full.",
	"New weapons unlock as you level up - the last at level 15.",
	"Ranked opens at level 10.",
	"Change your keys and volume in Settings.",
}

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name, gui.IgnoreGuiInset, gui.DisplayOrder, gui.ResetOnSpawn = "BlockfallLoading", true, 100, false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local back = Instance.new("Frame")
back.Name, back.Size, back.BorderSizePixel = "Back", UDim2.fromScale(1, 1), 0
back.BackgroundColor3 = Color3.fromRGB(35, 27, 51)
back.Parent = gui
local sky = Instance.new("UIGradient")
sky.Color = ColorSequence.new(Color3.fromRGB(70, 74, 150), Color3.fromRGB(35, 27, 51))
sky.Rotation = 90
sky.Parent = back
-- blocks falling behind the title, the game's own idea of itself
local blocks = {}
local COLOURS = { Color3.fromRGB(254, 231, 97), Color3.fromRGB(111, 182, 255), Color3.fromRGB(108, 196, 90), Color3.fromRGB(230, 90, 90) }
for i = 1, 14 do
	local b = Instance.new("Frame")
	b.Name, b.BorderSizePixel, b.AnchorPoint = "Block", 0, Vector2.new(0.5, 0.5)
	local size = 18 + (i * 7) % 26
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = COLOURS[i % #COLOURS + 1]
	b.BackgroundTransparency = 0.55
	b.ZIndex = 1
	b.Parent = back
	table.insert(blocks, { f = b, x = ((i * 0.618) % 1), y = (i * 0.37) % 1, speed = 0.05 + (i % 5) * 0.02, spin = (i % 3 - 1) * 40 })
end
-- the fight, under a shade so the words over it still read; both hidden until it starts
local arena = Instance.new("Frame")
arena.Name, arena.Size, arena.BackgroundTransparency, arena.ClipsDescendants = "Arena", UDim2.fromScale(1, 1), 1, true
arena.ZIndex, arena.Visible = 2, false
arena.Parent = back
local shade = Instance.new("Frame")
shade.Name, shade.Size, shade.BorderSizePixel = "Shade", UDim2.fromScale(1, 1), 0
shade.BackgroundColor3, shade.BackgroundTransparency = Color3.fromRGB(24, 20, 37), 0.45
shade.ZIndex, shade.Visible = 3, false
shade.Parent = back
local title = Instance.new("TextLabel")
title.Name, title.BackgroundTransparency, title.AnchorPoint = "Title", 1, Vector2.new(0.5, 0.5)
title.Position, title.Size = UDim2.fromScale(0.5, 0.38), UDim2.new(0.9, 0, 0, 90)
title.Font, title.Text, title.TextScaled = Enum.Font.Arcade, "BLOCKFALL", true
title.TextColor3 = Color3.fromRGB(255, 255, 255)
local tc = Instance.new("UITextSizeConstraint")
tc.MaxTextSize = 96
tc.Parent = title
local stroke = Instance.new("UIStroke")
stroke.Thickness, stroke.Color = 4, Color3.fromRGB(24, 20, 37)
stroke.Parent = title
title.ZIndex = 4
title.Parent = back
-- the bar
local track = Instance.new("Frame")
track.Name, track.AnchorPoint, track.BorderSizePixel = "Track", Vector2.new(0.5, 0.5), 0
track.Position, track.Size = UDim2.fromScale(0.5, 0.56), UDim2.new(0.6, 0, 0, 16)
track.BackgroundColor3 = Color3.fromRGB(24, 20, 37)
local ts = Instance.new("UIStroke")
ts.Thickness, ts.Color = 3, Color3.fromRGB(255, 255, 255)
ts.Parent = track
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(520, 16)
limit.Parent = track
track.ZIndex = 4
track.Parent = back
local fill = Instance.new("Frame")
fill.Name, fill.BorderSizePixel, fill.Size = "Fill", 0, UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(254, 231, 97)
fill.Parent = track
local status = Instance.new("TextLabel")
status.Name, status.BackgroundTransparency, status.AnchorPoint = "Status", 1, Vector2.new(0.5, 0)
status.Position, status.Size = UDim2.new(0.5, 0, 0.56, 18), UDim2.new(0.8, 0, 0, 22)
status.Font, status.TextSize, status.Text = Enum.Font.BuilderSansBold, 16, "Loading…"
status.TextColor3 = Color3.fromRGB(214, 228, 250)
status.ZIndex = 4
status.Parent = back
local tip = Instance.new("TextLabel")
tip.Name, tip.BackgroundTransparency, tip.AnchorPoint = "Tip", 1, Vector2.new(0.5, 1)
tip.Position, tip.Size = UDim2.new(0.5, 0, 1, -40), UDim2.new(0.86, 0, 0, 48)
tip.Font, tip.TextSize, tip.TextWrapped = Enum.Font.BuilderSansBold, 18, true
tip.TextColor3 = Color3.fromRGB(255, 255, 255)
tip.Text = "TIP: " .. TIPS[math.random(1, #TIPS)]
tip.ZIndex = 4
tip.Parent = back
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local fight: any = nil
local leaving = false
local function stopFight(why: string?)
	if why then warn(`[Blockfall] the loading screen's fight stopped: {why}`) end
	fight = nil
	arena.Visible, shade.Visible = false, false
	for _, b in blocks do b.f.Visible = true end
end
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	local scripts = player:WaitForChild("PlayerScripts", GIVE_UP)
	local client = scripts and scripts:WaitForChild("Client", GIVE_UP)
	local module = client and client:WaitForChild("LoadingFight", GIVE_UP)
	local canvasModule = client and client:WaitForChild("Canvas2D", GIVE_UP)
	if not module or not canvasModule or not ReplicatedStorage:WaitForChild("Shared", GIVE_UP) or leaving then return end
	local ok, err = pcall(function()
		local Canvas2D = require(canvasModule :: any) :: any
		local LoadingFight = require(module :: any) :: any
		fight = LoadingFight.new(Canvas2D.scratch(arena), function() return arena.AbsoluteSize end, os.time())
	end)
	if not ok then stopFight(tostring(err)); return end
	if leaving then fight = nil; return end
	arena.Visible, shade.Visible = true, true
	for _, b in blocks do b.f.Visible = false end
end)

-- the bar never goes backwards, and creeps while nothing it can measure is moving
local shown, started, tipAt = 0, os.clock(), os.clock()
local conn = RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local queue = ContentProvider.RequestQueueSize
	local target = if game:IsLoaded() then 0.7 else 0.35
	if queue == 0 and game:IsLoaded() then target = 0.85 end
	if player:GetAttribute("BlockfallReady") == true then target = 1 end
	shown = math.max(shown, math.min(target, shown + dt * 0.6), math.min(0.95, (now - started) / GIVE_UP))
	fill.Size = UDim2.fromScale(shown, 1)
	status.Text = if shown >= 1 then "Ready!" elseif game:IsLoaded() then "Getting the lobby ready…" else "Loading the game…"
	if now - tipAt > 5 then
		tipAt = now
		tip.Text = "TIP: " .. TIPS[math.random(1, #TIPS)]
	end
	if fight then
		local ok, err = pcall(fight.step, fight, dt)
		if not ok then stopFight(tostring(err)) end
	end
	for _, b in blocks do
		b.y = (b.y + b.speed * dt) % 1.1
		b.f.Position = UDim2.fromScale(b.x, b.y - 0.05)
		b.f.Rotation = (b.f.Rotation + b.spin * dt) % 360
	end
end)

if not game:IsLoaded() then game.Loaded:Wait() end
local waited = os.clock()
while player:GetAttribute("BlockfallReady") ~= true and os.clock() - waited < GIVE_UP do
	task.wait(0.1)
end
task.wait(0.3)
-- fade out, then gone (the fight holds its last frame while it fades)
leaving, fight = true, nil
local info = TweenInfo.new(0.4)
TweenService:Create(back, info, { BackgroundTransparency = 1 }):Play()
for _, d in back:GetDescendants() do
	if d:IsA("TextLabel") then TweenService:Create(d, info, { TextTransparency = 1 }):Play()
	elseif d:IsA("Frame") then TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then TweenService:Create(d, info, { Transparency = 1 }):Play() end
end
task.wait(0.45)
conn:Disconnect()
gui:Destroy()
