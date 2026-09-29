#!/usr/bin/env bash
set -e

# Starts dependencies, migrates the database and starts the platform services and Station.
# Stacks built on Face Matcher run this first; they may export STATION_IDENTIFICATION and STATION_PUBLIC_HOST.

if [ ! -f ./secrets/iengine.lic ]; then
  echo "ERROR: secrets/iengine.lic not found. See README.md." >&2
  exit 1
fi
chmod a+r ./secrets/iengine.lic

# run.sh expects iengine.lic next to docker-compose.yml.
[ -e ./iengine.lic ] || ln -sf secrets/iengine.lic ./iengine.lic
chmod a+r ./iengine.lic

# Station hands the browser presigned S3 URLs; they must point at this host.
export STATION_PUBLIC_HOST="${STATION_PUBLIC_HOST:-$(hostname)}"

bash run.sh

station_port="$(grep -E '^STATION_PORT=' ./.env | head -n1 | cut -d '=' -f2- | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/[[:space:]]+$//')"
echo ""
echo "Station     : http://localhost:${STATION_PORT:-${station_port:-8000}}"
echo "REST API    : http://localhost:8098"
echo "GraphQL API : http://localhost:8097/graphql"
