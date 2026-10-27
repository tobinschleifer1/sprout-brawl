--!strict
-- The Roblox build's realms: each stage's name and look, re-themed as a Brawlhalla-style floating
-- island in a fantasy realm. ROBLOX ONLY, by decision - the web build keeps its own stage names
-- and art, so this is a skin laid over web/src/data/stages, never a change to it.
--
-- What a realm changes: the name players see, and every colour and material the stage is drawn
-- in (RealmArt). What it never changes: the stage's id (saved choices, votes, rooms and the replay
-- tests all key on it), its layout, its hazards, its blast zones. A realm is paint.
--
-- Colours run dark to light within each ramp, the way FxArt's do, so the art can shade by index.

export type Realm = {
	id: string, name: string, tagline: string,
	sky: { string },                                 -- top of the sky to the horizon
	sun: { x: number, y: number, r: number, colour: string, glow: string },
	cloud: { string },                               -- shadow, body, highlight
	far: string, near: string,                       -- distant mountains, distant islands
	landmark: string,
	rock: { string },                                -- island body, five tones
	top: { string },                                 -- the walking surface, three tones
	material: string,                                -- what the top is: grass, snow, sand...
	shelf: string, shelfRamp: { string },            -- drop-through platforms, three tones
	hang: string, hangRamp: { string },              -- what dangles under an island
	accent: string,                                  -- ledge banners and trim
	glow: string,                                    -- cracks, crystals, lanterns
}

local Realms = {}

