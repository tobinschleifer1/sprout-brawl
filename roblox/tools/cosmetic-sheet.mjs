// Design tool for the cosmetics plan (docs/briefs/crates-and-monetisation-plan.md): renders every
// weapon skin, crate and key through the SAME compiler the game's weapon art uses
// (web/src/data/weaponArt.js compile / compileAwakened), so a design here is exactly what ships.
//
// A skin is a palette (the weapon's P S T A G H keys) plus overrides for the grid's own literal inks.
// It never changes a grid: the silhouette, the grip and the reach are the weapon's, which is the rule
// that keeps skins out of gameplay (a player reads range off the shape).
//
//   node tools/cosmetic-sheet.mjs <out-dir>     writes <id>.png for every design, and index.json
import fs from 'node:fs';
import path from 'node:path';
import { writePng } from './png.mjs';
import { WEB, G, gridOf, paletteOf } from './roblox-grids.mjs';
const { compile, compileAwakened } = await import(`${WEB}/weaponArt.js`);

export const RARITIES = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic'];

// Series 1, "Forgeborn": weapon skins. `ink` overrides the grid's literal colours (see the ink
// tables in weaponArt.js; a letter not overridden keeps the weapon's own).
export const SKINS = [
  // OATHBLADE
  { id: 'sword_rustwood', weapon: 'Sword', name: 'Rustwood Blade', rarity: 'Common',
    palette: { primary: '#8A6A4A', secondary: '#5E4630', tertiary: '#2E2218', accent: '#B89470', glow: '#D9A066' },
    ink: { u: '#6A5A48', U: '#8E7A62', y: '#3E3226', g: '#E8C9A0' } },
  { id: 'sword_frostbite', weapon: 'Sword', name: 'Frostbite', rarity: 'Rare',
    palette: { primary: '#CFEFFF', secondary: '#6FB6E0', tertiary: '#2B5B80', accent: '#FFFFFF', glow: '#7FE6FF' },
    ink: { u: '#9FD8F0', U: '#E6FBFF', y: '#4A86A8', h: '#22384E', j: '#3E6A8C', g: '#DFFAFF' } },
  { id: 'sword_emberoath', weapon: 'Sword', name: 'Ember Oath', rarity: 'Epic',
    palette: { primary: '#3A2A2A', secondary: '#1E1414', tertiary: '#0E0A0A', accent: '#FFB04A', glow: '#FF6A1A' },
    ink: { u: '#C24A1A', U: '#FFD27A', y: '#6A2A10', h: '#2A1010', j: '#5A1E14', g: '#FFE0A0' } },
  { id: 'sword_starforged', weapon: 'Sword', name: 'Starforged', rarity: 'Legendary',
    palette: { primary: '#1E1A3A', secondary: '#3A2F6E', tertiary: '#0C0A1E', accent: '#FFE08A', glow: '#FFD24A' },
    ink: { u: '#FFD24A', U: '#FFF6C8', y: '#A8761E', h: '#2A2050', j: '#4A3A8A', g: '#FFF2B0' } },
  // TWINFANG
  { id: 'daggers_bonefang', weapon: 'Daggers', name: 'Bone Fang', rarity: 'Uncommon',
    palette: { primary: '#EDE4D0', secondary: '#8C7F68', tertiary: '#3E362A', accent: '#FFFFFF', glow: '#D8CBA8' },
    ink: { c: '#CFC2A0', C: '#FFF8E6', q: '#7A6A4E', e: '#B8AE98', j: '#5A4E3A' } },
  { id: 'daggers_neontwins', weapon: 'Daggers', name: 'Neon Twins', rarity: 'Rare',
    palette: { primary: '#2A2A40', secondary: '#14141E', tertiary: '#0A0A12', accent: '#FFFFFF', glow: '#3CFFB4' },
    ink: { c: '#FF3CD8', C: '#FFB0F0', q: '#7A1A6A', e: '#3CFFB4', j: '#2A2A40' } },
  { id: 'daggers_venomfang', weapon: 'Daggers', name: 'Venomfang', rarity: 'Epic',
    palette: { primary: '#B8E86A', secondary: '#3A5A1E', tertiary: '#1A2A0E', accent: '#F0FFD0', glow: '#9CFF3C' },
    ink: { c: '#7AE83C', C: '#DAFFB0', q: '#2E5A12', e: '#5A6A4A', j: '#2A3A1A' } },
  // GROUNDBREAKER
  { id: 'hammer_cobblestone', weapon: 'Hammer', name: 'Cobblestone', rarity: 'Common',
    palette: { primary: '#9A9488', secondary: '#5A5248', tertiary: '#2A2622', accent: '#C8C2B6', glow: '#C8B48A' },
    ink: { s: '#6E685E', I: '#3A3630' } },
  { id: 'hammer_thunderhead', weapon: 'Hammer', name: 'Thunderhead', rarity: 'Epic',
    palette: { primary: '#4A5A7A', secondary: '#2A3450', tertiary: '#141A2A', accent: '#E6F0FF', glow: '#7FD8FF' },
    ink: { R: '#BFE8FF', g: '#E6FBFF', s: '#3A4660', I: '#1A2236' } },
  // BATTLE AXE
  { id: 'axe_lumberjack', weapon: 'Axe', name: 'Lumberjack', rarity: 'Common',
    palette: { primary: '#A8AEB6', secondary: '#B4462E', tertiary: '#3A1A12', hilt: '#5A3A22', accent: '#E6EAF0', glow: '#FF7A4A' },
    ink: { r: '#2E2A26' } },
  { id: 'axe_glacier', weapon: 'Axe', name: 'Glacier Cleaver', rarity: 'Rare',
    palette: { primary: '#CFE8F5', secondary: '#5A7A90', tertiary: '#22384A', hilt: '#3A5468', accent: '#FFFFFF', glow: '#9FF0FF' },
    ink: { h: '#4A6478', d: '#22384A', e: '#FFFFFF', r: '#7FD8FF' } },
  // GRAVE BLOOM
  { id: 'scythe_harvestmoon', weapon: 'Scythe', name: 'Harvest Moon', rarity: 'Rare',
    palette: { primary: '#C8761E', secondary: '#F2B44A', tertiary: '#5A2A0A', accent: '#FFF0C8', glow: '#FFB43C' },
    ink: { b: '#6A4A2A', B: '#9A7048', n: '#3E2A16', g: '#FFF0C8' } },
  { id: 'scythe_reaperslantern', weapon: 'Scythe', name: "Reaper's Lantern", rarity: 'Legendary',
    palette: { primary: '#14231E', secondary: '#2E5A4A', tertiary: '#08100E', accent: '#C8FFE6', glow: '#3CFFA0' },
    ink: { b: '#2A2A2A', B: '#4A4A4A', n: '#141414', Q: '#0A1410', g: '#B4FFE0' } },
  // TWIN RIVETS
  { id: 'blasters_toy', weapon: 'Blasters', name: 'Toy Blasters', rarity: 'Uncommon',
    palette: { primary: '#FF7A1A', secondary: '#3CC84A', tertiary: '#1E5A24', accent: '#FFF0A0', glow: '#FFE03C' },
    ink: { k: '#14301A', n: '#FFFFFF', j: '#FFD24A' } },
  { id: 'blasters_chrome', weapon: 'Blasters', name: 'Chrome Rivets', rarity: 'Rare',
    palette: { primary: '#D8DEE6', secondary: '#8A94A6', tertiary: '#2A303C', accent: '#FFFFFF', glow: '#7FD8FF' },
    ink: { j: '#E6EAF0' } },
  // OVERDRIVE KNUCKLES
  { id: 'gauntlets_boxingreds', weapon: 'Gauntlets', name: 'Boxing Reds', rarity: 'Common',
    palette: { primary: '#D8322E', secondary: '#8A1A16', tertiary: '#3A0A08', accent: '#FFD8D0', glow: '#FFFFFF' },
    ink: { v: '#FFFFFF', k: '#5A0A08', i: '#F0F0F0' } },
  { id: 'gauntlets_magma', weapon: 'Gauntlets', name: 'Magma Fists', rarity: 'Epic',
    palette: { primary: '#2A2020', secondary: '#141010', tertiary: '#080606', accent: '#FFD27A', glow: '#FF6A1A' },
    ink: { v: '#FF8A2A', k: '#FF4A1A', i: '#5A4A40' } },
  // WARPIKE
  { id: 'pike_royalguard', weapon: 'Pike', name: 'Royal Guard', rarity: 'Rare',
    palette: { primary: '#E8C04A', secondary: '#B4322E', tertiary: '#4A1410', accent: '#FFF0C8', glow: '#FFD24A' },
    ink: { a: '#FFE08A', d: '#8A6A2A', j: '#5A1410', c: '#2E3A8A', k: '#4A5AC8', Y: '#FFFFFF' } },
  // LONGBOW
  { id: 'longbow_elmwood', weapon: 'Longbow', name: 'Elmwood', rarity: 'Common',
    palette: { primary: '#8A6A42', secondary: '#4A3420', tertiary: '#2A1E12', accent: '#D8C49A', glow: '#C8E07A' } },
  { id: 'longbow_sunfire', weapon: 'Longbow', name: 'Sunfire Bow', rarity: 'Epic',
    palette: { primary: '#FFB43C', secondary: '#C24A1A', tertiary: '#5A1A08', accent: '#FFF4C8', glow: '#FF6A1A' },
    ink: { a: '#FFF4C8', L: '#FFE08A', w: '#5A1A08' } },
  // STARBOUND CODEX
  { id: 'grimoire_necro', weapon: 'Grimoire', name: 'Necro Tome', rarity: 'Rare',
    palette: { primary: '#1E2A1E', secondary: '#4A6A3A', tertiary: '#0E140E', accent: '#D8FFC8', glow: '#7AFF6A' },
    ink: { W: '#C8D8B8', m: '#6A7A5A', p: '#8A9A7A' } },
  // SHIELD
  { id: 'shield_lion', weapon: 'Shield', name: 'Lionheart', rarity: 'Uncommon',
    palette: { primary: '#C8322E', secondary: '#E8C04A', tertiary: '#4A1410', accent: '#FFF0C8', glow: '#FFD24A' },
    ink: { b: '#E8C04A', B: '#FFF0A0', r: '#8A6A2A' } },
  // CHAIN FLAIL
  { id: 'flail_lantern', weapon: 'Flail', name: 'Spiked Lantern', rarity: 'Rare',
    palette: { primary: '#4A3A2A', secondary: '#2A1E14', tertiary: '#140E0A', accent: '#FFE6A0', glow: '#FFB43C' },
    ink: { o: '#5A4A3A', O: '#8A7A5A', k: '#FFE6A0', i: '#FFFFFF' } },
  // BULLWHIP
  { id: 'whip_thornvine', weapon: 'Whip', name: 'Thornvine', rarity: 'Uncommon',
    palette: { primary: '#3A7A2E', secondary: '#1E4A16', tertiary: '#0E2A0A', accent: '#C8F0A0', glow: '#9CFF5A', hilt: '#2A1A0E' },
    ink: { a: '#8AD85A', y: '#3A6A1E' } },
  // Roblox-only weapons
  { id: 'chakram_halo', weapon: 'Chakram', name: 'Golden Halos', rarity: 'Epic',
    palette: { primary: '#FFE08A', secondary: '#C89A2A', tertiary: '#5A3A0A', accent: '#FFFFFF', glow: '#FFF4C8' } },
  { id: 'boots_retro', weapon: 'RocketBoots', name: 'Retro Rockets', rarity: 'Rare',
    palette: { primary: '#E8E0D0', secondary: '#C8322E', tertiary: '#2A2A3A', accent: '#FFFFFF', glow: '#FFB43C' } },
  // Series 1 expansion: Candy, Frostforged, Neon Night, Rustwood and Void.
  // Every literal ink is recoloured too; grids and anchors are always the weapon's.
  { id: 'daggers_sugarshivs', weapon: 'Daggers', name: 'Sugar Shivs', rarity: 'Common',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { c: '#BBFFD7', C: '#FFF1D5', q: '#3F2854', e: '#FF8BBF', j: '#A64F70' } },
  { id: 'hammer_permafrost', weapon: 'Hammer', name: 'Permafrost', rarity: 'Uncommon',
    palette: { primary: '#B9E7F4', secondary: '#4F839E', tertiary: '#20354D', accent: '#F0FCFF', glow: '#7BF2E3', hilt: '#385D78' },
    ink: { s: '#4F839E', I: '#20354D', h: '#385D78', d: '#20354D', R: '#F0FCFF', g: '#EFFFD6' } },
  { id: 'hammer_jawbreaker', weapon: 'Hammer', name: 'Jawbreaker', rarity: 'Common',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { s: '#5AAEAC', I: '#3F2854', h: '#A64F70', d: '#3F2854', R: '#FFF1D5', g: '#EFFFD6' } },
  { id: 'axe_afterhours', weapon: 'Axe', name: 'Afterhours Hatchet', rarity: 'Uncommon',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: { h: '#396387', d: '#171C32', e: '#B5FFF5', r: '#FF59CC' } },
  { id: 'axe_riftcleaver', weapon: 'Axe', name: 'Rift Cleaver', rarity: 'Epic',
    palette: { primary: '#514581', secondary: '#303451', tertiary: '#171C30', accent: '#D5F8FF', glow: '#DE72FF', hilt: '#7362A5' },
    ink: { h: '#7362A5', d: '#171C30', e: '#D5F8FF', r: '#DE72FF' } },
  { id: 'scythe_sugarreaper', weapon: 'Scythe', name: 'Sugar Reaper', rarity: 'Common',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { b: '#A64F70', B: '#FFF1D5', n: '#5AAEAC', Q: '#3F2854', g: '#EFFFF7' } },
  { id: 'scythe_rimereaper', weapon: 'Scythe', name: 'Rime Reaper', rarity: 'Uncommon',
    palette: { primary: '#B9E7F4', secondary: '#4F839E', tertiary: '#20354D', accent: '#F0FCFF', glow: '#7BF2E3', hilt: '#385D78' },
    ink: { b: '#385D78', B: '#F0FCFF', n: '#4F839E', Q: '#20354D', g: '#EFFFF7' } },
  { id: 'blasters_bubblegum', weapon: 'Blasters', name: 'Bubblegum Blasters', rarity: 'Common',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { k: '#3F2854', n: '#FFF1D5', j: '#A64F70' } },
  { id: 'blasters_nightshift', weapon: 'Blasters', name: 'Nightshift', rarity: 'Epic',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: { k: '#171C32', n: '#B5FFF5', j: '#396387' } },
  { id: 'gauntlets_coldsnap', weapon: 'Gauntlets', name: 'Cold Snap', rarity: 'Uncommon',
    palette: { primary: '#B9E7F4', secondary: '#4F839E', tertiary: '#20354D', accent: '#F0FCFF', glow: '#7BF2E3', hilt: '#385D78' },
    ink: { v: '#7BF2E3', k: '#20354D', i: '#D6E9F2' } },
  { id: 'gauntlets_arcade', weapon: 'Gauntlets', name: 'Arcade Breakers', rarity: 'Rare',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: { v: '#FF59CC', k: '#171C32', i: '#9CA6D8' } },
  { id: 'pike_roadwarden', weapon: 'Pike', name: 'Roadwarden', rarity: 'Common',
    palette: { primary: '#AA8158', secondary: '#566751', tertiary: '#293B35', accent: '#E6D7AF', glow: '#D9B75A', hilt: '#674631' },
    ink: { a: '#AA8158', d: '#674631', j: '#566751', w: '#E6D7AF', c: '#566751', k: '#D9B75A', Y: '#FFE3A0' } },
  { id: 'pike_icebound', weapon: 'Pike', name: 'Icebound Standard', rarity: 'Uncommon',
    palette: { primary: '#B9E7F4', secondary: '#4F839E', tertiary: '#20354D', accent: '#F0FCFF', glow: '#7BF2E3', hilt: '#385D78' },
    ink: { a: '#B9E7F4', d: '#385D78', j: '#4F839E', w: '#F0FCFF', c: '#4F839E', k: '#7BF2E3', Y: '#FFE3A0' } },
  { id: 'pike_eventide', weapon: 'Pike', name: 'Eventide Sovereign', rarity: 'Mythic',
    palette: { primary: '#E3F8FA', secondary: '#51468B', tertiary: '#202140', accent: '#FFFFD9', glow: '#6EFFE3', hilt: '#A06DC7' },
    ink: { a: '#8771C9', d: '#46386F', j: '#51468B', w: '#F6FCFF', c: '#32BEBE', k: '#6EFFE3', Y: '#FFFFD9' } },
  { id: 'longbow_licorice', weapon: 'Longbow', name: 'Licorice Recurve', rarity: 'Uncommon',
    palette: { primary: '#653B61', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { a: '#FFF1D5', L: '#FF9AC5', w: '#365C5A' } },
  { id: 'longbow_eclipse', weapon: 'Longbow', name: 'Eclipse String', rarity: 'Legendary',
    palette: { primary: '#46365E', secondary: '#7F5E31', tertiary: '#21152E', accent: '#FFF1B2', glow: '#FFD568', hilt: '#624167' },
    ink: { a: '#FFF1B2', L: '#FFD568', w: '#624167' } },
  { id: 'grimoire_sugarspell', weapon: 'Grimoire', name: 'Sugarspell', rarity: 'Common',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { W: '#FFF1D5', w: '#FFFFFF', m: '#A64F70', p: '#5AAEAC' } },
  { id: 'grimoire_mossbound', weapon: 'Grimoire', name: 'Mossbound Ledger', rarity: 'Uncommon',
    palette: { primary: '#AA8158', secondary: '#566751', tertiary: '#293B35', accent: '#E6D7AF', glow: '#D9B75A', hilt: '#674631' },
    ink: { W: '#E6D7AF', w: '#FFFFFF', m: '#674631', p: '#566751' } },
  { id: 'grimoire_lastlight', weapon: 'Grimoire', name: 'Last Light Codex', rarity: 'Mythic',
    palette: { primary: '#BEEFF1', secondary: '#653E89', tertiary: '#21223F', accent: '#FFF1C6', glow: '#FF6BBE', hilt: '#3C6380' },
    ink: { W: '#FFF1C6', w: '#FFFFEA', m: '#392D68', p: '#837AAC' } },
  { id: 'shield_ironbark', weapon: 'Shield', name: 'Ironbark', rarity: 'Common',
    palette: { primary: '#AA8158', secondary: '#566751', tertiary: '#293B35', accent: '#E6D7AF', glow: '#D9B75A', hilt: '#674631' },
    ink: { b: '#674631', B: '#E6D7AF', r: '#798167', k: '#243031', y: '#D9B75A', z: '#293B35', w: '#FFFFFF' } },
  { id: 'shield_whiteout', weapon: 'Shield', name: 'Whiteout Bulwark', rarity: 'Uncommon',
    palette: { primary: '#B9E7F4', secondary: '#4F839E', tertiary: '#20354D', accent: '#F0FCFF', glow: '#7BF2E3', hilt: '#385D78' },
    ink: { b: '#385D78', B: '#F0FCFF', r: '#7397A8', k: '#283247', y: '#7BF2E3', z: '#20354D', w: '#FFFFFF' } },
  { id: 'shield_afterimage', weapon: 'Shield', name: 'Afterimage Aegis', rarity: 'Epic',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: { b: '#396387', B: '#B5FFF5', r: '#6D5987', k: '#30213D', y: '#FF59CC', z: '#171C32', w: '#FFFFFF' } },
  { id: 'flail_scrapyard', weapon: 'Flail', name: 'Scrapyard Wrecker', rarity: 'Common',
    palette: { primary: '#AA8158', secondary: '#566751', tertiary: '#293B35', accent: '#E6D7AF', glow: '#D9B75A', hilt: '#674631' },
    ink: { o: '#AA8158', O: '#E6D7AF', k: '#E6D7AF', i: '#FFFFFF', h: '#674631', d: '#293B35' } },
  { id: 'flail_gumball', weapon: 'Flail', name: 'Gumball Wrecker', rarity: 'Uncommon',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { o: '#FF8BBF', O: '#FFF1D5', k: '#FFF1D5', i: '#FFFFFF', h: '#A64F70', d: '#3F2854' } },
  { id: 'flail_orbitbreaker', weapon: 'Flail', name: 'Orbit Breaker', rarity: 'Rare',
    palette: { primary: '#514581', secondary: '#303451', tertiary: '#171C30', accent: '#D5F8FF', glow: '#DE72FF', hilt: '#7362A5' },
    ink: { o: '#514581', O: '#D5F8FF', k: '#D5F8FF', i: '#FFFFFF', h: '#7362A5', d: '#171C30' } },
  { id: 'whip_taffy', weapon: 'Whip', name: 'Taffy Snap', rarity: 'Common',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: { a: '#FFF1D5', y: '#5AAEAC' } },
  { id: 'whip_livewire', weapon: 'Whip', name: 'Livewire Lash', rarity: 'Uncommon',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: { a: '#B5FFF5', y: '#263356' } },
  { id: 'whip_riftbinder', weapon: 'Whip', name: 'Riftbinder', rarity: 'Epic',
    palette: { primary: '#514581', secondary: '#303451', tertiary: '#171C30', accent: '#D5F8FF', glow: '#DE72FF', hilt: '#7362A5' },
    ink: { a: '#D5F8FF', y: '#303451' } },
  { id: 'chakram_peppermint', weapon: 'Chakram', name: 'Peppermint Rings', rarity: 'Common',
    palette: { primary: '#F1F6DE', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#EB668D', hilt: '#A64F70' },
    ink: {  } },
  { id: 'chakram_coldorbit', weapon: 'Chakram', name: 'Cold Orbit', rarity: 'Uncommon',
    palette: { primary: '#B9E7F4', secondary: '#4F839E', tertiary: '#20354D', accent: '#F0FCFF', glow: '#7BF2E3', hilt: '#385D78' },
    ink: {  } },
  { id: 'chakram_discotheque', weapon: 'Chakram', name: 'Discotheque', rarity: 'Rare',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: {  } },
  { id: 'boots_foundry', weapon: 'RocketBoots', name: 'Foundry Runners', rarity: 'Common',
    palette: { primary: '#AA8158', secondary: '#566751', tertiary: '#293B35', accent: '#E6D7AF', glow: '#D9B75A', hilt: '#674631' },
    ink: {  } },
  { id: 'boots_sugarrush', weapon: 'RocketBoots', name: 'Sugar Rush', rarity: 'Uncommon',
    palette: { primary: '#FF8BBF', secondary: '#5AAEAC', tertiary: '#3F2854', accent: '#FFF1D5', glow: '#BBFFD7', hilt: '#A64F70' },
    ink: {  } },
  { id: 'boots_nightdrive', weapon: 'RocketBoots', name: 'Nightdrive', rarity: 'Rare',
    palette: { primary: '#59449A', secondary: '#263356', tertiary: '#171C32', accent: '#B5FFF5', glow: '#FF59CC', hilt: '#396387' },
    ink: {  } },
];

// Crates and the key, drawn in the same pixel language as the weapons (the compiler outlines them).
export const PROPS = [
  { id: 'crate_scrap', name: 'Scrap Crate', palette: { primary: '#8A6A42', secondary: '#5A4028', tertiary: '#2E2014', accent: '#B8BEC8', glow: '#E8C88A', hilt: '#6E7684' },
    grid: G(0, 0, [
      '..TTTTTTTTTTTTTT..',
      '.TSSSSSSSSSSSSSST.',
      'TSPPPPPPPPPPPPPPST',
      'TSPAAPPPPPPPPAAPST',
      'TSPAPPPPPPPPPPAPST',
      'TTTTTTTTTTTTTTTTTT',
      'TSPPPPPPHHPPPPPPST',
      'TSPPPPPHGGHPPPPPST',
      'TSPPPPPHGGHPPPPPST',
      'TSPPPPPPHHPPPPPPST',
      'TSPAPPPPPPPPPPAPST',
      'TSPAAPPPPPPPPAAPST',
      'TSSSSSSSSSSSSSSSST',
      'TTTTTTTTTTTTTTTTTT',
    ]) },
  { id: 'crate_forge', name: 'Forge Crate', palette: { primary: '#3A3F4A', secondary: '#22262E', tertiary: '#121418', accent: '#FFB43C', glow: '#FFF0C8', hilt: '#C8761E' },
    grid: G(0, 0, [
      '..TTTTTTTTTTTTTT..',
      '.TSSSSSSSSSSSSSST.',
      'TSPPAPPPPPPPPAPPST',
      'TSPAPPPPPPPPPPAPST',
      'TSAPPPPPPPPPPPPAST',
      'TTAAAAAAAAAAAAAATT',
      'TSPPPPPPHHPPPPPPST',
      'TSPPPPPHGGHPPPPPST',
      'TSAPPPPHGGHPPPPAST',
      'TSPAPPPPHHPPPPAPST',
      'TSPPAPPPPPPPPAPPST',
      'TSPPPAPPPPPPAPPPST',
      'TSSSSSSSSSSSSSSSST',
      'TTTTTTTTTTTTTTTTTT',
    ]) },
  { id: 'key_forge', name: 'Forge Key', palette: { primary: '#FFB43C', secondary: '#C8761E', tertiary: '#5A2A0A', accent: '#FFF0C8', glow: '#FFF0C8' },
    grid: G(0, 0, [
      '..SSSS..........',
      '.SPAAPS.........',
      'SPA..APSSSSSSSSS',
      'SPA..APPPPPPPPPS',
      'SPP..PPSSSPSSPSS',
      '.SPPPPS...S..S..',
      '..SSSS..........',
    ]) },
];

// Paint compiled rectangles (studs, 8 cells a stud, rows growing down) at `px` screen pixels a cell.
function render(file, rects, px = 6, pad = 2, bg = [27, 36, 48]) {
  const xs = rects.flatMap((r) => [r[0], r[0] + r[2]]), ys = rects.flatMap((r) => [r[1], r[1] + r[3]]);
  const x0 = Math.min(...xs), y0 = Math.min(...ys);
  const cols = Math.round((Math.max(...xs) - x0) * 8) + pad * 2, rows = Math.round((Math.max(...ys) - y0) * 8) + pad * 2;
  const W = cols * px, H = rows * px;
  const img = Array.from({ length: W * H }, () => [...bg]);
  const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  for (const [x, y, w, h, col, a = 1] of rects) {
    const c = hex(col);
    const cx = Math.round((x - x0) * 8) + pad, cy = Math.round((y - y0) * 8) + pad;
    for (let yy = cy * px; yy < (cy + Math.round(h * 8)) * px; yy++) for (let xx = cx * px; xx < (cx + Math.round(w * 8)) * px; xx++) {
      const p = img[yy * W + xx];
      for (let k = 0; k < 3; k++) p[k] = Math.round(p[k] * (1 - a) + c[k] * a);
    }
  }
  writePng(file, W, H, (x, y) => img[y * W + x]);
  return { w: W, h: H };
}

export function skinGrid(skin) {
  const base = gridOf(skin.weapon);
  return { ...base, ink: { ...base.ink, ...(skin.ink || {}) } };
}

if (process.argv[1] && import.meta.url.endsWith(path.basename(process.argv[1]))) {
  const out = process.argv[2] || '/tmp/cosmetics';
  fs.mkdirSync(out, { recursive: true });
  const index = { skins: [], props: [], bases: [] };
  for (const w of [...new Set(SKINS.map((s) => s.weapon))]) {
    const size = render(path.join(out, `base_${w}.png`), compile(gridOf(w), paletteOf(w)));
    index.bases.push({ weapon: w, file: `base_${w}.png`, ...size });
  }
  for (const s of SKINS) {
    const g = skinGrid(s);
    const size = render(path.join(out, `${s.id}.png`), compile(g, s.palette));
    const aw = render(path.join(out, `${s.id}_awake.png`), compileAwakened(g, s.palette));
    index.skins.push({ id: s.id, weapon: s.weapon, name: s.name, rarity: s.rarity, file: `${s.id}.png`, awake: `${s.id}_awake.png`, ...size, awakeW: aw.w, awakeH: aw.h });
  }
  for (const p of PROPS) {
    const size = render(path.join(out, `${p.id}.png`), compile(p.grid, p.palette), 8);
    index.props.push({ id: p.id, name: p.name, file: `${p.id}.png`, ...size });
  }
  fs.writeFileSync(path.join(out, 'index.json'), JSON.stringify(index, null, 1));
  console.log(`${index.skins.length} skins, ${index.bases.length} bases, ${index.props.length} props -> ${out}`);
}
