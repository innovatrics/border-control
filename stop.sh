#!/usr/bin/env bash
set -e

# Stops the corridor services and Face Matcher, keeps data. MCT is separate, see README.md.
docker compose -f ./docker-compose.yml --env-file ./.env down
(cd ./face-matcher && bash stop.sh)
