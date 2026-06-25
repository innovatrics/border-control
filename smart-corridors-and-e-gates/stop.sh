#!/usr/bin/env bash
set -e

docker compose -f ./docker-compose.yml down
(cd ./vpp && docker compose down)
(cd ./vpp && docker compose -f sf_dependencies/docker-compose.yml down)
