#!/usr/bin/env bash
set -e

# Starts Face Matcher (face-matcher/), then the corridor services. MCT is separate, see README.md.

export STATION_IDENTIFICATION=false
export STATION_PUBLIC_HOST="${STATION_PUBLIC_HOST:-$(hostname)}"

# One license for everything. Face Matcher looks for it in its own secrets/.
if [ ! -f ./secrets/iengine.lic ]; then
  echo "ERROR: secrets/iengine.lic not found. See README.md." >&2
  exit 1
fi
chmod a+r ./secrets/iengine.lic
[ -e ./face-matcher/secrets/iengine.lic ] || ln -sf ../../secrets/iengine.lic ./face-matcher/secrets/iengine.lic

(cd ./face-matcher && bash start.sh)

# Create the Hub's crop bucket on the platform's S3 storage.
PLATFORM=./face-matcher
getvalue() { grep -E "^$1=" "$PLATFORM/.env" | head -n1 | cut -d '=' -f2- | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/[[:space:]]+$//'; }
docker run --rm --network face-matcher-network "$(getvalue REGISTRY)admin:$(getvalue VERSION)" \
  ensure-s3-bucket-exists \
    --endpoint "$(getvalue S3Bucket__Endpoint)" --access-key "$(getvalue S3Bucket__AccessKey)" \
    --secret-key "$(getvalue S3Bucket__SecretKey)" --bucket-name corridor-hub

# Give the platform APIs a head start before Hub and CIGS connect.
sleep 10

# The platform recreates its API containers; recreate the corridor services so they resolve the new addresses.
docker compose -f ./docker-compose.yml --env-file ./.env up -d --force-recreate

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-hub/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
echo "Station            : http://localhost:8000"
echo "REST API           : http://localhost:8098"
echo "GraphQL API        : http://localhost:8097/graphql"
