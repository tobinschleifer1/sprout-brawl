--!strict
-- The cosmetics catalogue (Roblox only; docs/briefs/crates-and-monetisation-plan.md). Every item a
-- player can own: what it is, how rare, which series it belongs to, and where it comes from.
-- Nothing here changes play - a cosmetic is presentation, and a weapon skin keeps its weapon's grid.
--
-- Not yet read by the game: phase 1 of the plan. Loot.luau rolls from it; the Locker, the drawing
-- hooks and the economy server come in later phases.
--
-- `source` says how an item is obtained:
--   "crate"   in its series' crates (and always craftable with Sparks: nothing is random-only)
--   "mastery" earned by playing a weapon, never sold, never in a crate
--   "season"  on a season track (free or premium)
--   "shop"    sold directly in the featured shop, never random
--   "pass"    granted by a game pass
-- `crates` lists which crates it can come out of when source is "crate".
local Cosmetics = {}

Cosmetics.TYPES = { "weapon_skin", "hit_effect", "ko_effect", "swing_trail", "step_trail", "spawn_effect", "shield_skin", "title" }
Cosmetics.RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

export type Item = {
	id: string, type: string, name: string, rarity: string, series: number, source: string,
	weapon: string?, crates: { string }?, ramp: string?, blurb: string?,
}

local S1 = 1
local BOTH = { "scrap", "forge" }
local SCRAP = { "scrap" }
local FORGE = { "forge" }
-- which crates a rarity appears in (Scrap: Common-Legendary, Forge: Rare-Mythic)
local function cratesFor(rarity: string): { string }
	if rarity == "Common" or rarity == "Uncommon" then return SCRAP end
	if rarity == "Mythic" then return FORGE end
	return BOTH
end

local LIST: { Item } = {}
local function add(t: any)
	t.series = t.series or S1
	t.source = t.source or "crate"
	if t.source == "crate" then t.crates = t.crates or cratesFor(t.rarity) end
	table.insert(LIST, t :: Item)
end

-- Weapon skins: the designs in tools/cosmetic-sheet.mjs, same ids.
local function skin(id: string, weapon: string, name: string, rarity: string)
	add({ id = id, type = "weapon_skin", weapon = weapon, name = name, rarity = rarity })
