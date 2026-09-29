#!/usr/bin/env bash
set -e

# Stops everything, keeps data.
docker compose down
docker compose -f dependencies/docker-compose.yml down
