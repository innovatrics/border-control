#!/usr/bin/env bash
set -e

# Stops Face Matcher and wipes its containers, images and volumes — watchlists, enrolled
# faces, crops and the database are all deleted. The license in ../secrets/ is left alone.

docker compose -f ./docker-compose.yml --env-file ./.env down -v --rmi all 2>/dev/null || true
(cd ./platform && docker compose down -v --rmi all 2>/dev/null || true)
(cd ./platform && docker compose -f dependencies/docker-compose.yml down -v --rmi all 2>/dev/null || true)
