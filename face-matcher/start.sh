#!/usr/bin/env bash
set -e

# Brings up Face Matcher: the platform (dependencies, database migration, S3 bucket, engine
# services) and then Station. Stacks that build on Face Matcher call this script first and
# add their own services afterwards; they may export STATION_IDENTIFICATION and
# STATION_PUBLIC_HOST to adjust Station before it starts.

# One license file serves both modules, so it lives at the repository root.
if [ ! -f ../secrets/iengine.lic ]; then
  echo "ERROR: no iengine.lic in secrets/ at the repository root. Obtain a license (see README.md) and place it there." >&2
  exit 1
fi
chmod a+r ../secrets/iengine.lic

# The platform's run.sh expects iengine.lic next to its docker-compose.yml.
[ -e ./platform/iengine.lic ] || ln -sf ../../secrets/iengine.lic ./platform/iengine.lic
chmod a+r ./platform/iengine.lic

# Bring up the platform: dependencies, database migration, S3 bucket and engine services.
(cd ./platform && bash run.sh)

# Station hands the browser presigned S3 URLs; they must point at this host, not at "seaweedfs".
export STATION_PUBLIC_HOST="${STATION_PUBLIC_HOST:-$(hostname)}"

# platform/run.sh recreates its API containers, so recreate Station too: its configuration is
# resolved at startup and would otherwise keep pointing at the previous container addresses.
docker compose -f ./docker-compose.yml --env-file ./.env up -d --force-recreate

# STATION_PORT is read by compose from .env, not by this shell — read it back for the summary.
station_port="$(grep -E '^STATION_PORT=' ./.env | head -n1 | cut -d '=' -f2- \
  | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/[[:space:]]+$//')"

echo ""
echo "Face Matcher Station : http://localhost:${STATION_PORT:-${station_port:-8000}}"
echo "REST API             : http://localhost:8098"
echo "GraphQL API          : http://localhost:8097/graphql"
