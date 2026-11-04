--!strict
-- The pop-up a party invite brings (Roblox only; the owner's ask, 2026-11-04): JOIN NAME'S PARTY?
-- with JOIN and NO, and the seconds left before the invite runs out (Parties.INVITE_SECONDS). One at
-- a time: the newest first, the next shown when it is answered or runs out. It decides nothing -
-- JOIN asks the server, which may say the invite has gone.
--
-- Its own ScreenGui, over the lobby and a fight alike: an invite can come while you are in a room.
local Ui = require(script.Parent.Ui)
local PartyPrompt = {}
PartyPrompt.__index = PartyPrompt

PartyPrompt.W, PartyPrompt.H = 380, 104
-- under the queue's card (LobbySocial), which sits at the top centre, 96 px tall from 12
PartyPrompt.TOP = 12 + 96 + 12

-- opts: { accept = (fromId) -> (), decline = (fromId) -> (), now = () -> number }
function PartyPrompt.new(parent: Instance, opts: any): any
	local self = setmetatable({ opts = opts, now = opts.now or os.clock, invites = {} :: { any }, shown = nil :: any }, PartyPrompt)
	local gui = Ui.make("ScreenGui", parent, { Name = "BlockfallPartyInvite", ResetOnSpawn = false, Enabled = false, DisplayOrder = 26,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.gui = gui
	local card = Ui.card(gui, "Invite", Ui.TEAL)
	card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, PartyPrompt.TOP), UDim2.fromOffset(PartyPrompt.W, PartyPrompt.H)
	local title, titleStroke = Ui.faceText(card, "", 20, Ui.TEAL)
	title.Name, title.Position, title.Size = "Title", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 26)
	Ui.fit(title, 12)
	Ui.paintTitle(title, titleStroke, Ui.TEAL)
	local left, leftStroke = Ui.faceText(card, "", 13, Ui.TEAL, Ui.LABEL)
	left.Name, left.Position, left.Size = "Left", UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 18)
	Ui.paintSecondary(left, leftStroke, Ui.TEAL)
	local w = (PartyPrompt.W - 28 - Ui.GAP) / 2
	local join = Ui.button(card, "JOIN", Ui.GREEN, function() self:answer(true) end, { size = 16 })
	join.Name, join.Position, join.Size = "Join", UDim2.fromOffset(14, 60), UDim2.fromOffset(w, 32)
	local no = Ui.button(card, "NO", Ui.PANEL2, function() self:answer(false) end, { size = 16 })
	no.Name, no.Position, no.Size = "No", UDim2.fromOffset(14 + w + Ui.GAP, 60), UDim2.fromOffset(w, 32)
	self.title, self.left = title, left
	return self
end

-- The server's PartyView: its invites, each with the seconds it has left.
function PartyPrompt.set(self: any, view: any)
	if type(view) ~= "table" then return end
	local now = self.now()
	self.invites = {}
	for _, i in view.invites or {} do
		table.insert(self.invites, { from = i.from, name = i.name, untilT = now + (i.left or 0) })
	end
	self:tick()
end

-- Every frame: the countdown, and the next invite when this one runs out.
function PartyPrompt.tick(self: any)
	local now = self.now()
	for k = #self.invites, 1, -1 do
		if self.invites[k].untilT <= now then table.remove(self.invites, k) end
	end
	local i = self.invites[1]
	self.shown = i
	self.gui.Enabled = i ~= nil
	if not i then return end
	self.title.Text = `JOIN {string.upper(i.name)}'S PARTY?`
	local secs = math.ceil(i.untilT - now)
	self.left.Text = `Fight beside them  ·  {secs}s` .. (if #self.invites > 1 then `  ·  {#self.invites - 1} more waiting` else "")
end

function PartyPrompt.answer(self: any, yes: boolean)
	local i = self.shown
	if not i then return end
	table.remove(self.invites, table.find(self.invites, i) :: number)
	if yes then self.opts.accept(i.from) else self.opts.decline(i.from) end
	self:tick()
end

return PartyPrompt
