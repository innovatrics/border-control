#!/usr/bin/env bash
set -e

# The license must exist; keep it readable by any user the containers may run as.
if [ ! -f ./secrets/iengine.lic ]; then
  echo "ERROR: ./secrets/iengine.lic not found. Obtain a license (see README.md) and place it there." >&2
  exit 1
fi
chmod a+r ./secrets/iengine.lic

[ -e ./vpp/iengine.lic ] || ln -sf ../secrets/iengine.lic ./vpp/iengine.lic

(cd ./vpp && bash run.sh)

docker run --rm --network sf-network --entrypoint sh minio/mc -c \
  "mc alias set l http://minio:9000 minioadmin minioadmin && mc mb --ignore-existing l/corridor-hub"

sleep 10

docker compose -f ./docker-compose.yml --env-file ./.env up -d

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-hub/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
