import { constants, existsSync, closeSync, openSync, fstatSync, readFileSync } from 'node:fs';
import { createHash, timingSafeEqual } from 'node:crypto';

export const API_URL = 'https://twblueride-sg.hellobike.com/api?action=blue.ride.near.bikes';
const MAX_BYTES = 1024 * 1024;
export class BikeError extends Error {
  constructor(code, status = 502) { super(code); this.status = status; }
}
export function privateFile(path) {
  let fd;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size > 16384) throw new Error();
    return readFileSync(fd, 'utf8').trim();
  } catch { throw new BikeError('login_required', 503); }
  finally { if (fd !== undefined) closeSync(fd); }
}
const coord = (n, max) => typeof n === 'number' && Number.isFinite(n) && Math.abs(n) <= max;
const radians = n => n * Math.PI / 180;
export async function nearby(sessionFile, lat, lng, transport = fetch) {
  if (!coord(lat, 90) || !coord(lng, 180)) throw new BikeError('bad_coordinates', 400);
  let session;
  try { session = JSON.parse(privateFile(sessionFile)); } catch { throw new BikeError('login_required', 503); }
  if (!session || !['token', 'ticket'].every(k => typeof session[k] === 'string' && session[k].trim())) throw new BikeError('login_required', 503);
  const body = { action: 'blue.ride.near.bikes', lat, lng, userLat: lat, userLng: lng,
    bikeShowGuid: '', tenantId: 't_sea_sg', locale: 'en', token: session.token, ticket: session.ticket };
  let envelope;
  try {
    const response = await transport(API_URL, { method: 'POST', redirect: 'error',
      signal: AbortSignal.timeout(15000), headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    if (response.status === 401 || response.status === 403) throw new BikeError('login_required', 503);
    if (!response.ok) throw new BikeError('upstream_unavailable');
    let size = 0;
    const chunks = [];
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_BYTES) { throw new BikeError('invalid_response'); }
      chunks.push(chunk);
    }
    envelope = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch (error) { throw error instanceof BikeError ? error : new BikeError('upstream_unavailable'); }
  if (!envelope || !Number.isSafeInteger(envelope.code)) throw new BikeError('invalid_response');
  if (envelope.code === 103) throw new BikeError('login_required', 503);
  if (envelope.code !== 0) throw new BikeError('upstream_rejected');
  if (!Array.isArray(envelope.data?.bikes)) throw new BikeError('invalid_response');
  const bikes = [];
  for (const b of envelope.data.bikes) {
    if (!b || b.bikeType !== 0 || b.bikeBizType !== 1 || typeof b.bikeNo !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(b.bikeNo) || !coord(b.bikeLat, 90) || !coord(b.bikeLng, 180)) continue;
    const a = radians(lat), c = radians(b.bikeLat), dl = radians(b.bikeLng - lng);
    const h = Math.sin((c-a)/2)**2 + Math.cos(a)*Math.cos(c)*Math.sin(dl/2)**2;
    const distance = Math.round(6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h)))));
    const bearing = (Math.atan2(Math.sin(dl)*Math.cos(c), Math.cos(a)*Math.sin(c)-Math.sin(a)*Math.cos(c)*Math.cos(dl))*180/Math.PI + 360)%360;
    bikes.push(Object.freeze({ id: b.bikeNo, lat: b.bikeLat, lng: b.bikeLng, distance, bearing: Math.round(bearing)%360 }));
  }
  bikes.sort((a,b) => a.distance - b.distance);
  return Object.freeze({ count: bikes.length, bikes: Object.freeze(bikes.slice(0,20)) });
}
export function bikeRoute({ sessionFile, tokenFile, transport, perMinute = 12 }) {
  let window = 0, count = 0;
  return async (request, response) => {
    let url;
    try { url = new URL(request.url, 'http://localhost'); } catch { return false; }
    if (url.pathname !== '/v1/helloride/nearby') return false;
    const send = (status, body) => { response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }); response.end(JSON.stringify(body)); };
    if (!sessionFile || !tokenFile || !existsSync(sessionFile) || !existsSync(tokenFile)) { send(404, {error:'disabled'}); return true; }
    try {
      const token = privateFile(tokenFile);
      const given = /^Bearer (.+)$/.exec(request.headers.authorization ?? '')?.[1] ?? '';
      const digest = v => createHash('sha256').update(v).digest();
      if (token.length < 32 || !given || !timingSafeEqual(digest(token),digest(given))) { send(401,{error:'bad_token'}); return true; }
      const now = Math.floor(Date.now()/60000);
      if (now !== window) { window=now; count=0; }
      if (++count > perMinute) { send(429,{error:'rate_limited'}); return true; }
      if (request.method !== 'GET') { send(405,{error:'method_not_allowed'}); return true; }
      if ([...url.searchParams.keys()].sort().join(',') !== 'lat,lng' || !['lat','lng'].every(k => /^-?\d+(\.\d+)?$/.test(url.searchParams.get(k)))) throw new BikeError('bad_coordinates',400);
      send(200, await nearby(sessionFile, Number(url.searchParams.get('lat')), Number(url.searchParams.get('lng')), transport));
    } catch (error) { send(error instanceof BikeError ? error.status : 502, {error: error instanceof BikeError ? error.message : 'upstream_unavailable'}); }
    return true;
  };
}
