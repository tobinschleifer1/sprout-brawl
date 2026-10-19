"""Independent faults against direct phase-four properties, restoring even on failure.

Run from roblox/: python3 tools/mutate-movement.py
Every fault must reach its expected assertion, not merely crash or fail to compile.
Do not run concurrently with checks, renders, or other edits to the client modules.
"""
from pathlib import Path
import subprocess

# name, module, original, fault, expected assertion
movement = [
    ('shared hip socket', 'Movement', 'rootX = lane * r * 0.30', 'rootX = 0', 'gait hips collapse to one socket'),
    ('sliding support', 'Movement', 'x = x0 - S * c', 'x = x0 - S * c * 0.9', 'support foot slides'),
    ('feet below floor', 'Movement', 'y = y - m.bob,', 'y = y - m.bob - 0.1,', 'foot penetrates ground'),
    ('stretching legs', 'Movement', 'len = G.leg,', 'len = nil,', 'gait leg is'),
    ('backward knees', 'Posture', 'Posture.limb(rx, ry, target.ex, target.ey, bend, -1)', 'Posture.limb(rx, ry, target.ex, target.ey, bend, 1)', 'gait knee bends backwards'),
    ('no passing clearance', 'Movement', 'h * (0.087 + 0.07 * run)', 'h * (0.01 + 0.07 * run)', 'passing feet collide'),
    ('walk identical to run', 'Movement', 'h * (0.087 + 0.07 * run)', 'h * 0.157', 'same swing lift'),
    ('no heel peel', 'Movement', 'y = heelMax * smooth((c - DP * 0.6) / (DP * 0.4))', 'y = 0', 'gait leg is'),
    ('early heel peel', 'Movement', 'y = heelMax * smooth((c - DP * 0.6) / (DP * 0.4))', 'y = heelMax * smooth((c - DP * 0.2) / (DP * 0.8))', 'flat-footed'),
    ('flat bounce', 'Movement', 'k * (-0.10 - 0.125 * math.cos', 'k * (-0.10 - 0.03 * math.cos', 'a run bounces'),
    ('bounce off the step', 'Movement', 'math.cos(2 * math.pi * (q - 0.28))', 'math.cos(2 * math.pi * (q - 0.78))', "a run's lowest point"),
    ('walk peaks in flight', 'Movement', 'math.cos(2 * math.pi * (q - passing))', 'math.cos(2 * math.pi * (q - passing - 0.5))', "a walk's highest point"),
    ('crouched walk', 'Movement', 'k * (-0.03 + 0.035', 'k * (-0.09 + 0.035', 'contact: the leading leg is bent'),
    ('bent walk passing', 'Movement', 'k * (-0.03 + 0.035', 'k * (-0.065 + 0.005', "a walk's planted leg is bent"),
    ('arm follows leg', 'Movement', 'm.back = -math.clamp', 'm.back = math.clamp', 'free arm does not oppose'),
    ('torso on another clock', 'Posture', 'motion.phase or s.frameCount * 0.38', 's.frameCount * 0.38', 'hips use a different stride clock'),
    ('frozen torso', 'Posture', 'motion.phase or s.frameCount * 0.38', '0', 'hips never exchange weight'),
    ('load lifts planted feet', 'Movement', 'plant(0.65, 12 + 50 * load)', 'feet(-r, 0.1, 12, r, 0.1, 12)', 'jumpsquat planted foot leaves floor'),
    ('landing feet follow squash', 'Movement', 'plant(0.65, 10 + 65 * load)', 'feet(-r, ch.bob, 10, r, ch.bob, 10)', 'landing planted foot leaves floor'),
    ('landing feet drift', 'Movement', 'plant(0.65, 10 + 65 * load)', 'plant(0.65 + sf * 0.1, 10 + 65 * load)', 'landing planted foot shifts sideways'),
    ('rise without trail', 'Movement', '0.10 + 0.08 * rise', '0.02 + 0.01 * rise', 'rise has no trailing leg'),
    ('flat apex', 'Movement', '0.12 * hang', '0.0 * hang', 'apex never gathers'),
    ('fall never reaches', 'Movement', '0.025 * rise + 0.12 * hang', '0.025 * rise + 0.12', 'rise has no trailing leg'),
    ('fast fall ignored', 'Movement', 'if s.fastFalling then', 'if false then', 'fast fall does not commit'),
    ('shield arm dropped', 'Movement', '1.25 * brace', '0 * brace', 'shield has no brace'),
    ('dodge stays tall', 'Movement', '-h * 0.045 * duck', '0 * duck', 'spot dodge does not duck'),
    ('impact ignores facing', 'Movement', 'else 1) * s.facing', 'else 1) * 1', 'impact ignores launch direction or facing'),
    ('untucked roll', 'Movement', 'h * 0.20 * tuck', '0 * tuck', 'rolling body fails to tuck'),
    ('splayed roll arm', 'Movement', '0.30 - 0.10 * tuck', '0.40', 'rolling support arm stays splayed'),
    ('never gets up', 'Movement', 'ch.rigRotZ * (1 - getup)', 'ch.rigRotZ', 'knockdown never gets up'),
    ('getup foot sinks', 'Movement', '-math.sin(angle) * x - math.cos(angle) * m.yOff - ch.bob', '-math.sin(angle) * x - math.cos(angle) * m.yOff - ch.bob + 0.1', 'getup foot goes through floor'),
    ('getup foot slides', 'Movement', 'math.cos(angle) * x - math.sin(angle) * m.yOff', 'math.cos(angle) * x - math.sin(angle) * m.yOff + 0.1', 'getup foot goes through floor'),
    ('ledge knee dropped', 'Movement', 'r * 0.65, h * 0.17, 76', 'r * 0.65, 0, 10', 'ledge loses overhead reach or climbing knee'),
    ('climb never plants', 'Movement', 'h * 0.22 * (1 - climb)', 'h * 0.22', 'ledge getup never plants'),
    ('climb knee lowers early', 'Movement', 'smooth((sf - 3) / (onStage - 3))', 'smooth(sf / onStage)', 'ledge getup never plants'),
    ('late platform contact', 'Movement', 'then 8 else 10', 'then 14 else 16', 'ledge action feet miss platform arrival'),
    ('overwritten attack', 'Movement', 'state == "run" and s.onGround', '(state == "run" and s.onGround) or state == "attack"', 'movement overwrote authored action'),
    ('snapshot written', 'Movement', 'local m: any =', 's.vx = 0\n\tlocal m: any =', 'readonly table'),
    ('channels written', 'Movement', 'local m: any =', 'ch.bob = 0\n\tlocal m: any =', 'readonly table'),
]
posture = [
    ('second weapon off its hand', 'Posture', 'bx, by, backBend = offX, offY, math.rad(dual.off.bend)', 'bx, by, backBend = offX + 0.1, offY, math.rad(dual.off.bend)', 'other hand/second weapon x'),
    ('back strike from the wrong hand', 'Posture', 'bx, by, backBend = gx, gy, frontBend', 'bx, by, backBend = offX, offY, frontBend', 'hand/grip x'),
    ('far leg on top', 'KitBody', 'for _, i in { 2, 1 } do', 'for _, i in { 1, 2 } do', 'near leg is not drawn over'),
    ('unlit near leg', 'PostureArt', 'PostureArt.NEAR_LIGHT = 0.14', 'PostureArt.NEAR_LIGHT = 0', 'is not lit'),
    ('lit outline', 'PostureArt', 'if hex == Compose.OUTLINE or type(hex) ~= "string" then', 'if type(hex) ~= "string" then', 'outline or far shade changed'),
]
overlap = [
    ('second dagger leads', 'Fighter2D', 'return lagOf(k, s, char, was, wrap(before.off.angle - off.angle))', 'return lagOf(k, s, char, was, wrap(off.angle - before.off.angle))', 'led its hand'),
    ('blade leads', 'Fighter2D', 'then 0 else k * turn', 'then 0 else -k * turn', 'the blade led it'),
    ('cut drags', 'Fighter2D', 'if math.abs(turn) > SNAP then 0', 'if false then 0', 'a cut between poses'),
    ('unclamped', 'Fighter2D', 'return math.clamp(lag, -MAX_LAG, MAX_LAG)', 'return lag * 2', 'past its limit'),
    ('never settles', 'Fighter2D', 'then 0 else k * turn', 'then 0 else k * turn - 0.02', 'still moving'),
    ('bounce carries the tip', 'Fighter2D', 'lag -= k * 0.9 *', 'lag += k * 0.9 *', 'and the blade tip'),
    ('drawn as posed', 'Fighter2D', 'drawn.angle += lag', 'drawn.angle += 0', 'the blade is drawn at'),
    ('ultimate lags', 'Fighter2D', 'if not k or wpose.hide or (move and move.id == "Ultimate") then return 0 end', 'if not k or wpose.hide then return 0 end', 'frozen frame lags'),
    ('every weapon lags', 'Fighter2D', 'local k = Fighter2D.OVERLAP[if char.weapon then char.weapon.id else ""]\n\t-- an ultimate', 'local k = 0.4\n\t-- an ultimate', 'is not listed, and lags'),
    ('every pair lags', 'Fighter2D', 'local k = Fighter2D.OVERLAP[if char.weapon then char.weapon.id else ""]\n\tif not k or not off', 'local k = 0.4\n\tif not k or not off', 'the second gauntlet trails'),
]
dual = [
    ('daggers in one hand', 'DualWield', 'DualWield.PAIRED = { Daggers = true,', 'DualWield.PAIRED = { Daggers = false,', 'one in each hand'),
    ('pair picture per hand', 'Weapons2D', 'if single and single[base] then return single[base] end', '', "draws the pair's picture"),
    ('jab, jab, jab', 'DualWield', 'LightNeutral1 = "front", LightNeutral2 = "back"', 'LightNeutral1 = "front", LightNeutral2 = "front"', 'front, back, both'),
    ('table ignored', 'DualWield', 'local striker = if attacking then (STRIKE[move.id] or "front") else "front"', 'local striker = "front"', 'struck with front, not the'),
    ('no chamber', 'DualWield', 'arm = lerp(g.arm, c.arm, k)', 'arm = g.arm', 'did not chamber'),
    ('no twist', 'Posture', '-r * 0.65 + DualWield.TWIST.back * r * twist', '-r * 0.65', 'did not twist'),
    ('twist on every strike', 'DualWield', 'local twist = if striker == "back" then k else 0', 'local twist = k', 'the torso twisted for a'),
    ('twist never eases', 'DualWield', '* (1 - smooth((mf - (total - 6)) / 6))', '', 'does not ease out'),
    ('both hands apart', 'DualWield', 'x = lerp(gx, hx + BOTH.dx * r, k)', 'x = gx', 'holds the second weapon'),
    ('rings ignored', 'DualWield', 'units = math.clamp(s.rings or 2, 0, 2)', 'units = 2', 'ring'),
    ('rear weapon never drawn', 'Fighter2D', 'end, if dual and dual.off and dual.off.hand == "back" then drawOff else nil)', 'end, nil)', 'one in each hand'),
    ('singles split', 'Fighter2D', 'local unitId = if dual and wid then wid .. ":one" else wid', 'local unitId = if wid then wid .. ":one" else wid', 'is drawn as a pair'),
]
kicks = [
    ('punching boots', 'Posture', 'local kick = Kicks.For(s, char, move, ch.bob)', 'local kick = nil', 'the boots are not kicking'),
    ('late strike', 'Kicks', 'elseif fa <= b then', 'elseif fa <= b and fa > a then', 'late: its box is live'),
    ('link frames ignored', 'Kicks', 'return (s.moveFrame or 0) + (move.startup - eff)', 'return (s.moveFrame or 0)', 'the leg and its box disagree'),
    ('kick off its line', 'Kicks', 'return hx + dx / d * reach, hy + dy / d * reach', 'return hx + dx / d * reach, hy + dy / d * reach * 0.5', 'does not strike along'),
    ('stretched kick', 'Kicks', 'local reach = math.min(L * 0.995, d)', 'local reach = math.min(L * 1.2, d)', 'long, not'),
    ('standing foot slides', 'Kicks', '-bob }, { r * 0.30 + WIDTH, -bob } }', '-bob }, { r * 0.30 + WIDTH * (1 - commit), -bob } }', 'standing foot slid'),
    ('no chamber', 'Kicks', 'return hx + ux * 0.30 * L, hy - L * 0.45 + math.max(0, uy) * L * 0.30', 'return hx + ux * 0.5 * L, hy - L * 0.85', 'chambered'),
    ('no axe lift', 'Kicks', 'if style.axe then return hx + 0.25 * L, hy + 0.85 * L end', '', 'raised overhead'),
    ('never sets down', 'Kicks', 'return lerp(cx, sx, k), lerp(cy, sy, k), ux, uy, false', 'return cx, cy, ux, uy, false', 'never sets down'),
    ('punching hands', 'Posture', 'if Kicks.guards(char, s) then', 'if false then', 'punches'),
    ('no lean', 'Kicks', 'lean = (style.lean or 0) * commit', 'lean = 0', 'lean the torso back'),
    ('no drop', 'Kicks', '(style.drop or 0) * L * commit', '0', 'drop the hips'),
    ('no ignition', 'Kicks', 'ignite = (move.fuelCost or 0) > 0 and fa >= a and fa <= a + 1', 'ignite = false', 'not doubled'),
    ('ignition never ends', 'Kicks', 'ignite = (move.fuelCost or 0) > 0 and fa >= a and fa <= a + 1', 'ignite = (move.fuelCost or 0) > 0', 'stays doubled'),
    ('short blast', 'Kicks', 'out.reach[i] = math.max(0, (target[1] - x) * ux + (target[2] - y) * uy + far)', 'out.reach[i] = 0.3', 'short of its box'),
    ('plain hits', 'FxPlayer', 'RocketBoots = "kick", -- (Roblox only)', '', 'burst in fire'),
    ('one-legged split', 'Kicks', 'kicking[2] = { target[1] - half, target[2] }', 'kicking[2] = nil', 'both feet'),
    ('one-legged redline', 'Kicks', 'local REDLINE: { any } = { 1, 2, "both" }', 'local REDLINE: { any } = { 1, 1, "both" }', 'reverse kick'),
    ('strike outlasts its box', 'Kicks', 'elseif fa <= b then', 'elseif fa <= b + 1 then', 'with no live box'),
]
loot = [
    ('uneven shares', 'shared/Loot', 'percent = pct * 100 / total / #ids', 'percent = pct * 100 / total / (#ids + 1)', 'sum to'),
    ('roll off its list', 'shared/Loot', 'local at = rand() * 100\n\tlocal pick', 'local at = rand() * 90\n\tlocal pick', 'times in'),
    ('guarantee one late', 'shared/Loot', 'if crate.guarantee and (count or 0) + 1 >= crate.guarantee.at then', 'if crate.guarantee and (count or 0) + 1 > crate.guarantee.at then', 'ruled out'),
    ('guarantee never resets', 'shared/Loot', 'then next = 0 end', 'then next = count + 1 end', 'reset'),
    ('drops off their table', 'shared/Loot', 'at -= d.chance', 'at -= d.chance * 0.9', 'times in'),
    ('meter never reaches 5', 'shared/Loot', 'lo + math.floor(rand() * (hi - lo + 1))', 'lo + math.floor(rand() * (hi - lo))', 'meter'),
    ('crate item in no crate', 'shared/Cosmetics', 'if t.source == "crate" then t.crates = t.crates or cratesFor(t.rarity) end', '', 'in no crate'),
    ('mythic in scrap', 'shared/Cosmetics', 'if rarity == "Mythic" then return FORGE end', 'if rarity == "Mythic" then return BOTH end', 'scrap never gives'),
    ('mastery items craftable', 'shared/Loot', 'if not item or item.source ~= "crate" then return nil end', 'if not item then return nil end', 'can be crafted'),
    ('odds rounded too far', 'shared/Loot', 'decimals = k + 4', 'decimals = k + 3', '0.03571%'),
    ('an item hidden', 'shared/Loot', 'for _, id in ids do\n\t\t\t\ttable.insert(out', 'for i, id in ids do\n\t\t\t\tif i == 1 then continue end\n\t\t\t\ttable.insert(out', 'sum to'),
]
cosmetics = [
    ('skins ignored', 'Weapons2D', 'if worn and worn.weapon == base then', 'if false then', "the skin's colours"),
    ('skin on any weapon', 'Weapons2D', 'if worn and worn.weapon == base then', 'if worn then', "another weapon"),
    ('pair unit unskinned', 'Weapons2D', 'local form = if one then (if awake then worn.singleAwakened else worn.single) else nil', 'local form = nil', 'one skinned dagger'),
    ('trail ignores skin', 'Fighter2D', 'local wpal = Weapons2D.skinPalette(skin) or char.weaponPalette or pal', 'local wpal = char.weaponPalette or pal', 'glow and trail'),
    ('unit id unskinned', 'Fighter2D', 'if unitId and skin then unitId ..= "@" .. skin end', '', 'a skinned sword drew'),
    ('worn trail dropped', 'Fighter2D', 'wpose.trail, wpose.scale, worn and worn.trail)', 'wpose.trail, wpose.scale)', 'worn trail is not drawn'),
    ('trail colours ignored', 'Weapons2D', 'elseif colours then Canvas2D.hex(colours[i % #colours + 1], glow) else glow', 'else glow', "worn trail's colour"),
    ('hit style ignored', 'FxPlayer', 'local style = worn and FxPlayer.HIT_STYLES[worn]', 'local style = nil', "own hit"),
    ('hit ramp ignored', 'FxPlayer', 'if it and it.ramp then glow = it.ramp end', '', 'did not recolour'),
    ('ko effects ignored', 'FxPlayer', 'if not style then return false end\n\t\tstyle(P, e.x or 0, e.y or 0)', 'if true then return false end\n\t\tstyle(P, e.x or 0, e.y or 0)', 'draws no KO'),
    ('ko off the line', 'FxPlayer', 'style(P, e.x or 0, e.y or 0)', 'style(P, (e.x or 0) + 20, e.y or 0)', 'away from the blast line'),
    ('unowned worn', 'shared/Inventory', 'if not inv.owned[id] then equipped.skins[weapon] = nil end', '', 'an unowned item is worn'),
    ('skin on wrong weapon', 'shared/Inventory', 'if it and it.weapon == weapon then out.skins[weapon] = id end', 'if it then out.skins[weapon] = id end', 'another weapon'),
    ('equip unowned', 'shared/Inventory', 'if not owns(id) then return false, "not owned" end', '', 'unowned item was equipped'),
    ('live owns all', 'server/Locker', 'if self.studio then return Cosmetics.get(id) ~= nil end', 'if true then return Cosmetics.get(id) ~= nil end', 'live server owns everything'),
    ('studio saves', 'server/Locker', 'if ok and not self.studio then', 'if ok then', 'session-only'),
    ('no showcase', 'server/Locker', 'return Inventory.cleanLoadout(Locker.SHOWCASE)', 'return out', 'showcase'),
    ('three-shell firework', 'FxPlayer', 'add(P, "star", x - 1.5, y + 2, 3, 0.3, "gold", { seed = 0, delay = 0.24 })', 'add(P, "burst", x - 2.2, y + 2.4, 4.5, 0.45, "volt", { seed = 0, delay = 0.2 })\n\t\tadd(P, "star", x - 1.5, y + 2, 3, 0.3, "gold", { seed = 0, delay = 0.24 })', 'ko_firework builds'),
    ('bots alike', 'server/Locker', 'hit = BOT_HITS[(i - 1) % #BOT_HITS + 1]', 'hit = BOT_HITS[1]', 'same effects'),
]
economy = [
    ('drop a match early', 'server/Economy', 'if inv.meter <= 0 then', 'if inv.meter <= 1 then', 'still to go'),
    ('Training counts', 'server/Economy', '\tif results.mode == "Training" then return false end\n', '', 'Training counted'),
    ('short matches count', 'server/Economy', 'frames < Economy.QUALIFY_SECONDS * 60 then return false end', 'frames < 0 then return false end', 'match counted'),
    ('hitless matches count', 'server/Economy', 'return (row.damage or 0) > 0 or (row.taken or 0) > 0', 'return true', 'without a hit'),
    ('no hourly cap', 'server/Economy', 'if #times >= Economy.HOURLY_CAP then return { counted = false, capped = true, left = inv.meter } end', '', 'thirteenth'),
    ('paid key first', 'server/Economy', 'paid = k.earned < 1', 'paid = k.paid >= 1', 'paid key was spent'),
    ('paid not marked', 'server/Economy', 'local uid, why = self:_grant(inv, id, paid, "crate")', 'local uid, why = self:_grant(inv, id, false, "crate")', 'not marked paid'),
    # ('spent before the serial' retired 2026-10-18: requests now run on a private copy of the inventory
    # that a failure discards (AvatarStore.inventoryTransaction), so a spend before the failure cannot
    # leak; tests/economy-security breaks the transaction itself.)
    ('guarantee not saved', 'server/Economy', 'track[crateId] = nextPity', '', 'guarantee'),
    ('free crafting', 'server/Economy', 'inv.sparks -= cost', '', 'did not cost'),
    ('salvage keeps it in existence', 'server/Economy', 'if ok then self.mint:destroy(result.id) end', '', 'still exists'),
    ('dropped item lost', 'server/Economy', '-- the vault could not be reached: the drop is a crate instead, never lost\n\t\tinv.crates[d.crate] = math.min(Inventory.MAX_COUNT, inv.crates[d.crate] + 1)', '-- lost', 'lost when the vault'),
    ('serials reused', 'server/Mint', 'return result.reserved - reserve + 1', 'return math.max(1, result.reserved - reserve - 5)', 'handed out twice'),
    ('no blocks', 'server/Mint', 'local size = Mint.FIRST_BLOCK', 'local size = 1', 'not reserving in blocks'),
    ('blocks never grow', 'server/Mint', 'size = math.min(Mint.MAX_BLOCK, b.size * 2)', 'size = b.size', 'did not grow'),
    ('stored owned trusted', 'shared/Inventory', '\treindex(inv)\n\tlocal equipped', '\treindex(inv)\n\tif type(src.owned) == "table" then for k, v in src.owned do if v == true then inv.owned[k] = true end end end\n\tlocal equipped', 'stored owned index was trusted'),
    ('no migration', 'shared/Inventory', 'elseif type(src.owned) == "table" then', 'elseif false then', 'did not migrate'),
    ('worn after removal', 'shared/Inventory', 'if not inv.owned[inst.i] then', 'if false then', 'left it worn'),
    ('uid collision', 'shared/Inventory', 'if num and num >= seq and num < Inventory.MAX_INTEGER then seq = num + 1 end', '', 'collide'),
    ('paid opening on the earned count', 'server/Economy', 'local track = if paid then inv.paidPity else inv.pity', 'local track = inv.pity', 'from a paid key'),
    ('CPU counts whole', 'server/Economy', '(if results.cpu then Economy.CPU_STEP else 1)', '1', 'CPU match moved'),
    ('first win every win', 'server/Economy', 'if Economy.won(results, row) and inv.firstWin ~= day then', 'if Economy.won(results, row) then', 'second win'),
    ('VIP Sparks ignored', 'server/Economy', 'local amount = math.floor(d.amount * (if vip then 1 + Economy.VIP_SPARKS else 1))', 'local amount = d.amount', 'VIP Spark drop'),
    ('banner without serial', 'DropBanner', 'local serial = if type(d.serial) == "number" and d.serial > 0 then `  #{d.serial}` else ""', 'local serial = ""', 'Starforged'),
]
lockerui = [
    ('cards in any order', 'LockerScreen', 'table.sort(out, byRarityThenName)\n\treturn out\nend\n\n-- The crate cards.', 'return out\nend\n\n-- The crate cards.', 'rarest is not first'),
    ('highest serial shown', 'LockerScreen', 'return (a.serial or 0) < (b.serial or 0)', 'return (a.serial or 0) > (b.serial or 0)', 'serial'),
    ('worn ignored', 'LockerScreen', 'worn = worn(locker and locker.wearing, it),', 'worn = false,', 'worn'),
    ('keyless forge offered', 'LockerScreen', 'canOpen = have > 0 and (c.key == nil or keys > 0),', 'canOpen = have > 0,', 'needs a key'),
    ('odds not Loot', 'LockerScreen', 'value = Loot.format(o.percent), rarity = rarity, id = o.id', 'value = Loot.format(o.percent * 1.01), rarity = rarity, id = o.id', 'not listed at its odds'),
    ('guaranteed view ignored', 'LockerScreen', 'local list = Loot.odds(crateId, if guaranteed then c.guarantee.at - 1 else pity)', 'local list = Loot.odds(crateId, pity)', 'odds lines for'),
    ('reel misses', 'LockerScreen', 'out[i] = if i == LockerScreen.REEL.win then resultId else', 'out[i] = if false then resultId else', 'does not stop on the result'),
    ('one-press spending', 'LockerScreen', 'if self.confirm and self.confirm.key == key and t - self.confirm.at <= LockerScreen.CONFIRM_SECONDS then', 'if true then', 'one press salvaged'),
    ('confirmation never expires', 'LockerScreen', 'self.confirm.key == key and t - self.confirm.at <= LockerScreen.CONFIRM_SECONDS then', 'self.confirm.key == key then', 'long after'),
    ('salvage the lowest serial', 'LockerScreen', 'for i = #list, 1, -1 do table.insert(u, list[i].uid) end', 'for i = 1, #list do table.insert(u, list[i].uid) end', 'salvage order'),
    ('skin taken off by slot', 'LockerScreen', 'if m.type == "weapon_skin" then msg.weapon = m.weapon else msg.slot = Inventory.SLOTS[m.type] end', 'msg.slot = Inventory.SLOTS[m.type]', 'off its weapon'),
    ('craft over the price', 'LockerScreen', 'c.primary.Position = UDim2.new(0, 6, 1, -34)\n\t\tc.primary.Text = "CRAFT"', 'c.primary.Text = "CRAFT"', 'lies under its'),
    ('workshop cells short', 'LockerScreen', 'grid(self.workshopBody, Vector2.new(168, 200))', 'grid(self.workshopBody, Vector2.new(168, 150))', 'lies under its'),
    ('double opening', 'LockerScreen', 'if self.pending then return end\n\tlocal m', 'local m', 'while one was pending'),
    ('keyless opening sent', 'LockerScreen', 'if m.key and m.keys < 1 then', 'if false then', 'keyless Forge Crate'),
    ('result unnamed', 'LockerScreen', 'o.result.Text = `{it.rarity}: {it.name}`', 'o.result.Text = it.name', 'land on the result'),
    ('refusal stays open', 'LockerScreen', 'if self.pending then self:closeOpening() end', '', 'stayed open'),
    ('unaffordable crafting', 'LockerScreen', 'if not m.affordable then self:say', 'if false then self:say', 'unaffordable craft'),
    ('no serial in result', 'LockerScreen', 'local serial = if res.serial and res.serial > 0 then `#{res.serial}` else ""', 'local serial = ""', 'lacks its serial'),
]
shop = [
    ('featured differs by server', 'server/Shop', 'local s = (day * 7919 + 104729) % 2147483647', 'local s = (day * 7919 + math.floor(os.clock() * 1000003)) % 2147483647', 'disagree'),
    ('featured any rarity', 'server/Shop', 'if (it.source == "crate" or it.source == "shop") and it.rarity == rarity then', 'if it.source == "crate" or it.source == "shop" then', 'crate item at its price'),
    ('keys shown to the restricted', 'server/Shop', 'if not restricted then\n\t\tfor _, b in Products.KEYS', 'if true then\n\t\tfor _, b in Products.KEYS', 'offered Forge Keys'),
    ('policy fails open', 'server/Shop', 'return not ok or r ~= false', 'return ok and r == true', 'failed policy'),
    ('unpriced keys prompted', 'server/Shop', 'if b.id == 0 then return false, "Forge Keys are not on sale yet" end', '', 'id 0 was prompted'),
    ('restricted prompted', 'server/Shop', 'if self:restricted(userId) then return false, "Forge Keys are not available for your account" end', '', 'restricted player was prompted'),
    ('owned prompted', 'server/Shop', 'if Inventory.owns(inv, pick.id) then return false, "you already own it" end', '', 'owned item was prompted'),
    ('coming soon prompted', 'server/Shop', 'if not p.available then return false, `{p.name} is coming soon` end', '', 'coming-soon'),
    ('keys granted twice', 'server/Economy', 'if table.find(inv.receipts, purchaseId) then return true, { already = true } end', '', 'granted keys twice'),
    ('bought item unpaid', 'server/Shop', 'local uid, why = self.economy:_grant(inv, intent.id, true, "shop")', 'local uid, why = self.economy:_grant(inv, intent.id, false, "shop")', 'not marked paid'),
    ('no credit', 'server/Shop', 'inv.credits[what] = math.min(Inventory.MAX_COUNT, inv.credits[what] + 1)', '', 'credit'),
    ('credit never spent', 'server/Shop', 'i.credits[pick.rarity] -= 1', '', 'not redeemed'),
    ('receipt store unchecked', 'server/Purchases', 'if seen then return "granted" end', '', 'granted again'),
    ('receipt store failure ignored', 'server/Purchases', 'if not ok then return "later" end         -- cannot tell', 'if false then return "later" end         -- cannot tell', 'without checking'),
    ('pass asked every time', 'server/Passes', 'if mine[id] == nil then', 'if true then', 'not remembered'),
    ('pass items twice', 'server/Shop', 'if not Inventory.owns(self.economy:inventory(userId), id) then', 'if true then', 'twice'),
    ('pass items unpaid', 'server/Shop', 'local uid = self.economy:grant(userId, id, true, "pass")', 'local uid = self.economy:grant(userId, id, false, "pass")', 'not marked paid'),
    ('studio owns unbuilt passes', 'server/Passes', 'if self.studio then return p.available end', 'if self.studio then return true end', 'not built'),
    ('outfits for everyone', 'server/Locker', 'return if ok and vip == true then Inventory.MAX_PRESETS else 1', 'return Inventory.MAX_PRESETS', 'without VIP'),
    ('outfit wears unowned', 'server/Locker', 'if wear[key] and not self:owns(userId, wear[key]) then wear[key] = nil end', '', 'no longer owned'),
    ('spawn effects ignored', 'FxPlayer', 'if not style or not s then return false end\n\t\tstyle(P, s.x, s.y, char.height)', 'if true then return false end\n\t\tstyle(P, s.x, s.y, char.height)', 'draws nothing'),
]
avatarstore = [
    ('wardrobe ignored', 'server/AvatarStore', 'return if ok and has == true then AvatarStore.STORED_SLOTS else AvatarStore.MAX_SLOTS', 'return AvatarStore.MAX_SLOTS', 'ninth character would not save'),
]
secondary = [
    ('missing rear hair', 'Secondary', 'layer.z == 10', 'layer.z == 999', 'catalogue tail missing or priority wrong'),
    ('wrong accessory priority', 'Secondary', 'if neck == "summitMantle" or neck == "scarf" then', 'if false then', 'catalogue tail missing or priority wrong'),
    ('rigid part trails', 'Secondary', 'layer.z == 10 and layer.y >= 8', 'layer.z == 50', 'rigid kit part grows a trailing sprite'),
    ('uncached art', 'Secondary', 'if cache[code] then return cache[code] end', 'if false then return cache[code] end', 'secondary art rebuilt per call'),
    ('oversize picture', 'Secondary', 'maxX - minX + 3', 'maxX - minX + 300', 'small-sprite budget'),
    ('duplicate painted tail', 'Secondary', 'glyph = "."', 'glyph = glyph', 'cut leaves a duplicate painted tail'),
    ('uncached cut expression', 'Secondary', 'if not art.heads[expression] then', 'if true then', 'expression cut rebuilt'),
    ('neutral cut expression', 'Secondary', 'Expressions.specFor(art.spec, expression)', 'Expressions.specFor(art.spec, "neutral")', 'cut expression is visually neutral'),
    ('expression restores hair', 'Secondary', 'cuts[art.category] = art.override[art.category]', 'cuts[art.category] = nil', 'expression repaints detached rear hair'),
    ('hat trim ignored', 'Secondary', 'and y >= trim', 'and y >= 0', 'tail restores hair clipped by headwear'),
    ('no lag', 'Secondary', 'old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))', 'old.angle = target', 'tail has no delayed trail'),
    ('never settles', 'Secondary', 'old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))', 'if s.state == "run" then old.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5)) end', 'tail snaps still when movement stops'),
    ('duplicate draw advances follower', 'Secondary', 'elseif fc > old.at then\n\t\told.angle += (target - old.angle) * (1 - math.exp(-(fc - old.at) / 5))', 'elseif fc >= old.at then\n\t\told.angle += (target - old.angle) * (1 - math.exp(-math.max(1, fc - old.at) / 5))', 'duplicate draw advances lag'),
    ('seek keeps old motion', 'Secondary', 'or fc < old.at', 'or false', 'seek retains old secondary state'),
    ('facing ignored', 'Secondary', 's.vx * s.facing / char.runSpeed', 's.vx / char.runSpeed', 'tail leads motion when facing left'),
    ('detached root', 'Secondary', 'x += dx * sx * cs - dy * sy * sn', 'x += dx * sx * cs - dy * sy * sn + 0.1', 'trailing root detached x'),
    ('sheared tail', 'Fighter2D', 'Canvas2D.rotate(c, trail.rot)\n\t\t\tCanvas2D.scale(c, trail.sx, trail.sy)', 'Canvas2D.scale(c, trail.sx, trail.sy)\n\t\t\tCanvas2D.rotate(c, trail.rot)', 'secondary draw shears a sprite'),
    ('tail drawn twice', 'Fighter2D', 'trail.pw, trail.ph, trailingArt.w, trailingArt.h)', 'trail.pw, trail.ph, trailingArt.w, trailingArt.h)\n\t\t\tCanvas2D.sprite(c, `secondary|{kitCode}`, trailingArt.full, -2 * trail.pw, trail.ph, trail.pw, trail.ph, trailingArt.w, trailingArt.h)', 'expected exactly one tail'),
    ('extra tail at match LOD', 'Fighter2D', 'if kitArt and not half then Secondary.art', 'if kitArt then Secondary.art', 'expected exactly one tail'),
    ('per-frame picture change', 'Fighter2D', '`secondary|{kitCode}`, trailingArt.full', '`secondary|{kitCode}`, table.clone(trailingArt.full)', 'movement changes the trailing picture'),
    ('time-dependent sprite keys', 'Fighter2D', '`secondary|{kitCode}`', '`secondary|{kitCode}|{s.frameCount}`', 'warm movement rebuilds pictures'),
    ('unbounded art cache', 'Secondary', 'if #order > Secondary.CACHE_MAX then', 'if false then', 'secondary cache is unbounded'),
]

