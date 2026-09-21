--!strict
-- Only the live values the world renderer reads. Never send owners, hitVictims, move definitions
-- or cyclic fighter references. Static art and item definitions are already on the client.
local SceneSnapshot = {}
function SceneSnapshot.encode(match: any): any
	local combat = match.combat
	local out: any = { frame = match.frame, hazards = match.stage.visual, projectiles = {}, items = {}, summons = {}, bursts = {} }
	for _, p in combat.projectiles do
		table.insert(out.projectiles, { x = p.x, y = p.y, vx = p.vx, vy = p.vy, w = p.w, h = p.h,
			shape = p.shape, owner = if p.owner then p.owner.index else nil,
			item = if p.itemDef then p.itemDef.id else nil, life = p.life, gravity = p.gravity })
	end
	for _, it in combat.items do
		table.insert(out.items, { id = it.def.id, x = it.x, y = it.y, life = it.life, uses = it.uses,
			held = if it.held then it.held.index else nil, hp = it.hp, onGround = it.onGround })
	end
	for _, pl in combat.plates do
		table.insert(out.items, { id = "SpringPlate", x = pl.x, y = pl.y, life = pl.life, cd = pl.cd })
	end
	for _, s in combat.summons do
		table.insert(out.summons, { type = s.type, x = s.x, y = s.y, w = s.w, h = s.h, r = s.r,
			armed = s.armed, trigger = s.trigger, owner = if s.owner then s.owner.index else nil })
	end
	for _, b in combat.bursts do
		table.insert(out.bursts, { x = b.x, y = b.y, frames = b.frames, radius = (b.rect.x2 - b.rect.x1) / 2 })
	end
	return out
end
return SceneSnapshot
