#!/usr/bin/env bash
set -e

# Stops Face Matcher and keeps all data. Stacks built on Face Matcher stop their own
# services first (smart-corridors-and-e-gates/stop.sh does).

docker compose -f ./docker-compose.yml --env-file ./.env down
(cd ./platform && docker compose down)
(cd ./platform && docker compose -f dependencies/docker-compose.yml down)