shopui = [
    ('countdown in hours only', 'ShopScreen', 'return `{m // 60}h {m % 60}m`', 'return `{m // 60}h`', 'countdown reads wrong'),
    ('per-key price truncated', 'ShopScreen', 'math.floor(bundle.price / bundle.count + 0.5)', 'math.floor(bundle.price / bundle.count)', 'per-key price'),
    ('owned featured buyable', 'ShopScreen', 'if not f.owned then self:request(key', 'if true then self:request(key', 'owned item was requested'),
    ('credit hidden', 'ShopScreen', 'elseif f.credit then "CLAIM"', 'elseif false then "CLAIM"', 'credit is not offered'),
    ('two requests at once', 'ShopScreen', 'if self.pending then return end\n\tself.pending = key', 'self.pending = key', 'while one was pending'),
    ('prompt dropped', 'ShopScreen', 'self.opts.prompt(e.prompt.kind, e.prompt.id)', 'local _ = e.prompt.id', 'not handed to Roblox'),
    ('odds not Loot', 'ShopScreen', 'row.label.Text, row.value.Text = r.text, r.value', 'row.label.Text, row.value.Text = r.text, r.value .. "!"', 'is not Loot'),
    ('guaranteed odds ignored', 'ShopScreen', 'LockerScreen.oddsRows("forge", 0, guaranteed)', 'LockerScreen.oddsRows("forge", 0, false)', 'guaranteed opening'),
    ('coming soon offered', 'ShopScreen', 'if not p.owned and p.available then self:request', 'if not p.owned then self:request', 'not on sale, or owned'),
    ('owned pass offered', 'ShopScreen', 'c.buy.Text = if p.owned then "OWNED" elseif not p.available', 'c.buy.Text = if false then "OWNED" elseif not p.available', 'owned pass'),
    ('keys for the restricted', 'ShopScreen', 'local keys = if shop.restricted then {} else shop.keys or {}', 'local keys = shop.keys or {}', 'should not have sent'),
    ('odds button for the restricted', 'ShopScreen', 'self.oddsButton.Visible = not shop.restricted', 'self.oddsButton.Visible = true', 'sees Forge Keys'),
    ('cells without slack', 'ShopScreen', '-math.ceil(10 * (cols - 1) / cols) - 1, 0, h)', '-math.ceil(10 * (cols - 1) / cols) + 1, 0, h)', 'do not fit'),
    ('pack offered regardless', 'ShopScreen', 'if pack.offer then self:request(key', 'if true then self:request(key', 'a pack not offered'),
    ('pack never BUY SINGLY', 'ShopScreen', 'elseif not pack.offer then "BUY SINGLY"', 'elseif false then "BUY SINGLY"', 'dearer than its missing pieces'),
    ('owned piece requested', 'ShopScreen', 'if not p.owned then self:request(pkey', 'if true then self:request(pkey', 'an owned piece, was requested'),
    ('pack line miscounts', 'ShopScreen', 'return `you own {n - pack.missing}', 'return `you own {n}', 'line reads wrong'),
    ('refusal silent', 'ShopScreen', 'self:say(`Could not do that: {e.error}`, Ui.RED)', 'self:say("", Ui.RED)', 'refusal was not shown'),
]

