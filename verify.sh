#!/usr/bin/env bash
# Post-boot smoke checks for the corridor-foundation stack. Best-effort; prints PASS/WARN and
# exits non-zero only if a hard check fails. Safe to run any time the stack is up.
#   ./verify.sh                           # full (infra + foundation)
#   ./verify.sh --no-foundation           # infra only (SmartFace + CIGS)
#   ./verify.sh --no-cigs --no-foundation # SmartFace/VPP only (matches run.sh --vpp-only)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_FND=0; NO_CIGS=0; NO_FE=0
for a in "$@"; do
  case "$a" in
    --no-foundation) NO_FND=1 ;;
    --no-cigs)       NO_CIGS=1 ;;
    --no-frontend)   NO_FE=1 ;;
    *) echo "verify.sh: unknown flag: $a (use --no-foundation, --no-cigs and/or --no-frontend)" >&2; exit 2 ;;
  esac
done
FE_PORT="$(grep -E '^FRONTEND_PORT=' "$ROOT/smart-corridors-and-e-gates/.env" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r')"; FE_PORT="${FE_PORT:-8095}"
EXPECTED_CAMERA="test2"; export EXPECTED_CAMERA   # looked up BY NAME — SmartFace reassigns the id on (re)create
PROBE="$ROOT/lib/gql-ws-probe.mjs"
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; Z=$'\033[0m'; else G=""; R=""; Y=""; Z=""; fi
P=0; F=0
pass(){ P=$((P+1)); echo "${G}  ✓${Z} $*"; }
fail(){ F=$((F+1)); echo "${R}  ✗${Z} $*"; }
warn(){ echo "${Y}  !${Z} $*"; }
jq_(){ node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{try{const d=JSON.parse(s);let r=eval(process.argv[1]);console.log(r==null?"":(typeof r=="object"?JSON.stringify(r):r))}catch(e){console.log("")}})' "$1"; }
# All JSON content checks below parse via node. Without it, degrade to warnings (not false failures).
HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1 || warn "node absent — JSON content checks will be skipped (install node ≥18 for full verification)"

