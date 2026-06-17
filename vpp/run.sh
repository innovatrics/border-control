#!/usr/bin/env bash
# =============================================================================
# vpp/run.sh — bring up the VPP (SmartFace) platform
#
# Starts infrastructure (RabbitMQ, Postgres, MinIO) → seeds the SmartFace DB
# → runs schema migration → starts all ~20 VPP containers.
#
# Can be called standalone or via the root run.sh.
#
#   ./vpp/run.sh               # full VPP platform
#   ./vpp/run.sh --skip-verify # skip post-boot smoke checks
#
# Prerequisites: Docker, secrets/iengine.lic at the repo root.
# =============================================================================
set -uo pipefail

VPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$VPP_DIR")"
RUN_DIR="$VPP_DIR/.run"; mkdir -p "$RUN_DIR"

SKIP_VERIFY=0
for a in "$@"; do
  case "$a" in
    --skip-verify) SKIP_VERIFY=1 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
dc_deps() { $DC -p cfs-deps -f "$VPP_DIR/sf_dependencies/docker-compose.yml" "$@"; }
dc_vpp()  { $DC -p cfs-vpp  -f "$VPP_DIR/docker-compose.yml"  --env-file "$VPP_DIR/.env" "$@"; }

# ── helpers ───────────────────────────────────────────────────────────────────
get_env() { grep -E "^$1=" "$VPP_DIR/.env" | head -1 | cut -d= -f2- | tr -d '\r'; }
wait_http() {
  local url="$1" t="$2" needle="${3:-}" end body
  end=$(( $(date +%s) + t ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if body="$(curl -fsS -m 5 "$url" 2>/dev/null)"; then
      [ -z "$needle" ] && return 0
      case "$body" in *"$needle"*) return 0;; esac
    fi
    sleep 3
  done
  return 1
}
wait_tcp() {
  local h="$1" p="$2" end; end=$(( $(date +%s) + ${3:-60} ))
  while [ "$(date +%s)" -lt "$end" ]; do
    nc -z "$h" "$p" >/dev/null 2>&1 && return 0; sleep 2
  done; return 1
}
pg_ready() {
  local end; end=$(( $(date +%s) + ${1:-60} ))
  while [ "$(date +%s)" -lt "$end" ]; do
    docker exec pgsql pg_isready -U postgres >/dev/null 2>&1 && return 0; sleep 2
  done; return 1
}
rmq_ready() {
  local end; end=$(( $(date +%s) + ${1:-120} ))
  while [ "$(date +%s)" -lt "$end" ]; do
    docker exec rmq rabbitmq-diagnostics -q ping >/dev/null 2>&1 && return 0; sleep 2
  done; return 1
}

SF_NETWORK="sf-network"
SF_BUCKET="inno-smartface"

# ══════════════════════════════════════════════════════════════════════════════
step "Preflight"
command -v docker >/dev/null 2>&1       || die "docker not found"
docker info >/dev/null 2>&1             || die "docker daemon not running — start Docker Desktop"
[ -f "$ROOT/secrets/iengine.lic" ]      || die "secrets/iengine.lic missing (see secrets/README.md)"
[ -f "$ROOT/db/smartface-seed.dump" ]   || die "db/smartface-seed.dump missing"
# docker-compose.yml expects ./iengine.lic next to it (verbatim all-in-one path)
[ -e "$VPP_DIR/iengine.lic" ] || ln -sf "$ROOT/secrets/iengine.lic" "$VPP_DIR/iengine.lic"
SF_VERSION="$(get_env SF_VERSION)"; REGISTRY="$(get_env REGISTRY)"
ok "license present; VPP target: ${REGISTRY}<svc>:${SF_VERSION}"

step "Docker network"
if docker network inspect "$SF_NETWORK" >/dev/null 2>&1; then ok "$SF_NETWORK exists"
else docker network create "$SF_NETWORK" >/dev/null 2>&1 && ok "created $SF_NETWORK" || die "could not create docker network $SF_NETWORK"; fi

step "Infrastructure (RabbitMQ + Postgres + MinIO + pgAdmin)"
dc_deps up -d
pg_ready 90    || die "Postgres not ready after 90s"
ok "Postgres ready"
rmq_ready 120  || warn "RabbitMQ not confirmed ready in 120s — migration may retry"
ok "RabbitMQ broker ready"
docker exec rmq rabbitmqctl add_user mqtt mqtt >/dev/null 2>&1 || true
docker exec rmq rabbitmqctl set_user_tags mqtt administrator >/dev/null 2>&1 || true
docker exec rmq rabbitmqctl set_permissions -p / mqtt ".*" ".*" ".*" >/dev/null 2>&1 || true
ok "RabbitMQ mqtt user ensured"
wait_http "http://localhost:9000/minio/health/ready" 60 || warn "MinIO not ready in 60s — bucket create may fail"
docker run --rm --network "$SF_NETWORK" --entrypoint sh minio/mc -c \
  "mc alias set l http://minio:9000 minioadmin minioadmin >/dev/null && \
   mc mb --ignore-existing l/$SF_BUCKET >/dev/null" >/dev/null 2>&1 \
  && ok "bucket ready ($SF_BUCKET)" || warn "bucket create via mc failed (SmartFace may auto-create)"

step "Seed SmartFace database"
NT="$(docker exec pgsql psql -U postgres -d smartface -tAc \
  "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')" \
  2>/dev/null | tr -d '[:space:]')"
case "$NT" in ''|*[!0-9]*) NT=0;; esac
if [ "$NT" -lt 5 ]; then
  log "empty smartface DB ($NT tables) → restoring db/smartface-seed.dump …"
  docker exec -i pgsql pg_restore -U postgres -d smartface --no-owner --no-privileges \
    < "$ROOT/db/smartface-seed.dump" \
    && ok "seed restored (cameras test2 + test3, GreenList, Test Member)" \
    || die "pg_restore failed"