emotes = [
    ('duplicate catalogue silhouette', 'Emotes', 'function Emotes.sample', 'Emotes.CLIPS.emote_shrug = Emotes.CLIPS.emote_wave\nfunction Emotes.sample', 'two catalogue poses share a silhouette'),
    ('missing free entitlement', 'shared/Inventory', 'if it.source == "free" then owned[it.id] = true end', 'if false then owned[it.id] = true end', 'free item not owned by everyone'),
    ('stored free instance', 'shared/Inventory', 'and item(inst.i).source ~= "free" then', 'then', 'free item has transferable instance'),
    ('migrated free instance', 'shared/Inventory', 'and item(id).source ~= "free" and n <', 'and n <', 'free item has transferable instance'),
    ('mint free copies', 'shared/Inventory', 'if not item(id) or item(id).source == "free" then return nil end', 'if not item(id) then return nil end', 'free item can be minted'),
    ('lost VIP grant', 'shared/Products', ', "emote_vip"', '', 'VIP emote not granted by pass'),
    ('exclusive items never sold', 'server/Shop', 'local sold = it.source == "crate" or (it.source == "shop" and it.type ~= "clothing")', 'local sold = it.source == "crate"', 'shop-only poses never offered'),
    ('exclusive item in crate', 'shared/Cosmetics', 'type = "emote", name = "En Garde", rarity = "Rare", source = "shop"', 'type = "emote", name = "En Garde", rarity = "Rare", source = "crate"', 'phase six catalogue distribution'),
    ('crate emote not craftable', 'shared/Loot', 'if not item or item.source ~= "crate" then return nil end', 'if not item or item.type == "emote" or item.source ~= "crate" then return nil end', 'crate emote is not craftable'),
    ('wrong direction fallback', 'shared/Inventory', 'neutral = "emote_wave"', 'neutral = "emote_cheer"', 'direction defaults changed'),
    ('missing directional slots', 'shared/Inventory', 'for _, slot in Inventory.EMOTE_SLOTS do TYPE_OF[slot] = "emote" end', 'for _, slot in {} do TYPE_OF[slot] = "emote" end', 'owned pose slots lost on sanitize'),
    ('worn unowned emote', 'shared/Inventory', 'if equipped[slot] and not inv.owned[equipped[slot]] then', 'if false then', 'unowned or misplaced emote survives sanitize'),
    ('wrong slot type accepted', 'shared/Inventory', 'if item(src[slot], t) then', 'if item(src[slot]) then', 'unowned or misplaced emote survives sanitize'),
    ('lost chosen slot', 'shared/Inventory', 's = slot\n', 's = Inventory.SLOTS[it.type]\n', 'emote direction did not equip'),
    ('uncleared direction', 'shared/Inventory', 'if slot and TYPE_OF[slot] then inv.equipped[slot] = nil; return true end', 'if slot and TYPE_OF[slot] then return true end', 'emote direction did not come off'),
    ('invalid slot accepted', 'shared/Inventory', 'TYPE_OF[slot] ~= "emote"', 'TYPE_OF[slot] == "invalid"', 'emote accepted invalid slot'),
    ('unowned emote allowed', 'shared/Inventory', 'if not owns(id) then return false, "not owned" end', 'if false then return false, "not owned" end', 'unowned emote equipped'),
    ('old directional gear stays after removal', 'shared/Inventory', 'for slot in TYPE_OF do if inv.equipped[slot] == inst.i then inv.equipped[slot] = nil end end', 'for slot in {} do if inv.equipped[slot] == inst.i then inv.equipped[slot] = nil end end', 'last copy left an emote equipped'),
    ('preset restores unowned direction', 'server/Locker', 'for key in Inventory.SLOT_TYPES do', 'for _, key in Inventory.SLOTS do', 'preset restores unowned directional emote'),
    ('locker drops slot', 'server/Locker', 'end, if type(msg.slot) == "string" then msg.slot else nil)', 'end)', 'locker dropped chosen emote direction'),
    ('showcase discards chosen emote', 'server/Locker', 'out.skins, out.hit, out.ko, out.trail = table.clone(Locker.SHOWCASE.skins), Locker.SHOWCASE.hit, Locker.SHOWCASE.ko, Locker.SHOWCASE.trail', 'return Inventory.cleanLoadout(Locker.SHOWCASE)', 'Studio showcase discarded chosen emote'),
    ('facing ignored', 'server/EmoteEvents', 'input.x * facing > 0.5', 'input.x > 0.5', 'server sent wrong emote slot or facing'),
    ('up direction lost', 'server/EmoteEvents', 'if input.y > 0.5 then return "up" end', 'if input.y > 0.5 then return "neutral" end', 'server sent wrong emote slot or facing'),
    ('down direction lost', 'server/EmoteEvents', 'if input.y < -0.5 then return "down" end', 'if input.y < -0.5 then return "up" end', 'server sent wrong emote slot or facing'),
    ('server never observes taunts', 'server/MatchService', 'EmoteEvents.observe(self.emotes, m)', '-- no presentation observation', 'server sent wrong emote slot or facing'),
    ('event repeats every frame', 'server/EmoteEvents', 'if not old or old.start ~= start then', 'if true then', 'holding direction repeats or changes emote event'),
    ('cancelled event survives', 'server/EmoteEvents', 'active[f.index] = nil', 'local _ = old', 'cancelled taunt kept active event'),
    ('join loses emote', 'server/MatchService', 'for _, e in self.emotes do table.insert(list, e) end', 'for _, e in {} do table.insert(list, e) end', 'late join lost active emote'),
    ('event lost on client', 'FxPlayer', 'if not old or e.start >= old.start then P.emotes[e.fighter] = e end', 'if false then P.emotes[e.fighter] = e end', 'emote event lost or allocated effect sprites'),
    ('old event overwrites newer', 'FxPlayer', 'if not old or e.start >= old.start then', 'if true then', 'late event overwrote current taunt'),
    ('match reset leaves events', 'FxPlayer', 'table.clear(P.emotes)', '-- stale', 'new match retains emote events'),
    ('receiver queues behind view', 'client/init.client', '\t\t\tFxPlayer.spawn(fxPlayer, e, {}, {})', '\t\t\ttable.insert(pendingFx, { frame = frame or 0, e = e })', 'client receiver delays emote behind interpolation'),
    ('join receiver loses events', 'client/init.client', 'for _, e in cfg.emotes or {} do FxPlayer.spawn(fxPlayer, e, {}, {}) end', '-- no active emotes', 'client join did not restore active emote'),
    ('scene loses emote table', 'FightScene', 'Fighter2D.emotes = if S.player then S.player.emotes else nil', 'Fighter2D.emotes = nil', 'live scene ignores emote event'),
    ('scene leaks into previews', 'FightScene', 'Fighter2D.emotes = nil\n', '-- retained\n', 'live scene leaks emote events to previews'),
    ('cancellation ignored', 'Emotes', 'if s.state ~= "taunt" then return nil end', 'if false then return nil end', 'cancelled emote still poses fighter'),
    ('entry identity ignored', 'Emotes', 'math.abs((s.frameCount - s.stateFrame) - event.start) < 0.01', 'true', 'stale event animates next taunt'),
    ('worn direction ignored', 'Emotes', 'local id = worn and worn[key]', 'local id = nil', 'client ignored equipped directional emote'),
    ('wrong fallback pose', 'Emotes', 'else Inventory.DEFAULT_POSE', 'else "pose_star"', 'invalid podium pose lacks fallback'),
    ('sampler freezes between keys', 'Emotes', 'local k = u * u * (3 - 2 * u)', 'local k = if u < 1 then 0 else 1', 'pose jumps between keyframes'),
    ('sampler never settles', 'Emotes', '{ Config.TAUNT_FRAMES :: any, Emotes.STANCE }', '{ Config.TAUNT_FRAMES :: any, pose(b) }', 'emote does not end at stance'),
    ('height discontinuity', 'Emotes', 'math.abs(p.legL) * (1 - p.kneeL)', 'if p.kneeL < 0.05 then math.abs(p.legL) else 0', 'applied pose height jumps'),
    ('floating support foot', 'Posture', 'y = -ch.bob + h * 0.26 * leg[2],', 'y = -ch.bob + h * 0.26 * leg[2] + 0.1,', 'emote support foot floats'),
    ('detached rear weapon', 'Posture', 'offX, offY = bx, by', 'offX, offY = bx + 0.1, by', 'emote second grip detached'),
    ('fighter skips override', 'Fighter2D', 'if emote then Emotes.apply(ch, wpose, emote, char) end', '-- no emote override', 'Fighter2D skipped emote override'),
    ('extra body sprite', 'KitBody', 'kitPiece("head", PW)', 'kitPiece("head", PW)\n\tif ch.emote then kitPiece("head", PW) end', 'emote adds body sprites beyond pose budget'),
    ('generic thumbnail', 'ItemArt', 'if it.type == "emote" or it.type == "victory_pose" then return "pose",', 'if false then return "pose",', 'thumbnail not the item key frame'),
    ('thumbnail wrong still', 'ItemArt', 'frame = Emotes.KEY_FRAME', 'frame = 0', 'thumbnail not the item key frame'),
    ('locker picker does not advance', 'LockerScreen', 'c.slotIndex = c.slotIndex % #Inventory.EMOTE_ORDER + 1', 'c.slotIndex = 1', 'Locker button sends wrong direction'),
    ('locker wear omits direction', 'LockerScreen', 'slot = if m.type == "emote" then slot else nil', 'slot = nil', 'Locker button sends wrong direction'),
    ('locker clears wrong direction', 'LockerScreen', 'if m.type == "emote" then msg.slot = slot end', 'if m.type == "emote" then msg.slot = "emoteNeutral" end', 'Locker button clears wrong direction'),
    ('podium ignores worn item', 'PodiumView', 'if won then st.victoryPose = Emotes.poseFor(char.cosmetics) end', 'if won then st.victoryPose = Emotes.poseFor(nil) end', 'podium did not use each winners worn pose'),
    ('losers use victory item', 'PodiumView', 'if won then st.victoryPose = Emotes.poseFor(char.cosmetics) end', 'st.victoryPose = Emotes.poseFor(char.cosmetics)', 'loser uses victory cosmetic'),
]

