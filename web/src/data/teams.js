// The two team colours: green and orange. The HUD tiles and labels and the team glow under each
// fighter all read these, as does roblox/src/client/HudColors.luau (HudColors.TEAM, same values).
export const TEAM_COLORS = { 0: '#3E8A2E', 1: '#DE621C' };
// The team glow under a fighter's feet, drawn with the ground shadow: how wide and tall, as a
// multiple of the fighter's radius and in studs, and how strong.
export const TEAM_GLOW = { rx: 1.7, ry: 0.62, alpha: 0.55 };
// The team chevron over a fighter's head, which stays with them in the air where the glow cannot:
// studs above the head, its width and height, and how strong. Point down, at the fighter.
export const TEAM_MARKER = { above: 1.0, w: 1.0, h: 0.7, alpha: 0.9 };
