--!strict
-- The first-time tutorial's lessons (Roblox only; the owner's ask, 2026-11-02): with the Sword,
-- against a CPU in a Training match of the player's own (Rooms.tutorial), one move at a time. Each
-- lesson STOPS the fight - a card with what to press and why, the controls held while it is up -
-- then hands them back with a goal on screen, and moves on once the player has done it. The last
-- sets the CPU fighting (an easy one) for a real exchange.
--
-- Pure: what the player did comes in as match events (the server's, and the predictor's own
-- movement) and as their input frames; TutorialView draws it, init.client wires it.
local Tutorial = {}

-- A lesson: `keys` are the actions whose keys it shows; `goal` the line on screen while it runs and
-- `need` how many times; `count(e, me)` - does this match event count - or `held(frame)` - does this
-- input frame. `fight`: the CPU fights from here.
export type Lesson = { id: string, title: string, body: string, keys: { string }, goal: string, need: number,
	count: ((any, number) -> boolean)?, held: ((any) -> boolean)?, fight: boolean? }

Tutorial.LESSONS = {
	{ id = "move", title = "MOVE", keys = { "left", "right" },
		body = "Run left and right. Hold a direction to keep running.",
		goal = "Run around", need = 45, held = function(f: any): boolean return (tonumber(f.x) or 0) ~= 0 end },
	{ id = "jump", title = "JUMP", keys = { "jump" },
		body = "Jump - and press it again in the air to jump a second time. That second jump is how you get back to the stage.",
		goal = "Double jump", need = 2, count = function(e: any, me: number): boolean return e.type == "doublejump" and e.fighter == me end },
	{ id = "light", title = "LIGHT ATTACK", keys = { "light" },
		body = "Walk up to the CPU and swing your Sword. Light attacks are fast: chain them together.",
		goal = "Land light attacks", need = 3,
		count = function(e: any, me: number): boolean return e.type == "hit" and e.attacker == me and not e.heavy end },
	{ id = "aim", title = "AIM YOUR ATTACKS", keys = { "up", "down", "light" },
		body = "Hold up or down as you attack and the Sword swings that way - up to hit someone above you, down to sweep low.",
		goal = "Attack up, then down", need = 2,
		count = function(e: any, me: number): boolean
			return e.type == "movestart" and e.fighter == me and type(e.move) == "string" and (string.find(e.move, "Up") ~= nil or string.find(e.move, "Down") ~= nil)
		end },
	{ id = "heavy", title = "HEAVY ATTACK", keys = { "heavy" },
		body = "Heavy attacks are slower but hit much harder. The more damage they have taken, the further they fly.",
		goal = "Land a heavy attack", need = 1,
		count = function(e: any, me: number): boolean return e.type == "hit" and e.attacker == me and e.heavy == true end },
	-- (counted by dash and air dodge: a dodge on the spot sends no event - the simulation, held to the
	-- JavaScript, has none - so the lesson asks for the dash, a direction with Dodge)
	{ id = "dodge", title = "DASH AND DODGE", keys = { "left", "right", "dodge" },
		body = "Hold left or right and press Dodge to dash out of trouble. In the air, Dodge slips you through an attack.",
		goal = "Dash with a direction", need = 2,
		count = function(e: any, me: number): boolean return (e.type == "dodge" or e.type == "dash") and e.fighter == me end },
	{ id = "shield", title = "SHIELD", keys = { "guard" },
		body = "HOLD to raise your shield and block. It wears down while you hold it - let go and it recovers.",
		goal = "Hold your shield", need = 40, held = function(f: any): boolean return f.guardHeld == true end },
	{ id = "grab", title = "GRAB", keys = { "grab" },
		body = "Grab gets through a shield. Stand close, grab, then press a direction to throw.",
		goal = "Grab the CPU", need = 1, count = function(e: any, me: number): boolean return e.type == "grabhit" and e.fighter == me end },
	{ id = "fight", title = "NOW FIGHT", keys = { "light", "heavy", "ult" },
		body = "The CPU fights back now. Knock it off the stage twice! Hits fill your ultimate meter: press Ultimate when it is full.",
		goal = "Knock the CPU out", need = 2, fight = true,
		count = function(e: any, me: number): boolean return e.type == "ko" and e.by == me and e.fighter ~= me end },
} :: { Lesson }

-- After a lesson is done, how long its "done" stays up before the next card.
Tutorial.DONE_HOLD = 1.2

-- `me`: the player's fighter index in the match (Snapshot's 0-based index).
function Tutorial.new(me: number): any
	return setmetatable({ me = me, index = 1, progress = 0, phase = "card", doneAt = nil, finished = false, fighting = false },
		{ __index = Tutorial })
end

function Tutorial.lesson(self: any): Lesson?
	return Tutorial.LESSONS[self.index]
end
-- Is the fight stopped for a card (the controls held)?
function Tutorial.stopped(self: any): boolean
	return self.phase == "card" or self.finished
end
-- The card read: the controls back, the goal on screen. Returns "fight" when this lesson sets the
-- CPU fighting - only now, never while a card holds the player still.
function Tutorial.continue(self: any): string?
	if self.phase ~= "card" or self.finished then return nil end
	self.phase = "goal"
	local l = self:lesson()
	if l and l.fight and not self.fighting then
		self.fighting = true
		return "fight"
	end
	return nil
end

local function advance(self: any, now: number)
	self.phase, self.doneAt = "done", now
end

-- A match event. Returns true when it moved the lesson on.
function Tutorial.event(self: any, e: any, now: number): boolean
	local l = self:lesson()
	if not l or self.phase ~= "goal" or not l.count or type(e) ~= "table" then return false end
	if not l.count(e, self.me) then return false end
	self.progress += 1
	if self.progress >= l.need then advance(self, now) end
	return true
end
-- One of the player's input frames.
function Tutorial.frame(self: any, f: any, now: number): boolean
	local l = self:lesson()
	if not l or self.phase ~= "goal" or not l.held or type(f) ~= "table" then return false end
	if not l.held(f) then return false end
	self.progress += 1
	if self.progress >= l.need then advance(self, now) end
	return true
end
-- Time passing: a finished lesson's "done" gives way to the next card. Returns "next" when a new
-- lesson's card came up, "finished" after the last.
function Tutorial.tick(self: any, now: number): string?
	if self.phase ~= "done" or now - self.doneAt < Tutorial.DONE_HOLD then return nil end
	self.index += 1
	self.progress, self.doneAt = 0, nil
	local l = self:lesson()
	if not l then
		self.finished, self.phase = true, "finished"
		return "finished"
	end
	self.phase = "card"
	return "next"
end

-- The goal line: "Land light attacks  2 / 3"; a held goal as a share.
function Tutorial.goalText(self: any): string
	local l = self:lesson()
	if not l then return "" end
	if self.phase == "done" then return "DONE!" end
	if l.held then return `{l.goal}  {math.floor(math.min(1, self.progress / l.need) * 100)}%` end
	return `{l.goal}  {math.min(self.progress, l.need)} / {l.need}`
end

return Tutorial