uikit = [
    ('outlines in ink', 'Ui', 'if not theme.tone then return Ui.INK end\n\treturn Ui.shade(c, -0.58)', 'if not theme.tone then return Ui.INK end\n\treturn Ui.INK', 'own colour darkened'),
    ('paint keeps the old border', 'Ui', 'if p.border and theme.tone then p.border.Color = Ui.tone(colour) end', 'if false then p.border.Color = Ui.tone(colour) end', "old colour's outline"),
    ('no light band', 'Ui', 'elseif arcade then UDim2.new(1, -8, 0.3, -2)', 'elseif arcade then UDim2.new(1, -8, 0, 3)', 'no light band'),
    ('dark words outlined', 'Ui', 'local dark = colour ~= nil and Ui.light(colour) < 0.45', 'local dark = false', 'dark words are outlined'),
    ('card gradient kept', 'Ui', 'if ch.ClassName == "UIGradient" then ch.Color = ColorSequence.new(Ui.shade(colour, 0.32), colour)', 'if ch.ClassName == "UIGradient" then local _ = colour', 'paintCard left part'),
    ('pale words on the window', 'Ui', 'TEXT = Color3.fromRGB(43, 33, 64), SUB', 'TEXT = Color3.fromRGB(150, 140, 160), SUB', 'under 7:1'),
    ('card words outlined in ink', 'Ui', 'else 1, Ui.tone(face))', 'else 1, Ui.INK)', 'in its own shade'),
    ('white on gold', 'Ui', 'if lightFace then b.TextColor3 = if theme.light then Ui.TEXT elseif theme.tone', 'if lightFace then b.TextColor3 = if false then Ui.TEXT elseif false', 'gold button kept white'),
    ('small words bare', 'Ui', 'or (o.small and not theme.tone) then nil', 'or o.small then nil', 'small words on a button are bare'),
    ('icon button keyless', 'Ui', 'if key then\n\t\tlocal cap = Ui.keycap(b, key, 10)', 'if false then\n\t\tlocal cap = Ui.keycap(b, key, 10)', 'icon button is not a square'),
    ('repainted title keeps outline', 'Ui', 'if ch.ClassName == "UIStroke" then ch.Color = Ui.tone(colour) end', 'if false then ch.Color = Ui.tone(colour) end', "kept its title's old outline"),
]

