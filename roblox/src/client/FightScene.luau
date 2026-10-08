--!strict
-- One frame of a fight, drawn: the sky, the stage, the disaster, every fighter, the world's
-- threats, the ultimates' world layer, the timed effects and the sparks, then the ultimate's
-- cutscene on top. Everything here was the body of the client's RenderStepped, moved out so that
-- tools/render-fight.luau can run the same draw on a real Match in Lune and turn it into a picture:
-- the game draws into a ScreenGui, so Studio's screenshot of a fight is empty, and an effect nobody
-- can look at cannot be designed.
--
-- Pure drawing. It reads the decoded states and the scene the client already holds, and writes
-- nothing back except particles into `fx`, as the fighter painter always has.
local Shared = game:GetService("ReplicatedStorage").Shared
local Stage = require(Shared.Stage)
local FRAME = require(Shared.Config).FRAME
local Canvas2D = require(script.Parent.Canvas2D)
local Stage2D = require(script.Parent.Stage2D)
local DisasterArt = require(script.Parent.DisasterArt)
local HazardArt = require(script.Parent.HazardArt)
local RealmArt = require(script.Parent.RealmArt)
local HitReact = require(script.Parent.HitReact)
local ShieldArt = require(script.Parent.ShieldArt)
local Realms = require(Shared.Realms)
local UltCinematic = require(script.Parent.UltCinematic)
local UltBanner = require(script.Parent.UltBanner)
local Effects = require(script.Parent.Effects)
local World2D = require(script.Parent.World2D)
local Fighter2D = require(script.Parent.Fighter2D)
local UltWorld = require(script.Parent.UltWorld)
local FxPlayer = require(script.Parent.FxPlayer)
local Danger = require(script.Parent.Danger)

-- a shield shatters in its owner's colour (FxPlayer reads this for `shieldbreak`)
FxPlayer.shieldColour = function(index: number?): string
	return ShieldArt.colourOf(index, Fighter2D.teamColours)
end

local FightScene = {}

local WHITE = Color3.new(1, 1, 1)
local NIGHT = Color3.fromRGB(5, 6, 10)

-- How hard a finisher shakes the camera: past a heavy hit's 0.5, short of an ultimate's 1.4.
FightScene.FINISHER_SHAKE = 1.2

-- One event, released at the frame it happened on: its sparks (Effects, the parity-held port) and
-- its drawn moment (FxPlayer). Where FxPlayer draws the event, the plain rings Effects would add
-- are dropped - a gold ring with spikes over the caster's own coloured shockwave is two drawings
-- of one thing, in two palettes. The sparks, dust and shake are kept.

function FightScene.spawn(fx: any, player: any, e: any, states: { any }, chars: { any },
	glowOf: (number?) -> string?, rand: () -> number, heightOf: (number?) -> number, sparks: boolean)
	local rings = #fx.rings
	if sparks then Effects.spawn(fx, e, glowOf, rand, heightOf) end
	-- A finisher lands with the hardest shake an ordinary hit gives (COMBO, config.js).
	if e.type == "hit" and e.finisher then fx.shake = math.max(fx.shake, FightScene.FINISHER_SHAKE) end
	if FxPlayer.spawn(player, e, states, chars) then
		for i = #fx.rings, rings + 1, -1 do table.remove(fx.rings, i) end
	end
end

