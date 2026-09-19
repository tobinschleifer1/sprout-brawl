--!strict
-- The bodies. One R15 rig per fighter, posed from the server's snapshot.
--
-- NORMALIZED SCALE, and this is the whole reason rigs are built here rather than left to Roblox.
-- The simulation's hurtbox is `char.height` tall and `char.radius * 2` wide for everyone on the
-- same weapon; a player wearing a tall avatar would otherwise look like a bigger target than they
-- are, and a small one would look like a smaller target than they are. Both are false, and both
-- teach the player something wrong about a game whose entire read is spacing. So every rig is
-- forced to identical proportions - BodyTypeScale and ProportionScale zeroed, then scaled to the
-- exact hurtbox height - and what a player keeps is their colours, clothing and face.
--
-- Rigs are anchored and driven. The Humanoid's state machine is off: Roblox physics has no part in
-- where a fighter is, and leaving it on gives you a second opinion about that every frame.
--
-- Limb animation is not here. web/src/render2d/weapons2d.js is the spec for it - it defines where
-- each weapon sits and how it swings on every frame of every move - and reproducing that as Motor6D
-- poses is its own phase. What this does is place the body, face it the right way, spin it while
-- tumbling, and hold the weapon, which is enough to read the simulation.

local Players = game:GetService("Players")

local Rigs = {}
Rigs.__index = Rigs

local function blankDescription(): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.BodyTypeScale = 0
	d.ProportionScale = 0
	d.HeightScale = 1
	d.WidthScale = 1
	d.DepthScale = 1
	d.HeadScale = 1
	return d
end

-- The player's own description with every scale flattened. Falls back to a bare R15 for bots, and
-- for a player whose appearance fails to load - which happens, and must not take the match with it.
local function describe(userId: number?): HumanoidDescription
	if userId then
		local ok, d = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if ok and d then
			d.BodyTypeScale = 0
			d.ProportionScale = 0
			d.HeightScale = 1
			d.WidthScale = 1
			d.DepthScale = 1
			d.HeadScale = 1
			return d
		end
	end
	return blankDescription()
end

local function buildRig(userId: number?, height: number, parent: Instance): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(describe(userId), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	local rig = model :: Model
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.EvaluateStateMachine = false
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	-- Scale to the hurtbox. GetExtentsSize is measured before parenting anything else to the rig so
	-- a weapon part cannot inflate the measurement and shrink the fighter.
	local extents = rig:GetExtentsSize()
	if extents.Y > 0 then
		rig:ScaleTo(height / extents.Y)
	end
	rig.Name = "Rig"
	rig.Parent = parent
	return rig
end

function Rigs.new(parent: Instance): any
	local self = setmetatable({}, Rigs)
	self.parent = parent
	self.byIndex = {} :: { [number]: any }
	return self
end

-- `entry` is one row of the match roster: index, height, radius, weapon, userId.
function Rigs.spawn(self: any, entry: any)
	if self.byIndex[entry.index] then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = `Fighter{entry.index}`
	holder.Parent = self.parent

	local record = { entry = entry, holder = holder, rig = nil :: Model?, weapon = nil :: BasePart? }
	self.byIndex[entry.index] = record

	-- Appearance loading yields and can fail; the match does not wait for it. Until the rig lands
	-- the fighter is a placeholder block at the right size, which is still an honest read of where
	-- they are and how big they are.
	local block = Instance.new("Part")
	block.Name = "Placeholder"
	block.Size = Vector3.new(entry.radius * 2, entry.height, entry.radius * 2)
	block.Anchored = true
	block.CanCollide = false
	block.CanQuery = false
	block.Color = Color3.fromRGB(200, 200, 205)
	block.Parent = holder
	record.block = block

	task.spawn(function()
		local rig = buildRig(entry.userId, entry.height, holder)
		if rig and record.holder.Parent then
			record.rig = rig
			block.Transparency = 1
		end
	end)
end

function Rigs.clear(self: any)
	for _, r in self.byIndex do
		r.holder:Destroy()
	end
	self.byIndex = {}
end

-- `s` is the interpolated fighter state: x, y (feet), facing, state, tumbling, alive, invincible.
function Rigs.pose(self: any, index: number, s: any)
	local r = self.byIndex[index]
	if not r then
		return
	end
	local visible = s.alive and s.state ~= "ko"
	local h = r.entry.height

	-- The simulation's y is the fighter's FEET. A rig's origin is its middle, so everything drawn
	-- from a snapshot has to be lifted by half a height or every fighter stands buried to the waist.
	local cf = CFrame.new(s.x, s.y + h / 2, 0)
		* CFrame.Angles(0, math.rad(if s.facing >= 0 then 90 else -90), 0)
	if s.tumbling then
		-- Tumble is the one rotation the simulation actually carries a meaning for: it is how the
		-- player knows they have to tech. Spun off horizontal speed so it reads as momentum.
		cf *= CFrame.Angles(0, 0, math.rad((s.x * 12) % 360) * (if s.facing >= 0 then -1 else 1))
	end

	if r.rig then
		r.rig:PivotTo(cf)
		for _, d in r.rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end
	r.block.CFrame = cf
	if not r.rig then
		r.block.Transparency = if visible then 0 else 1
	end
	-- Invincibility has to be legible or respawn protection looks like a bug, and it is drawn on
	-- the placeholder as well as the rig so it reads before appearances finish loading.
	if s.invincible > 0 and visible then
		local pulse = 0.35 + 0.25 * math.sin(os.clock() * 24)
		if r.rig then
			for _, d in r.rig:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = pulse
				end
			end
		else
			r.block.Transparency = pulse
		end
	end
end

return Rigs
