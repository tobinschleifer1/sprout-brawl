'use strict';
const screens={pick:'Weapon select',bazaar:'Skyhold Bazaar',studio:'Character Studio',map:'Arena vote',combat:'Combat HUD',results:'Results'};
const weapons=[['Sword','All-rounder',6,6,7,6],['Scythe','Reach / combo',6,6,6,5],['Blasters','Zoner',4,5,7,7],['Grimoire','Heavy zoner',5,7,6,5],['Battle Axe','Heavy bruiser',8,8,4,4],['Warpike','Spacer',6,5,5,6],['Gauntlets','Rushdown',4,4,9,8],['War Hammer','Superheavy',9,9,3,3],['Longbow','Precision zoner',6,4,5,6],['Chain Flail','Space control',6,6,5,5],['Shield','Counter attacker',6,7,5,4],['Dual Daggers','Combo monster',3,3,9,9]];
const maps=['Hall of Champions','Bifrost Bridge','Dwarven Forge','Sky Temple','Sunscorch Ruins','Viking Harbor','Crystal Mines','Thunder Canyon','Muspel Peak','Random'];
const fresh=()=>({view:'pick',weapon:0,map:3,rule:'Casual',ready:false,bot:'Normal',damage:[42,86,17,109],stocks:[3,3,3,3],ultimate:[60,100,40,50],name:'My Fighter',group:'Hair',part:0,color:0,pose:'Stand',slot:1,slots:3,dirty:false,locked:false,undo:[],redo:[],gg:false,spectating:false,climb:0});
let state=fresh(),showHints=false;
const $=id=>document.getElementById(id),esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function status(s){$('status').textContent=s;}
function hit(label,x,y,w,h,action){return `<button class="hit" style="left:${x}%;top:${y}%;width:${w}%;height:${h}%" aria-label="${esc(label)}" title="${esc(label)}" data-action="${esc(action)}"></button>`;}
function plate(label,x,y,w,h,action,cls=''){return `<${action?'button':'div'} class="plate ${cls}" style="left:${x}%;top:${y}%;width:${w}%;height:${h}%" ${action?`data-action="${esc(action)}"`:''}>${esc(label)}</${action?'button':'div'}>`;}
function selection(x,y,w,h){return `<div class="selected" style="left:${x}%;top:${y}%;width:${w}%;height:${h}%"></div>`;}
function choices(items,prefix){return '<div class="choices">'+items.map((x,i)=>`<button data-action="${prefix}:${i}">${esc(x)}</button>`).join('')+'</div>';}
function modal(title,body){$('modal-title').textContent=title;$('modal-body').innerHTML=body;if(!$('modal').open)$('modal').showModal();}
function close(){if($('modal').open)$('modal').close();}
function go(view){close();state.view=view;render();status({pick:'Choose your weapon. Ready starts the local voting flow.',bazaar:'Visit the tailor, arcade or fighter gates. Social controls open local panels.',studio:'Editing state is interactive. The illustrated fighter remains a static art reference.',map:'Cast your vote, then continue to rules. Votes here are local examples.',combat:'Use Match controls to demonstrate damage, stocks, ultimate and match events.',results:'Results example. Say GG or return to the room.'}[view]);}
function stats(index,x){let w=weapons[index];return `<div class="plate stats" style="left:${x}%;top:68%;width:23%;height:16.7%"><b>${w[0]}</b><small>${w[1]}</small>${['DMG','DEF','DEX','SPD'].map((v,j)=>`<div><label>${v}</label>${Array.from({length:10},(_,k)=>`<i class="${k<w[j+2]?'on':''}"></i>`).join('')} <span>${w[j+2]}</span></div>`).join('')}</div>`;}
function render(){let s=state,html='',bg='',pos='';$('navigation').innerHTML=Object.entries(screens).map(([k,v])=>`<button data-action="go:${k}" ${s.view===k?'aria-current="page"':''}>${v}</button>`).join('');$('stage').className=(['bazaar','map','results'].includes(s.view)?'family ':'')+(showHints?'show-hints':'');
if(s.view==='pick'){
 bg='weapon-select.png';weapons.forEach((w,i)=>html+=hit(w[0],28+(i%6)*7.45,4+Math.floor(i/6)*15,6.9,15,'weapon:'+i));html+=selection(28+(s.weapon%6)*7.45,4+Math.floor(s.weapon/6)*15,6.9,15);html+=stats(s.weapon,20.5)+stats(1,58.2);html+=plate(s.ready?'READY ✓':'READY',40,87,20,9,'ready',s.ready?'green':'gold');html+=hit('Back to bazaar',1,90,13,8,'go:bazaar')+hit('Change appearance',84.5,89,14.5,9,'go:studio');html+=plate('BOT · '+s.bot,59,64,19,4.5,'bot')+plate('3 STOCKS · '+s.rule.toUpperCase(),78,3,20,7,'rules');html+=plate('HIDE / ROOM',1,19,13,4.5,'lounge');
}
if(s.view==='bazaar'){
 pos='0% 0%';html+=hit('Open Character Studio',15,35,18,12,'go:studio')+hit('Arcade cabinet',72,55,13,21,'arcade')+hit('Enter fighter gates',85,32,14,43,'rooms');['Stamp','Say','People','Map'].forEach((n,i)=>html+=hit(n,8+i*22,87,21,11,'social:'+n));html+=plate('SKY CLIMB',80,5,18,6,'climb');
}
if(s.view==='studio'){
 bg='character-studio.png';html+=hit('Close Character Studio',84,1,15,9,'leave-studio');[1,2,3].forEach((n,i)=>html+=hit('Character slot '+n,1+i*6.3,12.5,6,7,'slot:'+n));html+=hit('Add character slot',20,12,6,7,'add-slot');html+=plate(s.name,8.3,20.1,23.3,5.5,'name');const groups=['Presets','Body','Face','Hair','Outfit','Extras'];groups.forEach((n,i)=>html+=hit(n,42.4+i*9.4,12.5,9,8,'group:'+n));html+=selection(42.4+groups.indexOf(s.group)*9.4,12.5,9,8);html+=plate(s.group.toUpperCase()+' · OPTION '+(s.part+1)+(s.locked?' · LOCKED':''),43.5,23,54,11,null);for(let i=0;i<8;i++)html+=hit('Select '+s.group+' option '+(i+1),44.5+i%4*13,36+Math.floor(i/4)*17,12,16,'part:'+i);html+=selection(44.5+s.part%4*13,36+Math.floor(s.part/4)*17,12,16);for(let i=0;i<13;i++)html+=hit('Color swatch '+(i+1),44.5+i*3.9,70,3.7,7,'color:'+i);html+=selection(44.5+s.color*3.9,70,3.7,7);html+=plate(s.locked?'UNLOCK PART':'LOCK PART',51,80,15.2,6,'lock');html+=hit('Randomize unlocked part',69,80,21,7,'random');['Stand','Run','Jump','Attack','Cheer'].forEach((n,i)=>html+=hit('Preview '+n,3.5+i*7.4,75,7,11,'pose:'+n));html+=selection(3.5+['Stand','Run','Jump','Attack','Cheer'].indexOf(s.pose)*7.4,75,7,11);html+=hit('Turn preview',5,88,13,7,'turn')+hit('Zoom preview',21,88,16,7,'zoom');html+=hit('Undo',41,91,7,7,'undo')+hit('Redo',48,91,8,7,'redo')+hit('Save as new',57,90,12,8,'save-new')+hit('Save and wear',69,90,19,8,'save')+hit('Delete character slot',89,91,10,7,'delete');html+=plate((s.dirty?'UNSAVED':'SAVED FOR SESSION')+' · SLOT '+s.slot,49,3,33,5,null,'toast-badge');
}
if(s.view==='map'){
 pos='0% 100%';for(let i=0;i<9;i++)html+=hit(maps[i],2+i%3*31.7,14+Math.floor(i/3)*24,30.7,23,'map:'+i);html+=hit('Vote Random',36,87,26,12,'map:9');if(s.map<9)html+=selection(2+s.map%3*31.7,14+Math.floor(s.map/3)*24,30.7,23);else html+=selection(36,87,26,12);html+=plate('VOTE: '+maps[s.map],3,2,71,10,null);html+=plate('CONTINUE →',76,2,23,10,'rules','gold');
}
if(s.view==='combat'){
 bg='combat.png';html+=plate(s.rule==='Chaos'?'2:14':'STOCK MATCH',45,2,12,7,null);html+=plate(s.spectating?'STOP WATCHING':'MATCH CONTROLS',77,2,21,6,s.spectating?'stop-watch':'match-controls');for(let i=0;i<4;i++){let x=4+i*24;html+=plate(s.damage[i]+'%',x+12,85,9,6,null);html+=plate('● '.repeat(s.stocks[i])||'OUT',x+6.5,89.5,13.5,3.2,null,'toast-badge');html+=plate('ULT '+s.ultimate[i]+'%',x+2,93,17,3.5,i===0?'ultimate':null,'toast-badge');}html+=plate('LOCAL SHIELD · READY',1,3,22,4,null,'toast-badge');
}
if(s.view==='results'){
 pos='100% 100%';html+=plate(s.gg?'GG! ✓':'SAY GG!',36,86,30,12,'gg','gold');html+=plate('RETURN TO ROOM →',69,92,30,7,'go:pick');
}
$('stage').style.backgroundImage=bg?`url('${bg}')`:'';$('stage').style.backgroundPosition=pos||'center';$('stage').innerHTML=html;
}
const avatarKeys=['name','group','part','color','pose','slot','locked'];
function snapshot(){return Object.fromEntries(avatarKeys.map(k=>[k,state[k]]));}
function edit(fn){state.undo.push(snapshot());state.redo=[];fn();state.dirty=true;render();}
function action(a){const [type,...rest]=a.split(':'),v=rest.join(':');
if(type==='go'){if(state.view==='studio'&&state.dirty&&v!=='studio'){modal('Unsaved changes',`<p>Your character has unsaved edits.</p><div class="choices"><button data-action="save-exit:${v}">Save and continue</button><button class="danger" data-action="discard:${v}">Discard edits</button><button data-action="close">Keep editing</button></div>`);return;}go(v);return;}
if(type==='close'){close();return;}
if(type==='weapon'){state.weapon=+v;state.ready=false;render();status(weapons[+v][0]+' selected. Stats updated; large fighter illustration is a fixed art reference.');}
if(type==='ready'){state.ready=true;render();modal('Ready confirmed — local demo','<p>Both sample players are ready. Continue to cast an arena vote.</p><button data-action="go:map">Choose arena →</button>');}
if(type==='map'){state.map=+v;render();status('Your example vote: '+maps[+v]+'. Continue to rules when ready.');}
if(type==='rules'){modal('Vote for match rules',choices(['Tournament 1v1 · 3 stocks · items off','Casual · 3 stocks · items on','Chaos · 3 minutes · all disasters','Keep Current'],'rule')+'<p class="fine">One local ballot is simulated. No server vote is sent.</p>');}
if(type==='rule'){const r=['Tournament 1v1','Casual','Chaos',state.rule][+v];state.rule=r;render();modal('Rules selected: '+r,'<p>Your example ballot has been accepted.</p><button data-action="launch">Preview match →</button>');}
if(type==='launch'){go('combat');modal('GET READY','<p>'+esc(maps[state.map])+' · '+esc(state.rule)+'</p><p class="fine">Static arena artwork; no gameplay simulation.</p><button data-action="close">GO!</button>');}
if(type==='bot'){modal('Bot proposal',choices(['Easy','Normal','Hard'],'bot-level')+'<p class="fine">Choose a difficulty to propose a change.</p>');}
if(type==='bot-level'){modal('Bot vote',`<p>Change CPU difficulty to ${['Easy','Normal','Hard'][+v]}?</p><button data-action="bot-accept:${v}">Vote yes · simulate acceptance</button>`);}
if(type==='bot-accept'){state.bot=['Easy','Normal','Hard'][+v];close();render();status('Sample ballot passed: '+state.bot+' CPU.');}
if(type==='lounge'){modal('Walkable room · selection hidden','<p>1v1 · '+(state.ready?'1':'0')+'/1 humans ready · CPU '+state.bot+'</p><button data-action="close">ROOM ▲ Reopen</button><p class="fine">The walkable lounge itself is not simulated in this art preview.</p>');}
if(type==='rooms'){modal('Fighters’ Gates','<button data-action="go:pick">Join sample 1v1 room</button><p class="fine">This art-direction preview contains the 1v1 layout. See the prior functional study for 2v2 and 3v3 layouts.</p>');}
if(type==='arcade'){modal('Arcade cabinet','<div class="choices"><button data-action="go:pick">Sit · versus CPU</button><button data-action="watch">Watch sample match</button></div>');}
if(type==='watch'){state.spectating=true;go('combat');}if(type==='stop-watch'){state.spectating=false;go('bazaar');}
if(type==='social'){const lists={Stamp:["GG", "Heart", "Fire", "Ha!", "Skull", "?", "!", "Thumbs up"],Say:["Hello!", "GG!", "One more?", "Nice!", "Good luck!", "Well played!", "Thanks!", "Rematch?", "Wow!", "Oops!", "Let's fight!", "Be right back", "Want to team up?", "Close one!"],People:['You · in bazaar','Sample player · in a match'],Map:["Tailor’s Terrace","Champions’ Square","The Arcade Grove","Fighters’ Gates","Sky Climb"]};modal(v,choices(lists[v],v==='Map'?'warp':'message-'+v)+'<p class="fine">Illustrative local social panel; nothing is sent to other players.</p>');}
if(type.startsWith('message-')){const list=type==='message-Say'?["Hello!", "GG!", "One more?", "Nice!", "Good luck!", "Well played!", "Thanks!", "Rematch?", "Wow!", "Oops!", "Let's fight!", "Be right back", "Want to team up?", "Close one!"]:["GG", "Heart", "Fire", "Ha!", "Skull", "?", "!", "Thumbs up"];close();status('Local preview: '+(list[+v]||'Player selected')+'. Nothing sent to other players.');}
if(type==='warp'){if(+v===0)go('studio');else if(+v===2)action('arcade');else if(+v===3)action('rooms');else if(+v===4)action('climb');else{close();status('Champions’ Square selected.');}}
if(type==='climb'){modal('Sky Climb',`<p>Checkpoint ${state.climb} · Falls 0 · local example</p><div class="choices"><button data-action="checkpoint">Reach next checkpoint</button><button data-action="records">Records</button><button data-action="restart-climb">Restart</button><button data-action="paid-skip">Paid skip information</button></div>`);}
if(type==='checkpoint'){state.climb++;action('climb');}if(type==='restart-climb'){state.climb=0;action('climb');}if(type==='records')modal('Climb records','<p>Speed leaderboard: no example record.</p><p>Level leaderboard: checkpoint '+state.climb+'</p><button data-action="climb">Back to climb</button>');if(type==='paid-skip')modal('Skip checkpoint','<p>In Roblox this opens a purchase prompt. This mockup makes no purchase and displays no invented price.</p>');
if(type==='group'){state.group=v;state.part=0;render();status(v+' category selected. Artwork thumbnails are static; selection state is live.');}
if(type==='part'){if(state.locked){status('Unlock this part before changing it.');return;}edit(()=>state.part=+v);}
if(type==='color'){if(state.locked){status('Unlock this part before changing its color.');return;}edit(()=>state.color=+v);status('Color '+(+v+1)+' selected. The illustration does not recolor.');}
if(type==='pose'){state.pose=v;render();status(v+' preview selected. Animation is not simulated.');}
if(type==='turn'||type==='zoom'){modal('Character preview',`<p>${type==='turn'?'Turn':'Zoom'} is an implementation control. This preview keeps the static concept pose.</p>`);}
if(type==='lock')edit(()=>state.locked=!state.locked);
if(type==='random'){if(state.locked){status('Part locked — randomization skipped.');return;}edit(()=>{state.part=(state.part+1+Math.floor(Math.random()*7))%8;state.color=Math.floor(Math.random()*13);});}
if(type==='name')modal('Fighter name',`<label class="field">Name <input id="fighter-name" maxlength="24" value="${esc(state.name)}"></label><button data-action="name-save">Apply</button>`);
if(type==='name-save'){const name=$('fighter-name').value.trim();if(!name)return;edit(()=>state.name=name);close();}
if(type==='slot'){edit(()=>state.slot=+v);status('Slot '+v+' selected for this local editing example.');}
if(type==='add-slot'||type==='save-new'){edit(()=>state.slot=++state.slots);status('New local slot '+state.slot+' created.');}
if(type==='undo'||type==='redo'){let from=state[type],to=state[type==='undo'?'redo':'undo'];if(!from.length){status('Nothing to '+type+'.');return;}to.push(snapshot());Object.assign(state,from.pop());state.dirty=true;render();}
if(type==='save'){state.dirty=false;state.saved=snapshot();render();status('Saved and worn in this prototype session. Reloading resets the example.');}
if(type==='leave-studio')action('go:bazaar');
if(type==='save-exit'){state.saved=snapshot();state.dirty=false;go(v);}
if(type==='discard'){Object.assign(state,state.saved||Object.fromEntries(avatarKeys.map(k=>[k,fresh()[k]])));state.dirty=false;state.undo=[];state.redo=[];go(v);}
if(type==='delete')modal('Delete this character slot?','<p>This affects only the local mockup.</p><button class="danger" data-action="delete-confirm">Delete slot</button>');
if(type==='delete-confirm'){edit(()=>{state.slot=1;state.slots=Math.max(1,state.slots-1);state.name='My Fighter';});close();}
if(type==='gg'){state.gg=true;render();status('GG! shown locally. No message sent.');}
if(type==='match-controls')modal('Match state preview','<div class="choices"><button data-action="damage">Take 18% damage</button><button data-action="ko">Lose one stock</button><button data-action="charge">Charge ultimate</button><button data-action="event:DISASTER INCOMING">Disaster warning</button><button data-action="event:SUDDEN DEATH">Sudden death</button><button data-action="event:3 HIT COMBO">Combo callout</button><button data-action="go:results">End match → Results</button></div>');
if(type==='damage'){state.damage[0]+=18;close();render();status('Local damage updated.');}
if(type==='ko'){state.stocks[0]=Math.max(0,state.stocks[0]-1);state.damage[0]=0;close();render();status(state.stocks[0]?'Stock lost; damage reset.':'Local fighter eliminated.');}
if(type==='charge'){state.ultimate[0]=100;close();render();status('Ultimate ready. Select the local meter to activate.');}
if(type==='ultimate'){if(state.ultimate[0]<100){status('Ultimate not ready. Charge it from Match controls.');return;}state.ultimate[0]=0;render();modal('ULTIMATE!','<p>Local ultimate activation example.</p>');}
if(type==='event'){close();modal(v,'<p>Example event overlay. Only one priority callout is shown at a time.</p>');}
}
document.addEventListener('click',e=>{const b=e.target.closest('[data-action]');if(b)action(b.dataset.action);});
$('hints').addEventListener('click',()=>{showHints=!showHints;$('hints').setAttribute('aria-pressed',showHints);render();});
$('reset').addEventListener('click',()=>{close();state=fresh();render();status('Example reset. Choose your weapon, then Ready.');});
render();
