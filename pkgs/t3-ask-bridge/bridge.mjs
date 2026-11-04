// t3-ask-bridge: lets the T3 Ask watch app list and answer T3 Code questions.
//
//   watch -> Garmin Connect -> Tailscale Funnel -> this bridge -> T3 WebSocket RPC
//                                                              -> T3 /mcp -> T3 Connect -> linked machines
//
// Questions on this machine come over the RPC. Questions on linked machines
// come through T3 Connect (peers.mjs), when an MCP client token is set up.
//
// The watch holds its own token, which only this bridge accepts. The T3 token
// (orchestration:read + operate) never leaves this machine. The bridge opens
// one T3 connection per watch request, so it keeps no session state to repair.

import { bikeRoute } from "./helloride.mjs";
import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { answerPeer, mcpClient, PeerError, peerItems } from "./peers.mjs";
import { readPeerCatalog } from "./peer-catalog.mjs";
import { parsePeerTid, pendingItems, resolveAnswer } from "./watch-api.mjs";

const configDir = `${process.env.XDG_CONFIG_HOME ?? `${process.env.HOME}/.config`}/t3-ask`;
const config = {
  host: process.env.T3_ASK_HOST ?? "127.0.0.1",
  port: Number(process.env.T3_ASK_PORT ?? 8789),
  t3Url: process.env.T3_ASK_T3_URL ?? "http://127.0.0.1:3773",
  t3TokenFile: process.env.T3_ASK_T3_TOKEN_FILE ?? `${configDir}/t3-token`,
  watchTokenFile: process.env.T3_ASK_WATCH_TOKEN_FILE ?? `${configDir}/watch-token`,
  // Optional. Without it, only this machine's questions are listed.
  t3McpTokenFile: process.env.T3_ASK_T3_MCP_TOKEN_FILE ?? `${configDir}/t3-mcp-token`,
  peersFile: process.env.T3_ASK_PEERS_FILE,
  perMinute: Number(process.env.T3_ASK_RATE_PER_MINUTE ?? 30),
};

function readSecret(path) {
  const mode = statSync(path).mode;
  if (mode & 0o077) throw new Error(`${path} must not be readable by others (chmod 600)`);
  const value = readFileSync(path, "utf8").trim();
  if (value.length < 32) throw new Error(`${path} holds no usable token`);
  return value;
}

// ---- T3 WebSocket RPC (Effect RPC, JSON serialization) ----

class T3Error extends Error {
  constructor(message, { threadNotFound = false } = {}) {
    super(message);
    this.threadNotFound = threadNotFound;
  }
}

