"""Run a private T3 backend and provision scoped credentials for its watch bridge."""
import argparse
import base64
import hashlib
import secrets as randomness
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import tempfile
import time
from typing import NamedTuple
import urllib.error
import urllib.parse
import urllib.request


class Config(NamedTuple):
    binary: str
    base: Path
    secrets: Path
    port: int

    @property
    def origin(self):
        return f'http://127.0.0.1:{self.port}'


def config():
    if os.environ.get('T3_GATEWAY_HOST', '127.0.0.1') != '127.0.0.1':
        raise RuntimeError('The T3 gateway must listen only on pod loopback')
    port = int(os.environ.get('T3_GATEWAY_PORT', '3773'))
    if not 1 <= port <= 65535:
        raise RuntimeError('Invalid T3 gateway port')
    return Config(os.environ.get('T3_BIN', 't3'),
                  Path(os.environ.get('T3_GATEWAY_BASE_DIR', '/data/t3')),
                  Path(os.environ.get('T3_GATEWAY_SECRETS_DIR', '/data/bridge-secrets')), port)


def read_private(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 16384:
                raise RuntimeError('Gateway credentials must be private files owned by this user')
            with os.fdopen(os.dup(fd), encoding='utf8') as stream:
                value = stream.read()
        finally:
            os.close(fd)
    except OSError:
        raise RuntimeError('Gateway credential cannot be read safely') from None
    return value


def private_secret(path):
    value = read_private(path).strip()
    if len(value) < 32 or '\n' in value or '\r' in value:
        raise RuntimeError('Gateway credential is invalid')
    return value


def private_write(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf8') as stream:
            stream.write(value + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def provision_tokens(binary, base, secrets):
    generated = {}
    for name, subject in [('t3-token', None)]:
        path = secrets / name
        if os.path.lexists(path):
            private_secret(path)
            continue
        args = [binary, 'auth', 'session', 'issue', '--base-dir', str(base),
                '--scope', 'orchestration:read', '--scope', 'orchestration:operate',
                '--ttl', '365d', '--label', 'watch-gateway-' + name, '--token-only']
        if subject:
            args += ['--subject', subject, '--scope', 'relay:read']
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        value = result.stdout.strip()
        if result.returncode != 0 or len(value) < 32 or '\n' in value or '\r' in value:
            raise RuntimeError('Cannot provision scoped gateway credentials')
        generated[path] = value
    for path, value in generated.items():
        private_write(path, value)


def oauth_post(settings, path, payload, form=False):
    data = urllib.parse.urlencode(payload).encode() if form else json.dumps(payload).encode()
    request = urllib.request.Request(settings.origin + path, data=data, headers={
        'Content-Type': 'application/x-www-form-urlencoded' if form else 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'Local MCP approval {path} returned HTTP {error.code}') from None


def issue_mcp_client(settings):
    result = subprocess.run([settings.binary, 'auth', 'pairing', 'create', '--base-dir', str(settings.base),
                             '--ttl', '5m', '--label', 'watch-bridge-local-approval', '--json'],
                            capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError('Cannot approve the local watch MCP client')
    pairing = json.loads(result.stdout)['credential']
    redirect = 'http://127.0.0.1/t3-watch-bridge'
    client = oauth_post(settings, '/oauth/mcp/register', {
        'client_name': 'T3 Watch Bridge', 'redirect_uris': [redirect]})
    verifier = randomness.token_urlsafe(32)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    state = randomness.token_urlsafe(24)
    resource = settings.origin + '/mcp'
    decision = oauth_post(settings, '/oauth/mcp/decision', {
        'authorization': {'response_type': 'code', 'client_id': client['client_id'],
                          'redirect_uri': redirect, 'code_challenge': challenge,
                          'code_challenge_method': 'S256', 'state': state, 'resource': resource},
        'decision': {'_tag': 'pairing-code', 'access': 'full-access', 'code': pairing}})
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(decision['redirectTo']).query)
    if query.get('state') != [state] or len(query.get('code', [])) != 1:
        raise RuntimeError('Local MCP approval did not return the expected state')
    issued = oauth_post(settings, '/oauth/mcp/token', {
        'grant_type': 'authorization_code', 'code': query['code'][0], 'redirect_uri': redirect,
        'client_id': client['client_id'], 'code_verifier': verifier, 'resource': resource}, form=True)
    token, lifetime = issued['access_token'], issued['expires_in']
    payload = token.split('.')[0]
    claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
    if claims.get('rtc') != 'full-access' or not isinstance(lifetime, int) or lifetime <= 86400:
        raise RuntimeError('Local MCP client approval has insufficient access or lifetime')
    return token, lifetime


def ensure_mcp_access(settings):
    path = settings.secrets / 't3-mcp-token'
    metadata_path = settings.secrets / 't3-mcp-session.json'
    token = private_secret(path) if os.path.lexists(path) else None
    if token and os.path.lexists(metadata_path):
        try:
            metadata = json.loads(read_private(metadata_path))
        except ValueError:
            metadata = None
        if (isinstance(metadata, dict) and metadata.get('access') == 'full-access'
                and metadata.get('tokenSha256') == hashlib.sha256(token.encode()).hexdigest()
                and isinstance(metadata.get('expiresAt'), (float, int))
                and metadata['expiresAt'] > time.time() + 86400):
            return
    try:
        token, lifetime = issue_mcp_client(settings)
    except (ValueError, KeyError, TypeError, OSError):
        raise RuntimeError('Cannot provision an approved local MCP client') from None
    private_write(path, token)
    private_write(metadata_path, json.dumps({'access': 'full-access',
        'tokenSha256': hashlib.sha256(token.encode()).hexdigest(), 'expiresAt': time.time() + lifetime}))


def rpc_healthy(settings, require_marker=True):
    try:
        if require_marker:
            if not (settings.secrets / 'ready').is_file():
                return False
            catalog = json.loads(private_secret(settings.secrets / 'peers.json'))
            age = time.time() * 1000 - catalog['updatedAt']
            if not isinstance(catalog.get('links'), list) or not 0 <= age <= 60000:
                return False
        token = private_secret(settings.secrets / 't3-token')
        if require_marker:
            private_secret(settings.secrets / 't3-mcp-token')
        request = urllib.request.Request(settings.origin + '/api/auth/websocket-ticket/rpc', data=b'',
                                         headers={'Authorization': 'Bearer ' + token}, method='POST')
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status == 200 and bool(json.load(response).get('ticket'))
    except (OSError, RuntimeError, ValueError, KeyError, TypeError):
        return False


def mcp_healthy(settings):
    token = private_secret(settings.secrets / 't3-mcp-token')
    headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json',
               'Accept': 'application/json, text/event-stream'}
    def post(body):
        request = urllib.request.Request(settings.origin + '/mcp', data=json.dumps(body).encode(), headers=headers)
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.headers.get('mcp-session-id'):
                headers['mcp-session-id'] = response.headers['mcp-session-id']
            data = response.read().decode()
            if not data.strip():
                return {}
            event = next((line[5:] for line in data.splitlines() if line.startswith('data:')), data)
            return json.loads(event)
    try:
        opened = post({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
            'protocolVersion': '2025-06-18', 'capabilities': {},
            'clientInfo': {'name': 'watch-gateway-health', 'version': '1'}}})
        if 'error' in opened or 'result' not in opened:
            return False
        post({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        checked = post({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
                        'params': {'name': 't3_thread_list', 'arguments': {'allProjects': True, 'limit': 1}}})
        return 'error' not in checked and isinstance(checked.get('result'), dict) and not checked['result'].get('isError')
    except (OSError, RuntimeError, ValueError):
        return False


def refresh_catalog(settings):
    result = subprocess.run([settings.binary, 'environment', 'list', '--base-dir', str(settings.base), '--json'],
                            capture_output=True, text=True, timeout=20)
    if result.returncode != 0:
        raise RuntimeError('Cannot discover linked T3 environments')
    try:
        records = json.loads(result.stdout)
        if not isinstance(records, list):
            raise ValueError()
        links = []
        for record in records:
            if not all(isinstance(record.get(k), str) for k in ('environmentId', 'label', 'status')):
                raise ValueError()
            links.append({k: record[k] for k in ('environmentId', 'label', 'status')})
    except (ValueError, AttributeError):
        raise RuntimeError('Invalid linked-environment discovery result') from None
    private_write(settings.secrets / 'peers.json', json.dumps({'updatedAt': int(time.time() * 1000), 'links': links}))


def enable_peer_links(base):
    directory = base / 'userdata'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / 'settings.json'
    try:
        settings = json.loads(read_private(path)) if os.path.lexists(path) else {}
    except ValueError:
        raise RuntimeError('Gateway settings JSON is invalid') from None
    if not isinstance(settings, dict):
        raise RuntimeError('Gateway settings must be a JSON object')
    if settings.get('linkedEnvironmentsEnabled') is not True:
        settings['linkedEnvironmentsEnabled'] = True
        private_write(path, json.dumps(settings))


def supervise(settings):
    for directory in (settings.base, settings.secrets):
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        if directory.stat().st_uid != os.getuid():
            raise RuntimeError('Gateway state must be owned by this user')
        directory.chmod(0o700)
    enable_peer_links(settings.base)
    marker = settings.secrets / 'ready'
    marker.unlink(missing_ok=True)
    provision_tokens(settings.binary, settings.base, settings.secrets)
    # T3 may print bootstrap credentials. They must not enter container logs.
    child = subprocess.Popen([settings.binary, 'serve', '--base-dir', str(settings.base),
                              '--host', '127.0.0.1', '--port', str(settings.port)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        deadline = time.monotonic() + 120
        while not rpc_healthy(settings, require_marker=False):
            if child.poll() is not None:
                raise RuntimeError('T3 exits before gateway authentication is ready')
            if time.monotonic() >= deadline:
                raise RuntimeError('T3 startup or credential verification deadline exceeded')
            time.sleep(.25)
        ensure_mcp_access(settings)
        if not mcp_healthy(settings):
            raise RuntimeError('Gateway MCP credentials cannot list threads')
        refresh_catalog(settings)
        private_write(marker, 'ready')
        print('T3 watch gateway ready; private RPC and MCP credentials verified', flush=True)
        refreshed = time.monotonic()
        while True:
            try:
                return child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            if time.monotonic() - refreshed >= 15:
                try:
                    ensure_mcp_access(settings)
                    refresh_catalog(settings)
                except (RuntimeError, subprocess.TimeoutExpired):
                    print('Linked-environment discovery failed; retrying', flush=True)
                refreshed = time.monotonic()
    finally:
        marker.unlink(missing_ok=True)
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()


def interrupted(signum, frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--healthcheck', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    settings = config()
    if args.healthcheck:
        return 0 if rpc_healthy(settings) else 1
    signal.signal(signal.SIGTERM, interrupted)
    try:
        return supervise(settings)
    except KeyboardInterrupt:
        return 0
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print('T3 watch gateway failed: ' + str(error), flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
