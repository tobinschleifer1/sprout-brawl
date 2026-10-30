--!strict
-- Counting what players do (docs/briefs/retention-plan.md, step 0), so each later step has a
-- baseline to beat: custom events to Roblox's AnalyticsService, read in the Creator Dashboard.
--
-- Events: session_start, session_end, queue (format), fill_bots (format), new_opponents (format),
-- match_finished (counted / capped / cpu / ranked), level_up (level). Up to three fields each, sent
-- as the dashboard's custom fields "key=value" in a fixed order. Never throws: a missing service or a
-- rejected call is skipped, because counting must never break playing.
local Analytics = {}

-- The AnalyticsService (set by the server entry point); nil outside Roblox or in tests.
Analytics.service = nil :: any
-- Every event sent this session (most recent last, at most KEEP), for the tests and for Studio.
Analytics.KEEP = 200
Analytics.sent = {} :: { any }

function Analytics.event(player: any, name: string, fields: { [string]: any }?)
	local f: { [string]: any } = fields or {}
	local keys = {}
	for k in f do table.insert(keys, k) end
	table.sort(keys)
	local custom = {}
	for i = 1, math.min(3, #keys) do custom[i] = `{keys[i]}={tostring(f[keys[i]])}` end
	table.insert(Analytics.sent, { name = name, userId = player and player.UserId, custom = custom })
	while #Analytics.sent > Analytics.KEEP do table.remove(Analytics.sent, 1) end
	local svc = Analytics.service
	if not svc then return end
	pcall(function()
		local enums = (Enum :: any).AnalyticsCustomFieldKeys
		local map = {}
		for i, v in custom do map[enums["CustomField0" .. i].Name] = v end
		svc:LogCustomEvent(player, name, 1, map)
	end)
end

return Analytics
