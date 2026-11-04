import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { once } from "node:events";
import test from "node:test";

async function unusedPort() {
  const reservation = createServer();
  reservation.listen(0, "127.0.0.2");
  await once(reservation, "listening");
  const { port } = reservation.address();
  await new Promise((resolve) => reservation.close(resolve));
  return port;
}

test("bridge serves HTTP on the configured bind address", {
  // Linux routes the loopback subnet automatically; macOS needs an alias.
  skip: process.platform !== "linux",
}, async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "t3-ask-bind-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const token = "test-token-".repeat(4);
  for (const name of ["t3-token", "watch-token"]) {
    await writeFile(join(dir, name), token, { mode: 0o600 });
  }
  const peersFile = join(dir, "peers.json");
  await writeFile(peersFile, JSON.stringify({ updatedAt: Date.now() - 60_001, links: [] }), { mode: 0o600 });
  const port = await unusedPort();
  const child = spawn(process.execPath, [new URL("./bridge.mjs", import.meta.url).pathname], {
    env: {
      ...process.env,
      T3_ASK_HOST: "127.0.0.2",
      T3_ASK_PORT: String(port),
      T3_ASK_T3_TOKEN_FILE: join(dir, "t3-token"),
      T3_ASK_WATCH_TOKEN_FILE: join(dir, "watch-token"),
      T3_ASK_T3_MCP_TOKEN_FILE: join(dir, "absent-mcp-token"),
      T3_ASK_PEERS_FILE: peersFile,
      HELLORIDE_SESSION_FILE: join(dir, "absent-session"),
      HELLORIDE_WATCH_TOKEN_FILE: join(dir, "absent-bike-token"),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { output += data; });
  t.after(async () => {
    if (child.exitCode === null) {
      child.kill("SIGTERM");
      await once(child, "exit");
    }
  });
  const deadline = Date.now() + 5_000;
  let response;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) assert.fail(`bridge exited: ${output}`);
    try {
      response = await fetch(`http://127.0.0.2:${port}/bind-test`);
      break;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  }
  assert.ok(response, `configured listener was unreachable: ${output}`);
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "bad_token" });
  const authorized = await fetch(`http://127.0.0.2:${port}/bind-test`, {
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(authorized.status, 404);
  assert.deepEqual(await authorized.json(), { error: "no_route" });
  const pending = await fetch(`http://127.0.0.2:${port}/v1/pending`, {
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(pending.status, 502);
  assert.deepEqual(await pending.json(), { error: "t3_unavailable" });
  assert.match(output, /error peer catalog is stale/);
});
