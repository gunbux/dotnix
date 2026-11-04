"""Pair two disposable real T3 servers and verify bridge MCP forwarding.

Run with --t3 pointing to the pinned headless binary. No provider is started.
Pairing credentials and server logs stay in a private temporary directory.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def unused_port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return connection.getsockname()[1]


def run(args, env, label, timeout=30):
    try:
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(label + ' timed out') from None
    if result.returncode:
        # CLI errors may repeat credentials from their arguments.
        if '--pairing-code' in args:
            credential = args[args.index('--pairing-code') + 1]
            details = (result.stderr + '\n' + result.stdout).replace(credential, '[redacted]')
            raise RuntimeError(label + ' failed: ' + details[:1200])
        raise RuntimeError(label + ' failed')
    return result.stdout


def stop(process):
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=25)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        raise RuntimeError('Disposable T3 process did not stop gracefully') from None


BRIDGE_CHECK = r'''
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const { mcpClient, peerItems } = await import(pathToFileURL(process.env.T3_PEERS_MODULE));
const { readPeerCatalog } = await import(pathToFileURL(process.env.T3_CATALOG_MODULE));
const [tokenPath, origin, catalogPath] = process.argv.slice(1);
const links = readPeerCatalog(catalogPath);
assert.equal(links.length, 1);
assert.equal(links[0].status, "reachable");
const client = mcpClient({url: `${origin}/mcp`, token: readFileSync(tokenPath, "utf8").trim()});
let forwarded = false;
const checked = {
  async call(name, args) {
    const result = await client.call(name, args);
    if (name === "t3_thread_list" && args.environmentId === links[0].environmentId) {
      assert.ok(Array.isArray(result?.threads));
      assert.equal(result.threads.length, 0);
      forwarded = true;
    }
    return result;
  },
};
assert.deepEqual(await peerItems(checked, () => {}, links), []);
assert.ok(forwarded, "Bridge did not forward its thread list to the linked environment");
console.log("Real linked-environment MCP thread-list forwarding passed");
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--t3', default=os.environ.get('T3_BIN', 't3'))
    args = parser.parse_args()
    binary = shutil.which(args.t3)
    node = shutil.which('node')
    if not binary or not node:
        raise RuntimeError('The pinned T3 binary and Node are required')
    package = Path(__file__).resolve().parent
    bridge = package.parent / 't3-ask-bridge'
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='t3-real-peer-smoke-') as temporary:
        work = Path(temporary)
        env = {'PATH': os.environ.get('PATH', os.defpath), 'HOME': str(work / 'home'),
               'XDG_CONFIG_HOME': str(work / 'config')}
        target_state = work / 'target'
        gateway_state = work / 'gateway'
        secrets = work / 'secrets'
        # Target opt-in is manual. The supervisor must enable its own fresh state.
        settings = target_state / 'userdata' / 'settings.json'
        settings.parent.mkdir(mode=0o700, parents=True)
        settings.write_text(json.dumps({'linkedEnvironmentsEnabled': True}))
        target_port, gateway_port = unused_port(), unused_port()
        while gateway_port == target_port:
            gateway_port = unused_port()
        target_origin = f'http://127.0.0.1:{target_port}'
        gateway_origin = f'http://127.0.0.1:{gateway_port}'
        target = gateway = None
        with (work / 'target.log').open('w') as target_log, (work / 'gateway.log').open('w') as gateway_log:
            try:
                # Pairing output contains a credential: keep the JSON only in memory.
                pairing = json.loads(run([binary, 'auth', 'pairing', 'create', '--base-dir', str(target_state),
                                          '--ttl', '5m', '--label', 'disposable-peer-smoke', '--json'],
                                         env, 'Disposable pairing issue'))
                credential = pairing['credential']
                if not isinstance(credential, str) or not credential:
                    raise RuntimeError('Unexpected pairing credential format')
                target = subprocess.Popen([binary, 'serve', '--base-dir', str(target_state), '--host', '127.0.0.1',
                                           '--port', str(target_port)], env=env, stdout=target_log,
                                          stderr=subprocess.STDOUT, start_new_session=True)
                gateway_env = dict(env, T3_BIN=binary, T3_GATEWAY_BASE_DIR=str(gateway_state),
                                   T3_GATEWAY_SECRETS_DIR=str(secrets), T3_GATEWAY_HOST='127.0.0.1',
                                   T3_GATEWAY_PORT=str(gateway_port))
                gateway = subprocess.Popen([sys.executable, str(package / 'gateway.py')], env=gateway_env,
                                           stdout=gateway_log, stderr=subprocess.STDOUT, start_new_session=True)
                deadline = time.monotonic() + 120
                while not (secrets / 'ready').is_file():
                    if target.poll() is not None or gateway.poll() is not None:
                        raise RuntimeError('Disposable server exited before pairing')
                    if time.monotonic() > deadline:
                        raise RuntimeError('Disposable gateway startup timed out')
                    time.sleep(.25)
                run([binary, 'environment', 'link', target_origin, '--base-dir', str(gateway_state),
                     '--pairing-code', credential, '--access', 'full-access'], env,
                    'Disposable environment link', timeout=45)
                credential = None
                deadline = time.monotonic() + 60
                while True:
                    catalog = json.loads((secrets / 'peers.json').read_text())
                    if any(link['status'] == 'reachable' for link in catalog['links']):
                        break
                    if target.poll() is not None or gateway.poll() is not None:
                        raise RuntimeError('Disposable server exited after pairing')
                    if time.monotonic() > deadline:
                        raise RuntimeError('Linked peer did not appear reachable in the supervisor catalog')
                    time.sleep(.25)
                node_env = dict(env, T3_PEERS_MODULE=str(bridge / 'peers.mjs'),
                                T3_CATALOG_MODULE=str(bridge / 'peer-catalog.mjs'))
                print(run([node, '--input-type=module', '-e', BRIDGE_CHECK, str(secrets / 't3-mcp-token'),
                           gateway_origin, str(secrets / 'peers.json')], node_env, 'Bridge peer MCP forwarding').strip())
            finally:
                try:
                    if gateway is not None:
                        stop(gateway)
                finally:
                    if target is not None:
                        stop(target)
        if (secrets / 'ready').exists():
            raise RuntimeError('Gateway left its readiness marker after shutdown')
        for port in (target_port, gateway_port):
            with socket.socket() as connection:
                if connection.connect_ex(('127.0.0.1', port)) == 0:
                    raise RuntimeError('Disposable T3 listener survived shutdown')
        print('Real peer pairing, reachable catalog, and both-server cleanup passed')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError) as error:
        print('Peer smoke failed: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
