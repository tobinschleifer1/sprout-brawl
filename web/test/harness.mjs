import { Match } from '../src/engine/match.js';
import { buildLoadout } from '../src/data/loadout.js';
import { STAGES } from '../src/data/stages/index.js';
export const EMPTY = () => ({ x:0,y:0,jump:false,light:false,heavy:false,dodge:false,guard:false,grab:false,taunt:false,pickup:false,
  jumpHeld:false,guardHeld:false,heavyHeld:false,lightHeld:false,downTap:false,anyPress:false });
export class FakeInput {
  constructor(){ this.state=new Map(); this.kb2Active=false; }
  poll(){} set(s,p){ this.state.set(s, Object.assign(EMPTY(), p)); }
  clear(s){ this.state.set(s, EMPTY()); } get(s){ return this.state.get(s) || EMPTY(); }
}
export function makeMatch(o={}){
  const input=new FakeInput();
  const m=new Match({ mode:o.mode||'StockFFA', stage:STAGES.find(s=>s.id===(o.stageId||'FoundryFloor')), input,
    stocks:o.stocks??3, timeLimit:o.timeLimit??180, items:false,
    // `loadouts` takes [avatarId, weaponId] pairs; `fighters` still takes legacy character ids.
    fighters:(o.loadouts
      ? o.loadouts.map(([a,w],i)=>{ const L=buildLoadout(a,w); return {char:L,skin:0,team:i,source:'p'+i,isBot:false,name:L.weapon.id}; })
      : (o.fighters||[['Classic','Sword'],['Noir','Sword']]).map(([a,w],i)=>{ const L=buildLoadout(a,w); return {char:L,skin:0,team:i,source:'p'+i,isBot:false,name:L.weapon.id}; })) });
  m._input=input; return m;
}
export const skipCountdown=(m)=>{ while(m.state==='countdown') m.step(); return m; };
