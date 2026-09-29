#!/bin/bash

# Brings up a deployment from the files shipped in this archive:
# starts the bundled dependencies, migrates the database to this version, creates the
# S3 bucket and finally starts the VPP services. The same script drives every
# shipped deployment - only the docker-compose.yml and .env packaged alongside it differ.
#
# Configuration is read from .env, which is shipped pre-filled with the released image
# coordinates (REGISTRY and VERSION) and working defaults for everything else.

set -x
set -e

function error_exit {
    echo "$1" 1>&2
    exit 1
}

# load shared helpers (getvalue); run this script from the deployment directory
. "$(dirname "$0")/deployment-common.sh"

if [ ! -f iengine.lic ]; then
    error_exit "License file not found. Please make sure that the iengine.lic file is present in the current directory."
fi

# fm-network lets the dependency and the platform containers reach each other.
# This is a no-op if the network already exists, which we don't mind.
docker network create fm-network || true

# load image coordinates and configuration from .env
VERSION="$(getvalue VERSION)"
REGISTRY="$(getvalue REGISTRY)"
DB_ENGINE="$(getvalue Database__DbEngine)"
ADMIN_IMAGE="${REGISTRY}admin:${VERSION}"

echo "Using admin image ${ADMIN_IMAGE}"

# start the dependencies (database, RabbitMQ, S3 storage)
# Face Matcher: the Milvus vector database bundled with the release is not used here. It was
# removed from dependencies/docker-compose.yml, so the release's ensure_milvus_user_provisioned
# wait is skipped as well (VectorDB__Provider stays "none" in .env).
docker compose -f dependencies/docker-compose.yml up -d

# stop VPP services (if any are running) before migrating the database
docker compose down --remove-orphans

# migrate the database to this version (run-migration waits for the dependencies itself)
docker run --rm --name admin_migration \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network fm-network \
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
docker run --rm --name s3-bucket-create --network fm-network "${ADMIN_IMAGE}" \
    ensure-s3-bucket-exists \
        --endpoint "$(getvalue S3Bucket__Endpoint)" --access-key "$(getvalue S3Bucket__AccessKey)" \
        --secret-key "$(getvalue S3Bucket__SecretKey)" --bucket-name "$(getvalue S3Bucket__BucketName)"

# finally start the VPP services
docker compose up -d
