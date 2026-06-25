#!/usr/bin/env bash
set -e

[ -e ./vpp/iengine.lic ] || ln -sf ../secrets/iengine.lic ./vpp/iengine.lic

(cd ./vpp && bash run.sh)

docker run --rm --network sf-network --entrypoint sh minio/mc -c \
  "mc alias set l http://minio:9000 minioadmin minioadmin && mc mb --ignore-existing l/corridor-foundation"

docker compose -f ./docker-compose.yml --env-file ./.env up -d

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-foundation/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
