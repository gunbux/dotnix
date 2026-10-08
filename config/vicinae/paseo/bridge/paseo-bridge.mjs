// Runs on Paseo's bundled Electron-as-node runtime (see modules/home/vicinae.nix) so
// it reuses the installed CLI's daemon client: same version, same local
// credential. The public CLI drops agent workspace ids, which the switcher needs.
//
//   paseo-vicinae-bridge snapshot           -> one JSON object
//   paseo-vicinae-bridge ask '<json>'       -> NDJSON events, see ask() below
//   paseo-vicinae-bridge archive <wks_id>   -> one JSON object
//   paseo-vicinae-bridge pin <wks_id> <0|1> -> one JSON object
import { mkdir, readFile } from "node:fs/promises";
import { join } from "node:path";

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

// The reply is every assistant message after the last user message.
async function reply(client, agentId) {
  const timeline = await client.fetchAgentTimeline(agentId, { limit: 200 });
  const items = timeline.entries.map((entry) => entry.item);
  const start = items.findLastIndex((item) => item.type === "user_message");
  return items
    .slice(start + 1)
    .filter((item) => item.type === "assistant_message")
    .map((item) => item.text)
    .join("\n\n");
}

// Events: {type:"started", agentId, workspaceId}, {type:"text", text} (whole reply
// so far), then {type:"done", text, status} or {type:"error", message}.
async function ask(client, request) {
  let agentId = request.agentId;
  let workspaceId = request.workspaceId ?? null;
  if (agentId) {
    await client.sendAgentMessage(agentId, request.prompt);
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
