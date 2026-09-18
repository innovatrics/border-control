#!/bin/bash

# Regenerates the watchlist update-log RMQ stream from the watchlist data currently in the SQL
# database. Useful for edge / watchlist-synchronization deployments - run it after a watchlist
# change or a version upgrade so the edge side resynchronizes from a fresh generation. The SQL
# database stays the source of truth; this only (re)builds the stream from it. Extra arguments
# are forwarded to the command (e.g. --tenant-id, --generation-id, --batch-size).

set -x
set -e

# load shared helpers (getvalue); run this script from the deployment directory
. "$(dirname "$0")/deployment-common.sh"

VERSION="$(getvalue VERSION)"
REGISTRY="$(getvalue REGISTRY)"
ADMIN_IMAGE="${REGISTRY}admin:${VERSION}"

echo "Calling populate-wl-update-log-stream command to rebuild the watchlist update-log stream from the database"

docker run --rm --name sf_admin \
  --network vpp-network \
  "${ADMIN_IMAGE}" \
  populate-wl-update-log-stream \
  -c "$(getvalue ConnectionStrings__CoreDbContext)" \
  -dbe "$(getvalue Database__DbEngine)" \
  --rmq-host "$(getvalue RabbitMQ__Hostname)" \
  --rmq-user "$(getvalue RabbitMQ__Username)" \
  --rmq-pass "$(getvalue RabbitMQ__Password)" \
  --rmq-virtual-host "$(getvalue RabbitMQ__VirtualHost)" \
  --rmq-port "$(getvalue RabbitMQ__Port)" \
  --rmq-streams-port "$(getvalue RabbitMQ__StreamsPort)" \
  --rmq-use-ssl "$(getvalue RabbitMQ__UseSsl)" \
  "$@"

echo "Done"
