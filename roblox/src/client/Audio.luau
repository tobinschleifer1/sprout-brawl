--!strict
-- The game's sound (Roblox only; the owner's ask, 2026-11-02). The JavaScript synthesises its
-- effects through Web Audio (web/src/audio/sfx.js), which Roblox has no equivalent of, so the port
-- plays recorded sounds instead - the ones the Roblox client ships with itself (rbxasset://sounds),
-- which every player already has and nobody else owns. Which match event makes which sound follows
-- the JavaScript's own table (SFX_FOR in web/src/main.js), with movestart's swing.
--
-- Two SoundGroups, Music and Effects, carry the settings menu's two volumes. MUSIC is empty: the
-- client ships no music, and a track is an asset the owner chooses (and has the rights to); its id
-- goes there, and the Music volume already applies to it.
local Audio = {}

-- name -> { id, volume, speed (playback rate), spread (± random rate, so a run of hits is not one
-- note repeated) }
Audio.SOUNDS = {
	hit = { id = "rbxasset://sounds/hit.wav", volume = 0.55, speed = 1.15, spread = 0.08 },
	hitheavy = { id = "rbxasset://sounds/hit.wav", volume = 0.8, speed = 0.8, spread = 0.05 },
	chip = { id = "rbxasset://sounds/snap.mp3", volume = 0.35, speed = 1.3, spread = 0.05 },
	block = { id = "rbxasset://sounds/snap.mp3", volume = 0.5, speed = 0.9, spread = 0.05 },
	whiff = { id = "rbxasset://sounds/swordslash.wav", volume = 0.35, speed = 1.1, spread = 0.1 },
	whiffheavy = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.45, speed = 0.9, spread = 0.06 },
	jump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, speed = 1, spread = 0.04 },
	doublejump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.4, speed = 1.25, spread = 0.04 },
	land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.35, speed = 1, spread = 0.05 },
	dodge = { id = "rbxasset://sounds/swordslash.wav", volume = 0.25, speed = 1.6, spread = 0.05 },
	dash = { id = "rbxasset://sounds/swordslash.wav", volume = 0.2, speed = 1.8, spread = 0.05 },
	grab = { id = "rbxasset://sounds/unsheath.wav", volume = 0.45, speed = 1.2, spread = 0.04 },
	shieldbreak = { id = "rbxasset://sounds/glassbreak.wav", volume = 0.6, speed = 1, spread = 0 },
	ko = { id = "rbxasset://sounds/collide.wav", volume = 0.8, speed = 0.8, spread = 0 },
	explosion = { id = "rbxasset://sounds/collide.wav", volume = 0.6, speed = 1, spread = 0.06 },
	projectile = { id = "rbxasset://sounds/paintball.wav", volume = 0.35, speed = 1.2, spread = 0.08 },
	pickup = { id = "rbxasset://sounds/clickfast.wav", volume = 0.5, speed = 1, spread = 0 },
	throwitem = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.35, speed = 1.3, spread = 0.05 },
	count = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45, speed = 1, spread = 0 },
	go = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 1.5, spread = 0 },
	game = { id = "rbxasset://sounds/victory.wav", volume = 0.6, speed = 1, spread = 0 },
	ui = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4, speed = 1, spread = 0 },
	lesson = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45, speed = 1.25, spread = 0 },
} :: { [string]: { id: string, volume: number, speed: number, spread: number } }
-- Music tracks (asset ids, "rbxassetid://..."): none yet; see above.
Audio.MUSIC = {} :: { string }

-- The match event -> sound table (web/src/main.js SFX_FOR), cut to the sounds above.
local FOR: { [string]: string } = { chip = "chip", block = "block", ko = "ko", jump = "jump", doublejump = "doublejump",
	land = "land", dash = "dash", dodge = "dodge", shieldbreak = "shieldbreak", grabhit = "grab", explosion = "explosion",
	projectile = "projectile", pickup = "pickup", throwitem = "throwitem", count = "count", go = "go", game = "game",
	burst = "explosion", fruiting = "explosion", pulse = "explosion", shock = "land" }
