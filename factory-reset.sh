#!/usr/bin/env bash
set -e

# Stops everything and deletes containers, images and volumes. MCT is separate, see README.md.
docker compose -f ./docker-compose.yml --env-file ./.env down -v --rmi all 2>/dev/null || true
(cd ./face-matcher && bash factory-reset.sh)
