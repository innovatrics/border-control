#!/usr/bin/env bash
set -euo pipefail

REQUIRED_DOCKER_VERSION="20.10.10"
ENV_FILE=".env"

# ── Helpers ────────────────────────────────────────────────────────────────────

log()  { echo "[border-control] $*"; }
fail() { echo "[border-control] ERROR: $*" >&2; exit 1; }

getvalue() {
  local key="$1"
  grep -E "^${key}=" "${ENV_FILE}" | cut -d'=' -f2- | tr -d '\r'
}

version_gte() {
  # returns 0 if $1 >= $2
  printf '%s\n%s' "$2" "$1" | sort -V -C
}

# ── Pre-flight checks ──────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  fail "Docker is not installed. See https://docs.docker.com/get-docker/"
fi

DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
if ! version_gte "${DOCKER_VERSION}" "${REQUIRED_DOCKER_VERSION}"; then
  fail "Docker ${REQUIRED_DOCKER_VERSION}+ required (found ${DOCKER_VERSION})"
fi

if [[ ! -f iengine.lic ]]; then
  fail "License file 'iengine.lic' not found in $(pwd). Obtain it from the Innovatrics Customer Portal."
fi

# ── Read config ────────────────────────────────────────────────────────────────

REGISTRY=$(getvalue REGISTRY)
SF_VERSION=$(getvalue SF_VERSION)
DB_ENGINE=$(getvalue Database__DbEngine)

log "Registry : ${REGISTRY}"
log "SF version: ${SF_VERSION}"
log "DB engine : ${DB_ENGINE}"

# ── Network ────────────────────────────────────────────────────────────────────

if ! docker network inspect sf-network &>/dev/null; then
  log "Creating docker network 'sf-network'..."
  docker network create sf-network
fi

# ── Dependencies (pgsql / rmq / minio) ────────────────────────────────────────

log "Starting infrastructure services..."
docker compose -f sf_dependencies/docker-compose.yml up -d

log "Waiting for PostgreSQL to be ready..."
until docker compose -f sf_dependencies/docker-compose.yml exec -T pgsql \
  pg_isready -U postgres &>/dev/null; do
  sleep 2
done

# ── Database bootstrap ─────────────────────────────────────────────────────────

log "Creating SmartFace database (if not exists)..."
docker compose -f sf_dependencies/docker-compose.yml exec -T pgsql \
  psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='smartface'" \
  | grep -q 1 || \
  docker compose -f sf_dependencies/docker-compose.yml exec -T pgsql \
  psql -U postgres -c "CREATE DATABASE smartface"

# ── RabbitMQ bootstrap ─────────────────────────────────────────────────────────

log "Waiting for RabbitMQ to be ready..."
until docker compose -f sf_dependencies/docker-compose.yml exec -T rmq \
  rabbitmqctl status &>/dev/null; do
  sleep 2
done

log "Configuring RabbitMQ user permissions..."
docker compose -f sf_dependencies/docker-compose.yml exec -T rmq \
  rabbitmqctl set_permissions -p / guest ".*" ".*" ".*" || true

# ── MinIO bucket ───────────────────────────────────────────────────────────────

BUCKET=$(getvalue S3Bucket__BucketName)
log "Ensuring MinIO bucket '${BUCKET}' exists..."
docker run --rm --network sf-network \
  minio/mc sh -c "
    mc alias set local http://minio:9000 minioadmin minioadmin &&
    mc mb --ignore-existing local/${BUCKET}
  "

# ── SmartFace migrations ───────────────────────────────────────────────────────

log "Running SmartFace database migrations..."
docker compose run --rm SFBase

# ── Main services ──────────────────────────────────────────────────────────────

log "Starting Smart Corridors and e-Gates services..."
docker compose up -d

log ""
log "All services started."
log "  SmartFace Station : http://localhost:8000"
log "  REST API          : http://localhost:8098"
log "  GraphQL API       : http://localhost:8097"
log "  OData API         : http://localhost:8099"
log "  RabbitMQ UI       : http://localhost:15672  (guest/guest)"
log "  MinIO Console     : http://localhost:9001   (minioadmin/minioadmin)"
log "  pgAdmin           : http://localhost:7070   (admin@admin.com/admin)"
