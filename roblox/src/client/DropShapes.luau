--!strict
-- A weapon drop on the stage, as shapes: ported from web/src/render2d/dropShapes.js, which says
-- what each part is. Held to it by tests/drop-parity.luau. Driven by the match frame, never
-- wall-clock, so both builds draw the same drop on the same frame.
-- Shapes in world units, y up: { "r", x, y, w, h, colour, alpha } and { "e", cx, cy, rx, ry, colour, alpha }.
local DropShapes = {}
DropShapes.FADE = 120
DropShapes.BEAM = 12

-- a shape row; `any` because strict mode would type a literal mixing strings and numbers as strings
local function shape(...: any): any
	return { ... }
end

-- Returns the shapes and, for a thrown weapon lying there, { id, x, y, angle, alpha } for its sprite.
function DropShapes.shapes(d: any, frame: number): ({ any }, any)
	local out: { any } = {}
	local blink = if d.onGround and d.life < DropShapes.FADE and (frame // 8) % 2 == 0 then 0.45 else 1
	local pulse = 0.5 + 0.5 * math.sin(frame * 0.12 + d.x)
	local bob = if d.onGround then math.sin(frame * 0.08 + d.x) * 0.12 else 0
	local y = d.y + bob
	if not d.onGround then
		table.insert(out, shape("r", d.x - 0.9, d.y, 1.8, DropShapes.BEAM, "#FFF3C4", 0.16 * blink))
		table.insert(out, shape("r", d.x - 0.35, d.y, 0.7, DropShapes.BEAM, "#FFFFFF", 0.22 * blink))
	end
	table.insert(out, shape("e", d.x, d.y + 0.15, 1.5 + 0.2 * pulse, 0.45, "#FFD54A", (0.22 + 0.14 * pulse) * blink))
	if d.look then
		return out, { id = d.look, x = d.x - 1, y = y + 0.45, angle = 0.25, alpha = blink }
	end
	table.insert(out, shape("r", d.x - 0.7, y, 1.4, 1.0, "#8A5A2B", blink))
	table.insert(out, shape("r", d.x - 0.78, y + 0.92, 1.56, 0.24, "#A6703A", blink))
	table.insert(out, shape("r", d.x - 0.7, y + 0.22, 1.4, 0.14, "#4E3016", blink))
	table.insert(out, shape("r", d.x - 0.7, y + 0.62, 1.4, 0.14, "#4E3016", blink))
	table.insert(out, shape("r", d.x - 0.18, y + 0.4, 0.36, 0.32, "#FFD54A", blink))
	local g = (frame % 120) / 120
	if g < 0.3 then
		table.insert(out, shape("r", d.x - 0.78 + g / 0.3 * 1.4, y + 0.98, 0.16, 0.16, "#FFFFFF", 0.9 * blink))
	end
	return out, nil
end

return DropShapes
