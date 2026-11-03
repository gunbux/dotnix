import {test} from 'node:test';
import assert from 'node:assert/strict';
import {geometry, mapService} from './street-map.mjs';
test('Mercator crop and pins share integer origin, including dateline and empty',()=>{
 for(const lng of [103.85,179.999,-179.999]) {
  const g=geometry(1.35,lng,[{lat:1.351,lng:lng>179? -179.999:lng+.001}]);
  assert.equal(g.width,280); assert.equal(g.height,200);
  assert.deepEqual(g.centre,{x:140,y:89});
  assert.ok(g.pins[0].visible); assert.ok(g.tiles.length<=6);
 }
 assert.equal(geometry(90,0,[]).pins.length,0);
});
test('capabilities are random, bounded, reusable, expire, and reject arbitrary proxy inputs',async()=>{
 let now=0, renders=0;
 const s=mapService({clock:()=>now,render:async()=>{renders++;return Buffer.from('png')},maxCaps:2});
 const m=s.issue(1.35,103.85,[]), other=s.issue(1.35,103.85,[]);
 assert.match(m.path,/^\/v1\/helloride\/map\/[a-f0-9]{32}\.png$/); assert.notEqual(m.path,other.path);
 assert.equal(await s.image('/v1/helloride/map/https://example.com'),null);
 assert.equal(await s.image(m.path+'?lat=1'),null);
 const [a,b]=await Promise.all([s.image(m.path),s.image(m.path)]); assert.deepEqual(a,b); assert.equal(renders,1);
 s.issue(0,0,[]); assert.equal(await s.image(m.path),null);
 now=120001; assert.equal(await s.image(other.path),null);
});

import {tileCache} from './street-map.mjs';
import {mkdtemp,rm,utimes} from 'node:fs/promises';
import {tmpdir} from 'node:os';
const png=Buffer.from('89504e470d0a1a0a','hex');
test('tile cache deduplicates concurrent loads, persists hits, expires after seven days',async t=>{
 const directory=await mkdtemp(tmpdir()+'/map-test-'); t.after(()=>rm(directory,{recursive:true,force:true}));
 let calls=0;
 const transport=async(url,options)=>{
  calls++;assert.equal(url,'https://tile.openstreetmap.org/16/1/2.png');
  assert.equal(options.redirect,'error');assert.ok(options.signal);assert.deepEqual(Object.keys(options.headers),['user-agent']);
  return new Response(png,{headers:{'content-type':'image/png'}});
 };
 const tile=tileCache({directory,transport}), key={z:16,x:1,y:2};
 await Promise.all([tile(key),tile(key),tile(key)]);assert.equal(calls,1);
 await tileCache({directory,transport})(key);assert.equal(calls,1);
 await utimes(directory+'/16-1-2.png',new Date(0),new Date(0));await tile(key);assert.equal(calls,2);
});
test('tile errors, redirect, timeout, invalid type and excess bytes never enter cache',async t=>{
 const directory=await mkdtemp(tmpdir()+'/map-test-');t.after(()=>rm(directory,{recursive:true,force:true}));
 const bad=[async()=>{throw new Error('timeout')},async()=>new Response('',{status:302}),async()=>new Response('bad'),async()=>new Response(Buffer.alloc(262145),{headers:{'content-type':'image/png'}})];
 for(const transport of bad) await assert.rejects(tileCache({directory,transport})({z:16,x:1,y:2}));
});
test('far bikes are explicitly outside instead of false pin positions',()=>{
 const g=geometry(1.35,103.85,[{lat:40,lng:-70}]); assert.equal(g.zoom,12);assert.equal(g.pins[0].visible,false);
 const g2=geometry(1.35,103.85,[{lat:1.35,lng:103.85}]);assert.deepEqual(g2.pins[0],{...g2.centre,visible:true});
});
test('real redirects stop before a second provider request',async t=>{
 const {createServer}=await import('node:http');let hits=0;
 const server=createServer((req,res)=>{hits++;res.writeHead(302,{location:'/other'});res.end();});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
 const directory=await mkdtemp(tmpdir()+'/map-test-');t.after(()=>rm(directory,{recursive:true,force:true}));
 await assert.rejects(tileCache({directory,transport:(_,opts)=>fetch(`http://127.0.0.1:${server.address().port}/tile`,opts)})({z:16,x:1,y:2}));
 assert.equal(hits,1);
});