local LIST: { Realm } = {
	{
		id = "FoundryFloor", name = "Hall of Champions", tagline = "Where every tournament ends.",
		sky = { "#3C8BE0", "#6FB5F2", "#BFE3FA", "#FCE6B8" },
		sun = { x = 0.78, y = 0.24, r = 18, colour = "#FFF6D6", glow = "#FFE7A3" },
		cloud = { "#C9D9F0", "#F2F7FF", "#FFFFFF" }, far = "#7DA9D8", near = "#5C8FC4",
		landmark = "hall",
		rock = { "#3B2A2E", "#6B4E48", "#94705E", "#BC9878", "#E2C49C" },
		top = { "#2F7D32", "#52B347", "#8CE06A" }, material = "grass",
		shelf = "wood", shelfRamp = { "#6B3F22", "#A2683A", "#D49A5C" },
		hang = "roots", hangRamp = { "#3E2A1C", "#6B4A2E" },
		accent = "#D93B3B", glow = "#FFD45A",
	},
	{
		id = "TheSpan", name = "Bifrost Bridge", tagline = "A bridge of light between worlds.",
		sky = { "#1B1450", "#4A2A8C", "#B05AB8", "#FFB3A0" },
		sun = { x = 0.2, y = 0.3, r = 14, colour = "#FFF0F6", glow = "#FFB8E6" },
		cloud = { "#7A5AA8", "#C99AD8", "#FFE0F2" }, far = "#5A3E8E", near = "#3E2C70",
		landmark = "rainbow",
		rock = { "#2E2A5E", "#4E4A8E", "#7470B8", "#9C98D8", "#C8C4F0" },
		top = { "#3A7CC4", "#5FD0F0", "#E8FBFF" }, material = "light",
		shelf = "stone", shelfRamp = { "#4A4266", "#7A72A0", "#B5AFD6" },
		hang = "chains", hangRamp = { "#3A3450", "#8A84A8" },
		accent = "#FFD45A", glow = "#7DF0FF",
	},
	{
		id = "Smeltworks", name = "Dwarven Forge", tagline = "The anvils never cool.",
		sky = { "#2A1230", "#7A2A3A", "#E2643A", "#FFC27A" },
		sun = { x = 0.2, y = 0.24, r = 18, colour = "#FFE2A8", glow = "#FF9A4A" },
		cloud = { "#7A3A3A", "#C4644A", "#FFB37A" }, far = "#6A2E36", near = "#4A1E28",
		landmark = "forge",
		rock = { "#2A3038", "#46525E", "#647482", "#8494A2", "#AAB8C4" },
		top = { "#5A4A46", "#8C7A70", "#C4AE9C" }, material = "flagstone",
		shelf = "iron", shelfRamp = { "#2E2A30", "#5E5862", "#9C96A0" },
		hang = "lava", hangRamp = { "#C4361A", "#FFB43C" },
		accent = "#FF7A3C", glow = "#FFB43C",
	},
	{
		id = "Rooftops", name = "Sky Temple", tagline = "Fight above the clouds.",
		sky = { "#2E7FB8", "#5FB2D8", "#B8E4EC", "#FFE2D2" },
		sun = { x = 0.66, y = 0.2, r = 15, colour = "#FFFBEA", glow = "#FFE4C4" },
		cloud = { "#C4DCEC", "#F0F8FF", "#FFFFFF" }, far = "#7AAED0", near = "#5A92B8",
		landmark = "pagoda",
		rock = { "#1E2C3E", "#30465E", "#466480", "#6686A2", "#90AEC6" },
		top = { "#2E8A5A", "#4FC07A", "#9CEAA8" }, material = "jade",
		shelf = "temple", shelfRamp = { "#7A1E22", "#C23A32", "#F07A5A" },
		hang = "lanterns", hangRamp = { "#7A1E22", "#FFB45A" },
		accent = "#FFD45A", glow = "#FFB45A",
	},
	{
		id = "Saltflat", name = "Sunscorch Ruins", tagline = "The sand remembers kings.",
		sky = { "#3A9AD8", "#7CC4EC", "#D8EEF0", "#FFE8B4" },
		sun = { x = 0.3, y = 0.18, r = 24, colour = "#FFFDF0", glow = "#FFF0B0" },
		cloud = { "#E8DCC8", "#FFF6E8", "#FFFFFF" }, far = "#D8B07A", near = "#C4925A",
		landmark = "pyramid",
		rock = { "#5A3A22", "#865A36", "#A87648", "#C29460", "#DEBB86" },
		top = { "#B88838", "#D2AA5E", "#ECCB86" }, material = "sand",
		shelf = "sandstone", shelfRamp = { "#8A6036", "#C49456", "#ECC88A" },
		hang = "vines", hangRamp = { "#3E6A2A", "#6EA040" },
		accent = "#3A8AD8", glow = "#FFE07A",
	},
	{
		id = "Undertow", name = "Viking Harbor", tagline = "Mind the tide, mind the longships.",
		sky = { "#2E6AA8", "#5E9ACC", "#A8D2E4", "#E8F4F0" },
		sun = { x = 0.82, y = 0.3, r = 16, colour = "#FFFCEE", glow = "#E0F4FF" },
		cloud = { "#A8BCD0", "#E2ECF4", "#FFFFFF" }, far = "#5E7EA0", near = "#3E5E80",
		landmark = "longship",
		rock = { "#2A2620", "#4E463A", "#746856", "#9A8C74", "#C4B698" },
		top = { "#6A4A2E", "#9A6E44", "#C8986A" }, material = "planks",
		shelf = "wood", shelfRamp = { "#5A3A22", "#8E6038", "#C08E5C" },
		hang = "seaweed", hangRamp = { "#1E5A44", "#3E8A5A" },
		accent = "#D93B3B", glow = "#FFE08A",
	},
	{
		id = "FreightLift", name = "Crystal Mines", tagline = "Deep enough to glow.",
		sky = { "#1E1846", "#3A2874", "#563A98", "#7A4AB0" },
		sun = { x = 0.62, y = 0.32, r = 10, colour = "#E8D8FF", glow = "#B48AFF" },
		cloud = { "#2E2058", "#4A3684", "#7A5AB8" }, far = "#2A1E52", near = "#1C1440",
		landmark = "crystals",
		rock = { "#342C58", "#544A86", "#7A70B0", "#9C94CC", "#C4BEE8" },
		top = { "#4A3E62", "#6E628E", "#A498C8" }, material = "cavestone",
		shelf = "minecart", shelfRamp = { "#4A3424", "#7A5634", "#B4824E" },
		hang = "crystals", hangRamp = { "#3AC8E8", "#C8FAFF" },
		accent = "#3AE8C8", glow = "#7DF0FF",
	},
	{
		id = "Faultline", name = "Thunder Canyon", tagline = "The sky is the hazard.",
		sky = { "#1E2238", "#3A3E62", "#6A6A8A", "#C49A7A" },
		sun = { x = 0.7, y = 0.22, r = 12, colour = "#E8ECFF", glow = "#AAB8FF" },
		cloud = { "#2E3048", "#4E5270", "#7A80A8" }, far = "#6A4A44", near = "#4E3430",
		landmark = "storm",
		rock = { "#4A2218", "#763A26", "#A65A36", "#CC7C4A", "#EAA46E" },
		top = { "#6A7A3A", "#94A84E", "#C4D47A" }, material = "scrub",
		shelf = "stone", shelfRamp = { "#5E3424", "#8A5A3E", "#B88A62" },
		hang = "roots", hangRamp = { "#2E1A12", "#5A3424" },
		accent = "#FFE45A", glow = "#C8D8FF",
	},
	{
		id = "AshfallSummit", name = "Muspel Peak", tagline = "Born in fire. Fought in fire.",
		sky = { "#2E1212", "#6A2018", "#B03A1A", "#FF9A3A" },
		sun = { x = 0.5, y = 0.6, r = 26, colour = "#FFE0A0", glow = "#FF6A2A" },
		cloud = { "#4A1C1A", "#7A2E24", "#C4583A" }, far = "#3A1414", near = "#260C0C",
		landmark = "volcano",
		rock = { "#3A262A", "#5E4244", "#8A6660", "#B08A7E", "#D2AE9E" },
		top = { "#3A2E2E", "#5E4E4A", "#8A7670" }, material = "ash",
		shelf = "obsidian", shelfRamp = { "#241C2E", "#4A3E58", "#7A6C8E" },
		hang = "lava", hangRamp = { "#C4361A", "#FFB43C" },
		accent = "#FF6A2A", glow = "#FF9A3A",
	},
}

