#!/usr/bin/env bash
# =============================================================================
# smart-corridors-and-e-gates/run.sh — bring up the solution layer
#
# Assumes VPP is already running (./vpp/run.sh or root ./run.sh).
# Starts: CIGS (identity grouping) → Hub → Frontend dashboard.
#
#   ./smart-corridors-and-e-gates/run.sh
#   ./smart-corridors-and-e-gates/run.sh --no-cigs
#   ./smart-corridors-and-e-gates/run.sh --no-frontend
#   ./smart-corridors-and-e-gates/run.sh --skip-verify
#
# Prerequisites: secrets/cigs.env (IFACE_SPEED_MATCH_PHRASE) at the repo root.
# =============================================================================
set -uo pipefail

SC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SC_DIR")"

NO_CIGS=0; NO_FRONTEND=0; SKIP_VERIFY=0
for a in "$@"; do
  case "$a" in
    --no-cigs)     NO_CIGS=1 ;;
    --no-frontend) NO_FRONTEND=1 ;;
    --skip-verify) SKIP_VERIFY=1 ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $a (try --help)"; exit 2 ;;
  esac
done

# ── logging ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[2m'; Z=$'\033[0m'
else R=""; G=""; Y=""; B=""; D=""; Z=""; fi
log()  { echo "${D}[$(date +%H:%M:%S)]${Z} $*"; }
step() { echo; echo "${B}──▶ $*${Z}"; }
ok()   { echo "${G}  ✓${Z} $*"; }
warn() { echo "${Y}  !${Z} $*"; }
die()  { echo "${R}✗ $*${Z}" >&2; exit 1; }

# ── docker compose detection ──────────────────────────────────────────────────
if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else die "neither 'docker compose' nor 'docker-compose' found"; fi
dc_sceg() { $DC -p cfs-corridor -f "$SC_DIR/docker-compose.yml" --env-file "$SC_DIR/.env" "$@"; }

# ── helpers ───────────────────────────────────────────────────────────────────
get_env() { grep -E "^$1=" "$SC_DIR/.env" | head -1 | cut -d= -f2- | tr -d '\r'; }
wait_http() {
  local url="$1" t="$2" needle="${3:-}" end body
  end=$(( $(date +%s) + t ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if body="$(curl -fsS -m 5 "$url" 2>/dev/null)"; then
      [ -z "$needle" ] && return 0
      case "$body" in *"$needle"*) return 0;; esac
    fi
    sleep 3
  done; return 1
}
detect_host_ip() {
  local ifc cand ip
  ifc="$(route -n get default 2>/dev/null | awk '/interface:/{print $NF; exit}')"
  for cand in "$ifc" en0 en1 en2 eth0; do
    [ -n "$cand" ] || continue
    ip="$(ipconfig getifaddr "$cand" 2>/dev/null || ip -4 addr show "$cand" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
    case "$ip" in [0-9]*.[0-9]*.[0-9]*.[0-9]*) echo "$ip"; return 0;; esac
  done; return 1
}

# ══════════════════════════════════════════════════════════════════════════════
step "Preflight"
command -v docker >/dev/null 2>&1 || die "docker not found"
docker info >/dev/null 2>&1       || die "docker daemon not running"
curl -fsS -m 5 "http://localhost:8098/api/v1/Watchlists" >/dev/null 2>&1 \
  || die "VPP REST not reachable (:8098) — run ./vpp/run.sh first"
ok "VPP is up"

[ -f "$ROOT/secrets/cigs.env" ] && { set -a; . "$ROOT/secrets/cigs.env"; set +a; }
[ -n "${IFACE_SPEED_MATCH_PHRASE:-}" ] \
  || die "IFACE_SPEED_MATCH_PHRASE unset — set it in secrets/cigs.env (see secrets/README.md)"

HARBOR="$(get_env HARBOR)"
CIGS_VERSION="$(get_env CIGS_VERSION)"
HUB_VERSION="$(get_env HUB_VERSION)"
FRONTEND_VERSION="$(get_env FRONTEND_VERSION)"
FRONTEND_PORT="$(get_env FRONTEND_PORT)"; FRONTEND_PORT="${FRONTEND_PORT:-8095}"
FRONTEND_REGISTRY="$(get_env FRONTEND_REGISTRY)"

