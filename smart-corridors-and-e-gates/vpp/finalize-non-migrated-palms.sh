#!/bin/bash

# Finalizes a palm template migration: marks every palm that could not be migrated as
# errored so the matchers skip it at startup. Run this only after migrate-palms.sh has
# been re-run enough times that the remaining failures are genuinely unmigratable.

set -x
set -e

# load shared helpers (getvalue); run this script from the deployment directory
. "$(dirname "$0")/deployment-common.sh"

VERSION="$(getvalue VERSION)"
REGISTRY="$(getvalue REGISTRY)"
ADMIN_IMAGE="${REGISTRY}admin:${VERSION}"

echo "Calling set-state-error-non-migrated-palms command to mark palms that cannot be migrated to error state"

docker run --rm --name sf_admin \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network vpp-network \
    "${ADMIN_IMAGE}" \
    set-state-error-non-migrated-palms \
    --no-confirm \
    -c "$(getvalue ConnectionStrings__CoreDbContext)" \
    -dbe "$(getvalue Database__DbEngine)"

echo "Done"
echo "You can start the services again with docker compose up -d"