hudwrites = [
    ('card see-through on update', 'Hud', 'if out then 0.6 elseif Ui.lightPanels() then 0 else 0.08', 'if out then 0.6 else 0.08', 'see-through on update'),
    ('card percent too pale', 'Hud', 'while contrast(c, Ui.PANEL) < 4.5 and k < 12 do', 'while contrast(c, Ui.PANEL) < 3 and k < 12 do', 'reads under 4.5'),
]

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--suite', action='append', help='Run only this suite (repeatable); default all')
args = parser.parse_args()
selected = 0
kitk2 = [
    ('k2 for everyone', 'shared/AvatarKit', 'if #worn > 0 then\n\t\tout[1] = AvatarKit.K2', 'if true then\n\t\tout[1] = AvatarKit.K2', 'left k1'),
    ('piece number off by one', 'shared/AvatarKit', 'local hi, lo = p.n // 36, p.n % 36', 'local hi, lo = p.n // 36, (p.n + 1) % 36', 'did not round trip'),
    ('misfiled piece worn', 'shared/AvatarKit', 'if c and p and p.category == c.id then parts[c.id] = p.id end', 'if c and p then parts[c.id] = p.id end', 'worn as a top'),
    ('sanitize ignores category', 'shared/AvatarKit', 'if optionIndex(c, v) or (p and p.category == c.id) then v', 'if optionIndex(c, v) or p ~= nil then v', 'wrong category'),
    ('k2 not a code', 'shared/AvatarKit', 'return v == AvatarKit.VERSION or v == AvatarKit.K2', 'return v == AvatarKit.VERSION', 'round trip'),
    ('strip keeps everything', 'shared/AvatarKit', 'if not (ok and has == true) then parts[PIECE[id].category]', 'if false then parts[PIECE[id].category]', 'stayed on'),
    ('strip trusts a failed read', 'shared/AvatarKit', 'if not (ok and has == true) then parts[PIECE[id].category]', 'if ok and has == false then parts[PIECE[id].category]', 'could not be read'),
    ('save without ownership', 'server/AvatarStore', 'if not (ok and has == true) then\n\t\t\t\treturn false, "That character wears', 'if false then\n\t\t\t\treturn false, "That character wears', 'unowned piece was saved'),
    ('active not stripped', 'server/AvatarStore', 'return self:wearable(userId, rec.slots[rec.active].code)', 'return rec.slots[rec.active].code', 'no longer owned stayed on'),
    ('piece drawn as a free part', 'AvatarCompose', 'chosen = AvatarKit.option(cat.id, spec.parts[cat.id])', 'chosen = cat.options[1]', 'not drawn on the torso'),
    ('clothing in crates', 'shared/Cosmetics', 'rarity = it.rarity, source = "shop",', 'rarity = it.rarity, source = "crate",', 'bought outright'),
]

