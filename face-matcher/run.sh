#!/bin/bash

# Starts the dependencies, migrates the database, creates the S3 bucket and starts the services and Station.
# Stacks built on Face Matcher run this first; they may export STATION_IDENTIFICATION and STATION_PUBLIC_HOST.

set -e

function error_exit {
    echo "$1" 1>&2
    exit 1
}

# load shared helpers (getvalue); run this script from the deployment directory
cd "$(dirname "$0")"
. ./deployment-common.sh

if [ ! -f secrets/iengine.lic ]; then
    error_exit "secrets/iengine.lic not found. See README.md."
fi
chmod a+r secrets/iengine.lic

# the services mount iengine.lic from the deployment directory
[ -e iengine.lic ] || ln -sf secrets/iengine.lic iengine.lic
chmod a+r iengine.lic

# Station hands the browser presigned S3 URLs; they must point at this host
export STATION_PUBLIC_HOST="${STATION_PUBLIC_HOST:-$(hostname)}"

# face-matcher-network lets the dependency and the platform containers reach each other.
# This is a no-op if the network already exists, which we don't mind.
docker network create face-matcher-network || true

# load image coordinates and configuration from .env
VERSION="$(getvalue VERSION)"
REGISTRY="$(getvalue REGISTRY)"
DB_ENGINE="$(getvalue Database__DbEngine)"
ADMIN_IMAGE="${REGISTRY}admin:${VERSION}"

echo "Using admin image ${ADMIN_IMAGE}"

# start the dependencies (database, RabbitMQ, S3 storage)
docker compose -f dependencies/docker-compose.yml up -d

# stop the services (if any are running) before migrating the database
docker compose down --remove-orphans

# migrate the database to this version (run-migration waits for the dependencies itself)
docker run --rm --name admin_migration \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network face-matcher-network \
    "${ADMIN_IMAGE}" \
    run-migration \
        -p "$(getvalue CameraServicesCount)" \
        -c "$(getvalue ConnectionStrings__CoreDbContext)" -dbe "${DB_ENGINE}" \
        --tenant-id default \
        --rmq-host "$(getvalue RabbitMQ__Hostname)" --rmq-user "$(getvalue RabbitMQ__Username)" --rmq-pass "$(getvalue RabbitMQ__Password)" \
        --rmq-virtual-host "$(getvalue RabbitMQ__VirtualHost)" --rmq-port "$(getvalue RabbitMQ__Port)" \
        --rmq-streams-port "$(getvalue RabbitMQ__StreamsPort)" --rmq-use-ssl "$(getvalue RabbitMQ__UseSsl)" \
        --skip-queue-purge true \
        --dependencies-availability-timeout 120

# create the S3 bucket the services read and write crops to
docker run --rm --name s3-bucket-create --network face-matcher-network "${ADMIN_IMAGE}" \
    ensure-s3-bucket-exists \
        --endpoint "$(getvalue S3Bucket__Endpoint)" --access-key "$(getvalue S3Bucket__AccessKey)" \
        --secret-key "$(getvalue S3Bucket__SecretKey)" --bucket-name "$(getvalue S3Bucket__BucketName)"

# finally start the services and Station (docker-compose.override.yml)
docker compose up -d

echo ""
echo "Station     : http://localhost:$(getvalue STATION_PORT)"
echo "REST API    : http://localhost:8098"
echo "GraphQL API : http://localhost:8097/graphql"
