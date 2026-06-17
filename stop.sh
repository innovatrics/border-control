#!/usr/bin/env bash
# Tear down everything. Keeps data volumes by default (seed + buckets survive).
# Pass --wipe to also drop Postgres / MinIO / RabbitMQ volumes (next run.sh re-seeds).
#
#   ./stop.sh           # stop stack, keep data
#   ./stop.sh --wipe    # stop stack + delete volumes
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPP_DIR="$ROOT/vpp"
SC_DIR="$ROOT/smart-corridors-and-e-gates"
WIPE=0; [ "${1:-}" = "--wipe" ] && WIPE=1
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
VOLFLAG=""; [ "$WIPE" -eq 1 ] && VOLFLAG="-v"

echo "──▶ Smart Corridors & e-Gates (Foundation + CIGS + frontend) down"
$DC -p cfs-corridor -f "$SC_DIR/docker-compose.yml" down --remove-orphans $VOLFLAG 2>/dev/null || true

echo "──▶ VPP / SmartFace down"
$DC -p cfs-vpp -f "$VPP_DIR/docker-compose.yml" down --remove-orphans $VOLFLAG 2>/dev/null || true

echo "──▶ Infrastructure (Postgres + RabbitMQ + MinIO) down"
$DC -p cfs-deps -f "$VPP_DIR/sf_dependencies/docker-compose.yml" down --remove-orphans $VOLFLAG 2>/dev/null || true

[ "$WIPE" -eq 1 ] && echo "✓ stopped + volumes wiped" || echo "✓ stopped (data volumes kept; use --wipe to remove)"
