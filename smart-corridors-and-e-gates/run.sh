#!/usr/bin/env bash
set -e

[ -e ./vpp/iengine.lic ] || ln -sf ../secrets/iengine.lic ./vpp/iengine.lic

(cd ./vpp && bash run.sh)

docker run --rm --network sf-network --entrypoint sh minio/mc -c \
  "mc alias set l http://minio:9000 minioadmin minioadmin && mc mb --ignore-existing l/corridor-foundation"

# Host LAN IP for browser-reachable presigned crop URLs (else dashboard thumbnails won't load).
# Honor a caller-provided HOST_S3_IP; else auto-detect (Linux, then macOS); else fall back to 'minio'.
# An exported var takes precedence over --env-file, so ${HOST_S3_IP:-minio} in docker-compose.yml uses it.
if [ -z "${HOST_S3_IP:-}" ]; then
  HOST_S3_IP="$( { ip route get 1.1.1.1 | grep -oP 'src \K[0-9.]+' | head -1; } 2>/dev/null )" || true
fi
if [ -z "${HOST_S3_IP:-}" ]; then
  _ifc="$(route -n get default 2>/dev/null | awk '/interface:/{print $NF}')" || true
  HOST_S3_IP="$(ipconfig getifaddr "${_ifc:-en0}" 2>/dev/null)" || true
fi
if [ -n "${HOST_S3_IP:-}" ]; then
  export HOST_S3_IP
  echo "Crop URL host IP: $HOST_S3_IP"
else
  echo "WARN: could not detect host LAN IP — run 'HOST_S3_IP=<ip> ./run.sh', else crop thumbnails won't load"
fi

docker compose -f ./docker-compose.yml --env-file ./.env up -d

echo ""
echo "Corridor dashboard : http://localhost:8095"
echo "Hub GraphQL        : http://localhost:8090/corridor-foundation/graphql"
echo "CIGS health        : http://localhost:8096/actuator/health"