-- The lobby is a realm too: a bazaar on floating islands under a midday sky, in sight of the great
-- hall the champions fight for. Not a stage - nothing looks it up by a stage id.
Realms.LOBBY = {
	id = "Lobby", name = "Skyhold Bazaar", tagline = "Pick your fight.",
	sky = { "#3C8BE0", "#6FB5F2", "#BFE3FA", "#FCE6B8" },
	sun = { x = 0.22, y = 0.2, r = 16, colour = "#FFF6D6", glow = "#FFE7A3" },
	cloud = { "#C9D9F0", "#F2F7FF", "#FFFFFF" }, far = "#7DA9D8", near = "#5C8FC4",
	-- no landmark: the bazaar's own stalls stand where one would, and a hall cut off behind them
	-- reads as clutter
	landmark = "none",
	rock = { "#3A3346", "#5B5266", "#7D7488", "#A39AAE", "#C9C1D2" },
	top = { "#2F7D32", "#52B347", "#8CE06A" }, material = "grass",
	shelf = "wood", shelfRamp = { "#6B3F22", "#A2683A", "#D49A5C" },
	hang = "roots", hangRamp = { "#3E2A1C", "#6B4A2E" },
	accent = "#D93B3B", glow = "#FFD45A",
} :: Realm

-- The lobby's districts and rooms, by the ids web/src/data/plaza.js gives them, as Roblox names
-- them. The data's own names are the web's and stay there.
Realms.PLACES = {
	tailor = "Tailor's Terrace", square = "Champions' Square", arcade = "The Arcade Grove",
	gates = "Fighters' Gates", climb = "Climbers' Yard", lounge = "The War Room",
}
function Realms.place(id: string?, fallback: string): string
	return (if id then Realms.PLACES[id] else nil) or fallback
end

local BY_ID: { [string]: Realm } = {}
for _, r in LIST do BY_ID[r.id] = r end
Realms.LIST = LIST
Realms.BY_ID = BY_ID

-- The realm a stage is drawn as, or nil for a stage no realm covers (it then draws as the web does).
function Realms.of(stageId: string?): Realm?
	return if stageId then BY_ID[stageId] else nil
end

-- The name players see for a stage: the realm's, or the stage's own if no realm covers it.
function Realms.name(stage: any): string
	local r = Realms.of(stage and stage.id)
	return if r then r.name else (stage and stage.name or "")
end

-- A copy of `stage` dressed in its realm's colours, for the parity-held StageThumb: the geometry is
-- the stage's own, only `palette` (and the name) change.
function Realms.dress(stage: any): any
	local r = Realms.of(stage and stage.id)
	if not r then return stage end
	local copy = table.clone(stage)
	copy.name = r.name
	local stops: { any } = {}
	for i, at in { 0, 0.45, 0.8, 1 } do
		local stop: { any } = { at }
		stop[2] = r.sky[i]
		stops[i] = stop
	end
	copy.palette = {
		sky = r.sky[2], skyStops = stops,
		ground = r.rock[3], groundTop = r.top[2], platform = r.shelfRamp[2], accent = r.accent,
	}
	return copy
end

return Realms
