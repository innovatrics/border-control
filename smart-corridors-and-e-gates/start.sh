#!/usr/bin/env bash
set -e

# Starts Face Matcher (the base module: platform + Station) and then the corridor services.
# MCT is a separate overlay and is never started here — see README.md.

# Station belongs to Face Matcher and keeps the Face Matcher brand here too; only its 1:N
# Identification page is switched off, because the corridor dashboard is the operator surface.
export STATION_IDENTIFICATION=false
# SFS_PUBLIC_HOST was this variable's name before Station moved into the Face Matcher module;
# it is still honoured so existing site scripts keep working.
export STATION_PUBLIC_HOST="${STATION_PUBLIC_HOST:-${SFS_PUBLIC_HOST:-$(hostname)}}"

(cd ../face-matcher && bash start.sh)

# Create the Hub's crop bucket on the platform's S3 storage (SeaweedFS) with its admin tool.
PLATFORM=../face-matcher/platform
getvalue() { grep -E "^$1=" "$PLATFORM/.env" | head -n1 | cut -d '=' -f2- | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/[[:space:]]+$//'; }
docker run --rm --network fm-network "$(getvalue REGISTRY)admin:$(getvalue VERSION)" \
  ensure-s3-bucket-exists \
    --endpoint "$(getvalue S3Bucket__Endpoint)" --access-key "$(getvalue S3Bucket__AccessKey)" \
    --secret-key "$(getvalue S3Bucket__SecretKey)" --bucket-name corridor-hub

# platform/run.sh waits for the database migration, then starts the services asynchronously.
# Give the APIs a head start before Hub and CIGS connect.
sleep 10

# The platform recreates its API containers, so recreate the corridor services too: the
# frontend's nginx resolves the Hub and the APIs at startup and would keep the old addresses.
docker compose -f ./docker-compose.yml --env-file ./.env up -d --force-recreate

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-hub/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
echo "Platform REST API  : http://localhost:8098"
echo "Platform GraphQL   : http://localhost:8097/graphql"
echo "Station            : http://localhost:8000"
