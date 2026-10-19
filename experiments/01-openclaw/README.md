# 01 · Vanilla OpenClaw

Run one OpenClaw gateway exactly as upstream ships it for Kubernetes, then take it apart.

**Pinned:** upstream manifests `v2026.9.9`, image `ghcr.io/openclaw/openclaw:2026.9.9-slim`
(see [k8s/kustomization.yaml](k8s/kustomization.yaml)).

## Run

```bash
./stack oc up       # namespace, secret (token + keys from .env), gateway
./stack oc status   # pods, volume, CPU/memory
./stack oc ui       # Control UI on http://127.0.0.1:18789, prints the token
./stack oc logs     # follow gateway logs
./stack oc shell    # shell inside the gateway container
./stack oc down     # delete the namespace and its state volume
```

## What upstream deploys

One `Deployment` (1 replica, `Recreate`), an init container that seeds `openclaw.json` and
`AGENTS.md` onto a 10Gi PVC, a `ClusterIP` service on 18789, and a non-root, read-only-rootfs
gateway container. The gateway binds to loopback inside the pod and is reached by port-forward.

## Checks

| # | Question | How |
|---|---|---|
| 1 | Processes, ports, protocol | `oc shell`: `ps`, `netstat`; Control UI network tab |
| 2 | State layout | `oc shell`: walk `~/.openclaw` (config, SQLite, workspace, skills, memory) |
| 3 | Default plugins and secret access | config + logs; which plugins load, which env they read |
| 4 | Trust model | two Control UI clients on one gateway: can one see or act on the other's sessions? |
| 5 | Restart and replicas | delete the pod mid-session; try 2 replicas on one PVC |
| 6 | Footprint | `oc status` at idle and during a chat |
| 7 | Egress | Hubble flows from the `openclaw` namespace |

Results go in [findings.md](findings.md).
