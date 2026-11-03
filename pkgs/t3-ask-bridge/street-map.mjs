import {randomBytes} from 'node:crypto';
import {mkdir, readFile, writeFile, rename, readdir, stat, unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {execFile} from 'node:child_process';
const WIDTH=280, HEIGHT=200, TTL=120000, WEEK=7*86400000;
const world=(lat,lng,z)=>{
 const n=256*2**z, s=Math.sin(Math.max(-85.05112878,Math.min(85.05112878,lat))*Math.PI/180);
 return {x:(lng+180)/360*n,y:(.5-Math.log((1+s)/(1-s))/(4*Math.PI))*n};
};
export function geometry(lat,lng,bikes) {
 let zoom=18, points, centre, left, top;
 for(;zoom>=12;zoom--) {
  const size=256*2**zoom; centre=world(lat,lng,zoom);
  left=Math.round(centre.x-WIDTH/2); top=Math.round(centre.y-89);
  points=bikes.map(b=>{const p=world(b.lat,b.lng,zoom); let dx=p.x-centre.x; dx-=Math.round(dx/size)*size; return {x:Math.round(centre.x+dx-left),y:Math.round(p.y-top)};});
  if(points.every(p=>p.x>=18&&p.x<WIDTH-18&&p.y>=18&&p.y<HEIGHT-38)||zoom===12) break;
 }
 const count=2**zoom, tiles=[];
 for(let y=Math.floor(top/256);y<=Math.floor((top+HEIGHT-1)/256);y++)
  for(let x=Math.floor(left/256);x<=Math.floor((left+WIDTH-1)/256);x++)
   if(y>=0&&y<count) tiles.push({z:zoom,x:((x%count)+count)%count,y,dx:x*256-left,dy:y*256-top});
 const metresPerPixel=156543.03392*Math.cos(Math.max(-85,Math.min(85,lat))*Math.PI/180)/2**zoom;
 return {width:WIDTH,height:HEIGHT,zoom,centre:{x:Math.round(centre.x-left),y:Math.round(centre.y-top)},
  pins:points.map(p=>({...p,visible:p.x>=8&&p.x<WIDTH-8&&p.y>=8&&p.y<HEIGHT-28})),scaleMetres:Math.round(metresPerPixel*50),tiles};
}
export function tileCache({directory=join(process.env.XDG_CACHE_HOME||join(homedir(),'.cache'),'bus-aunty-tiles'),transport=fetch,clock=Date.now,maxFiles=2048}={}) {
 const loading=new Map();
 return async function tile(t) {
  const key=`${t.z}-${t.x}-${t.y}.png`, path=join(directory,key);
  if(loading.has(key)) return loading.get(key);
  if(loading.size>=6) throw new Error('map_busy');
  const pending=(async()=>{
   await mkdir(directory,{recursive:true,mode:0o700});
   try {if(clock()-(await stat(path)).mtimeMs<WEEK) return await readFile(path);}catch{}
   // Never evict fresh tiles to make room: repeated views must remain cached for seven days.
   const names=await readdir(directory);
   if(!names.includes(key)&&names.length+loading.size>maxFiles) {
    const expired=await Promise.all(names.filter(n=>/^\d+-\d+-\d+\.png$/.test(n)).map(async n=>({n,s:await stat(join(directory,n))})));
    const old=expired.find(e=>clock()-e.s.mtimeMs>=WEEK);
    if(!old) throw new Error('cache_full');
    await unlink(join(directory,old.n));
   }
   const r=await transport(`https://tile.openstreetmap.org/${t.z}/${t.x}/${t.y}.png`,{
    redirect:'error',signal:AbortSignal.timeout(8000),headers:{'user-agent':'BusAuntyHelloRide/1.0 (+https://github.com/gunbux/garmin)'}});
   if(!r.ok||!r.headers.get('content-type')?.startsWith('image/png')) throw new Error('tile_unavailable');
   let size=0;const chunks=[];
   for await(const b of r.body){size+=b.length;if(size>262144) throw new Error('tile_too_large');chunks.push(b);}
   const png=Buffer.concat(chunks);
   if(!png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('invalid_tile');
   const temp=path+'.'+randomBytes(8).toString('hex');
   try {await writeFile(temp,png,{mode:0o600});await rename(temp,path);}finally{await unlink(temp).catch(()=>{});}
   return png;
  })();
  loading.set(key,pending);try{return await pending;}finally{loading.delete(key);}
 };
}
export function renderer(tile=tileCache()) {
 return async g=>{
  const tiles=[];
  for(const t of g.tiles) tiles.push({...t,png:(await tile(t)).toString('base64')});
  return new Promise((resolve,reject)=>{
   if(!process.env.BUS_AUNTY_MAP_PYTHON) return reject(new Error('renderer_disabled'));
   const child=execFile(process.env.BUS_AUNTY_MAP_PYTHON,[new URL('./street-render.py',import.meta.url).pathname],
    {timeout:5000,maxBuffer:262144,encoding:'buffer'},(e,out)=>e?reject(new Error('render_failed')):resolve(out));
   child.stdin.on('error',()=>{});child.stdin.end(JSON.stringify({...g,tiles}));
  });
 };
}
export function mapService({clock=Date.now,render=renderer(),maxCaps=64}={}) {
 const caps=new Map();let running=0;
 return {
  issue(lat,lng,bikes){
   for(const [id,c] of caps) if(c.expires<=clock()) caps.delete(id);
   if(caps.size>=maxCaps) caps.delete(caps.keys().next().value);
   const g=geometry(lat,lng,bikes), id=randomBytes(16).toString('hex');
   caps.set(id,{query:{lat,lng},bikes:bikes.map(b=>({...b})),g,expires:clock()+TTL,png:null});
   const {tiles,...metadata}=g;
   return {...metadata,path:`/v1/helloride/map/${id}.png`};
  },
  async image(path){
   const id=/^\/v1\/helloride\/map\/([a-f0-9]{32})\.png$/.exec(path)?.[1], c=caps.get(id);
   if(!c||c.expires<=clock()) return null;
   if(!c.png){
    if(running>=2) throw new Error('map_busy');
    running++;c.png=Promise.resolve().then(()=>render(c.g)).catch(e=>{c.png=null;throw e;}).finally(()=>running--);
   }
   return c.png;
  }
 };
}
