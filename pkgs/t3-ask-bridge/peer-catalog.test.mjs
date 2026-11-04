import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { readPeerCatalog } from "./peer-catalog.mjs";

const NOW = 1_800_000_000_000;
const link = { environmentId: "peer-1", label: "MacBook", status: "reachable" };
function catalog(t, value = { updatedAt: NOW, links: [link] }) {
  const dir = mkdtempSync(join(tmpdir(), "t3-peer-catalog-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, "peers.json");
  writeFileSync(path, JSON.stringify(value), { mode: 0o600 });
  return path;
}

test("private current peer catalog supplies links", (t) => {
  assert.deepEqual(readPeerCatalog(catalog(t), { now: NOW }), [link]);
});

test("stale catalog and excessive future timestamp are rejected", (t) => {
  for (const updatedAt of [NOW - 60_001, NOW + 5_001]) {
    assert.throws(() => readPeerCatalog(catalog(t, { updatedAt, links: [link] }), { now: NOW }), /peer catalog.*(?:stale|future)/);
  }
});

test("catalog must be a private regular file owned by the current user", (t) => {
  const path = catalog(t);
  chmodSync(path, 0o640);
  assert.throws(() => readPeerCatalog(path, { now: NOW }), /peer catalog.*private/);
  chmodSync(path, 0o600);
  const symlink = `${path}.link`;
  symlinkSync(path, symlink);
  assert.throws(() => readPeerCatalog(symlink, { now: NOW }), /peer catalog/);
  assert.throws(() => readPeerCatalog(path, { now: NOW, uid: process.getuid() + 1 }), /peer catalog.*owner/);
});

test("malformed catalogs are rejected without logging their contents", (t) => {
  const invalid = [null, {}, { updatedAt: NOW, links: null },
    { updatedAt: NOW, links: [{ ...link, environmentId: "" }] },
    { updatedAt: NOW, links: [{ ...link, label: "private\nlog" }] },
    { updatedAt: NOW, links: [{ ...link, status: 1 }] },
  ];
  for (const value of invalid) {
    assert.throws(() => readPeerCatalog(catalog(t, value), { now: NOW }), /^Error: peer catalog has invalid data$/);
  }
  const path = catalog(t);
  writeFileSync(path, '{"private-url":"https://secret.invalid/credential"');
  assert.throws(() => readPeerCatalog(path, { now: NOW }), /^Error: peer catalog has invalid JSON$/);
});
