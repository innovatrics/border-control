#!/bin/bash

# Migrates stored face templates to the template model bundled with this version.
# Spawns temporary face detector/extractor workers, runs the migration, then reports
# (dry-run) which faces could not be migrated. Run finalize-non-migrated-faces.sh
# afterwards to mark the remaining faces as errored. Safe to re-run after transient errors.

set -x
set -e

# load shared helpers (getvalue); run this script from the deployment directory
. "$(dirname "$0")/deployment-common.sh"

VERSION="$(getvalue VERSION)"
REGISTRY="$(getvalue REGISTRY)"

ADMIN_IMAGE="${REGISTRY}admin:${VERSION}"
DETECTOR_IMAGE="${REGISTRY}detector:${VERSION}"
EXTRACTOR_IMAGE="${REGISTRY}extractor:${VERSION}"

# stop all services before migration
docker compose down --remove-orphans

# Number of face detector/extractor workers to spawn for the migration (default 3 each).
FACE_DETECTORS_COUNT=${FACE_DETECTORS_COUNT:-3}
FACE_EXTRACTORS_COUNT=${FACE_EXTRACTORS_COUNT:-3}
# Template model version to migrate to. 52=fast, 53=balanced, 54=accurate, 55=accurate_server.
FACE_MODEL_VERSION=${FACE_MODEL_VERSION:-53}

# Stop any workers left over from a previous run
for c in $(docker ps -aq --filter "name=^/sf_migration_"); do
  docker stop "$c" 2>/dev/null || true
done

echo "Spawning face detector and extractor containers for migration"

for i in $(seq 1 $FACE_DETECTORS_COUNT)
do
  echo "Spawning face detector container"

  docker run -d --rm --name sf_migration_face_detector_$i \
    --env RabbitMQ__Hostname="$(getvalue RabbitMQ__Hostname)" \
    --env RabbitMQ__Username="$(getvalue RabbitMQ__Username)" \
    --env RabbitMQ__Password="$(getvalue RabbitMQ__Password)" \
    --env RabbitMQ__Port="$(getvalue RabbitMQ__Port)" \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network vpp-network \
    "${DETECTOR_IMAGE}"
done

for i in $(seq 1 $FACE_EXTRACTORS_COUNT)
do
  echo "Spawning face extractor container"

  docker run -d --rm --name sf_migration_face_extractor_$i \
    --env RabbitMQ__Hostname="$(getvalue RabbitMQ__Hostname)" \
    --env RabbitMQ__Username="$(getvalue RabbitMQ__Username)" \
    --env RabbitMQ__Password="$(getvalue RabbitMQ__Password)" \
    --env RabbitMQ__Port="$(getvalue RabbitMQ__Port)" \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network vpp-network \
    "${EXTRACTOR_IMAGE}"
done

echo "Calling migrate-faces command to migrate faces"

docker run --rm --name sf_admin \
  --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
  --network vpp-network \
  "${ADMIN_IMAGE}" \
  migrate-faces \
  -c "$(getvalue ConnectionStrings__CoreDbContext)" \
  -dbe "$(getvalue Database__DbEngine)" \
  -rmq-host "$(getvalue RabbitMQ__Hostname)" \
  -rmq-user "$(getvalue RabbitMQ__Username)" \
  -rmq-pass "$(getvalue RabbitMQ__Password)" \
  -rmq-vhost "$(getvalue RabbitMQ__VirtualHost)" \
  -rmq-p "$(getvalue RabbitMQ__Port)" \
  -rmq-use-ssl "$(getvalue RabbitMQ__UseSsl)" \
  -s3-e "$(getvalue S3Bucket__Endpoint)" \
  -s3-bn "$(getvalue S3Bucket__BucketName)" \
  -s3-ak "$(getvalue S3Bucket__AccessKey)" \
  -s3-sk "$(getvalue S3Bucket__SecretKey)" \
  -s3-f "$(getvalue S3Bucket__Folder)" \
  --parallelism 4 \
  --face-model-version "${FACE_MODEL_VERSION}"

echo "Stopping spawned containers"

docker ps -aq --filter "name=^/sf_migration_" | xargs -r -P 0 -n 1 docker stop 2>/dev/null || true

echo "Calling set-state-error-non-migrated-faces command with dry-run to see what was not migrated successfully"

docker run --rm --name sf_admin \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network vpp-network \
    "${ADMIN_IMAGE}" \
    set-state-error-non-migrated-faces \
    -c "$(getvalue ConnectionStrings__CoreDbContext)" \
    -dbe "$(getvalue Database__DbEngine)" \
    --dry-run \
    --face-model-version "${FACE_MODEL_VERSION}"

echo "WARNING: If there were transient errors like RPC timeouts, do not finalize the migration and try to migrate again"
echo "To finalize migration for faces that cannot be migrated, run script ./finalize-non-migrated-faces.sh"
echo "NOTE: the VPP services are stopped; once you are done migrating, start them again with 'docker compose up -d'"
