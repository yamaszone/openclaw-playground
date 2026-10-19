#!/usr/bin/env bash
#
# Test 6: memory under load. Runs a fixed scenario through `openclaw agent`
# while sample.sh records memory, and Hubble records egress (Test 7).
#
# Phases: idle -> one chat -> browser task -> 3 concurrent chats -> cooldown.
# Uses a handful of short, low-thinking prompts to keep model spend small.
#
# Usage: load.sh [context] [namespace] [out_dir]

set -euo pipefail

CTX="${1:-oc-lab}"; NS="${2:-openclaw}"; OUT="${3:-captures}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"
LABEL="$OUT/.phase"; MEM="$OUT/01-memory.csv"; EGRESS="$OUT/01-egress.jsonl"

k() { kubectl --context "$CTX" -n "$NS" "$@"; }
phase() { echo "$1" > "$LABEL"; echo "## $(date +%T) phase: $1" >&2; }
turn() {  # turn <session-key> <message>
    k exec deploy/openclaw -c gateway -- openclaw agent --agent default \
        --session-key "$1" --thinking low --timeout 300 -m "$2" >/dev/null 2>&1 \
        || echo "## turn $1 failed" >&2
}

phase idle
"$HERE/sample.sh" "$LABEL" "$CTX" "$NS" 5 > "$MEM" &
SAMPLER=$!
kubectl --context "$CTX" -n kube-system exec ds/cilium -c cilium-agent -- \
    hubble observe --namespace "$NS" --traffic-direction egress --follow -o jsonpb > "$EGRESS" 2>/dev/null &
HUBBLE=$!
trap 'kill $SAMPLER $HUBBLE 2>/dev/null || true; rm -f "$LABEL"' EXIT

sleep 120

phase single-chat
turn load-a "In two sentences, what is Kubernetes?"
sleep 20

phase browser-task
turn load-b "Use the browser tool to open https://example.com and tell me the page heading."
sleep 20

phase concurrent-3
turn load-c "Name three prime numbers." &
turn load-d "Name three rivers." &
turn load-e "Name three colors." &
wait %1 %2 %3 2>/dev/null || true
sleep 20

phase cooldown
sleep 120

echo "## done: $MEM, $EGRESS" >&2
