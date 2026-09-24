// Builds the animation production doc: every key pose the revamp's hand-drawn sprites must cover,
// with its exact frames, what to draw, the game's own reference numbers, and its basic placeholder.
//
// Generated, never edited: rerun it after drawing (or after a balance change) and the doc follows.
// Usage: node web/tools/build-animation-doc.mjs <out.html>
import fs from 'node:fs';
import { manifest } from '../src/data/animations.js';
import { buildSheets, CELL } from './basic-sprites.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';

const m = manifest();
const sheets = buildSheets();
const frames = sheets.flatMap((s) => s.index);
const find = (group, anim, key) => frames.find((f) => (f.sheet === group || f.sheet.startsWith(group + '-')) && f.anim === anim && f.key === key);
// A hand-drawn replacement lands as art/drawn/<Sheet>.png with the same cell layout; the doc marks
// those poses drawn. None exist yet.
const drawn = new Set(fs.existsSync('art/drawn/drawn.json') ? JSON.parse(fs.readFileSync('art/drawn/drawn.json', 'utf8')) : []);

const data = {
  totals: m.totals, cell: CELL,
  shared: m.shared.map((a) => ({ id: a.id, label: a.label, frames: a.frames, driver: a.driver, note: a.note,
    keys: a.keys.map((k, i) => ({ name: k.name, brief: k.brief || '', f: find('Shared', a.id, i) })) })),
  weapons: m.weapons.map((w) => ({ id: w.id, archetype: w.archetype, moves: w.moves.map((mv) => ({
    id: mv.id, label: mv.label, template: mv.template, startup: mv.startup, active: mv.active, recovery: mv.recovery, total: mv.total,
    keys: mv.keys.map((k, i) => ({ ...k, f: find(w.id, mv.id, i) })) })) })),
  vfx: m.vfx,
  drawn: [...drawn],
};
const sheetCss = sheets.map((s) => `.s-${s.id.replace(/[^A-Za-z0-9-]/g, '')}{background-image:url(data:image/png;base64,${s.raster.png().toString('base64')})}`).join('\n');
const weaponIds = WEAPONS.map((w) => w.id);