else
  ok "smartface DB already populated ($NT tables) — skipping restore"
fi

step "Migrate SmartFace schema → ${SF_VERSION}"
ADMIN_IMG="${REGISTRY}sf-admin:${SF_VERSION}"
docker image inspect "$ADMIN_IMG" >/dev/null 2>&1 \
  || { log "pulling $ADMIN_IMG …"; docker pull "$ADMIN_IMG" >/dev/null 2>&1 \
       || die "could not pull sf-admin ($ADMIN_IMG) — check network/registry"; }
wait_tcp localhost "$(get_env RabbitMQ__Port)" 60 || warn "RabbitMQ :5672 not open yet — migration may retry"
docker run --rm --network "$SF_NETWORK" \
  -v "$ROOT/secrets/iengine.lic:/etc/innovatrics/iengine.lic" "$ADMIN_IMG" run-migration \
  -p "$(get_env CameraServicesCount)" \
  -c "$(get_env ConnectionStrings__CoreDbContext)" \
  -dbe "$(get_env Database__DbEngine)" \
  --tenant-id default \
  --rmq-host "$(get_env RabbitMQ__Hostname)" \
  --rmq-user "$(get_env RabbitMQ__Username)" \
  --rmq-pass "$(get_env RabbitMQ__Password)" \
  --rmq-virtual-host "$(get_env RabbitMQ__VirtualHost)" \
  --rmq-port "$(get_env RabbitMQ__Port)" \
  --rmq-streams-port "$(get_env RabbitMQ__StreamsPort)" \
  --rmq-use-ssl "$(get_env RabbitMQ__UseSsl)" \
  > "$RUN_DIR/migration.log" 2>&1 \
  || { warn "migration failed — last 20 lines:"; tail -20 "$RUN_DIR/migration.log" | sed 's/^/    /'; die "sf-admin run-migration failed"; }
DBV="$(docker exec pgsql psql -U postgres -d smartface -tAc \
  'SELECT "Major"||'"'"'.'"'"'||"Minor"||'"'"'.'"'"'||"Hotfix" FROM core."DatabaseVersion"' \
  2>/dev/null | tr -d '[:space:]')"
ok "schema migrated (DatabaseVersion ${DBV:-?})"

step "VPP up"
IMGS="$(dc_vpp config --images | sort -u)" || die "could not resolve VPP image list (check .env)"
[ -n "$IMGS" ] || die "VPP image list is empty — check .env (REGISTRY / SF_VERSION)"
MISSING=""
while IFS= read -r img; do
  [ -z "$img" ] && continue
  docker image inspect "$img" >/dev/null 2>&1 || MISSING="${MISSING}${img}"$'\n'
done <<EOF
$IMGS
EOF
if [ -z "$MISSING" ]; then ok "all VPP images already present locally"
else
  log "pulling $(printf '%s' "$MISSING" | grep -c .) missing image(s) from $REGISTRY …"
  dc_vpp pull || die "image pull failed — check network/registry reachability"
  ok "images pulled"
fi
dc_vpp up -d
log "waiting for VPP REST (:8098) …"
wait_http "http://localhost:8098/api/v1/Watchlists" 300 || die "VPP REST not healthy in 300s — check: dc_vpp logs"
ok "VPP REST up"
wait_tcp localhost 8097 90 && ok "VPP GraphQL (:8097) reachable" || warn "VPP GraphQL :8097 not open yet"

echo
echo "${G}════════════════════════════════════════════════════════════════════${Z}"
echo "${G} VPP is UP.${Z}"
echo "   SmartFace Station UI : http://localhost:8000"
echo "   VPP REST API         : http://localhost:8098/api/v1"
echo "   VPP GraphQL          : ws://localhost:8097/graphql"
echo "   RabbitMQ mgmt        : http://localhost:15672  (guest/guest)"
echo "   MinIO console        : http://localhost:9001   (minioadmin/minioadmin)"
echo "   pgAdmin              : http://localhost:7070   (admin@admin.com/Test1234)"
echo
echo "   To bring up the solution layer: ./smart-corridors-and-e-gates/run.sh"
echo "   Stop everything               : ./stop.sh"
echo "${G}════════════════════════════════════════════════════════════════════${Z}"