clothingui = [
    ('studio offers no clothing', 'AvatarEditor', 'if it.category == c.id then table.insert(out, AvatarKit.option(c.id, it.id)) end', 'if false then table.insert(out, AvatarKit.option(c.id, it.id)) end', 'every top piece'),
    ('every piece wearable', 'AvatarEditor', 'if AvatarKit.piece(optionId) then return self.pieces[optionId] == true end', 'if AvatarKit.piece(optionId) then return true end', 'wearable does not follow'),
    ('no price given', 'AvatarEditor', '{price} R$ on its own', 'on its own', 'where it is sold'),
    ('locked as LOCKED', 'AvatarEditor', 'local tag = if AvatarKit.piece(o.id) then "SHOP" else "LOCKED"', 'local tag = "LOCKED"', 'tiles do not tell'),
    ('pieces not read', 'AvatarEditor', 'pieces[id] = true\n\t\t\ttable.insert(sig, "piece:" .. id)', 'table.insert(sig, "piece:" .. id)', 'wearable does not follow'),
    ('arrows skip clothing', 'AvatarEditor', 'local options = self:optionsOf(c)\n\tfor i, o in options do', 'local options = c.options\n\tfor i, o in options do', 'did not reach the owned piece'),
    ('random hands out anything', 'AvatarEditor', 'if self:wearable(c.id, o.id) then table.insert(out, o) end', 'table.insert(out, o)', 'unowned piece'),
    ('clothing worn by slot', 'LockerScreen', 'if m.type == "clothing" then\n\t\t\t\t-- clothing', 'if false then\n\t\t\t\t-- clothing', 'did not go to the Studio'),
    ('clothing button says WEAR', 'LockerScreen', 'c.primary.Text = if m.type == "clothing" then "WEAR IN STUDIO" elseif', 'c.primary.Text = if false then "WEAR IN STUDIO" elseif', 'offers a Locker slot'),
    ('hats on a figure', 'ItemArt', 'if HEAD_WORN[it.category] then "head" else "figure"', '"figure"', 'wrong view'),
]

