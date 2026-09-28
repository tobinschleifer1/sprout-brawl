--!strict
-- The arcade's rules, driven directly: sitting, the countdown, vs CPU, winner-stays streaks,
-- watching, and people leaving at the worst moment.
local Loader = require("./loader")
local Cabinets = Loader.loadFrom("src/server/", "Cabinets")
local function player(id: number): any return { UserId = id, DisplayName = `P{id}` } end
local a, b, c, d = player(1), player(2), player(3), player(4)
local now = 0

local arcade = Cabinets.new()
-- Sitting.
assert(arcade:sit(a, 1, "A", now), "an empty seat can be taken")
assert(not arcade:sit(a, 1, "B", now), "one seat at a time")
assert(not arcade:sit(b, 1, "A", now), "a taken seat cannot be")
assert(not arcade:sit(b, 99, "A", now) and not arcade:sit(b, 1, "C", now) and not arcade:sit(b, "1", "A", now), "no such seat")
assert(arcade.cabs[1].state == "open", "one player alone waits")
-- The countdown, and getting up during it.
assert(arcade:sit(b, 1, "B", now), "the other side")
assert(arcade.cabs[1].state == "countdown", "two players start the countdown")
assert(#arcade:due(now + Cabinets.COUNTDOWN - 0.1) == 0, "not before it runs out")
arcade:stand(b)
assert(arcade.cabs[1].state == "open" and #arcade:due(now + 10) == 0, "getting up cancels the countdown")
assert(arcade:sit(b, 1, "B", now + 10))
now += 10
local due = arcade:due(now + Cabinets.COUNTDOWN)
assert(#due == 1 and due[1].number == 1 and due[1].state == "playing", "the countdown runs out and the fight starts")
-- Mid-fight: seats are fixed, and anyone can watch.
assert(not arcade:stand(a) and arcade.seatOf[1], "nobody gets up mid-fight")
assert(not arcade:sit(c, 1, "A", now), "nobody sits down mid-fight")
assert(arcade:watch(c, 1) and arcade:watch(d, 1), "people can watch")
assert(not arcade:watch(a, 1), "the players are not spectators")
assert(not arcade:watch(c, 2), "an idle cabinet has nothing to watch")
assert(arcade:views(now)[1].watchers == 2, "the cabinet counts its watchers")
-- The winner stays, the loser gets up, the streak starts.
local up = arcade:finish(1, 2)
assert(#up == 1 and up[1] == a and not arcade.seatOf[1] and arcade.seatOf[2], "the loser gets up; the winner stays")
local v = arcade:views(now)[1]
assert(v.state == "open" and v.streak.userId == 2 and v.streak.wins == 1 and v.streak.name == "P2", "a first win starts a streak")
assert(v.watchers == 0 and not arcade.watching[3], "the audience goes home with the result")
-- The challenger sits, loses, and the streak grows.
assert(arcade:sit(c, 1, "A", now))
arcade:due(now + 10)
arcade:finish(1, 2)
assert(arcade:views(now)[1].streak.wins == 2, "a second win grows the streak")
-- A new winner starts their own.
assert(arcade:sit(d, 1, "A", now))
arcade:due(now + 10)
up = arcade:finish(1, 4)
assert(up[1] == b and arcade:views(now)[1].streak.userId == 4 and arcade:views(now)[1].streak.wins == 1, "the champion falls; a new streak")
-- Getting up gives up your streak.
arcade:stand(d)
assert(arcade:views(now)[1].streak == nil, "walking away gives up the streak")
-- Against the CPU.
assert(arcade:sit(a, 2, "A", now))
assert(arcade:vsCpu(a) and arcade.cabs[2].state == "playing" and arcade.cabs[2].cpu, "alone, you can fight the CPU")
assert(not arcade:sit(c, 2, "B", now), "nobody takes the empty seat during a fight against the CPU")
up = arcade:finish(2, 1)
assert(#up == 0 and arcade.seatOf[1] and arcade:views(now)[2].streak.wins == 1, "beating the CPU keeps your seat and counts")
up = arcade:finish(2, nil)
assert(#up == 0 and arcade.seatOf[1], "losing to the CPU keeps your seat too")
assert(arcade:sit(b, 2, "B", now) and not arcade:vsCpu(a), "no CPU when someone is sitting across")
-- Leaving: mid-countdown is just getting up; mid-fight hands back the cabinet to cancel.
assert(arcade:leave(b) == nil and arcade.cabs[2].state == "open", "leaving in the countdown cancels it")
assert(arcade:sit(b, 2, "B", now))
arcade:due(now + 10)
local cab = arcade:leave(a)
assert(cab and cab.number == 2, "leaving mid-fight hands back the fight to cancel")
local out = arcade:cancel(2)
assert(#out == 2 and not arcade.seatOf[1] and not arcade.seatOf[2] and arcade.cabs[2].state == "open", "a cancelled fight clears the cabinet")
print("PASS cabinets: seats, countdown and cancelling it, winner stays and streaks, new champions, vs CPU, watching, leaving mid-countdown and mid-fight")
