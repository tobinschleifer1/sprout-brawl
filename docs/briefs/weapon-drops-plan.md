# Weapon drops: two weapons, fists, throws

The first of the "deeper fights" features, agreed 2026-10-08. Brawlhalla's core loop on Blockfall's
twelve weapons.

## The design (decided with the user)

- **Two weapons per fighter.** Picked on the select screen. A fighter spawns on **fists** and holds
  neither until they take a drop.
- **Drops are generic.** Taking one arms you with whichever of your two you did not hold last
  (`nextArm`). A drop only *looks* like a weapon when it is one somebody threw.
- **The pickup button** (P): unarmed over a drop, take it; armed, throw. An item in reach is taken
  before a throw while you hold no item. Works on the ground and in the air.
- **Throws depend on the weapon** (phase 2): the hammer arcs heavy, the daggers fly fast and
  straight, the shield bounces. Phase 1 gives every weapon the generic `DROPS.thrown`. A thrown
  weapon hits for damage, then lands as a drop anyone can take.
- **Fists**: a basic kit (jab, cross, shove, uppercut, sweep, kicks, three slow heavies), quick and
  weak, no ultimate, no finishers, no mechanic; the meter keeps filling and waits for a weapon.
  Their strongest hit has under half the knockback growth of any weapon's kill move.
- **Your weapon is your stats**: weight, speed, size, jumps and mechanic come from what is in hand.
- **Lost stock, lost weapon**: every life starts on fists.
- **Off unless the match asks** (`cfg.weaponDrops`), so the replay suites' matches and their random
  streams are untouched; rooms will turn it on (phase 6).

## Phases

1. **Engine core** (done): `DROPS` config, the fists kit, `buildArmed`, `Fighter.equip/arm/disarm`,
   the throw move, drops (spawn, fall, land, fade, cap), the generic throw, landing a throw in the
   air. Ported to Luau in the same commit; `tests/drops-parity.luau` replays it.
2. **Per-weapon throws and balance** (done): a `thrown` profile per weapon; the pike pierces, the
   shield skips off floors (platforms and solids' tops, not their sides). Kill percents by the
   signatures' own oracle (balance.mjs koPercent): Hammer 174, Axe 185, Flail 217, Sword 226,
   Scythe 236, Shield 247, Pike 253; the five light throws never kill.
3. **Bots** (done): `weaponAction` in ai.js - go for the nearest drop (jump, double jump, step up
   via a platform in between, drop through a soft one), fight on fists when it is on you, throw at
   a target in a clear lane, twice as readily with a killing throw at kill percent. Two new level
   dials, `arm` and `throws`. Four normal bots are armed ~80% of a fight, median ~3 s on fists.
   No generator draws unless drops are on.
4. **Look and feel (web)** (done): the throw's body, drops falling in a beam (dropShapes.js, shared
   with the Luau by tests/drop-parity), the spinning thrown weapon, both weapons on the HUD card.
5. **Roblox client** (done; the HUD is unseen until the phase 6 playtest): `armed` on the fighter
   wire, drops and thrown weapons on the scene wire, the predictor carrying the kit and taking the
   server's loadout on correction (a pickup and a weapon leaving are the server's to decide; the
   throw itself is predicted), drops and thrown weapons drawn, both weapon names on the HUD tile
   with the held one gold. tests/drops-client.luau.
6. **Select screen and rooms** (done): a room slot holds `weapon` and `weapon2`, always two
   different ones (picking the other hand's weapon swaps them), remembered in the profile; a bot's
   second is by slot. On the select screen clicks fill hand 1 then hand 2, a weapon you already
   hold is kept and its partner chosen next, both are ringed gold and named with their hand, the
   card names the pair. Rooms start with `weaponDrops`. Live Studio playtest (2026-10-09): picking
   by real clicks, the longest pair fits its card, drops reach the client and draw as crates, the
   HUD tiles name both weapons with the held one gold, a real P press armed, threw and re-armed
   with the second weapon. It found one bug: an unnamed fighter (every bot) was named "Fists",
   for the char it spawns holding - now named for its first weapon in both builds. Not seen in
   Studio: a thrown weapon's sprite in flight or lying (covered by tests/drops-client's renderer
   check only).

After this: new weapons (whip, chakram, rocket boots), then KO effects / emotes, then progression.
