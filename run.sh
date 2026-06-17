#!/usr/bin/env bash
# =============================================================================
# run.sh — bring up the full border-control stack
#
# Sequentially runs:
#   1. vpp/run.sh              — infrastructure + VPP / SmartFace platform
#   2. smart-corridors-and-e-gates/run.sh   — CIGS + Foundation + dashboard
#
#   ./run.sh                   # full stack
#   ./run.sh --vpp-only        # VPP platform only (no solution layer)
#   ./run.sh --no-cigs         # skip CIGS in the solution layer
#   ./run.sh --no-frontend     # skip the dashboard
#   ./run.sh --skip-verify     # skip post-boot smoke checks
#
# Prerequisites (see README.md):
#   • Docker Desktop (or Docker Engine + Compose plugin)
#   • secrets/iengine.lic       — IFace engine license
#   • secrets/cigs.env          — IFACE_SPEED_MATCH_PHRASE (for CIGS)
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VPP_ONLY=0; SC_FLAGS=()
for a in "$@"; do
  case "$a" in
    --vpp-only)    VPP_ONLY=1 ;;
    --no-cigs)     SC_FLAGS+=("--no-cigs") ;;
    --no-frontend) SC_FLAGS+=("--no-frontend") ;;
    --skip-verify) SC_FLAGS+=("--skip-verify") ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $a (try --help)"; exit 2 ;;
  esac
done

if [ -t 1 ]; then B=$'\033[34m'; G=$'\033[32m'; Z=$'\033[0m'; else B=""; G=""; Z=""; fi
section() { echo; echo "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Z}"; echo "${B} $*${Z}"; echo "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Z}"; }

section "VPP platform"
bash "$ROOT/vpp/run.sh" --skip-verify

if [ "$VPP_ONLY" -eq 1 ]; then
  echo
  echo "${G} VPP-only mode. To add the solution layer later:${Z}"
  echo "   ./smart-corridors-and-e-gates/run.sh"
  exit 0
fi

section "Smart Corridors & e-Gates"
bash "$ROOT/smart-corridors-and-e-gates/run.sh" "${SC_FLAGS[@]+"${SC_FLAGS[@]}"}"
