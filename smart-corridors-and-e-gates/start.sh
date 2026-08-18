#!/usr/bin/env bash
set -e

[ -e ./vpp/iengine.lic ] || ln -sf ../secrets/iengine.lic ./vpp/iengine.lic

(cd ./vpp && bash run.sh)

docker run --rm --network sf-network --entrypoint sh minio/mc -c \
  "mc alias set l http://minio:9000 minioadmin minioadmin && mc mb --ignore-existing l/corridor-hub"

# vpp/run.sh returns as soon as `compose up -d` is issued, so pgsql and rmq may still be
# starting. Give them a head start before hub and CIGS open their connections; if they are not
# ready in time the healthchecks in docker-compose.yml plus autoheal recover the containers.
sleep 10

docker compose -f ./docker-compose.yml --env-file ./.env up -d

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-hub/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
