# Watch gateway runtime

The bridge and this headless T3 server share a pod network. T3 listens only on loopback. A private PVC subdirectory supplies scoped RPC and MCP credentials to the bridge. The image contains code and tools, without account state or tokens.

Build the OCI archives:

```sh
nix build --no-link --print-out-paths .#t3-ask-bridge-image .#t3-watch-gateway-image
```

The images run as UID/GID 65532. Only the bridge listens on the pod interface. Image tags derive from their Nix output and are immutable. Kubernetes manifests and the operator workflow live in `gunbux/pinfra/k8s/apps/t3-watch-gateway`.

Before starting its private server, the supervisor enables Linked environments in the pinned runtime settings and preserves other settings. Target machines must enable Settings → Labs → Linked environments too.

The supervisor creates private credentials on first boot and retains them across restarts. It verifies RPC and MCP access before publishing a `ready` marker. The init container removes any stale marker before both regular containers start. The bridge waits beside T3, never in an init container.

T3 0.1.7 does not expose `t3_environment_links` through its public MCP endpoint. The supervisor uses the supported `t3 environment list --json` command every 15 seconds. It writes only environment ID, label, and reachability into `peers.json`. The bridge rejects stale or unsafe catalogs. MCP still supplies thread and pending-question operations.

This deployment supports one exact T3 Connect URL per linked machine. Alternate routes can make the CLI's sequential reachability checks exceed the 20-second discovery deadline. The operator wizard refuses to retain links with extra URLs. Do not add alternate routes outside that workflow.

T3 currently requires full-access links to answer questions in pre-existing target threads. The operator must approve that broad grant separately for each machine. Target machines must remain awake with T3 servers running. Use a background T3 service on targets when desktop windows should close independently.

Generated local bridge tokens last 365 days. There is no automatic renewal. Rotate them through the T3 auth CLI, revoke old grants, replace the private files, and restart the pod before expiry. Readiness fails when the RPC credential stops working. Keep credential backups private and preserve numeric owners and file modes.

Unit tests:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 pkgs/t3-watch-gateway/gateway_test.py
```

A Docker smoke test uses fresh disposable volumes and three containers to model a shared pod network. It checks authenticated HTTP, credential persistence, restart recovery, and SIGTERM cleanup. It does not sign in to T3 Connect or deploy Kubernetes resources.

```sh
python3 pkgs/t3-watch-gateway/docker_smoke.py /path/to/pinfra/k8s/apps/t3-watch-gateway/image-lock.json
```

The archives in the image lock must exist locally. The test loads them into the local Docker daemon and removes only its own containers and volume afterward. It never uses workstation account state or publishes an image.
