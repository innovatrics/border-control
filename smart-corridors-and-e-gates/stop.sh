#!/usr/bin/env bash
set -e

# Stops the corridor services and the Face Matcher module underneath, keeping all data.
# MCT is a separate Compose project and is not touched — see README.md.

docker compose -f ./docker-compose.yml --env-file ./.env down
(cd ../face-matcher && bash stop.sh)
