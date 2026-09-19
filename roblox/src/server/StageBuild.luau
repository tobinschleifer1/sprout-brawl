--!strict
-- Turns a Stage into parts you can see.
--
-- The geometry here is decoration and nothing else. Collision is resolved by Stage.collide against
-- the numbers, exactly as it is in the web build, so these parts are CanCollide false and
-- Anchored: if a part and the simulation ever disagreed, the simulation would be right and the
-- player would be confused. Nothing physical is allowed to touch a fighter.
--
-- The play plane is z = 0. World x and y map straight onto Roblox X and Y, because the stage data
-- is already in studs and the engine's gravity is already 150 studs/s^2.

local PLANE_DEPTH = 8       -- how thick the stage looks front-to-back; play is a plane at z = 0

local StageBuild = {}

local function part(name: string, size: Vector3, cf: CFrame, colour: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = colour
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function hexColour(hex: string?, fallback: Color3): Color3
	if type(hex) ~= "string" or #hex ~= 7 then
		return fallback
	end
	local ok, c = pcall(Color3.fromHex, hex)
	return if ok then c else fallback
end

-- Returns a model plus the list of { part, platform } pairs that move, for the caller to drive.
function StageBuild.build(stage: any, parent: Instance): (Model, { any })
	local model = Instance.new("Model")
	model.Name = `Stage_{stage.data.id}`

	local pal = stage.data.palette or {}
	local ground = hexColour(pal.ground, Color3.fromRGB(62, 68, 80))
	local groundTop = hexColour(pal.groundTop, Color3.fromRGB(138, 148, 166))
	local shelf = hexColour(pal.platform, Color3.fromRGB(110, 119, 136))

	local moving = {}
	for _, p in stage.platforms do
		local w = p.x2 - p.x1
		local thickness = p.top - p.bottom
		local cf = CFrame.new((p.x1 + p.x2) / 2, (p.top + p.bottom) / 2, 0)
		local body = part(p.id, Vector3.new(w, thickness, PLANE_DEPTH), cf,
			if p.solid then ground else shelf, model)
		-- A lip on the top surface. It is not just decoration: the top face is the line a player
		-- reads to judge whether a recovery clears the ledge, and a flat slab of one colour makes
		-- that line guesswork from the camera distance this game plays at.
		local lip = part(`{p.id}_top`, Vector3.new(w, 0.5, PLANE_DEPTH + 0.05),
			CFrame.new((p.x1 + p.x2) / 2, p.top - 0.25, 0),
			if p.solid then groundTop else shelf:Lerp(Color3.new(1, 1, 1), 0.25), model)
		lip.Material = Enum.Material.Metal
		if p.moving or p.sinking then
			table.insert(moving, { platform = p, body = body, lip = lip })
		end
	end

	model.Parent = parent
	return model, moving
end

-- Moving and sinking platforms mutate x1/x2/top/bottom in place as Stage.step runs, so the parts
-- are placed from those live numbers every frame rather than from a remembered origin plus a
-- delta. Deriving a position from dx/dy would drift: dy is the change THIS frame, not the total.
function StageBuild.follow(moving: { any })
	for _, m in moving do
		local p = m.platform
		local cx, cy = (p.x1 + p.x2) / 2, (p.top + p.bottom) / 2
		m.body.CFrame = CFrame.new(cx, cy, 0)
		m.lip.CFrame = CFrame.new(cx, p.top - 0.25, 0)
	end
end

return StageBuild