end
skin("sword_rustwood", "Sword", "Rustwood Blade", "Common")
skin("sword_frostbite", "Sword", "Frostbite", "Rare")
skin("sword_emberoath", "Sword", "Ember Oath", "Epic")
skin("sword_starforged", "Sword", "Starforged", "Legendary")
skin("daggers_bonefang", "Daggers", "Bone Fang", "Uncommon")
skin("daggers_neontwins", "Daggers", "Neon Twins", "Rare")
skin("daggers_venomfang", "Daggers", "Venomfang", "Epic")
skin("hammer_cobblestone", "Hammer", "Cobblestone", "Common")
skin("hammer_thunderhead", "Hammer", "Thunderhead", "Epic")
skin("axe_lumberjack", "Axe", "Lumberjack", "Common")
skin("axe_glacier", "Axe", "Glacier Cleaver", "Rare")
skin("scythe_harvestmoon", "Scythe", "Harvest Moon", "Rare")
skin("scythe_reaperslantern", "Scythe", "Reaper's Lantern", "Legendary")
skin("blasters_toy", "Blasters", "Toy Blasters", "Uncommon")
skin("blasters_chrome", "Blasters", "Chrome Rivets", "Rare")
skin("gauntlets_boxingreds", "Gauntlets", "Boxing Reds", "Common")
skin("gauntlets_magma", "Gauntlets", "Magma Fists", "Epic")
skin("pike_royalguard", "Pike", "Royal Guard", "Rare")
skin("longbow_elmwood", "Longbow", "Elmwood", "Common")
skin("longbow_sunfire", "Longbow", "Sunfire Bow", "Epic")
skin("grimoire_necro", "Grimoire", "Necro Tome", "Rare")
skin("shield_lion", "Shield", "Lionheart", "Uncommon")
skin("flail_lantern", "Flail", "Spiked Lantern", "Rare")
skin("whip_thornvine", "Whip", "Thornvine", "Uncommon")
skin("chakram_halo", "Chakram", "Golden Halos", "Epic")
skin("boots_retro", "RocketBoots", "Retro Rockets", "Rare")
skin("daggers_sugarshivs", "Daggers", "Sugar Shivs", "Common")
skin("hammer_permafrost", "Hammer", "Permafrost", "Uncommon")
skin("hammer_jawbreaker", "Hammer", "Jawbreaker", "Common")
skin("axe_afterhours", "Axe", "Afterhours Hatchet", "Uncommon")
skin("axe_riftcleaver", "Axe", "Rift Cleaver", "Epic")
skin("scythe_sugarreaper", "Scythe", "Sugar Reaper", "Common")
skin("scythe_rimereaper", "Scythe", "Rime Reaper", "Uncommon")
skin("blasters_bubblegum", "Blasters", "Bubblegum Blasters", "Common")
skin("blasters_nightshift", "Blasters", "Nightshift", "Epic")
skin("gauntlets_coldsnap", "Gauntlets", "Cold Snap", "Uncommon")
skin("gauntlets_arcade", "Gauntlets", "Arcade Breakers", "Rare")
skin("pike_roadwarden", "Pike", "Roadwarden", "Common")
skin("pike_icebound", "Pike", "Icebound Standard", "Uncommon")
skin("pike_eventide", "Pike", "Eventide Sovereign", "Mythic")
skin("longbow_licorice", "Longbow", "Licorice Recurve", "Uncommon")
skin("longbow_eclipse", "Longbow", "Eclipse String", "Legendary")
skin("grimoire_sugarspell", "Grimoire", "Sugarspell", "Common")
skin("grimoire_mossbound", "Grimoire", "Mossbound Ledger", "Uncommon")
skin("grimoire_lastlight", "Grimoire", "Last Light Codex", "Mythic")
skin("shield_ironbark", "Shield", "Ironbark", "Common")
skin("shield_whiteout", "Shield", "Whiteout Bulwark", "Uncommon")
skin("shield_afterimage", "Shield", "Afterimage Aegis", "Epic")
skin("flail_scrapyard", "Flail", "Scrapyard Wrecker", "Common")
skin("flail_gumball", "Flail", "Gumball Wrecker", "Uncommon")
skin("flail_orbitbreaker", "Flail", "Orbit Breaker", "Rare")
skin("whip_taffy", "Whip", "Taffy Snap", "Common")
skin("whip_livewire", "Whip", "Livewire Lash", "Uncommon")
skin("whip_riftbinder", "Whip", "Riftbinder", "Epic")
skin("chakram_peppermint", "Chakram", "Peppermint Rings", "Common")
skin("chakram_coldorbit", "Chakram", "Cold Orbit", "Uncommon")
skin("chakram_discotheque", "Chakram", "Discotheque", "Rare")
skin("boots_foundry", "RocketBoots", "Foundry Runners", "Common")
skin("boots_sugarrush", "RocketBoots", "Sugar Rush", "Uncommon")
skin("boots_nightdrive", "RocketBoots", "Nightdrive", "Rare")

-- Hit effects. Common-Rare recolour the weapon's own hit drawings (FxArt ramps); Epic and up are
-- new drawings, still to be made.
add({ id = "hit_pixelpop", type = "hit_effect", name = "Pixel Pop", rarity = "Common", ramp = "#E8ECF2" })
add({ id = "hit_confetti", type = "hit_effect", name = "Confetti", rarity = "Uncommon", ramp = "#FFD24A" })
add({ id = "hit_sakura", type = "hit_effect", name = "Sakura", rarity = "Rare", ramp = "#FF8AC8" })
add({ id = "hit_static", type = "hit_effect", name = "Static", rarity = "Rare", ramp = "#7FE6FF" })
add({ id = "hit_toxic", type = "hit_effect", name = "Toxic", rarity = "Uncommon", ramp = "#9CFF3C" })
add({ id = "hit_inkblot", type = "hit_effect", name = "Inkblot", rarity = "Epic", ramp = "#6A3AFF",
	blurb = "Splats of ink, and the screen remembers them for a moment." })
add({ id = "hit_comicpow", type = "hit_effect", name = "Comic POW!", rarity = "Epic",
	blurb = "POW, BAM and KRAK in a starburst, picked by the hit's strength." })
add({ id = "hit_supernova", type = "hit_effect", name = "Supernova", rarity = "Legendary", ramp = "gold",
	blurb = "Every hit a small star; heavy hits a ring of them." })