-- `S` carries what one frame needs:
--   view { x, y, ppu }, shakeX, shakeY   where the camera is (already punched in by the cutscene)
--   stage, platforms                     the view-only Stage and the moving platforms' state
--   scene                                the newest SceneSnapshot at or before the drawn frame
--   states, chars                        decoded fighters and their characters (index + 1)
--   t                                    wall clock, for what breathes
--   fx, player                           Effects state (sparks) and FxPlayer state (timed sprites)
--   cine, caster, casterChar, ult        the cutscene, if one is running
--   report(key, err)                     called once per failure kind; nil to rethrow
-- Returns the banner layout, which the HUD needs for the caster's name.
function FightScene.draw(c: any, S: any): any
	local view = S.view
	local function guard(key: number, what: string, fn: () -> ())
		local ok, err = pcall(fn :: any)
		if not ok then
			if S.report then S.report(key, `{what}: {err}`) else error(err, 0) end
		end
	end
	Stage2D.sky(c, S.stage or { data = {} }, view.x, S.t)
	c:world(view.x, view.y, view.ppu, S.shakeX, S.shakeY)
	if S.stage then
		-- The view-only Stage is never stepped; the server sends what it cannot derive. `moving` is
		-- a function of stage time and `sinking` is a function of who is standing on it, and only
		-- the server knows the second.
		Stage.applyDynamicState(S.stage, S.platforms)
		Stage2D.draw(c, S.stage)
	end
	-- Natural disasters, in the realm's pixel art (DisasterArt): the body behind the fighters, the
	-- bolts and the falling rocks over them. The view is the server's, through the scene stream.
	local scene = S.scene
	local disaster = if scene and scene.hazards then scene.hazards.disaster else nil
	local realm = if S.stage then (Realms.of(S.stage.data and S.stage.data.id) or Realms.LIST[1]) else nil
	if disaster and S.stage then
		guard(-5, "the disaster failed to draw", function()
			DisasterArt.back(c, disaster, S.stage, realm, S.t, S.player, view.x)
			if S.fx then S.fx.shake = math.max(S.fx.shake, DisasterArt.shake(disaster)) end
		end)
	end
	-- the realm's weather, in the air behind the fighters
	if realm then
		local vp = c:viewport()
		RealmArt.weather(c, realm, view.x, view.y, vp.X / view.ppu, vp.Y / view.ppu, S.t)
	end
	local cine, caster = S.cine, S.caster
	-- The ultimates' ground layer - rune circles, cracks, the sky going dark - sits behind bodies.
	guard(-3, "the ultimates' world layer failed to draw", function()
		UltWorld.under(c, S.states, S.chars, scene, S.stage, S.t)
	end)
	-- the hard-hit: speed lines and smoke trails behind anyone launched
	guard(-7, "the hit reactions failed to draw", function()
		HitReact.draw(c, S.states, S.chars, S.t)
	end)
	Fighter2D.glows = if S.player then S.player.glows else nil
	for _, st in S.states do
		local char = S.chars[st.index + 1]
		if char and not (cine and cine.active and st == caster) then
			guard(st.index, `fighter {st.index} failed to draw`, function()
				local surface = if S.stage then Stage.surfaceUnder(S.stage, st.x, st.y + 0.1) else nil
				Fighter2D.draw(c, st, char, S.t, if surface then surface.top else nil)
			end)
		end
	end
	-- Danger: anyone close to being KO'd smokes (Danger.luau says how close is measured).
	if S.stage and S.stage.blast then
		guard(-8, "the danger smoke failed to draw", function()
			for _, st in S.states do
				local char = S.chars[st.index + 1]
				if char and st.alive and st.state ~= "ko" and st.state ~= "respawn" then
					local k = Danger.level(st.percent or 0, Danger.percent(char.weight, S.stage.blast))
					for _, sh in Danger.shapes(st.x, st.y, char.height, k, math.floor(S.t * 60)) do
						Canvas2D.rect(c, sh[2], sh[3], sh[4], sh[5], Canvas2D.hex(sh[6], WHITE), sh[7])
					end
				end
			end
		end)
	end
	if scene and S.stage then
		guard(-6, "the hazards failed to draw", function()
			HazardArt.draw(c, scene.hazards or {}, S.stage, realm, scene.frame * FRAME)
		end)
		World2D.entities(c, scene, S.chars, S.states, scene.frame * FRAME)
	end
	if disaster and S.stage then
		guard(-5, "the disaster failed to draw", function()
			DisasterArt.front(c, disaster, S.stage, realm, S.t, S.player)
		end)
	end
	guard(-3, "the ultimates' world layer failed to draw", function()
		UltWorld.over(c, S.states, S.chars, scene, S.stage, S.t)
		if S.player then FxPlayer.draw(S.player, c) end
	end)
	-- Sparks and rings, from the shape list both builds draw.
	guard(-2, "effects failed to draw", function()
		for _, sh in Effects.shapes(S.fx) do
			if sh[1] == "r" then
				Canvas2D.rect(c, sh[2], sh[3], sh[4], sh[5], Canvas2D.hex(sh[6], WHITE), sh[7])
			else
				local dx, dy = sh[4] - sh[2], sh[5] - sh[3]
				Canvas2D.save(c)
				Canvas2D.translate(c, sh[2], sh[3])
				Canvas2D.rotate(c, math.atan2(dy, dx))
				Canvas2D.rect(c, 0, -sh[6] / 2, math.sqrt(dx * dx + dy * dy), sh[6], Canvas2D.hex(sh[7], WHITE), sh[8])
				Canvas2D.restore(c)
			end
		end
	end)
	-- The kill hit (Config.KILL_HIT): the whole view flashes white for Effects.KILL_FLASH, so the
	-- hit that sends someone out is seen as that by everyone, not just by whoever was watching it.
	if S.fx and (S.fx.flash or 0) > 0 then
		local vp = c:viewport()
		Canvas2D.screen(c)
		Canvas2D.rect(c, 0, 0, vp.X, vp.Y, WHITE, Effects.KILL_FLASH_ALPHA * S.fx.flash / Effects.KILL_FLASH)
		c:world(view.x, view.y, view.ppu, S.shakeX, S.shakeY)
	end
	-- The impact frame: a white (or caster-coloured) flash over the whole view, for a few
	-- hundredths of a second, when an ultimate lands its big moment.
	if S.player and S.player.flash > 0.01 then
		local vp = c:viewport()
		Canvas2D.screen(c)
		Canvas2D.rect(c, 0, 0, vp.X, vp.Y, Canvas2D.hex(S.player.flashColour, WHITE), S.player.flash * 0.5)
		Canvas2D.rect(c, 0, 0, vp.X, vp.Y, WHITE, S.player.flash * 0.35)
		c:world(view.x, view.y, view.ppu, S.shakeX, S.shakeY)
	end
	-- Everything but the caster falls into shadow; the caster stands in gold for exactly the frames
	-- they cannot be hit, then is drawn on top of it all, then the banner crosses the screen.
	local banner = nil
	local casterChar = S.casterChar
	if caster and casterChar and cine and (cine.active or cine.glow) then
		guard(-1, "the ultimate cutscene failed to draw", function()
			if cine.dim > 0 then
				local vp = c:viewport()
				Canvas2D.screen(c)
				Canvas2D.rect(c, 0, 0, vp.X, vp.Y, NIGHT, cine.dim)
				c:world(view.x, view.y, view.ppu, S.shakeX, S.shakeY)
			end
			for _, sh in UltCinematic.glowShapes(cine, caster.x, caster.y, casterChar.height) do
				Canvas2D.ellipse(c, sh[2], sh[3], sh[4], sh[5], Canvas2D.hex(sh[6], WHITE), sh[7])
			end
			if cine.active then
				local surface = if S.stage then Stage.surfaceUnder(S.stage, caster.x, caster.y + 0.1) else nil
				Fighter2D.draw(c, caster, casterChar, S.t, if surface then surface.top else nil)
				local vp = c:viewport()
				banner = UltCinematic.bannerLayout(cine, vp.X, vp.Y)
				if banner then UltBanner.paint(c, banner, S.ult.colour, S.ult.weapon, caster, casterChar, S.t) end
			end
		end)
		c:world(view.x, view.y, view.ppu, S.shakeX, S.shakeY)
	end
	return banner
end

return FightScene