-- The sound for a match event, or nil.
function Audio.forEvent(e: any): string?
	if type(e) ~= "table" then return nil end
	if e.type == "hit" then return if e.heavy or (tonumber(e.launch) or 0) > 60 then "hitheavy" else "hit" end
	if e.type == "movestart" then return if e.heavy then "whiffheavy" else "whiff" end
	return FOR[e.type]
end

-- No sound plays again within GAP seconds of itself, and no more than PER_FRAME start in one
-- frame: a four-player brawl sets off dozens of events a second, and that is noise, not feedback.
Audio.GAP, Audio.PER_FRAME = 0.04, 6

-- opts: { make = (name, def) -> sound (an object with Play, Volume, PlaybackSpeed), clock = () -> number,
-- rand = () -> number, groups = { music = group?, sfx = group? } }
function Audio.new(opts: any): any
	return setmetatable({ make = opts.make, clock = opts.clock or os.clock, rand = opts.rand or math.random,
		groups = opts.groups or {}, pool = {}, last = {}, frameAt = -1, started = 0, music = 0.6, sfx = 0.8 }, { __index = Audio })
end

-- The settings' volumes, 0..1 each (Settings.music, Settings.sfx).
function Audio.setVolumes(self: any, music: number, sfx: number)
	self.music, self.sfx = math.clamp(music, 0, 1), math.clamp(sfx, 0, 1)
	if self.groups.music then self.groups.music.Volume = self.music end
	if self.groups.sfx then self.groups.sfx.Volume = self.sfx end
end

-- Play a sound by name. Returns whether it started.
function Audio.play(self: any, name: string): boolean
	local def = Audio.SOUNDS[name]
	if not def or self.sfx <= 0 or not self.make then return false end
	local now = self.clock()
	if now ~= self.frameAt then self.frameAt, self.started = now, 0 end
	if self.started >= Audio.PER_FRAME then return false end
	if self.last[name] and now - self.last[name] < Audio.GAP then return false end
	-- a few voices per sound, round-robin, so one can start while the last still rings
	local voices = self.pool[name]
	if not voices then voices = { n = 0 }; self.pool[name] = voices end
	voices.n = voices.n % 3 + 1
	local s = voices[voices.n]
	if not s then
		s = self.make(name, def)
		voices[voices.n] = s
	end
	if not s then return false end
	s.Volume = def.volume
	s.PlaybackSpeed = def.speed + (self.rand() * 2 - 1) * def.spread
	s:Play()
	self.last[name], self.started = now, self.started + 1
	return true
end

-- A match event's sound, if it has one.
function Audio.event(self: any, e: any): boolean
	local name = Audio.forEvent(e)
	return if name then self:play(name) else false
end

-- The real thing: SoundGroups in SoundService, sounds made on first use. Returns the Audio.
function Audio.attach(): any
	local SoundService = game:GetService("SoundService")
	local function group(name: string): any
		local g = SoundService:FindFirstChild(name) or Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
		return g
	end
	local music, sfx = group("BlockfallMusic"), group("BlockfallEffects")
	local holder = Instance.new("Folder")
	holder.Name = "BlockfallSounds"
	holder.Parent = SoundService
	local self = Audio.new({ groups = { music = music, sfx = sfx }, make = function(name: string, def: any): any
		local s = Instance.new("Sound")
		s.Name, s.SoundId, s.SoundGroup = name, def.id, sfx
		s.Parent = holder
		return s
	end })
	-- music, once there is any: one track after another, under the Music volume
	if #Audio.MUSIC > 0 then
		local track = Instance.new("Sound")
		track.Name, track.SoundGroup, track.Looped = "Music", music, false
		track.Parent = holder
		local i = 0
		local function nextTrack()
			i = i % #Audio.MUSIC + 1
			track.SoundId = Audio.MUSIC[i]
			track:Play()
		end
		track.Ended:Connect(nextTrack)
		nextTrack()
	end
	return self
end

return Audio
