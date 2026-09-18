--!strict
-- The per-frame input frame, ported from web/src/engine/input.js.
--
-- Only the FRAME SHAPE ports. The JavaScript file is mostly keyboard and gamepad polling, which on
-- Roblox is the client's job and arrives over a remote instead. Everything downstream - Fighter's
-- buffers, the state machine, the bots - reads this shape and nothing else, so the transport can
-- change without the simulation noticing.

local Input = {}

export type Frame = {
	x: number, y: number,
	jump: boolean, light: boolean, heavy: boolean, dodge: boolean, guard: boolean,
	grab: boolean, taunt: boolean, pickup: boolean, ult: boolean,
	jumpHeld: boolean, guardHeld: boolean, heavyHeld: boolean, lightHeld: boolean,
	downTap: boolean, anyPress: boolean,
}

function Input.emptyFrame(): Frame
	return {
		x = 0, y = 0,
		jump = false, light = false, heavy = false, dodge = false, guard = false,
		grab = false, taunt = false, pickup = false, ult = false,
		jumpHeld = false, guardHeld = false, heavyHeld = false, lightHeld = false,
		downTap = false, anyPress = false,
	}
end

return Input
