// Questions from agents on the user's other machines, through T3 Connect.
//
//   bridge -> this machine's T3 /mcp (MCP client token) -> T3 Connect -> linked machine
//
// The local T3 server forwards T3 MCP tools that take `environmentId` to the
// linked machine, under the link's access. So the bridge needs no route to
// the other machine and no token from it. The MCP endpoint takes only MCP
// client sessions: `t3 auth session issue --subject mcp-client`.

import { answerFor, parsePeerTid, peerTid, watchItem } from "./watch-api.mjs";

export class PeerError extends Error {}

// A minimal MCP client over streamable HTTP: initialize once, then
// tools/call. A response is JSON or one SSE event. An expired session is
// opened again once.
export function mcpClient({ url, token, fetch: doFetch = fetch }) {
  let session = null;
  let nextId = 1;
  let currentToken;

  async function post(body, sessionId) {
    const headers = {
      authorization: `Bearer ${currentToken}`,
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
    };
    if (sessionId) headers["mcp-session-id"] = sessionId;
    const response = await doFetch(url, { method: "POST", headers, body: JSON.stringify(body) }).catch(
      (cause) => {
        throw new PeerError(`T3 MCP unreachable: ${cause.cause?.code ?? cause.message}`);
      },
    );
    const text = await response.text();
    if (!response.ok) {
      const error = new PeerError(`T3 MCP HTTP ${response.status}: ${text.slice(0, 200)}`);
      error.status = response.status;
      throw error;
    }
    const data = text.split("\n").find((line) => line.startsWith("data:"));
    return {
      sessionId: response.headers.get("mcp-session-id"),
      message: text.trim() === "" ? null : JSON.parse(data ? data.slice(5) : text),
    };
  }

  async function open() {
    const { sessionId } = await post({
      jsonrpc: "2.0",
      id: nextId++,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "t3-ask-bridge", version: "1" },
      },
    });
    await post({ jsonrpc: "2.0", method: "notifications/initialized" }, sessionId);
    session = sessionId;
  }

  async function callOnce(name, args) {
    const latestToken = typeof token === "function" ? token() : token;
    if (latestToken !== currentToken) {
      currentToken = latestToken;
      session = null;
    }
    if (session === null) await open();
    const { message } = await post(
      { jsonrpc: "2.0", id: nextId++, method: "tools/call", params: { name, arguments: args } },
      session,
    );
    if (message?.error) throw new PeerError(`${name}: ${message.error.message}`);
    const result = message?.result;
    if (result?.isError) {
      throw new PeerError(`${name}: ${result.content?.[0]?.text?.slice(0, 300) ?? "failed"}`);
    }
    return result?.structuredContent;
  }

  return {
    async call(name, args) {
      try {
        return await callOnce(name, args);
      } catch (error) {
        if (error.status !== 400 && error.status !== 404) throw error;
        session = null;
        return callOnce(name, args);
      }
    },
  };
}

// "Chun's MacBook Pro" -> "MacBook Pro": the watch line is short.
export const shortLabel = (label) => String(label ?? "Linked").replace(/^.*?['’]s\s+/, "");

// Every pending question on every reachable linked machine, as watch items.
// One machine failing does not hide the others.
export async function peerItems(mcp, log = () => {}, links) {
  // T3 0.1.7 exposes link discovery through its CLI, rather than public MCP.
  // Gateway callers supply that catalog; older installations retain MCP discovery.
  if (links === undefined) ({ links = [] } = (await mcp.call("t3_environment_links", {})) ?? {});
  const perMachine = await Promise.all(
    links
      .filter((link) => link.status === "reachable")
      .map((link) =>
        machineItems(mcp, link).catch((error) => {
          log(`peer ${link.label}: ${error.message}`);
          return [];
        }),
      ),
  );
  return perMachine.flat();
}

async function machineItems(mcp, link) {
  const environmentId = link.environmentId;
  // Async questions can remain pending after their agent run completes.
  // The request list, rather than the run status, decides what needs an answer.
  const { threads = [] } =
    (await mcp.call("t3_thread_list", {
      environmentId,
      allProjects: true,
      limit: 50,
    })) ?? {};
  const lists = await Promise.all(
    threads.map(async (thread) => ({
      thread,
      requestIds:
        ((await mcp.call("t3_pending_request", { action: "list", environmentId, threadId: thread.threadId })) ?? {})
          .requestIds ?? [],
    })),
  );
  const items = [];
  for (const { thread, requestIds } of lists) {
    for (const requestId of requestIds) {
      const read = await mcp.call("t3_pending_request", {
        action: "read",
        environmentId,
        threadId: thread.threadId,
        requestId,
      });
      items.push(
        watchItem({
          rid: requestId,
          tid: peerTid(environmentId, thread.threadId),
          thread: `${shortLabel(link.label)} · ${thread.title}`,
          questions: read?.questions ?? [],
        }),
      );
    }
  }
  return items;
}

// Answers one question on a linked machine. Returns the same shapes as
// resolveAnswer: { answer, question, label, thread } or { status, error }.
export async function answerPeer(mcp, tid, requestId, picks) {
  const target = parsePeerTid(tid);
  if (target === null) return { status: 404, error: "not_found" };
  const { environmentId, threadId } = target;
  const { requestIds = [] } =
    (await mcp.call("t3_pending_request", { action: "list", environmentId, threadId })) ?? {};
  // The list holds only pending questions, so a missing id was answered or
  // withdrawn; the watch shows both as "already answered".
  if (!requestIds.includes(requestId)) return { status: 409, error: "already_answered" };
  const read = await mcp.call("t3_pending_request", { action: "read", environmentId, threadId, requestId });
  const resolved = answerFor(read?.questions ?? [], picks);
  if (resolved.status) return resolved;
  await mcp.call("t3_pending_request", {
    action: "respond",
    environmentId,
    threadId,
    requestId,
    answers: resolved.answer,
  });
  return { ...resolved, thread: `${environmentId}/${threadId}` };
}
