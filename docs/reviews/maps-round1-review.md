# Maps, round 1: reviews (2026-10-23)

Two independent Claude reviewers (the Codex plan has ended). **Reviewer 1: 5.6** (faithful 5.5 · fits
6.0 · readability 5.0 · consistency 6.5 · hierarchy 5.0). **Reviewer 2: 5.8** (faithful 5.5 · fits
6.5 · readability 5.75 · consistency 6.5 · hierarchy 5.0). Both "getting better, not good enough".

Both:
- The value structure is upside down on all nine maps: the island rock is the darkest thing on
  screen. The 40% landmark haze mixes toward `sky[3]`, the pale horizon, so daylight landmarks got
  lighter (hall roof L 0.52 to 0.57), on top of each landmark function's own sky mix. Meanwhile the
  strata darkened the rock (Foundry 0.19 to 0.11). On dark realms rock is about 1:1 against the sky;
  only the ink rim draws the island.
- The near sky islands (`layer("near")`, fixed positions, no outline) read as places to stand. The
  one at (150,88) sits at play height beside real platforms, with a top colour 85% of the real
  surface.
- The strata read as planks or siding. Seams (R[1] every 4 cells) are as strong as the walking edge.
- Mixed pixel density: the body at BODY_PPU 2 against surfaces, platforms and fighters at 4.
- Every realm has the same sky layout (clouds and near islands at hard-coded positions; a cloud
  behind the fighters' heads in every shot).
- Ink rim plus shine gives every top edge 3:1 or better (the ink on light skies, the shine on dark
  ones). Platforms now wear the button anatomy, and that is the most on-brief part.

Reviewer 1: Smeltworks' vent grates (HazardArt) fail 3:1 (down to 1.19); the main floor is under the
HUD cards on Foundry and Saltflat; the top HUD band covers a fighter (Smeltworks, Faultline); five rock
palettes are near-identical grey-violet; fighters' colours nearly match some skies (blue shirt 1.05:1
on Undertow).
Reviewer 2: landmarks too saturated in dark realms (volcano lava S 0.76); volcano lava streaks run
behind the centre platform; iron girders are the weak platform.