async function withT3(t3Token, use) {
  const ticketResponse = await fetch(`${config.t3Url}/api/auth/websocket-ticket/rpc`, {
    method: "POST",
    headers: { authorization: `Bearer ${t3Token}` },
  }).catch((cause) => {
    throw new T3Error(`T3 server unreachable: ${cause.cause?.code ?? cause.message}`);
  });
  if (!ticketResponse.ok) throw new T3Error(`T3 ticket request failed: HTTP ${ticketResponse.status}`);
  const { ticket } = await ticketResponse.json();

  const url = new URL("/ws", config.t3Url.replace(/^http/, "ws"));
  url.searchParams.set("orchestrationProtocol", "2");
  url.searchParams.set("wsTicket", ticket);
  const socket = new WebSocket(url);
  const waiting = new Map();
  let nextId = 1;

  const failAll = (error) => {
    for (const { reject } of waiting.values()) reject(error);
    waiting.clear();
  };
  socket.addEventListener("message", (event) => {
    for (const message of [JSON.parse(String(event.data))].flat()) {
      const call = waiting.get(String(message.requestId));
      if (call === undefined) continue;
      if (message._tag === "Chunk") {
        waiting.delete(String(message.requestId));
        call.resolve(message.values[0]);
      } else if (message._tag === "Exit") {
        waiting.delete(String(message.requestId));
        if (message.exit._tag === "Success") call.resolve(message.exit.value);
        else {
          const cause = JSON.stringify(message.exit.cause);
          call.reject(new T3Error(`${call.tag} failed: ${cause.slice(0, 400)}`, {
            threadNotFound: cause.includes("ThreadNotFoundError"),
          }));
        }
      }
    }
  });
  socket.addEventListener("close", (event) => failAll(new T3Error(`T3 socket closed (${event.code})`)));
  socket.addEventListener("error", () => failAll(new T3Error("T3 socket error (protocol changed? expect HTTP 426)")));
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", () => reject(new T3Error("T3 WebSocket upgrade refused")), { once: true });
  });

  // Resolves with a unary result, or with the first chunk of a stream.
  const call = (tag, payload) =>
    new Promise((resolve, reject) => {
      const id = String(nextId++);
      waiting.set(id, { resolve, reject, tag });
      socket.send(JSON.stringify({ _tag: "Request", id, tag, payload, headers: [] }));
    });

  try {
    return await use({
      shell: async () => {
        const first = await call("orchestration.subscribeShell", {});
        if (first?.kind !== "snapshot") throw new T3Error(`unexpected shell item ${first?.kind}`);
        return first.snapshot;
      },
      projection: (threadId) => call("orchestration.getThreadProjection", { threadId }),
      respond: (threadId, requestId, answers) =>
        call("orchestration.dispatchCommand", {
          type: "runtime-request.respond",
          commandId: `t3-ask-${randomUUID()}`,
          threadId,
          requestId,
          answers,
        }),
    });
  } finally {
    socket.close();
  }
}

// ---- Watch API ----

async function listPending(t3) {
  const shell = await t3.shell();
  // The shell names one pending request per thread; a question can sit
  // behind an approval, so read every thread that has any.
  const waiting = shell.threads.filter((thread) => thread.pendingRuntimeRequest != null);
  const items = [];
  for (const thread of waiting) items.push(...pendingItems(await t3.projection(thread.id)));
  return items;
}

// The MCP client for linked machines, or null when there is no MCP token.
let peerMcp = null;

// This machine's questions, then the linked machines'. A linked machine
// that fails is logged and left out; this machine failing still fails.
async function listAll(t3Token) {
  // Catalog failure must fail the poll, rather than claim no linked questions.
  const links = config.peersFile === undefined ? undefined : readPeerCatalog(config.peersFile);
  const [local, remote] = await Promise.all([
    withT3(t3Token, listPending),
    peerMcp === null
      ? []
      : peerItems(peerMcp, log, links).catch((error) => {
          log(`peers: ${error.message}`);
          return [];
        }),
  ]);
  return [...local, ...remote];
}

// A request the bridge is answering, or answered in the last 10 minutes,
// gets 409 at once. T3 also refuses a second answer, but its projection can
// lag the dispatch by a moment.
const answered = new Map();
const ANSWERED_TTL_MS = 10 * 60 * 1000;

async function answer(t3Token, body) {
  // `a` (one index list per question) comes from current watch builds; `i`
  // (one index) from the first build. resolveAnswer checks the contents.
  const { rid, tid, a, i } = body ?? {};
  const picks = Array.isArray(a) ? a : i;
  if (typeof rid !== "string" || typeof tid !== "string" || !(Array.isArray(picks) || Number.isInteger(picks))) {
    return [400, { error: "bad_body" }];
  }
  if (answered.has(rid)) return [409, { error: "already_answered" }];
  answered.set(rid, Date.now());
  try {
    const result = parsePeerTid(tid) !== null ? await answerOnPeer(tid, rid, picks) : await withT3(t3Token, async (t3) => {
      const projection = await t3.projection(tid);
      const resolved = resolveAnswer(projection, rid, picks);
      if (resolved.status) return resolved;
      await t3.respond(tid, rid, resolved.answer);
      log(`answered thread="${projection.thread.title}" question="${resolved.question}" choice="${resolved.label}" rid=${rid}`);
      return resolved;
    });
    if (result.status) answered.delete(rid);
    return result.status ? [result.status, { error: result.error }] : [200, { ok: true }];
  } catch (error) {
    answered.delete(rid);
    if (error.threadNotFound) return [404, { error: "not_found" }];
    throw error;
  }
}

