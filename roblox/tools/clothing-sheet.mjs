// Offline design proof, not a k1 extension. Uses fresh Lune loaders and installs each design in
// the default option's private in-memory slot before calling the SHIPPING KitPortrait renderer.
// No generated data or runtime source is edited; the temporary helper is always removed.
//
// node tools/clothing-sheet.mjs <out-dir> [--self-test]
// Emits labelled PNGs per piece/pack, contact sheets, baseline controls, and index.json containing
// rectangle/real Frame counts and warm draw timings. Requires only node + lune (no image packages).
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cwd = fileURLToPath(new URL('../', import.meta.url));
const out = path.resolve(process.argv[2] || '/tmp/blockfall-clothing');
const helper = path.join(cwd, 'tools', `.clothing-sheet-${process.pid}.luau`);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'blockfall-clothing-'));
fs.mkdirSync(out, { recursive: true });
const source = String.raw`
--!nocheck
local fs, luau, process, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/process"), require("@lune/serde")
local Rbx, Recorder = require("@lune/roblox"), require("./recorder")
local function fresh()
 return luau.load(fs.readFile("tests/loader.luau"), { environment = { require = require }, injectGlobals = true })()
end
local initial = fresh()
local data, Kit = initial.load("RobloxClothing"), initial.load("AvatarKit")
local function validate(d)
 local packs, ids, slots, sums = {}, {}, {}, {}
 for _, p in d.packs do
  assert(not packs[p.id], "duplicate pack")
  packs[p.id], slots[p.id], sums[p.id] = p, {}, 0
 end
 for _, v in d.items do
  assert(type(v.id) == "string" and string.match(v.id, "^[a-z][a-z0-9_]+$") and not ids[v.id], "duplicate/invalid item id")
  ids[v.id] = true
  assert(type(v.name) == "string" and #v.name > 0, "missing name")
  assert(Kit.category(v.category), "unknown category")
  assert(table.find({"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"}, v.rarity), "unknown rarity")
  assert(packs[v.pack], "unknown pack")
  assert(not slots[v.pack][v.category], "pack occupies category twice")
  slots[v.pack][v.category] = true
  local price = d.priceTiers[v.priceTier]
  assert(type(price) == "number" and price > 0 and price % 1 == 0, "invalid price tier")
  sums[v.pack] += price
  assert(type(v.layers) == "table" and #v.layers > 0, "empty layers")
  if v.trim then assert(v.category == "headwear" and v.trim % 1 == 0 and v.trim >= 0 and v.trim <= 20, "invalid hair trim") end
  for _, l in v.layers do
   local p = Kit.KIT.parts[l.part]
   assert(p and not p.of, "unknown puppet piece")
   assert(type(l.z) == "number" and l.z % 1 == 0 and not l.base, "invalid layer order/base mask")
   assert(l.x % 1 == 0 and l.y % 1 == 0 and l.x >= 0 and l.y >= 0, "invalid layer offset")
   assert(#l.rows > 0 and l.y + #l.rows <= p.h, "layer exceeds canvas height")
   assert(v.category ~= "hair" or l.hair == true, "hair must respect hat trim")
   local painted = 0
   for _, row in l.rows do
    assert(l.x + #row <= p.w, "layer exceeds canvas width")
    for ch in string.gmatch(row, ".") do
     if ch ~= "." then
      local role = Kit.KIT.roles[ch]
      assert(role and role.slot and not role.fixed, "unknown or fixed colour role")
      painted += 1
     end
    end
   end
   assert(painted > 0, "empty grid")
  end
 end
 for id, p in packs do assert(p.suggestedPriceRobux > 0 and p.suggestedPriceRobux < sums[id], "pack is not discounted") end
end
validate(data)
local mutationCount = 0
if process.args[2] == "--self-test" then
 local function reject(change)
  local d = serde.decode("json", serde.encode("json", data))
  change(d)
  assert(not pcall(validate, d), "validator accepted a deliberate mutation")
  mutationCount += 1
 end
 reject(function(d) d.items[2].id = d.items[1].id end)
 reject(function(d) d.items[1].layers[1].x = 99 end)
 reject(function(d) d.items[1].layers[1].y = 99 end)
 reject(function(d) d.items[1].layers[1].rows[1] = "?" end)
 reject(function(d) d.items[1].layers[1].rows[1] = "w" end)
 reject(function(d) d.items[1].layers = {} end)
 reject(function(d) d.items[1].category = "wings" end)
 reject(function(d) d.items[1].priceTier = "free" end)
 reject(function(d) d.items[1].pack = "absent" end)
 reject(function(d) d.items[1].rarity = "absent" end)
 reject(function(d) d.items[2].category = d.items[1].category end)
 reject(function(d) d.packs[1].suggestedPriceRobux = 999 end)
 reject(function(d) d.items[4].layers[1].hair = nil end)
end
local ways = {
 { id = "midnight", colours = {skin=6, hair=11, eyes=9, top=16, trim=14, bottom=4, shoes=17, accessory=17} },
 { id = "daybreak", colours = {skin=1, hair=5, eyes=3, top=0, trim=6, bottom=21, shoes=0, accessory=7} },
}
local entries = {{ id = "baseline", name = "Default kit", kind = "baseline", items = {} }}
for _, v in data.items do table.insert(entries, {id=v.id, name=v.name, pack=v.pack, category=v.category, kind="piece", items={v}}) end
for _, p in data.packs do
 local picked = {}
 for _, v in data.items do if v.pack == p.id then table.insert(picked, v) end end
 table.insert(entries, {id=p.id, name=p.name, pack=p.id, kind="pack", items=picked})
end
local frames, metrics = {}, {}
for _, entry in entries do
 for _, way in ways do
  -- Fresh caches per outfit. The replaced option retains its k1 id/index only inside this process;
  -- the emitted names are catalogue ids, never fake distributable character codes.
  local Loader = fresh()
  local kit = Loader.load("AvatarKit")
  local spec = kit.sanitize({colours=way.colours})
  for _, item in entry.items do
   local cat = kit.category(item.category)
   for i, option in cat.options do
    if option.id == spec.parts[item.category] then
     local replacement = table.clone(option)
     replacement.layers, replacement.trim = item.layers, item.trim
     cat.options[i] = replacement
     break
    end
   end
  end
  local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
  local Portrait = Loader.loadFrom("src/client/", "KitPortrait")
  local code = kit.encode(spec)
  local shapes = Recorder.install(Canvas)
  local rectangleCounts = {}
  local variants = {
   {id="portrait", w=150, h=230, half=false},
   {id="stud26", w=100, h=160, scale=26, half=false},
   {id="match26", w=40, h=42, scale=26/Portrait.HEIGHT, half=true},
  }
  for _, v in variants do
   local c = Recorder.canvas(Canvas, v.w, v.h)
   table.clear(shapes)
   if v.scale then Canvas.setTransform(c, v.scale, 0, 0, -v.scale, v.w/2, v.h-5)
   else Portrait.frame(c, "figure", v.w, v.h) end
   Portrait.figure(c, code, 0, 0, 1, v.half)
   assert(#shapes > 0, "empty portrait")
   rectangleCounts[v.half] = #shapes
   table.insert(frames, {id=entry.id, name=entry.name, kind=entry.kind, pack=entry.pack, category=entry.category,
    colourway=way.id, view=v.id, w=v.w, h=v.h, shapes=table.clone(shapes)})
  end
  -- Real Canvas2D + real Lune Roblox Frames, not recorder timings. Each LOD gets a fresh canvas.
  local Real = luau.load(fs.readFile("src/client/Canvas2D.luau"), { environment = {
   Instance=Rbx.Instance, UDim=Rbx.UDim, UDim2=Rbx.UDim2, Vector2=Rbx.Vector2, Color3=Rbx.Color3,
  }, injectGlobals=true })()
  Real.IMAGES = false
  for k, v in Real do Canvas[k] = v end
  Canvas.IMAGES = false
  for _, half in {false, true} do
   local root = Rbx.Instance.new("Frame")
   local c = Canvas.inFrame(root)
   local function draw()
    local scale = if half then 26/Portrait.HEIGHT else 26
    Canvas.setTransform(c, scale, 0, 0, -scale, 80, 160)
    Portrait.figure(c, code, 0, 0, 1, half)
    Canvas.finish(c)
   end
   draw()
   local before = root:GetDescendants()
   local start = os.clock()
   for _ = 1, 100 do draw() end
   local ms = (os.clock()-start)*10
   local after = root:GetDescendants()
   assert(#after == #before, "warm draw changed Frame count")
   for i, child in before do assert(after[i] == child, "warm draw replaced a Frame") end
   local count = 0
   for _, child in root:GetDescendants() do if child:IsA("Frame") then count += 1 end end
   table.insert(metrics, {id=entry.id, colourway=way.id, half=half, rectangles=rectangleCounts[half], frames=count, warmDrawMs=ms})
   root:Destroy()
  end
 end
end
fs.writeFile(process.args[1], serde.encode("json", {catalogue=data, colourways=ways, frames=frames, metrics=metrics, mutationsCaught=mutationCount}))
`;

