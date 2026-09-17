#!/usr/bin/env bash
set -e

# The license must exist and be readable by every service user.
if [ ! -f ./secrets/iengine.lic ]; then
  echo "ERROR: ./secrets/iengine.lic not found. Obtain a license (see README.md) and place it there." >&2
  exit 1
fi
chmod a+r ./secrets/iengine.lic

# The VPP release expects iengine.lic next to its docker-compose.yml.
[ -e ./vpp/iengine.lic ] || ln -sf ../secrets/iengine.lic ./vpp/iengine.lic
chmod a+r ./vpp/iengine.lic

# Bring up VPP: dependencies, database migration, S3 bucket and services.
(cd ./vpp && bash run.sh)

# Create the Hub's crop bucket on the VPP S3 storage (SeaweedFS) with the VPP admin tool.
getvalue() { grep -E "^$1=" ./vpp/.env | head -n1 | cut -d '=' -f2- | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/[[:space:]]+$//'; }
docker run --rm --network vpp-network "$(getvalue REGISTRY)admin:$(getvalue VERSION)" \
  ensure-s3-bucket-exists \
    --endpoint "$(getvalue S3Bucket__Endpoint)" --access-key "$(getvalue S3Bucket__AccessKey)" \
    --secret-key "$(getvalue S3Bucket__SecretKey)" --bucket-name corridor-hub

# vpp/run.sh waits for the database migration, then starts the VPP services asynchronously.
# Give the APIs a head start before Hub and CIGS connect.
sleep 10

# SF Station hands the browser presigned S3 URLs; they must point at this host, not at "seaweedfs".
export SFS_PUBLIC_HOST="${SFS_PUBLIC_HOST:-$(hostname)}"

# VPP run.sh recreates its API containers. Recreate the corridor services too so the frontend's
# nginx resolves their current addresses, even when its own image and configuration are unchanged.
docker compose -f ./docker-compose.yml --env-file ./.env up -d --force-recreate

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-hub/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
echo "VPP REST API       : http://localhost:8098"
echo "VPP GraphQL        : http://localhost:8097/graphql"
echo "SF Station         : http://localhost:8000"