echo "──▶ SmartFace"
# Reachability is judged from the Cameras LIST (a stable endpoint), then the expected camera is looked
# up BY NAME. SmartFace mints a fresh UUID whenever a camera is recreated in VPP, so pinning an id is
# fragile — a 404 on a dead id used to be misreported here as "REST not reachable".
cams="$(curl -fsS -m 10 "http://localhost:8098/api/v1/Cameras?PageSize=100" 2>/dev/null)"
if [ -z "$cams" ]; then fail "SmartFace REST not reachable (:8098)"
elif [ "$HAVE_NODE" -eq 0 ]; then warn "REST reachable; camera content check skipped (no node)"
else
  cam="$(printf '%s' "$cams" | jq_ '(d.items||(Array.isArray(d)?d:[])).find(c=>c.name===process.env.EXPECTED_CAMERA)||""')"
  if [ -z "$cam" ]; then
    names="$(printf '%s' "$cams" | jq_ '(d.items||(Array.isArray(d)?d:[])).map(c=>c.name).join(",")')"
    fail "camera '$EXPECTED_CAMERA' not found (REST is up; cameras present: ${names:-none}) — re-seed or ./bundle.sh"
  else
    src="$(printf '%s' "$cam" | jq_ 'd.source')"; en="$(printf '%s' "$cam" | jq_ 'd.enabled')"
    case "$src" in
      *test-data/*) pass "camera $EXPECTED_CAMERA source=$src enabled=$en";;
      *)            fail "camera $EXPECTED_CAMERA source unexpected (not a test-data clip): '$src'";;
    esac
  fi
fi
if [ "$HAVE_NODE" -eq 1 ]; then
  wl="$(curl -fsS -m 10 "http://localhost:8098/api/v1/Watchlists?PageSize=50" 2>/dev/null | jq_ '(d.items||[]).map(w=>w.displayName).join(",")')"
  case "$wl" in *GreenList*) pass "GreenList present ($wl)";; *) fail "GreenList missing (watchlists: $wl)";; esac
else warn "watchlist check skipped (no node)"; fi

if [ "$NO_CIGS" -eq 0 ]; then
  echo "──▶ CIGS"
  if curl -fsS -m 8 "http://localhost:8096/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then pass "CIGS health UP"; else fail "CIGS not UP (:8096)"; fi
fi

echo "──▶ RabbitMQ"
if curl -fsS -m 8 -u guest:guest "http://localhost:15672/api/exchanges/%2F/biometric_events" 2>/dev/null | grep -q biometric_events; then
  pass "exchange biometric_events present"; else warn "biometric_events exchange not found yet (appears once the foundation connects)"; fi

if [ "$NO_FND" -eq 0 ]; then
  echo "──▶ Foundation"
  if curl -fsS -m 8 "http://localhost:8090/corridor-foundation/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then pass "foundation health UP"; else fail "foundation not UP (:8090)"; fi
  ver="$(curl -fsS -m 8 "http://localhost:8090/corridor-foundation/version" 2>/dev/null)"; [ -n "$ver" ] && pass "version: $ver" || warn "version endpoint empty"
  # GraphQL: units (no DB needed) + events count
  q='{"query":"{ units { id type } events(take:1){ totalCount } }"}'
  resp="$(curl -fsS -m 12 -H 'Content-Type: application/json' -d "$q" "http://localhost:8090/corridor-foundation/graphql" 2>/dev/null)"
  if [ "$HAVE_NODE" -eq 1 ]; then
    units="$(printf '%s' "$resp" | jq_ '(d.data&&d.data.units||[]).map(u=>u.id).join(",")')"
    case "$units" in *corridor-1*) pass "GraphQL units → $units";; *) fail "GraphQL units query failed (resp: ${resp:0:200})";; esac
    tc="$(printf '%s' "$resp" | jq_ 'd.data&&d.data.events&&d.data.events.totalCount')"
    [ -n "$tc" ] && pass "events.totalCount=$tc (grows as faces are processed)" || warn "events query returned no count yet"
  else warn "GraphQL content checks skipped (no node)"; fi
  # Optional: live subscription smoke (needs node + the probe; ~30s budget)
  if command -v node >/dev/null 2>&1 && [ -f "$PROBE" ]; then
    qf="$(mktemp)"; printf 'subscription { foundationEvents { __typename eventType } }\n' > "$qf"
    if node "$PROBE" --url "ws://localhost:8090/corridor-foundation/graphql" --protocol modern --query-file "$qf" --max 1 --timeout 40 --quiet >/dev/null 2>&1; then
      pass "live subscription delivered an event"; else warn "no live event within 40s (matching may still be warming up)"; fi
    rm -f "$qf"
  fi
fi

if [ "$NO_FE" -eq 0 ] && [ "$NO_FND" -eq 0 ]; then
  echo "──▶ Dashboard (frontend)"
  # SPA is served by nginx
  if curl -fsS -m 8 "http://localhost:$FE_PORT/" 2>/dev/null | grep -qiE '<div id=|<title|<script'; then pass "dashboard serving (:$FE_PORT)"; else fail "dashboard not serving (:$FE_PORT)"; fi
  # nginx proxies the SPA's HTTP query path to the Foundation
  if curl -fsS -m 8 -H 'Content-Type: application/json' -d '{"query":"{ units { id } }"}' "http://localhost:$FE_PORT/graphql-proxy" 2>/dev/null | grep -q corridor-1; then
    pass "/graphql-proxy → Foundation OK"; else fail "/graphql-proxy not reaching Foundation"; fi
  # nginx proxies the SmartFace enrichment path (silhouette/liveness) — warn-only (non-core)
  if curl -fsS -m 8 -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "http://localhost:$FE_PORT/smartface-gql" 2>/dev/null | grep -q __typename; then
    pass "/smartface-gql → SmartFace OK"; else warn "/smartface-gql proxy not responding (silhouette/liveness enrichment only)"; fi
fi

echo
[ "$F" -eq 0 ] && echo "${G}verify: $P passed, 0 failed${Z}" || echo "${R}verify: $P passed, $F FAILED${Z}"
[ "$F" -eq 0 ]