# Host IP for presigned face-crop URLs (browser must reach MinIO directly)
if [ -z "${HOST_S3_IP:-}" ]; then HOST_S3_IP="$(detect_host_ip || true)"; fi
if [ -n "${HOST_S3_IP:-}" ]; then export HOST_S3_IP; log "host IP for crop URLs: $HOST_S3_IP"
else warn "could not detect host LAN IP — face thumbnails in the dashboard may not load (re-run with HOST_S3_IP=<ip>)"; fi

# Ensure Hub S3 bucket exists
HUB_BUCKET="corridor-foundation"
docker run --rm --network sf-network --entrypoint sh minio/mc -c \
  "mc alias set l http://minio:9000 minioadmin minioadmin >/dev/null && \
   mc mb --ignore-existing l/$HUB_BUCKET >/dev/null" >/dev/null 2>&1 \
  && ok "bucket ready ($HUB_BUCKET)" || warn "bucket create failed (Hub may auto-create)"

if [ "$NO_CIGS" -eq 0 ]; then
  step "CIGS — ${HARBOR}corridor-identity-grouping-service:${CIGS_VERSION}"
  dc_sceg up -d cigs \
    || die "CIGS failed to start — could not pull/run ${HARBOR}corridor-identity-grouping-service:${CIGS_VERSION}"
  wait_http "http://localhost:8096/actuator/health" 120 '"status":"UP"' \
    || { warn "CIGS not UP in 120s — last logs:"; dc_sceg logs --tail 25 cigs | sed 's/^/    /'; die "CIGS failed"; }
  ok "CIGS up (http://localhost:8096)"
fi

step "Hub — ${HARBOR}corridor-foundation-service:${HUB_VERSION}"
[ -f "$SC_DIR/hub/hub.env" ] || die "hub/hub.env missing"
dc_sceg up -d hub \
  || die "Hub failed to start — could not pull/run ${HARBOR}corridor-foundation-service:${HUB_VERSION}"
wait_http "http://localhost:8090/corridor-foundation/actuator/health" 150 '"status":"UP"' \
  || { warn "Hub not UP in 150s — last logs:"; dc_sceg logs --tail 25 hub | sed 's/^/    /'; die "Hub failed"; }
ok "Hub up"

if [ "$NO_FRONTEND" -eq 0 ]; then
  step "Corridor dashboard — ${FRONTEND_REGISTRY}biometriccorridor:${FRONTEND_VERSION}"
  dc_sceg up -d frontend \
    || die "Frontend failed — could not pull/run ${FRONTEND_REGISTRY}biometriccorridor:${FRONTEND_VERSION}"
  wait_http "http://localhost:${FRONTEND_PORT}/" 60 \
    || { warn "Dashboard not serving on :${FRONTEND_PORT} in 60s"; dc_sceg logs --tail 25 frontend | sed 's/^/    /'; die "frontend failed"; }
  ok "Dashboard up"
fi

echo
echo "${G}════════════════════════════════════════════════════════════════════${Z}"
echo "${G} Smart Corridors & e-Gates is UP.${Z}"
[ "$NO_FRONTEND" -eq 0 ] && echo "   Corridor dashboard   : http://localhost:${FRONTEND_PORT}   ◀ the UI"
echo "   Hub GraphiQL         : http://localhost:8090/corridor-foundation/graphiql"
echo "   Hub GraphQL          : http://localhost:8090/corridor-foundation/graphql"
[ "$NO_CIGS" -eq 0 ]    && echo "   CIGS health          : http://localhost:8096/actuator/health"
echo "   SmartFace Station UI : http://localhost:8000"
echo "   VPP REST / GraphQL   : http://localhost:8098   ws://localhost:8097/graphql"
echo "   RabbitMQ mgmt        : http://localhost:15672  (guest/guest)"
echo "   MinIO console        : http://localhost:9001   (minioadmin/minioadmin)"
echo
echo "   Stop everything      : ./stop.sh   (add --wipe to drop data volumes)"
echo "${G}════════════════════════════════════════════════════════════════════${Z}"
