#!/usr/bin/env bash
#
# Test 5b: run two gateway replicas on the same state volume and record what
# OpenClaw does (refuse, corrupt, or standby). Restores one replica at the end.
#
# Usage: replicas.sh [context] [namespace] [wait_seconds]

set -euo pipefail

CTX="${1:-oc-lab}"; NS="${2:-openclaw}"; WAIT="${3:-120}"
k() { kubectl --context "$CTX" -n "$NS" "$@"; }

restore() { k scale deploy/openclaw --replicas=1 >/dev/null; }
trap restore EXIT

echo "## scaling to 2 replicas; waiting ${WAIT}s"
k scale deploy/openclaw --replicas=2 >/dev/null
sleep "$WAIT"

echo "## pods"
k get pods -l app=openclaw -o wide

for p in $(k get pods -l app=openclaw -o name); do
    echo "## $p status"
    k get "$p" -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} restarts={.restartCount} last={.lastState.terminated.reason}{"\n"}{end}'
    echo "## $p log lines about locks, leases and errors"
    k logs "$p" -c gateway --tail=300 2>&1 \
        | grep -iE 'lease|lock|exclusive|owner|standby|another|already|corrupt|fatal|error' \
        | tail -12 | cut -c1-240 || true
done

echo "## readiness of each pod"
for p in $(k get pods -l app=openclaw -o name); do
    printf '%s ' "$p"
    k exec "$p" -c gateway -- node -e "require('http').get('http://127.0.0.1:18789/readyz',r=>{let b='';r.on('data',d=>b+=d);r.on('end',()=>console.log(r.statusCode,b.slice(0,160)))}).on('error',e=>console.log('ERR',e.message))" 2>&1 || true
done
