#!/usr/bin/env bash
set -e

# Stops everything and wipes the containers, images and volumes of both modules. MCT keeps
# its own project and volumes; reset it separately (see README.md).

docker compose -f ./docker-compose.yml --env-file ./.env down -v --rmi all 2>/dev/null || true
(cd ../face-matcher && bash factory-reset.sh)
