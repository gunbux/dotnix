// Runs on Paseo's bundled Electron-as-node runtime (see pkgs/paseo-bridge) so it
// reuses the installed CLI's daemon client: same version, same local credential.
// The public CLI drops agent workspace ids, which the switcher needs, and cannot
// set a system prompt, which glance needs.
//
//   paseo-bridge snapshot            -> one JSON object
//   paseo-bridge ask '<json>'        -> NDJSON events, see ask() below
//   paseo-bridge history <agent_id>  -> one JSON object, see history() below
//   paseo-bridge archive <wks_id>    -> one JSON object
//   paseo-bridge pin <wks_id> <0|1>  -> one JSON object
import { mkdir, readFile } from "node:fs/promises";
import { extname, join } from "node:path";

const cli = `${process.env.PASEO_RESOURCES}/app.asar/node_modules/@getpaseo/cli/dist/utils`;
const { connectToDaemon } = await import(`${cli}/client.js`);
const { selectDaemonTarget } = await import(`${cli}/daemon-target.js`);

const emit = (event) => process.stdout.write(`${JSON.stringify(event)}\n`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const message = (error) =>
  error instanceof Error ? error.message : typeof error?.message === "string" ? error.message : String(error);

async function serverId() {
  const home = process.env.PASEO_HOME ?? join(process.env.HOME, ".paseo");
  return (await readFile(join(home, "server-id"), "utf8")).trim();
}

async function pages(fetch) {
  const entries = [];
  let cursor;
  do {
    const page = await fetch({ page: { limit: 200, ...(cursor ? { cursor } : {}) } });
    entries.push(...page.entries);
    cursor = page.pageInfo?.hasMore ? page.pageInfo.nextCursor : undefined;
  } while (cursor);
  return entries;
}

async function snapshot(client) {
  const [workspaces, agents] = await Promise.all([
    pages((options) => client.fetchWorkspaces(options)),
    pages((options) => client.fetchAgents(options)),
  ]);
  return {
    serverId: await serverId(),
    workspaces: workspaces.map((w) => ({
      id: w.id,
      title: w.title ?? w.name,
      project: w.projectCustomName ?? w.projectDisplayName,
      directory: w.workspaceDirectory,
      kind: w.workspaceKind,
      status: w.status,
      labels: w.labels ?? [],
      pinnedAt: w.pinnedAt ?? null,
      archivingAt: w.archivingAt ?? null,
      activityAt: w.activityAt ?? w.statusEnteredAt ?? null,
      branch: w.gitRuntime?.currentBranch ?? null,
    })),
    agents: agents
      .map((entry) => entry.agent)
      .filter((a) => !a.archivedAt)
      .map((a) => ({
        id: a.id,
        title: a.title ?? null,
        status: a.status,
        workspaceId: a.workspaceId ?? null,
        provider: a.provider,
        model: a.runtimeInfo?.model ?? a.model ?? null,
        labels: a.labels ?? {},
        updatedAt: a.updatedAt,
        requiresAttention: a.requiresAttention ?? false,
      })),
  };
}

// Paseo shows an image the agent read (e.g. an attachment) as an assistant
// message holding only the image; it is not part of the reply.
const imageEcho = (item) => item.type === "assistant_message" && /^!\[[^\]]*\]\(file:\/\/[^)]*\)$/.test(item.text.trim());

const timelineItems = async (client, agentId) =>
  (await client.fetchAgentTimeline(agentId, { limit: 500 })).entries.map((entry) => entry.item).filter((item) => !imageEcho(item));

// The reply is every assistant message after the last user message.
async function reply(client, agentId) {
  const items = await timelineItems(client, agentId);
  const start = items.findLastIndex((item) => item.type === "user_message");
  return items
    .slice(start + 1)
    .filter((item) => item.type === "assistant_message")
    .map((item) => item.text)
    .join("\n\n")
    .trim();
}

