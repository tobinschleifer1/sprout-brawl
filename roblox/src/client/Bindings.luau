--!strict
-- One definition for actual input polling and the visible keyboard/gamepad reference.
local Bindings = {}
Bindings.keyboard = {
	left = { "A", "Left" }, right = { "D", "Right" }, up = { "W", "Up" }, down = { "S", "Down" },
	jump = { "Space", "W", "Up" }, light = { "J" }, heavy = { "K" }, dodge = { "L", "LeftShift" },
	guard = { "I", "LeftControl" }, grab = { "U" }, taunt = { "T" }, pickup = { "P" }, ult = { "O" },
}
Bindings.gamepad = {
	jump = "ButtonA", light = "ButtonX", heavy = "ButtonY", dodge = "ButtonB",
	guard = "ButtonR1", grab = "ButtonL1", taunt = "ButtonSelect", pickup = "ButtonR3", ult = "ButtonL3",
}
Bindings.actions = {
	{ id = "jump", name = "Jump", hint = "Jump again in the air." },
	{ id = "light", name = "Light attack", hint = "Hold a direction to change your attack." },
	{ id = "heavy", name = "Heavy / use item", hint = "Up + Heavy in air: recovery. Down + Heavy: ground pound." },
	{ id = "dodge", name = "Dodge / dash", hint = "Use direction to dodge away or through a threat." },
	{ id = "guard", name = "Shield", hint = "HOLD to shield. Release to recover shield energy." },
	{ id = "grab", name = "Grab", hint = "Grab a nearby opponent; also Guard + Light." },
	{ id = "pickup", name = "Pick up / throw", hint = "Take a weapon drop or an item. Holding a weapon, throw it. Heavy uses the item you are holding." },
	{ id = "ult", name = "Ultimate", hint = "Press when your ultimate meter is FULL; hits build charge." },
	{ id = "taunt", name = "Taunt", hint = "A cosmetic flourish between exchanges." },
}
local names = {
	LeftControl = "Left Ctrl", LeftShift = "Left Shift", Up = "Up arrow",
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y", ButtonR1 = "RB", ButtonL1 = "LB",
	ButtonR3 = "Right stick click", ButtonL3 = "Left stick click", ButtonSelect = "Back / Select",
}
function Bindings.key(id: string): string
	local out = {}
	for _, code in (Bindings.keyboard :: any)[id] or {} do table.insert(out, names[code] or code) end
	return table.concat(out, " / ")
end
function Bindings.pad(id: string): string
	local code = (Bindings.gamepad :: any)[id]
	return names[code] or code or "Stick / D-pad"
end
return Bindings