async function answerOnPeer(tid, rid, picks) {
  if (peerMcp === null) return { status: 404, error: "not_found" };
  const resolved = await answerPeer(peerMcp, tid, rid, picks);
  if (!resolved.status) {
    log(`answered peer thread=${resolved.thread} question="${resolved.question}" choice="${resolved.label}" rid=${rid}`);
  }
  return resolved;
}

// ---- HTTP ----

const log = (line) => console.log(line);

function sameToken(given, expected) {
  const digest = (value) => createHash("sha256").update(value).digest();
  return timingSafeEqual(digest(given), digest(expected));
}

// Fixed one-minute windows. Callers with the watch token and callers without
// it count apart, so a stranger who finds the URL cannot lock the watch out.
function rateLimiter(perMinute) {
  const windows = { authorized: { start: 0, count: 0 }, unauthorized: { start: 0, count: 0 } };
  return (kind) => {
    const window = windows[kind];
    const now = Date.now();
    if (now - window.start >= 60_000) Object.assign(window, { start: now, count: 0 });
    return ++window.count <= perMinute;
  };
}

// T3 request ids run to about 420 characters, so an answer body is near
// 500 bytes. 4 KB leaves room and still bounds what a stranger can send.
async function readJson(request) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 4096) return undefined;
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    return undefined;
  }
}

const routes = {
  "GET /v1/pending": async (t3Token) => [200, { items: await listAll(t3Token) }],
  // The glance has 64 KB of memory and shows only a count, so it gets the
  // items without the full question text.
  "GET /v1/pending?brief=1": async (t3Token) => [
    200,
    { items: (await listAll(t3Token)).map(({ qs, ...item }) => item) },
  ],
  "POST /v1/answer": async (t3Token, request) => answer(t3Token, await readJson(request)),
};

function main() {
  const t3Token = readSecret(config.t3TokenFile);
  const watchToken = readSecret(config.watchTokenFile);
  const allow = rateLimiter(config.perMinute);
  if (existsSync(config.t3McpTokenFile)) {
    peerMcp = mcpClient({ url: new URL("/mcp", config.t3Url).href, token: () => readSecret(config.t3McpTokenFile) });
  }

  const bikes = bikeRoute({ sessionFile: process.env.HELLORIDE_SESSION_FILE, tokenFile: process.env.HELLORIDE_WATCH_TOKEN_FILE });
  const server = createServer(async (request, response) => {
    if (await bikes(request, response)) return;
    const started = Date.now();
    const route = routes[`${request.method} ${request.url}`];
    const send = (status, body) => {
      response.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" });
      response.end(JSON.stringify(body));
      log(`${request.method} ${request.url} ${status} ${Date.now() - started}ms${body.items ? ` items=${body.items.length}` : ""}`);
    };
    const bearer = /^Bearer (.+)$/.exec(request.headers.authorization ?? "")?.[1] ?? "";
    const authorized = bearer !== "" && sameToken(bearer, watchToken);
    if (!allow(authorized ? "authorized" : "unauthorized")) return send(429, { error: "rate_limited" });
    if (!authorized) return send(401, { error: "bad_token" });
    if (route === undefined) return send(404, { error: "no_route" });
    try {
      const [status, body] = await route(t3Token, request);
      send(status, body);
    } catch (error) {
      log(`error ${error.message}`);
      send(502, { error: error instanceof T3Error || error instanceof PeerError ? "t3_unavailable" : "bridge_error" });
    }
  });
  setInterval(() => {
    for (const [rid, at] of answered) if (Date.now() - at > ANSWERED_TTL_MS) answered.delete(rid);
  }, 60_000).unref();
  server.listen(config.port, config.host, () => log(`t3-ask-bridge on http://${config.host}:${config.port}, T3 at ${config.t3Url}, linked machines ${peerMcp ? "on" : "off (no MCP token)"}`));
}

main();
