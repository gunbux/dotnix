import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createServer } from 'node:http';
import { nearby, bikeRoute, API_URL } from './helloride.mjs';
const dir = mkdtempSync(`${tmpdir()}/bikes-test-`);
const session = `${dir}/session`, token = `${dir}/token`;
writeFileSync(session, JSON.stringify({token:'dummy-upstream',ticket:'dummy-ticket'}),{mode:0o600});
writeFileSync(token,'dummy-watch-token-01234567890123456789',{mode:0o600});
process.on('exit',()=>rmSync(dir,{recursive:true,force:true}));
const reply = value => async (url, options) => {
  assert.equal(url,API_URL); assert.equal(options.redirect,'error'); assert.ok(options.signal);
  const b=JSON.parse(options.body); assert.equal(b.lat,b.userLat); assert.equal(b.lng,b.userLng);
  assert.equal(b.action,'blue.ride.near.bikes'); assert.equal(b.bikeShowGuid,'');
  return new Response(JSON.stringify(value));
};
test('normalizes, sorts, freezes and caps regular bikes; count describes returned regular bikes', async()=>{
  const bikes=Array.from({length:30},(_,i)=>({bikeType:0,bikeBizType:1,bikeNo:`00${i}`,bikeLat:1.35+(30-i)*0.0001,bikeLng:103.85}));
  bikes.push(null,{bikeNo:'bad',bikeLat:true,bikeLng:103.85});
  const r=await nearby(session,1.35,103.85,reply({code:0,data:{bikes}}));
  assert.equal(r.count,30); assert.equal(r.bikes.length,20); assert.equal(r.bikes[0].id,'0029');
  assert.ok(Object.isFrozen(r.bikes[0])); assert.ok(r.bikes[0].distance<r.bikes[19].distance);
  assert.equal(r.bikes[0].bearing,0);
});
test('excludes family and other bike types before counting and limiting nearby results', async()=>{
  const regular = Array.from({length:25},(_,i)=>({bikeType:0,bikeBizType:1,bikeNo:`regular-${i}`,bikeLat:1.35+(i+1)*0.0001,bikeLng:103.85}));
  const family = Array.from({length:30},(_,i)=>({bikeType:0,bikeBizType:2,bikeNo:`family-${i}`,bikeLat:1.35,bikeLng:103.85}));
  const other = [{bikeType:1,bikeBizType:1,bikeNo:'electric',bikeLat:1.35,bikeLng:103.85},
    {bikeType:2,bikeBizType:1,bikeNo:'scooter',bikeLat:1.35,bikeLng:103.85}];
  const result=await nearby(session,1.35,103.85,reply({code:0,data:{bikes:[...family,...other,...regular]}}));
  assert.equal(result.count,25);
  assert.equal(result.bikes.length,20);
  assert.deepEqual(result.bikes.map(b=>b.id),regular.slice(0,20).map(b=>b.bikeNo));
});
test('does not classify missing, unknown or string category values as regular bikes', async()=>{
  const categories = [{}, {bikeType:0}, {bikeBizType:1}, {bikeType:99,bikeBizType:1},
    {bikeType:0,bikeBizType:99}, {bikeType:'0',bikeBizType:1}, {bikeType:0,bikeBizType:'1'}];
  const bikes=categories.map((category,i)=>({...category,bikeNo:`unknown-${i}`,bikeLat:1.35,bikeLng:103.85}));
  const result=await nearby(session,1.35,103.85,reply({code:0,data:{bikes}}));
  assert.deepEqual(result,{count:0,bikes:[]});
});
test('empty is distinct from expired, malformed, unsafe codes and unknown API errors',async()=>{
  assert.deepEqual((await nearby(session,0,0,reply({code:0,data:{bikes:[]}}))).bikes,[]);
  for(const [v,code] of [[{code:103,msg:'secret'},'login_required'],[{code:1101002,msg:'secret'},'upstream_rejected'],[{code:false},'invalid_response'],[{code:1e30},'invalid_response'],[{code:0},'invalid_response']]) {
    await assert.rejects(nearby(session,0,0,reply(v)),{message:code});
  }
});
test('invalid coordinates never send credentials',async()=>{
  for(const [a,b] of [[NaN,0],[91,0],[0,181],[true,0],['1',0]]) await assert.rejects(nearby(session,a,b,()=>assert.fail()),{message:'bad_coordinates'});
});
test('timeout, malformed JSON, oversize and redirects fail safely',async()=>{
  for(const transport of [async()=>{throw new Error('secret timeout')},async()=>new Response('bad secret'),async()=>new Response(' '.repeat(1048577)),async()=>new Response('',{status:307,headers:{location:'https://example.com'}})]) {
    await assert.rejects(nearby(session,0,0,transport),e=>!e.message.includes('secret'));
  }
});
test('HTTP route isolates tokens, validates query and method, disables without config',async(t)=>{
  const route=bikeRoute({sessionFile:session,tokenFile:token,transport:reply({code:0,data:{bikes:[]}})});
  const server=createServer(async(req,res)=>{if(!await route(req,res)){res.writeHead(404);res.end();}});
  await new Promise(r=>server.listen(0,'127.0.0.1',r)); t.after(()=>server.close());
  const url=`http://127.0.0.1:${server.address().port}/v1/helloride/nearby`;
  const headers={authorization:'Bearer dummy-watch-token-01234567890123456789'};
  const good=await (await fetch(url+'?lat=1.35&lng=103.85',{headers})).json();
  assert.match(good.map.path,/^\/v1\/helloride\/map\/[a-f0-9]{32}\.png$/);
  assert.equal((await fetch(url.replace('/nearby','/map/unknown.png'))).status,404);
  assert.equal((await fetch(url+'?lat=1&lng=2',{headers:{authorization:'Bearer t3-token'}})).status,401);
  for(const q of ['','?lat=&lng=2','?lat=NaN&lng=2','?lat=91&lng=2','?lat=1&lng=2&action=unlock','?lat=1&lat=2&lng=3']) assert.equal((await fetch(url+q,{headers})).status,400);
  assert.equal((await fetch(url,{headers,method:'POST'})).status,405);
  const disabled=bikeRoute({}); let status;
  await disabled({url:'/v1/helloride/nearby'}, {writeHead:n=>status=n,end:()=>{}}); assert.equal(status,404);
});
test('real HTTP redirect cannot forward upstream secrets', async(t)=>{
  let requests=0;
  const server=createServer((req,res)=>{requests++;res.writeHead(307,{location:'/capture'});res.end();});
  await new Promise(r=>server.listen(0,'127.0.0.1',r)); t.after(()=>server.close());
  const transport=(_url,options)=>fetch(`http://127.0.0.1:${server.address().port}/redirect`,options);
  await assert.rejects(nearby(session,1,2,transport),{message:'upstream_unavailable'});
  assert.equal(requests,1);
});
test('actual bridge keeps T3 routes separate from bike authorization', {timeout:10000}, async(t)=>{
  const {spawn}=await import('node:child_process');
  const t3Token=`${dir}/t3-token`;
  writeFileSync(t3Token,'dummy-t3-only-token-01234567890123456789',{mode:0o600});
  const reservation=createServer();
  await new Promise(r=>reservation.listen(0,'127.0.0.1',r));
  const port=reservation.address().port; await new Promise(r=>reservation.close(r));
  const child=spawn(process.execPath,[new URL('./bridge.mjs',import.meta.url).pathname],{
    env:{...process.env,T3_ASK_PORT:String(port),T3_ASK_T3_TOKEN_FILE:t3Token,T3_ASK_WATCH_TOKEN_FILE:t3Token,T3_ASK_T3_MCP_TOKEN_FILE:`${dir}/absent`,HELLORIDE_SESSION_FILE:session,HELLORIDE_WATCH_TOKEN_FILE:token},stdio:['ignore','pipe','pipe']});
  t.after(()=>child.kill());
  await new Promise((resolve,reject)=>{child.stdout.once('data',resolve);child.once('error',reject);child.once('exit',()=>reject(new Error('Bridge exited before listening')));});
  const origin=`http://127.0.0.1:${port}`;
  assert.equal((await fetch(origin+'/v1/pending',{headers:{authorization:'Bearer dummy-watch-token-01234567890123456789'}})).status,401);
  assert.equal((await fetch(origin+'/v1/helloride/nearby?lat=1&lng=2',{headers:{authorization:'Bearer dummy-t3-only-token-01234567890123456789'}})).status,401);
  assert.equal((await fetch(origin+'/v1/not-a-route',{headers:{authorization:'Bearer dummy-t3-only-token-01234567890123456789'}})).status,404);
});
test('shared and symlinked private files cannot supply credentials',async()=>{
  const {symlinkSync,chmodSync}=await import('node:fs');
  const path=`${dir}/shared`;
  writeFileSync(path,JSON.stringify({token:'dummy',ticket:'dummy'}),{mode:0o644});
  chmodSync(path,0o644);
  await assert.rejects(nearby(path,1,2,()=>assert.fail()),{message:'login_required'});
  symlinkSync(session,`${dir}/link`);
  await assert.rejects(nearby(`${dir}/link`,1,2,()=>assert.fail()),{message:'login_required'});
});
test('only authenticated nearby can mint images; headerless capability retries return PNG',async t=>{
 const {mapService}=await import('./street-map.mjs');
 let minted=0;
 const maps=mapService({render:async()=>Buffer.from('dummy-png')});
 const issue=maps.issue;maps.issue=(...args)=>{minted++;return issue(...args);};
 const route=bikeRoute({sessionFile:session,tokenFile:token,transport:reply({code:0,data:{bikes:[]}}),maps});
 const server=createServer(async(req,res)=>{if(!await route(req,res)){res.writeHead(404);res.end();}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
 const origin=`http://127.0.0.1:${server.address().port}`;
 assert.equal((await fetch(origin+'/v1/helloride/nearby?lat=1&lng=2')).status,401);assert.equal(minted,0);
 const data=await(await fetch(origin+'/v1/helloride/nearby?lat=1&lng=2',{headers:{authorization:'Bearer dummy-watch-token-01234567890123456789',host:'evil.invalid'}})).json();
 assert.equal(minted,1);assert.ok(!JSON.stringify(data).includes('evil.invalid'));
 for(let i=0;i<2;i++) {const r=await fetch(origin+data.map.path);assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'image/png');assert.equal(await r.text(),'dummy-png');}
 assert.equal((await fetch(origin+data.map.path+'?url=https://example.com')).status,404);
});
