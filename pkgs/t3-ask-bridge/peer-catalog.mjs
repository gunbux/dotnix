// The supervisor writes this private snapshot atomically from the official CLI.
// Read and validate on every poll so a dead refresher cannot look up to date.
import { closeSync, constants, fstatSync, openSync, readFileSync } from "node:fs";
import { PeerError } from "./peers.mjs";

export function readPeerCatalog(path, { now = Date.now(), uid = process.getuid() } = {}) {
  let fd;
  let text;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const stat = fstatSync(fd);
    if (!stat.isFile()) throw new PeerError("peer catalog must be a regular file");
    if (stat.uid !== uid) throw new PeerError("peer catalog has the wrong owner");
    if (stat.mode & 0o077) throw new PeerError("peer catalog must be private (chmod 600)");
    if (stat.size > 256 * 1024) throw new PeerError("peer catalog is too large");
    text = readFileSync(fd, "utf8");
  } catch (error) {
    if (error instanceof PeerError) throw error;
    throw new PeerError("peer catalog cannot be read");
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new PeerError("peer catalog has invalid JSON");
  }
  const safeText = (s, max) => typeof s === "string" && s.length > 0 && s.length <= max && !/[\x00-\x1f\x7f]/.test(s);
  if (!Number.isSafeInteger(value?.updatedAt) || value.updatedAt <= 0 || !Array.isArray(value.links) ||
      value.links.length > 1024 || !value.links.every((link) =>
        safeText(link?.environmentId, 256) && !/[\s/]/.test(link.environmentId) &&
        safeText(link.label, 256) && safeText(link.status, 64))) {
    throw new PeerError("peer catalog has invalid data");
  }
  if (now - value.updatedAt > 60_000) throw new PeerError("peer catalog is stale");
  if (value.updatedAt - now > 5_000) throw new PeerError("peer catalog timestamp is in the future");
  return value.links.map(({ environmentId, label, status }) => ({ environmentId, label, status }));
}