const html = `<title>Blockfall Animation Bible</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Pixelify+Sans:wght@500;700&family=Atkinson+Hyperlegible:wght@400;700&family=JetBrains+Mono:wght@400;600&display=swap">
<style>
:root{color-scheme:dark;--ground:#0B1017;--panel:#131A24;--panel2:#18212D;--line:#263142;--line2:#33404F;--ink:#E9E5DB;--muted:#9AA5B3;--dim:#6B7684;
--amber:#E5AB65;--amber-ink:#2A1D0F;--hot:#F08B60;--gold:#FFD58A;--cool:#7FD4FF;--safe:#8EE86A;
--display:"Pixelify Sans","Arial Black",system-ui,sans-serif;--body:"Atkinson Hyperlegible",system-ui,sans-serif;--mono:"JetBrains Mono",ui-monospace,Menlo,monospace}
*{box-sizing:border-box} body{background:var(--ground);color:var(--ink);font:15px/1.55 var(--body)}
a{color:var(--cool)} :focus-visible{outline:2px solid var(--gold);outline-offset:2px}
.wrap{max-width:1240px;margin:0 auto;padding-inline:20px;padding-block:28px 80px}
.eyebrow{font:600 12px var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--amber);margin:0 0 10px}
h1{font:700 clamp(36px,6vw,60px)/1 var(--display);margin:0 0 14px}
h2{font:700 30px/1.1 var(--display);margin:40px 0 12px}
h3{font:700 19px/1.25 var(--body);margin:0}
p{max-width:72ch;margin:0 0 12px} .muted{color:var(--muted)}
code{font-family:var(--mono);font-size:.88em;background:var(--panel2);border:1px solid var(--line);border-radius:4px;padding:1px 5px}
.stats{display:flex;flex-wrap:wrap;gap:12px 30px;margin:18px 0 6px;font:13px var(--mono);color:var(--muted)}
.stats b{display:block;font:700 28px/1.1 var(--display);color:var(--gold)}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,340px),1fr));gap:14px}
.box{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px}
.box ol,.box ul{margin:0;padding-left:20px} .box li{margin:5px 0;font-size:14.5px}
.pbar{display:flex;height:10px;border-radius:5px;overflow:hidden;background:var(--line);margin:6px 0 2px}
.pbar i{display:block} .pb-drawn{background:var(--safe)} .pb-basic{background:var(--amber)} .pb-planned{background:#46566C}
.legend{display:flex;flex-wrap:wrap;gap:6px 18px;font:12px var(--mono);color:var(--muted)} .legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:8px}
table{border-collapse:collapse;width:100%;font-size:14px;min-width:620px} th,td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--line);vertical-align:middle}
th{font:600 11px var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--muted);background:var(--panel2)} tr:last-child td{border-bottom:0}
td.num{text-align:right;font:13px var(--mono);font-variant-numeric:tabular-nums}
tr.pick{cursor:pointer} tr.pick:hover td{background:var(--panel2)} tr.sel td{background:#1C2330}
.toolbar{position:sticky;top:env(safe-area-inset-top,0px);z-index:5;background:var(--ground);padding:12px 0;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:10px;align-items:center}
select,input{font:14px var(--body);background:var(--panel2);color:var(--ink);border:1px solid var(--line2);border-radius:6px;padding:7px 10px}
input{min-width:0;flex:1 1 180px}
.anim{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px;margin:16px 0}
.anim header{display:flex;flex-wrap:wrap;gap:6px 14px;align-items:baseline;margin-bottom:8px}
.anim .meta{font:12px var(--mono);color:var(--muted)}
.strip{display:flex;height:16px;border-radius:3px;overflow:hidden;margin:6px 0 12px}
.strip span{display:block;height:100%;border-right:1px solid var(--ground)} .ph-startup{background:#8A6A3E}.ph-active{background:var(--hot)}.ph-recovery{background:#46566C}
.keys{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,250px),1fr));gap:10px}
.key{background:var(--panel2);border:1px solid var(--line);border-radius:8px;padding:10px;display:grid;grid-template-columns:auto minmax(0,1fr);gap:10px;align-items:start}
.thumb{width:${CELL.w}px;height:${CELL.h}px;background-color:#070B10;background-repeat:no-repeat;image-rendering:pixelated;border-radius:4px;flex:none}
.thumb.none{display:grid;place-items:center;font:11px var(--mono);color:var(--dim);text-align:center;padding:6px}
@media (max-width:420px){.key{grid-template-columns:minmax(0,1fr)}}
.key b{display:block;font-size:14px}
.key .fr{font:12px var(--mono);color:var(--muted)}
.key .brief{font-size:13px;color:var(--muted);margin:4px 0}
.key .ref{font:11px var(--mono);color:var(--dim)}
.chip{display:inline-block;font:600 10.5px var(--mono);letter-spacing:.06em;text-transform:uppercase;padding:1px 7px;border-radius:999px;margin-right:4px}
.c-basic{background:#3A3029;color:var(--amber)} .c-planned{background:#232B37;color:var(--muted)} .c-drawn{background:#1B2E1C;color:var(--safe)}
.c-startup{background:#3A2E1E;color:#E0B070} .c-active{background:#4A2418;color:var(--hot)} .c-recovery{background:#1E2733;color:#9FB0C6}
.empty{color:var(--muted);padding:30px 0}
${sheetCss}
</style>
<div class="wrap">
<p class="eyebrow">Blockfall · revamp · animation production</p>
<h1>The Animation Bible</h1>
<p style="font-size:18px">Every animation Blockfall's hand-drawn sprites have to cover, pose by pose. This is the work queue for the art. Each key pose has the exact game frames it's shown on, what it has to show, the numbers the game currently uses for it, and a <b>basic sprite</b> to draw over.</p>
<p class="muted">Generated from the game itself (<code>web/src/data/animations.js</code>, <code>web/tools/basic-sprites.mjs</code>), never typed in, so it can't drift from the frame data. After drawing, or after any balance change, rebuild it with <code>node web/tools/build-animation-doc.mjs</code>.</p>
<div class="stats" id="stats"></div>
<div class="pbar" id="pbar"></div>
<div class="legend"><span><i class="pb-drawn"></i>drawn by hand</span><span><i class="pb-basic"></i>basic placeholder in game</span><span><i class="pb-planned"></i>no version yet</span></div>

<h2>How a pose gets made</h2>
<div class="grid2">
  <div class="box"><h3 style="margin-bottom:8px">Workflow</h3><ol>
    <li>Generate the underlays: <code>node web/tools/basic-sprites.mjs art/basic</code>. That's one sheet per weapon, plus the shared sheets, in the same ${CELL.w}×${CELL.h} cell layout this doc shows.</li>
    <li>Open the sheet in Aseprite as a reference layer, and draw each pose over its basic sprite. Keep the feet on the cell's floor point (x ${CELL.footX}, y ${CELL.footY}).</li>
    <li>Use one layer per tint mask: <b>outline, primary, secondary, tertiary</b> (greyscale ramps, recoloured per avatar). The weapon goes on its own layer.</li>
    <li>Tag each pose <code>Weapon/Move/key</code>, and set its frame duration to the frame count listed here (the build checks the total matches the move).</li>
    <li>Export to <code>art/drawn/&lt;Sheet&gt;.png</code>, add the pose to <code>art/drawn/drawn.json</code>, and rebuild this doc. The pose turns green.</li>
  </ol></div>
  <div class="box"><h3 style="margin-bottom:8px">Rules every pose follows</h3><ul>
    <li><b>8 pixels per stud.</b> A fighter is 42 px tall, and the hurtbox is 18 px wide. The body must not stick out past the hurtbox by more than a couple of pixels.</li>
    <li><b>Anticipation is sacred.</b> It's the frame the defender reacts to, so exaggerate it and never shorten it.</li>
    <li><b>Contact is brightest.</b> The active frames carry the highest values in the move.</li>
    <li><b>Hold, don't tween.</b> Each pose is shown for every frame in its range, then snaps to the next.</li>
    <li><b>Invincible frames get a 1 px pale outline</b> (spot dodge 3–14, air dodge 3–13).</li>
    <li><b>No blood.</b> Roblox's content rules count realistic blood toward the maturity rating, so use crimson shards and sparks instead.</li>
    <li>Use the reference numbers (lean, weapon angle, squash) as the target pose, not as a cage. Character is the point.</li>
  </ul></div>
</div>

<h2>Progress by group</h2>
<div class="tablewrap"><table><thead><tr><th>Group</th><th class="num">Animations</th><th class="num">Key poses</th><th class="num">Frames covered</th><th style="width:34%">Status</th></tr></thead><tbody id="groups"></tbody></table></div>

<h2 id="browse">Browse</h2>
<div class="toolbar">
  <label class="muted" for="grp">Group</label><select id="grp"></select>
  <label class="muted" for="st">Status</label><select id="st"><option value="">any</option><option value="basic">basic</option><option value="planned">no version yet</option><option value="drawn">drawn</option></select>
  <input id="q" type="search" placeholder="Search a move, pose or phase (try: contact, ledge, Crescent)" aria-label="Search">
</div>
<div id="list"></div>

<h2>Effects (flipbooks)</h2>
<p class="muted">These play over the fighters rather than being body poses. "Basic" means the game already draws a procedural version today.</p>
<div class="tablewrap"><table><thead><tr><th>Effect</th><th class="num">Frames</th><th>Status</th></tr></thead><tbody id="vfx"></tbody></table></div>
</div>
<script>
(function(){
"use strict";
const D=${JSON.stringify(data)};
const W=${JSON.stringify(weaponIds)};
const drawnSet=new Set(D.drawn);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function status(group,anim,k){const id=group+'/'+anim+'/'+k.name;if(drawnSet.has(id))return 'drawn';return k.f&&k.f.basic?'basic':'planned';}
function thumb(k){if(!k.f||!k.f.basic)return '<div class="thumb none">no version<br>yet</div>';return '<div class="thumb s-'+k.f.sheet.replace(/[^A-Za-z0-9-]/g,'')+'" style="background-position:-'+k.f.x+'px -'+k.f.y+'px" role="img" aria-label="basic sprite"></div>';}
function ref(k){if(!k.f||!k.f.ref)return '';const r=k.f.ref;return '<div class="ref">lean '+r.lean+'°'+(r.weapon!=null?' · weapon '+r.weapon+'°':'')+' · squash '+r.squash[0]+'×'+r.squash[1]+(r.smear>0.05?' · smear '+r.smear:'')+(r.spin?' · spin '+r.spin+'°':'')+(r.opacity<1?' · opacity '+r.opacity:'')+'</div>';}
// groups
const groups=[{id:'Shared',label:'Shared body',anims:D.shared.map(a=>({id:a.id,label:a.label,meta:a.frames+' frames · chosen by '+a.driver+(a.note?' · '+a.note:''),keys:a.keys.map(k=>({...k,phase:null}))}))}]
  .concat(D.weapons.map(w=>({id:w.id,label:w.id+' ('+w.archetype+')',anims:w.moves.map(mv=>({id:mv.id,label:mv.id+' · '+mv.label,move:mv,meta:mv.startup+' startup · '+mv.active+' active · '+mv.recovery+' recovery = '+mv.total+' frames',keys:mv.keys}))})));
let tot={drawn:0,basic:0,planned:0};
const gt=document.getElementById('groups');
for(const g of groups){const c={drawn:0,basic:0,planned:0};let fr=0;for(const a of g.anims){for(const k of a.keys){c[status(g.id,a.id,k)]++;}if(a.move)fr+=a.move.total;}
  for(const s in c)tot[s]+=c[s];const n=c.drawn+c.basic+c.planned;
  const tr=document.createElement('tr');tr.className='pick';tr.tabIndex=0;tr.innerHTML='<td>'+esc(g.label)+'</td><td class="num">'+g.anims.length+'</td><td class="num">'+n+'</td><td class="num">'+(fr||'n/a')+'</td><td><div class="pbar">'+['drawn','basic','planned'].map(s=>'<i class="pb-'+s+'" style="width:'+(100*c[s]/n)+'%"></i>').join('')+'</div><span class="muted" style="font:12px var(--mono)">'+c.drawn+' drawn · '+c.basic+' basic · '+c.planned+' none</span></td>';
  const go=()=>{grp.value=g.id;render();document.getElementById('browse').scrollIntoView({behavior:'smooth'});};tr.addEventListener('click',go);tr.addEventListener('keydown',e=>{if(e.key==='Enter')go();});gt.appendChild(tr);}
const allKeys=tot.drawn+tot.basic+tot.planned;
document.getElementById('stats').innerHTML='<span><b>'+D.totals.all.toLocaleString()+'</b>things to draw in all</span><span><b>'+allKeys.toLocaleString()+'</b>body and move key poses</span><span><b>'+D.totals.vfxFrames+'</b>effect frames</span><span><b>'+tot.basic.toLocaleString()+'</b>have a basic sprite</span><span><b>'+tot.drawn+'</b>drawn by hand</span>';
document.getElementById('pbar').innerHTML=['drawn','basic','planned'].map(s=>'<i class="pb-'+s+'" style="width:'+(100*tot[s]/allKeys)+'%"></i>').join('');
// browse
const grp=document.getElementById('grp'),st=document.getElementById('st'),q=document.getElementById('q'),list=document.getElementById('list');
grp.innerHTML=groups.map(g=>'<option value="'+g.id+'">'+esc(g.label)+'</option>').join('')+'<option value="*">Everything ('+allKeys+' poses)</option>';
function render(){const want=st.value,text=q.value.trim().toLowerCase();let out='',shown=0;
  for(const g of groups){if(grp.value!=='*'&&grp.value!==g.id)continue;
    for(const a of g.anims){const keys=a.keys.filter(k=>{const s=status(g.id,a.id,k);if(want&&s!==want)return false;if(!text)return true;return (g.id+' '+a.label+' '+k.name+' '+(k.phase||'')+' '+(k.brief||'')).toLowerCase().includes(text);});
      if(!keys.length)continue;shown+=keys.length;
      let strip='';if(a.move){strip='<div class="strip" aria-hidden="true">'+a.move.keys.map(k=>'<span class="ph-'+k.phase+'" style="flex:'+(k.to-k.from)+'" title="'+esc(k.name)+' · frames '+k.from+'–'+(k.to-1)+'"></span>').join('')+'</div>';}
      out+='<article class="anim"><header><h3>'+esc(g.id==='Shared'?a.label:g.id+' · '+a.label)+'</h3><span class="meta">'+esc(a.meta)+'</span></header>'+strip+'<div class="keys">'+keys.map(k=>{const s=status(g.id,a.id,k);const fr=k.from!=null?'frames '+k.from+'–'+(k.to-1)+' · <b style="display:inline;color:var(--ink)">'+(k.to-k.from)+'</b> frame'+(k.to-k.from===1?'':'s'):(k.f&&k.f.basic?'sample: '+esc(JSON.stringify(D.shared.find(x=>x.id===a.id).keys.find(x=>x.name===k.name)?.f?.name||'')):'');
        return '<div class="key">'+thumb(k)+'<div><b>'+esc(k.name)+'</b><div class="fr">'+(k.from!=null?fr:'')+'</div><div style="margin:4px 0"><span class="chip c-'+s+'">'+(s==='planned'?'no version':s)+'</span>'+(k.phase?'<span class="chip c-'+k.phase+'">'+k.phase+'</span>':'')+'</div>'+(k.brief?'<div class="brief">'+esc(k.brief)+'</div>':'')+ref(k)+'</div></div>';}).join('')+'</div></article>';}}
  list.innerHTML=out||'<p class="empty">Nothing matches that filter.</p>';}
for(const el of [grp,st])el.addEventListener('change',render);q.addEventListener('input',render);
render();
// effects
document.getElementById('vfx').innerHTML=D.vfx.map(v=>'<tr><td>'+esc(v.label)+'</td><td class="num">'+v.frames+'</td><td><span class="chip c-'+(v.procedural?'basic':'planned')+'">'+(v.procedural?'basic':'no version')+'</span></td></tr>').join('');
})();
</script>
`;
const out = process.argv[2] || 'animation-bible.html';
fs.writeFileSync(out, html);
console.log(`wrote ${out}: ${(html.length / 1024).toFixed(0)} KB, ${m.totals.all} items`);
