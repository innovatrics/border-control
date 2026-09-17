#!/usr/bin/env bash
set -e

docker compose -f ./docker-compose.yml down -v --rmi all 2>/dev/null || true
(cd ./vpp && docker compose down -v --rmi all 2>/dev/null || true)
(cd ./vpp && docker compose -f sf_dependencies/docker-compose.yml down -v --rmi all 2>/dev/null || true)