clothingshop = [
    ('pack grants owned pieces', 'server/Shop', 'if not Inventory.owns(inv, it.id) then\n\t\t\t\t\tlocal uid, why = self.economy:_grant(inv, it.id, true, "shop")', 'if true then\n\t\t\t\t\tlocal uid, why = self.economy:_grant(inv, it.id, true, "shop")', 'exactly what was missing'),
    ('pack always offered', 'server/Shop', 'offer = missing > 0 and price < missingTotal,', 'offer = missing > 0,', 'dearer than its missing pieces is offered'),
    ('pack dearer than singles sold', 'server/Shop', 'if product.price >= missingTotal then return false', 'if false then return false', 'could be bought'),
    ('owned pack sold', 'server/Shop', 'if #missing == 0 then return false, "you already own every piece in it" end', 'local _ = #missing', 'fully owned pack could be bought'),
    ('race paid twice', 'server/Shop', 'elseif fresh and table.find(intent.missing, it.id) then', 'elseif false then', 'paid for twice'),
    ('one intent for all', 'server/Shop', 'self.packIntents[userId] = { id = msg.id', 'self.pieceIntents[userId] = { id = msg.id', 'paid for twice'),
    ('credit of any tier', 'server/Shop', 'if inv.credits[it.priceTier] > 0 then\n\t\t\t-- a clothing purchase', 'if inv.credits.accent + inv.credits.standard + inv.credits.statement > 0 then\n\t\t\t-- a clothing purchase', 'accent credit paid'),
    ('clothing product unknown', 'shared/Products', 'for tier, t in Products.CLOTHING do if t.id == productId then return "clothing", tier end end', 'local _ = productId', 'not recognised'),
    ('prompted before created', 'server/Shop', 'if product.id == 0 then return false, "clothing is not on sale yet" end\n\t\tself.pieceIntents', 'if false then return false, "clothing is not on sale yet" end\n\t\tself.pieceIntents', 'with no product was prompted'),
    ('forget forgets nothing', 'server/Shop', 'self.intents[userId], self.pieceIntents[userId], self.packIntents[userId] = nil, nil, nil', 'local _ = userId', 'kept after they left'),
]

