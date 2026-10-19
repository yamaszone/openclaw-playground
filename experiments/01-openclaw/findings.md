# 01 · Findings

Environment: minikube `vfkit` (4 CPU / 8 GB), Kubernetes 1.37, Cilium 1.20, OpenClaw `2026.9.9-slim`,
OpenAI provider key only. Date: 2026-10-17. Reproduce with `./stack oc probe`.

| # | Question | Result | Evidence |
|---|---|---|---|
| 1 | Processes, ports, protocol | One pod, many processes: the gateway (`node … gateway run`, PID 1), worker threads/processes (spawn broker, SQLite store and read-only session workers, state-lease heartbeat), and one Codex app-server per active agent run (Node wrapper + native `codex` binary). Listens on 127.0.0.1:18789 (HTTP + WebSocket RPC for the Control UI) and one internal loopback port. | probe: processes, ports; logs show WS RPCs `sessions.subscribe`, `models.list` |
| 2 | State layout | All state is local files on the PVC under `~/.openclaw`: `state/openclaw.sqlite` (gateway, WAL), `agents/<id>/agent/openclaw-agent.sqlite`, `codex-home/*.sqlite` (threads, queue, goals, memories, logs), persona/memory Markdown in `workspace/` (`AGENTS.md`, `SOUL.md`, `USER.md`, `IDENTITY.md`, `BOOTSTRAP.md`), plugin skills, media. A `gateway.state.lock` plus a lease-heartbeat worker enforce a single writer. | probe: state layout, sqlite files |
| 3 | Default plugins and secret access | 41 of 66 stock plugins enabled by default: model providers (OpenAI, Anthropic, Google, xAI, NVIDIA, OpenRouter, Ollama, vLLM, LiteLLM, LM Studio, SGLang…), tools (browser, computer use, file transfer, GitHub, document extract, geolocation, device pairing), voice and media. Plugins run in the gateway process, so they share its environment and provider keys. | `openclaw plugins list` |
| 4 | Trust model | **Single principal.** (a) The same gateway token in a normal and a private browser window gave both full access to the same sessions and history. (b) A fact told in the Control UI ("favorite color is green") was written to the shared `workspace/USER.md`, and a different person @mentioning the bot in an allowlisted Slack channel got it back. Memory and persona are per agent, not per user. Channel access is gated (Slack `groupPolicy: allowlist`, `dmPolicy: pairing` by default), but anyone allowed in sees everything the agent knows. | `USER.md:23`; Slack reply "green" |
| 5 | Restart and replicas | An in-container `openclaw plugins install @openclaw/slack` was OOMKilled together with the gateway; the container restarted (about 20 s to ready). One gateway per state volume means any crash is a full outage for every user of that gateway. Chat history survived the restart (state is on the PVC). Two replicas: _tbd_. | pod `lastState: OOMKilled, exit 137` |
| 6 | Footprint (idle / busy) | Idle after one UI session: 73m CPU, 1.66 GiB memory (gateway RSS about 1.3 GiB, each Codex process 50–220 MB). The gateway logs a memory-pressure warning above 1 GiB RSS. Busy: _tbd_ | `kubectl top`, gateway logs |
| 7 | Egress | _tbd_ | |

## Setup notes

- **Upstream manifests lag the image.** The `v2026.9.9` tag's Kustomize base still pins image
  `2026.7.1-2-slim` and has no `XDG_CACHE_HOME`. With the `2026.9.9` image the gateway crash-loops:
  `Unable to create fallback OpenClaw temp dir: /home/node/.cache/openclaw-1000`. SQLite snapshot
  staging resolves its root from `XDG_CACHE_HOME`, else `~/.cache`, which is on the read-only root
  filesystem. Fixed in our overlay by setting `XDG_CACHE_HOME=/home/node/.openclaw/.cache` (the PVC),
  as upstream's Kubernetes docs require for images from `2026.8.1`.
- **Image size.** `2026.9.9-slim` is about 3.4 GB; the first pull took about 80 s.
- **Health contract.** `/healthz` returns `{"ok":true,"status":"live"}`. `/readyz` returns readiness
  plus event-loop and CPU diagnostics.
- **The agent harness is Codex.** With an OpenAI key, agent runs go through an embedded Codex
  app-server (`@openai/codex` 0.160) rather than a built-in loop; the default model logged was
  `openai/gpt-6-astra`.
- **Admin CLI shares the gateway's memory budget.** `kubectl exec … openclaw plugins install` runs a
  second full OpenClaw process in the same container. With upstream's 2 GiB limit and a gateway at
  1.4–1.7 GiB, the install pushed the container over the limit and the OOM killer took the gateway
  down. Runtime plugin installs also fetch from npm, so they need registry egress. For Kubernetes,
  bake plugins into the image or install them from an init container. With upstream's read-only
  root filesystem the install also fails until npm's cache is redirected
  (`NPM_CONFIG_CACHE=/home/node/.openclaw/.cache/npm`, now in our overlay). Our overlay now sets
  requests 250m / 1.5Gi and limits 2 CPU / 4Gi; measurements after this point use those limits.
- **Runtime plugin install needs four fixes on upstream's own manifests.** After the memory limit,
  `openclaw plugins install @openclaw/slack` failed three more times:
  1. npm cache on the read-only root filesystem. Setting it in your shell does not help: the CLI
     delegates to the gateway's spawn broker, which runs npm with the *gateway's* environment. Fixed
     with `NPM_CONFIG_CACHE` on the Deployment.
  2. `temp workspace ancestor is group/world writable without sticky protection` because of the
     volume root (`root:root 0777` on minikube hostpath; cloud disks with `fsGroup` are typically
     setgid and group-writable, which this check would also reject).
  3. The same error from `/tmp`: the upstream `emptyDir` is `2777` with no sticky bit.

  Fixed with a `fix-state-perms` init container (root, only `CHOWN`/`FOWNER`) that sets the state
  root to `1000:1000 0700` and `/tmp` to `1777`. After that the install succeeded and was hot-loaded
  ("Applied in Gateway generation 3") with no restart. The plugin lives on the PVC under
  `~/.openclaw/npm/projects/openclaw-slack-*`. The resolver picked `2026.9.9` because the latest
  `@openclaw/slack` (`2026.10.4`) is incompatible with the `2026.9.9` runtime, so plugin and
  runtime versions must move together.
- **The CLI rewrites config.** The gateway migrated `agents.entries` to `agents.list` on boot; running
  `openclaw plugins list` in the pod migrated it back. Avoid CLI commands during measurements, or
  treat the config as changed.

## Summary

_tbd_
