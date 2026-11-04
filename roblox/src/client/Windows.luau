--!strict
-- One lobby window at a time (Roblox only; the owner's ask, 2026-11-04): the Shop, the Locker,
-- Settings, the climb's records, the PLAY and MAP panels and the Character Studio each register
-- here, and opening one closes whichever others are open. Before this, each opened over the last,
-- and three were up at once - Shop, Settings and PLAY stacked on each other.
--
-- A window that cannot simply be shut (the Character Studio asks before throwing away unsaved
-- work) registers with `keep = true`: opening it closes the others, but nothing closes it.
local Windows = {}
Windows.__index = Windows

function Windows.new(): any
	return setmetatable({ list = {} :: { any } }, Windows)
end

-- `w`: { isOpen = () -> boolean, close = () -> (), keep = boolean? }
function Windows.add(self: any, name: string, w: any)
	table.insert(self.list, { name = name, isOpen = w.isOpen, close = w.close, keep = w.keep })
end

-- `name` is about to open: close every one that is open. (It is shut itself, so that is the others.)
function Windows.opening(self: any, _name: string)
	for _, w in self.list do
		if not w.keep and w.isOpen() then w.close() end
	end
end

-- Toggle `name`: close it if open, else close the others and open it.
function Windows.toggle(self: any, name: string, isOpen: () -> boolean, open: () -> (), close: () -> ())
	if isOpen() then close() else self:opening(name); open() end
end

return Windows
