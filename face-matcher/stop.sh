#!/usr/bin/env bash
set -e

# Stops everything, keeps data.
docker compose -f ./docker-compose.yml --env-file ./.env down
(cd ./platform && docker compose down)
(cd ./platform && docker compose -f dependencies/docker-compose.yml down)
