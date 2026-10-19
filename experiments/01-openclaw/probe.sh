#!/usr/bin/env bash
#
# Read-only snapshot of a running gateway: processes, listening ports, state
# layout, config and resource use. Safe to re-run; it changes nothing.
#
# Usage: probe.sh [context] [namespace]

set -euo pipefail

CTX="${1:-${LAB_PROFILE:-oc-lab}}"
NS="${2:-${OC_NAMESPACE:-openclaw}}"

x() { kubectl --context "$CTX" -n "$NS" exec deploy/openclaw -c gateway -- "$@"; }
section() { printf '\n## %s\n' "$1"; }

section "processes (pid ppid rss_kb cmd)"
x node -e '
const fs = require("fs");
for (const p of fs.readdirSync("/proc").filter(d => /^\d+$/.test(d))) {
  try {
    const cmd = fs.readFileSync(`/proc/${p}/cmdline`, "utf8").split("\0").join(" ").trim();
    const st = fs.readFileSync(`/proc/${p}/status`, "utf8");
    const ppid = /PPid:\s+(\d+)/.exec(st)[1];
    const rss = (/VmRSS:\s+(\d+)/.exec(st) || [, "0"])[1];
    if (cmd) console.log(p, ppid, rss, cmd.slice(0, 140));
  } catch {}
}'

section "listening TCP ports"
x node -e '
const fs = require("fs");
for (const f of ["/proc/net/tcp", "/proc/net/tcp6"]) {
  for (const l of fs.readFileSync(f, "utf8").split("\n").slice(1)) {
    const c = l.trim().split(/\s+/);
    if (c[3] !== "0A") continue;
    const [addr, port] = c[1].split(":");
    const loop = /^(0100007F|0+1000000|00000000000000000000000001000000)$/.test(addr);
    console.log(parseInt(port, 16), loop ? "loopback" : addr);
  }
}'

section "state layout (~/.openclaw, depth 3)"
x find /home/node/.openclaw -maxdepth 3 -not -path '*/.cache/*' -not -path '*/node_modules/*'

section "state sizes"
x du -sh /home/node/.openclaw/.cache /home/node/.openclaw/workspace /home/node/.openclaw/openclaw.json

section "sqlite files"
x find /home/node/.openclaw -name '*.sqlite*' -o -name '*.db' -o -name '*.db-wal'

section "config (openclaw.json)"
x cat /home/node/.openclaw/openclaw.json

section "resource use"
kubectl --context "$CTX" -n "$NS" top pod --containers 2>/dev/null || echo "metrics not ready"