// A tiny built-in label font keeps the PNG tool as dependency-free as the existing kit tools.
const glyphs = {
 A:'01110/10001/10001/11111/10001/10001/10001',B:'11110/10001/10001/11110/10001/10001/11110',C:'01111/10000/10000/10000/10000/10000/01111',
 D:'11110/10001/10001/10001/10001/10001/11110',E:'11111/10000/10000/11110/10000/10000/11111',F:'11111/10000/10000/11110/10000/10000/10000',
 G:'01111/10000/10000/10111/10001/10001/01111',H:'10001/10001/10001/11111/10001/10001/10001',I:'111/010/010/010/010/010/111',
 J:'00111/00010/00010/00010/10010/10010/01100',K:'10001/10010/10100/11000/10100/10010/10001',L:'10000/10000/10000/10000/10000/10000/11111',
 M:'10001/11011/10101/10101/10001/10001/10001',N:'10001/11001/10101/10011/10001/10001/10001',O:'01110/10001/10001/10001/10001/10001/01110',
 P:'11110/10001/10001/11110/10000/10000/10000',Q:'01110/10001/10001/10001/10101/10010/01101',R:'11110/10001/10001/11110/10100/10010/10001',
 S:'01111/10000/10000/01110/00001/00001/11110',T:'11111/00100/00100/00100/00100/00100/00100',U:'10001/10001/10001/10001/10001/10001/01110',
 V:'10001/10001/10001/10001/10001/01010/00100',W:'10001/10001/10001/10101/10101/10101/01010',X:'10001/10001/01010/00100/01010/10001/10001',
 Y:'10001/10001/01010/00100/00100/00100/00100',Z:'11111/00001/00010/00100/01000/10000/11111',
 0:'01110/10001/10011/10101/11001/10001/01110',1:'010/110/010/010/010/010/111',2:'01110/10001/00001/00010/00100/01000/11111',
 3:'11110/00001/00001/01110/00001/00001/11110',4:'10010/10010/10010/11111/00010/00010/00010',5:'11111/10000/10000/11110/00001/00001/11110',
 6:'01110/10000/10000/11110/10001/10001/01110',7:'11111/00001/00010/00100/01000/01000/01000',8:'01110/10001/10001/01110/10001/10001/01110',
 9:'01110/10001/10001/01111/00001/00001/01110','-':'000/000/000/111/000/000/000','/':'00001/00001/00010/00100/01000/10000/10000',
};
function label(text, x, y, colour='#C9D7E5', scale=1) {
 const shapes=[];
 for(const ch of text.toUpperCase()) {
  const rows=glyphs[ch]?.split('/');
  if(!rows){x+=4*scale;continue;}
  rows.forEach((row,dy)=>[...row].forEach((v,dx)=>{if(v==='1') {
   const l=x+dx*scale,t=y+dy*scale;
   shapes.push(['p',[l,t],[l+scale,t],[l+scale,t+scale],[l,t+scale],colour,1]);
  }}));
  x+=(rows[0].length+1)*scale;
 }
 return shapes;
}
function shift(shapes,x,y) {
 return shapes.map(s=>s[0]==='p'?['p',...s.slice(1,5).map(([a,b])=>[a+x,b+y]),...s.slice(5)]:['e',s[1]+x,s[2]+y,...s.slice(3)]);
}
const rectangle=(x,y,w,h,c)=>['p',[x,y],[x+w,y],[x+w,y+h],[x,y+h],c,1];
function raster(frames,file,cols=1) {
 const input=path.join(scratch,'raster.json');
 fs.writeFileSync(input,JSON.stringify({w:520,h:310,frames}));
 execFileSync(process.execPath,['tools/fight-png.mjs',input,file,String(cols),'1'],{cwd,stdio:'pipe'});
}
// fight-png uses our PNG writer (RGB/filter 0); decode only that known output to count actual
// changed pixels in the tiny fighter views. This guards against a preview silently drawing base art.
function readOwnPng(file) {
 const b=fs.readFileSync(file), chunks=[]; let pos=8,w,h;
 while(pos<b.length){const len=b.readUInt32BE(pos),tag=b.toString('ascii',pos+4,pos+8),d=b.subarray(pos+8,pos+8+len);if(tag==='IHDR'){w=d.readUInt32BE(0);h=d.readUInt32BE(4);}if(tag==='IDAT')chunks.push(d);pos+=12+len;}
 const raw=zlib.inflateSync(Buffer.concat(chunks));
 for(let y=0;y<h;y++)if(raw[y*(w*3+1)]!==0)throw Error('Unexpected PNG filter');
 return {w,h,pixel:(x,y)=>raw.subarray(y*(w*3+1)+1+x*3,y*(w*3+1)+4+x*3)};
}
function matchPixels(png, controls, i) {
 let changed=0;
 for(let y=233;y<275;y++)for(let x=335+i*90;x<375+i*90;x++)if(!png.pixel(x,y).equals(controls.pixel(x,y)))changed++;
 if(changed===0)throw Error('Invisible at match scale');
 return changed;
}
try {
 fs.writeFileSync(helper,source);
 const record=path.join(scratch,'record.json');
 execFileSync('lune',['run',helper,record,...(process.argv.includes('--self-test')?['--self-test']:[])],{cwd,stdio:'pipe',maxBuffer:64*1024*1024});
 const d=JSON.parse(fs.readFileSync(record,'utf8'));
 const entries=[...new Map(d.frames.map(f=>[f.id,{id:f.id,name:f.name,kind:f.kind,pack:f.pack,category:f.category}])).values()];
 const tiles=entries.map(entry=>{
  const shapes=[rectangle(0,0,520,310,'#263341'),...label(entry.name,12,10,'#F0E7D2',2),...label(entry.category||entry.kind,12,31)];
  for(const [i,way] of d.colourways.entries()) {
   const find=view=>d.frames.find(f=>f.id===entry.id&&f.colourway===way.id&&f.view===view);
   shapes.push(...shift(find('portrait').shapes,4+i*150,45));
   shapes.push(...label(way.id,15+i*150,286));
   shapes.push(...shift(find('stud26').shapes,310+i*100,55));
   shapes.push(...shift(find('match26').shapes,335+i*90,233));
  }
  shapes.push(...label('26 PX / STUD',315,43),...label('26 PX TALL / HALF',315,219));
  const tile={label:entry.id,shapes};
  raster([tile],path.join(out,`${entry.id}.png`));
  return tile;
 });
 const controls=readOwnPng(path.join(out,'baseline.png'));
 if(process.argv.includes('--self-test')) {
  let caught=false;
  try { matchPixels(controls,controls,0); } catch { caught=true; }
  if(!caught)throw Error('Visibility guard accepted unchanged base art');
  d.mutationsCaught++;
 }
 for(const entry of entries.filter(e=>e.kind!=='baseline')) {
  const png=readOwnPng(path.join(out,`${entry.id}.png`));
  entry.changedMatchPixels={};
  for(const [i,way] of d.colourways.entries()) {
   try { entry.changedMatchPixels[way.id]=matchPixels(png,controls,i); }
   catch(error) { throw Error(`${entry.id}/${way.id}: ${error.message}`); }
  }
 }
 for(const pack of d.catalogue.packs) {
  const chosen=entries.filter(e=>e.kind==='piece'&&e.pack===pack.id);
  raster(chosen.map(e=>tiles[entries.indexOf(e)]),path.join(out,`sheet-${pack.id}.png`),2);
 }
 raster(entries.filter(e=>e.kind==='pack').map(e=>tiles[entries.indexOf(e)]),path.join(out,'packs.png'),2);
 fs.writeFileSync(path.join(out,'index.json'),JSON.stringify({catalogue:d.catalogue,colourways:d.colourways,entries,metrics:d.metrics,mutationsCaught:d.mutationsCaught},null,2));
 console.log(`${d.catalogue.items.length} pieces + ${d.catalogue.packs.length} packs; two colourways; portrait, 26 px/stud and 26 px tall; ${d.mutationsCaught} mutations rejected -> ${out}`);
} finally {
 fs.rmSync(helper,{force:true});
 fs.rmSync(scratch,{recursive:true,force:true});
}