add({ id = "hit_eventhorizon", type = "hit_effect", name = "Event Horizon", rarity = "Mythic",
	blurb = "Hits fold space: a ring of light sucked into a point, then released." })

-- KO effects: on the stock you take, at the blast line.
add({ id = "ko_balloonpop", type = "ko_effect", name = "Balloon Pop", rarity = "Uncommon" })
add({ id = "ko_ghostrise", type = "ko_effect", name = "Ghost Rise", rarity = "Rare" })
add({ id = "ko_firework", type = "ko_effect", name = "Firework", rarity = "Rare" })
add({ id = "ko_pixelshatter", type = "ko_effect", name = "Pixel Shatter", rarity = "Epic" })
add({ id = "ko_meteor", type = "ko_effect", name = "Meteor Crater", rarity = "Epic" })
add({ id = "ko_blackhole", type = "ko_effect", name = "Black Hole", rarity = "Legendary" })
add({ id = "ko_dragonsbreath", type = "ko_effect", name = "Dragon's Breath", rarity = "Mythic",
	blurb = "A pixel dragon crosses the screen and breathes the stock away." })

-- Swing trails, step trails, spawn effects, shield skins.
add({ id = "trail_shadow", type = "swing_trail", name = "Shadow", rarity = "Uncommon", ramp = "#2A2438" })
add({ id = "trail_ember", type = "swing_trail", name = "Ember", rarity = "Rare", ramp = "fire" })
add({ id = "trail_frost", type = "swing_trail", name = "Frost", rarity = "Rare", ramp = "#BFF4FF" })
add({ id = "trail_glitch", type = "swing_trail", name = "Glitch", rarity = "Epic" })
add({ id = "trail_rainbow", type = "swing_trail", name = "Rainbow", rarity = "Epic" })
add({ id = "trail_gold", type = "swing_trail", name = "Gilded", rarity = "Legendary", ramp = "gold" })
add({ id = "steps_leaves", type = "step_trail", name = "Leaf Swirl", rarity = "Common" })
add({ id = "steps_sparkle", type = "step_trail", name = "Sparkle Steps", rarity = "Uncommon" })
add({ id = "steps_flame", type = "step_trail", name = "Flame Steps", rarity = "Rare", ramp = "fire" })
add({ id = "spawn_confetti", type = "spawn_effect", name = "Confetti Cannon", rarity = "Uncommon" })
add({ id = "spawn_portal", type = "spawn_effect", name = "Portal", rarity = "Rare" })
add({ id = "spawn_droppod", type = "spawn_effect", name = "Drop Pod", rarity = "Epic" })
add({ id = "spawn_lightning", type = "spawn_effect", name = "Lightning Strike", rarity = "Legendary" })
add({ id = "shield_hex", type = "shield_skin", name = "Hex Grid", rarity = "Common" })
add({ id = "shield_crystal", type = "shield_skin", name = "Crystal", rarity = "Epic" })
add({ id = "shield_runes", type = "shield_skin", name = "Rune Circle", rarity = "Legendary" })

-- Titles. The crate ones are flavour; the proud ones are earned and never sold.
add({ id = "title_brawler", type = "title", name = "Brawler", rarity = "Common" })
add({ id = "title_ringleader", type = "title", name = "Ringleader", rarity = "Rare" })
add({ id = "title_untouchable", type = "title", name = "Untouchable", rarity = "Epic", source = "mastery" })
add({ id = "title_legend", type = "title", name = "Legend", rarity = "Legendary", source = "season" })
add({ id = "title_vip", type = "title", name = "VIP", rarity = "Epic", source = "pass" })
-- VIP's Series 1 cosmetic, and its respawn sparkle (Products.PASS_ITEMS): kept forever, not random.
add({ id = "trail_vipgold", type = "swing_trail", name = "VIP Gold Rush", rarity = "Epic", source = "pass" })
add({ id = "spawn_vipsparkle", type = "spawn_effect", name = "VIP Sparkle", rarity = "Epic", source = "pass" })

Cosmetics.LIST = LIST
local BY_ID: { [string]: Item } = {}
for _, item in LIST do BY_ID[item.id] = item end
Cosmetics.BY_ID = BY_ID

function Cosmetics.get(id: string): Item?
	return BY_ID[id]
end

return Cosmetics
