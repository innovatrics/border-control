#!/usr/bin/env bash
set -e

# Stops everything and deletes containers, images and volumes. The license in secrets/ is kept.
docker compose -f ./docker-compose.yml --env-file ./.env down -v --rmi all 2>/dev/null || true
(cd ./platform && docker compose down -v --rmi all 2>/dev/null || true)
(cd ./platform && docker compose -f dependencies/docker-compose.yml down -v --rmi all 2>/dev/null || true)
