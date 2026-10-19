#!/usr/bin/env bash
#
# Sample gateway container memory every N seconds until killed. Prints CSV:
#   time,label,cgroup_mib,anon_mib,gateway_rss_mib,codex_rss_mib,cli_rss_mib,other_rss_mib,codex_procs
# cgroup_mib is memory.current: what the limit and the OOM killer act on.
# The label is read from a file so a driver script can mark test phases.
#
# Usage: sample.sh <label_file> [context] [namespace] [interval_seconds]

set -euo pipefail

LABEL_FILE="$1"; CTX="${2:-oc-lab}"; NS="${3:-openclaw}"; EVERY="${4:-5}"

read -r -d '' PROBE <<'JS' || true
const fs = require("fs");
const mib = n => (n / 1048576).toFixed(0);
const cur = +fs.readFileSync("/sys/fs/cgroup/memory.current", "utf8");
const anon = +/^anon (\d+)/m.exec(fs.readFileSync("/sys/fs/cgroup/memory.stat", "utf8"))[1];
const rss = { gateway: 0, codex: 0, cli: 0, other: 0 }; let codex = 0;
for (const p of fs.readdirSync("/proc").filter(d => /^\d+$/.test(d))) {
  try {
    const cmd = fs.readFileSync(`/proc/${p}/cmdline`, "utf8");
    const kb = +((/VmRSS:\s+(\d+)/.exec(fs.readFileSync(`/proc/${p}/status`, "utf8")) || [, 0])[1]);
    const b = kb * 1024;
    if (p === "1") rss.gateway += b;
    else if (cmd.includes("codex")) { rss.codex += b; if (cmd.includes("/vendor/")) codex++; }
    else if (/index\.js\0(agent|plugins|config)/.test(cmd)) rss.cli += b;
    else if (p !== String(process.pid)) rss.other += b;
  } catch {}
}
console.log([mib(cur), mib(anon), mib(rss.gateway), mib(rss.codex), mib(rss.cli), mib(rss.other), codex].join(","));
JS

echo "time,label,cgroup_mib,anon_mib,gateway_rss_mib,codex_rss_mib,cli_rss_mib,other_rss_mib,codex_procs"
while true; do
    row="$(kubectl --context "$CTX" -n "$NS" exec deploy/openclaw -c gateway -- node -e "$PROBE" 2>/dev/null || echo ",,,,,,")"
    printf '%s,%s,%s\n' "$(date +%T)" "$(cat "$LABEL_FILE" 2>/dev/null || echo -)" "$row"
    sleep "$EVERY"
done
