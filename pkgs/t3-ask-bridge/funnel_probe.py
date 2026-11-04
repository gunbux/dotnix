"""Opt-in, foreground-only port-443 comparison for the existing public bridge."""
import argparse
import json
import signal
import subprocess
import tempfile
import time
from pathlib import Path

TARGET = "http://127.0.0.1:8789"


def port_view(config, port):
    result = []
    part = {
        "TCP": config.get("TCP", {}).get(str(port)),
        "Web": {k: v for k, v in config.get("Web", {}).items() if k.endswith(":" + str(port))},
        "AllowFunnel": {k: v for k, v in config.get("AllowFunnel", {}).items() if k.endswith(":" + str(port))},
    }
    if part["TCP"] is not None or part["Web"] or part["AllowFunnel"]:
        result.append(part)
    for name in ("Foreground", "Services"):
        for child in config.get(name, {}).values():
            result.extend(port_view(child, port))
    return result


def preflight(config):
    if port_view(config, 443):
        raise RuntimeError("Port 443 already has a Tailscale configuration; refusing to change it")
    if config.get("TCP", {}).get("8443", {}).get("HTTPS") is not True:
        raise RuntimeError("Existing port 8443 is not an HTTPS bridge")
    hosts = [k for k, v in config.get("Web", {}).items()
             if k.endswith(":8443") and v.get("Handlers", {}).get("/", {}).get("Proxy") == TARGET]
    if len(hosts) != 1 or config.get("AllowFunnel", {}).get(hosts[0]) is not True:
        raise RuntimeError("The same bridge is not already public on port 8443; refusing new exposure")
    return port_view(config, 8443)


def read_config(binary):
    return json.loads(subprocess.check_output([binary, "serve", "status", "--json"], stderr=subprocess.PIPE))


def run_probe(binary="tailscale", seconds=600, ready_timeout=30):
    before = preflight(read_config(binary))
    with tempfile.TemporaryDirectory(prefix="helloride-funnel-probe-") as directory:
        log_path = Path(directory) / "funnel.log"
        with log_path.open("w+") as log:
            log_path.chmod(0o600)
            # No --bg: Tailscale owns this session and removes it when this child exits.
            child = subprocess.Popen([binary, "funnel", "--https=443", TARGET], stdout=log, stderr=log)
            try:
                ready_by = time.monotonic() + ready_timeout
                while True:
                    if child.poll() is not None:
                        raise RuntimeError("Foreground Funnel exited before the probe became ready")
                    current = read_config(binary)
                    if port_view(current, 8443) != before:
                        raise RuntimeError("Existing port 8443 changed during startup")
                    if port_view(current, 443):
                        break
                    if time.monotonic() >= ready_by:
                        raise RuntimeError("Port 443 did not become ready")
                    time.sleep(0.1)
                print("Temporary public port 443 is ready; existing port 8443 is unchanged", flush=True)
                end = time.monotonic() + seconds
                while time.monotonic() < end:
                    if child.poll() is not None:
                        raise RuntimeError("Foreground Funnel stopped during the probe")
                    time.sleep(min(0.5, max(0, end - time.monotonic())))
            finally:
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
                cleanup_by = time.monotonic() + 5
                while port_view(read_config(binary), 443) and time.monotonic() < cleanup_by:
                    time.sleep(0.1)
                after = read_config(binary)
                if port_view(after, 8443) != before or port_view(after, 443):
                    raise RuntimeError("Probe cleanup needs inspection; no broad reset was attempted")
                print("Temporary port 443 removed; existing port 8443 is unchanged", flush=True)


def interrupt(signum, frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Publish temporary port 443; requires operator approval")
    parser.add_argument("--seconds", type=int, default=600)
    args = parser.parse_args()
    if not 60 <= args.seconds <= 900:
        parser.error("--seconds must be between 60 and 900")
    if not args.run:
        preflight(read_config("tailscale"))
        print("Read-only preflight passes: port 443 is unused and the same bridge is already public on 8443")
        return
    signal.signal(signal.SIGTERM, interrupt)
    run_probe(seconds=args.seconds)


if __name__ == "__main__":
    main()
