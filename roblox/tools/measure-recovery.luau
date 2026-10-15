--!nocheck
-- Reproduce the controlled fuel/recovery comparison used by tests/rocketboots.
local measure = require("../tests/fuel-recovery-case")
local result = measure()
print(`Recovery: {result.recovered}/{result.cases}; pre-launch fuel: {table.concat(result.fuels, ", ")}`)