// {type:"history", status, turns:[{prompt, answer}]}: each user message with the
// assistant messages that followed it. Assistant text before the first user
// message (none in practice) is dropped.
async function history(client, agentId) {
  const [items, agent] = await Promise.all([timelineItems(client, agentId), client.fetchAgent(agentId)]);
  const turns = [];
  for (const item of items) {
    if (item.type === "user_message") turns.push({ prompt: item.text, answer: "" });
    else if (item.type === "assistant_message" && turns.length) {
      const turn = turns[turns.length - 1];
      turn.answer = turn.answer ? `${turn.answer}\n\n${item.text}` : item.text;
    }
  }
  for (const turn of turns) turn.answer = turn.answer.trim();
  return { type: "history", status: agent?.agent.status ?? "unknown", turns };
}

const MIME = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif" };
const readImages = (paths = []) =>
  Promise.all(
    paths.map(async (path) => ({
      data: (await readFile(path)).toString("base64"),
      mimeType: MIME[extname(path).toLowerCase()] ?? "image/png",
    })),
  );

// Events: {type:"started", agentId, workspaceId}, {type:"text", text} (whole reply
// so far), then {type:"done", text, status} or {type:"error", message}.
// `images` are file paths sent with the prompt. With an agentId and no prompt it
// only follows the current turn, e.g. to reattach after the caller went away.
async function ask(client, request) {
  let agentId = request.agentId;
  let workspaceId = request.workspaceId ?? null;
  const images = await readImages(request.images);
  if (agentId) {
    if (request.prompt) await client.sendAgentMessage(agentId, request.prompt, images.length ? { images } : undefined);
  } else {
    await mkdir(request.cwd, { recursive: true });
    const title = request.title ?? request.prompt.slice(0, 60);
    const created = await client.createWorkspace({ source: { kind: "directory", path: request.cwd }, title });
    if (!created.workspace) throw new Error(created.error ?? "Could not create a workspace.");
    workspaceId = created.workspace.id;
    // The label marks the workspace for auto-archive's shorter threshold and stops
    // auto-label spending a model call on it.
    if (request.workspaceLabel) {
      await client
        .setWorkspaceLabel({ workspaceId, label: { name: request.workspaceLabel, color: "sky" }, assigned: true })
        .catch((error) => emit({ type: "warning", message: `Could not label workspace: ${message(error)}` }));
    }
    const agent = await client.createAgent({
      provider: request.provider,
      model: request.model || undefined,
      modeId: request.modeId || undefined,
      thinkingOptionId: request.thinking || undefined,
      cwd: created.workspace.workspaceDirectory ?? request.cwd,
      workspaceId,
      title,
      initialPrompt: request.prompt,
      ...(images.length ? { images } : {}),
      ...(request.systemPrompt ? { systemPrompt: request.systemPrompt } : {}),
      labels: request.labels ?? {},
    });
    agentId = agent.id;
  }
  emit({ type: "started", agentId, workspaceId });

  const finished = client.waitForFinish(agentId, request.timeoutMs ?? 600000);
  let done = null;
  finished.then(
    (state) => (done = { state }),
    (error) => (done = { error }),
  );
  let last = "";
  while (!done) {
    await sleep(700);
    const text = await reply(client, agentId).catch(() => last);
    if (text !== last) emit({ type: "text", text: (last = text) });
  }
  if (done.error) throw done.error;
  emit({ type: "done", text: await reply(client, agentId), status: done.state.status });
}

const [command, ...args] = process.argv.slice(2);
// A shell launched by a Paseo agent would otherwise parent new agents to it.
delete process.env.PASEO_AGENT_ID;
delete process.env.PASEO_WORKSPACE_ID;
const client = await connectToDaemon({ target: selectDaemonTarget({}) });
try {
  if (command === "snapshot") emit(await snapshot(client));
  else if (command === "ask") await ask(client, JSON.parse(args[0]));
  else if (command === "history") emit(await history(client, args[0]));
  else if (command === "archive") emit(await client.archiveWorkspace(args[0]));
  else if (command === "pin") emit(await client.setWorkspacePinned(args[0], args[1] === "1"));
  else throw new Error(`Unknown command: ${command}`);
} catch (error) {
  emit({ type: "error", message: message(error) });
  process.exitCode = 1;
} finally {
  await client.close().catch(() => {});
  process.exit();
}