for suite, faults in [('movement', movement), ('posture', posture), ('overlap', overlap), ('dual-wield', dual), ('kicks', kicks), ('loot', loot), ('cosmetics', cosmetics), ('economy', economy), ('locker-ui', lockerui), ('shop-ui', shopui), ('kit-k2', kitk2), ('clothing-ui', clothingui), ('clothing-shop', clothingshop), ('shop', shop), ('avatar-store', avatarstore), ('secondary', secondary), ('emotes', emotes), ('ui-kit', uikit), ('hud-writes', hudwrites)]:
    if args.suite and suite not in args.suite:
        continue
    selected += len(faults)
    subprocess.run(['lune', 'run', f'tests/{suite}'], check=True)
    for name, module, old, new, expected in faults:
        # 'shared/Loot' reaches src/shared; a bare name is a client module
        path = Path(f'src/{module}.luau' if '/' in module else f'src/client/{module}.luau')
        source = path.read_bytes()
        text = source.decode()
        assert text.count(old) == 1, (name, text.count(old))
        try:
            path.write_text(text.replace(old, new))
            result = subprocess.run(['lune', 'run', f'tests/{suite}'], capture_output=True, text=True)
            output = result.stdout + result.stderr
            assert result.returncode != 0, f'SURVIVED: {name}'
            assert expected in output, f'WRONG FAILURE: {name}\n{output}'
            line = next(line for line in output.splitlines() if expected in line)
            print(f'CAUGHT {suite}/{name}: {line}', flush=True)
        finally:
            path.write_bytes(source)
    subprocess.run(['lune', 'run', f'tests/{suite}'], check=True)
print(f'All {selected} independent mutations rejected; sources restored.')
