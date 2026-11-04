import assert from "node:assert/strict";
import { test } from "node:test";
import { answerPeer, mcpClient, peerItems, shortLabel } from "./peers.mjs";

const MAC = "3669c1b1-d4ee-4188-b125-d8bfe3e2117f";
const THREAD = "mcp:launch:0ded73a4";
const questions = [
  { id: "fruit", header: "Fruit", question: "Which fruit?", options: [{ label: "Apple", description: "Red." }, { label: "Banana", description: "Yellow." }] },
  { id: "colours", header: "Colours", question: "Which colours?", multiSelect: true, options: [{ label: "Red", description: "" }, { label: "Blue", description: "" }] },
];

// A fake T3 MCP: one reachable Mac with one waiting thread and one question.
function fakeMcp({ pending = ["r1"], reachable = "reachable", failThreads = false } = {}) {
  const calls = [];
  return {
    calls,
    async call(name, args) {
      calls.push([name, args]);
      if (name === "t3_environment_links") {
        return { links: [{ environmentId: MAC, label: "Chun's MacBook Pro", status: reachable }, { environmentId: "x", label: "Old", status: "expired" }] };
      }
      if (name === "t3_thread_list") {
        if (failThreads) throw new Error("relay down");
        return { threads: [{ threadId: THREAD, title: "t3-ask test" }] };
      }
      if (name === "t3_pending_request" && args.action === "list") return { requestIds: pending };
      if (name === "t3_pending_request" && args.action === "read") return { requestId: args.requestId, questions };
      if (name === "t3_pending_request" && args.action === "respond") return { ok: true };
      throw new Error(`unexpected ${name}`);
    },
  };
}

test("shortLabel drops the owner", () => {
  assert.equal(shortLabel("Chun's MacBook Pro"), "MacBook Pro");
  assert.equal(shortLabel("Chun’s Mac mini"), "Mac mini");
  assert.equal(shortLabel("legion-nix"), "legion-nix");
});

test("peerItems lists waiting questions on reachable machines only", async () => {
  const mcp = fakeMcp();
  const items = await peerItems(mcp);
  assert.equal(items.length, 1);
  assert.equal(items[0].tid, `${MAC}/${THREAD}`);
  assert.equal(items[0].thread, "MacBook Pro · t3-ask test");
  assert.equal(items[0].qs.length, 2);
  assert.equal(items[0].qs[1].m, true);
  const list = mcp.calls.find(([name]) => name === "t3_thread_list")[1];
  assert.deepEqual(list, { environmentId: MAC, allProjects: true, statuses: ["running", "waiting"], limit: 50 });
  assert.ok(!mcp.calls.some(([, args]) => args.environmentId === "x"));
});

test("a failing machine is logged and left out", async () => {
  const lines = [];
  assert.deepEqual(await peerItems(fakeMcp({ failThreads: true }), (l) => lines.push(l)), []);
  assert.match(lines[0], /relay down/);
});

test("supplied peer catalog bypasses MCP discovery and keeps list/read/respond routing", async () => {
  const mcp = fakeMcp();
  const links = [{ environmentId: MAC, label: "Catalog Mac", status: "reachable" }];
  const items = await peerItems(mcp, () => {}, links);
  assert.equal(items[0].thread, "Catalog Mac · t3-ask test");
  assert.ok(!mcp.calls.some(([name]) => name === "t3_environment_links"));
  const result = await answerPeer(mcp, items[0].tid, items[0].rid, [[1], [0, 1]]);
  assert.equal(result.label, "Banana | Red, Blue");
  const operations = mcp.calls.filter(([name]) => name === "t3_pending_request");
  assert.deepEqual(operations.map(([, args]) => args.action), ["list", "read", "list", "read", "respond"]);
  assert.ok(operations.every(([, args]) => args.environmentId === MAC && args.threadId === THREAD));
});

test("an empty supplied catalog does not try unsupported MCP discovery", async () => {
  const mcp = fakeMcp();
  assert.deepEqual(await peerItems(mcp, () => {}, []), []);
  assert.deepEqual(mcp.calls, []);
});

test("answerPeer responds on the right machine and thread", async () => {
  const mcp = fakeMcp();
  const result = await answerPeer(mcp, `${MAC}/${THREAD}`, "r1", [[1], [0, 1]]);
  assert.equal(result.label, "Banana | Red, Blue");
  const respond = mcp.calls.find(([, a]) => a.action === "respond")[1];
  assert.deepEqual(respond, {
    action: "respond",
    environmentId: MAC,
    threadId: THREAD,
    requestId: "r1",
    answers: { fruit: "Banana", colours: ["Red", "Blue"] },
  });
});

test("answerPeer: answered elsewhere is 409, bad picks 422, nothing sent", async () => {
  const gone = fakeMcp({ pending: [] });
  assert.equal((await answerPeer(gone, `${MAC}/${THREAD}`, "r1", [[0], [0]])).status, 409);
  const bad = fakeMcp();
  assert.equal((await answerPeer(bad, `${MAC}/${THREAD}`, "r1", [[0]])).status, 422);
  assert.ok(!bad.calls.some(([, a]) => a.action === "respond"));
  assert.equal((await answerPeer(bad, "not-a-peer", "r1", [[0], [0]])).status, 404);
});

test("mcpClient opens a session, reads SSE, and reopens an expired one", async () => {
  const seen = [];
  let expired = true;
  const fetch = async (url, { headers, body }) => {
    const msg = JSON.parse(body);
    seen.push([msg.method, headers["mcp-session-id"] ?? null]);
    const reply = (status, text, sid) => ({
      ok: status < 300,
      status,
      text: async () => text,
      headers: { get: (h) => (h === "mcp-session-id" ? sid : null) },
    });
    if (msg.method === "initialize") return reply(200, JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: {} }), `s${seen.length}`);
    if (msg.method === "notifications/initialized") return reply(202, "", null);
    if (expired) {
      expired = false;
      return reply(404, "session not found", null);
    }
    return reply(200, `event: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { structuredContent: { ok: 1 } } })}\n`, null);
  };
  const mcp = mcpClient({ url: "http://t3/mcp", token: "t", fetch });
  assert.deepEqual(await mcp.call("t3_environment_links", {}), { ok: 1 });
  assert.deepEqual(seen.map(([m]) => m), ["initialize", "notifications/initialized", "tools/call", "initialize", "notifications/initialized", "tools/call"]);
  assert.equal(seen[5][1], "s4");
});
