--!strict
local Loader = require("./loader")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local fixture = serde.decode("json", fs.readFile("tests/hub-fixture.json"))
local Lobby = Loader.load("Lobby")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local HUB = Loader.load("Data/Hub")
local checks = 0
for _, case in fixture.cases do
	local scene = HUB
	for _, data in HUB.rooms do if data.id == case.scene then scene = data end end
	local hub = Lobby.new(Loadout.build("Classic", case.weapon), scene)
	for frame, sample in case.frames do
		if frame == 801 then hub:setScene(scene) end
		hub:step(sample.input)
		for k, field in fixture.fields do
			local actual, expected = hub.fighter[field], sample.values[k]
			if type(expected) == "number" then
				assert(math.abs(actual - expected) <= 1e-10 * math.max(1, math.abs(expected)), `{case.weapon} frame {frame}: {field} differs`)
			else assert(actual == expected, `{case.weapon}: {field} differs`) end
			checks += 1
		end
		local near = hub:nearest()
		assert((if near then near.id else "") == sample.near, "interaction target drift")
		assert(hub.fighter.state ~= "attack" and hub.fighter.state ~= "ultimate", "lobby is harmless even when combat buttons are pressed")
	end
end
for _, station in HUB.stations do
	local hub = Lobby.new(Loadout.build("Classic", "Sword"))
	for _ = 1, 1000 do
		if math.abs(hub.fighter.x - station.x) <= 1 then break end
		local input = Input.emptyFrame()
		input.x = if hub.fighter.x < station.x then 1 else -1
		hub:step(input)
	end
	assert(hub:nearest() == station, "every station must be reachable by walking")
end
print(`PASS walkable hub: {checks} replayed values, twelve weapons, four scenes and scene-transfer resets`)
