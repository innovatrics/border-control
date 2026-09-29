#!/bin/bash

# Finalizes a face template migration: marks every face that could not be migrated as
# errored so the matchers skip it at startup. Run this only after migrate-faces.sh has
# been re-run enough times that the remaining failures are genuinely unmigratable.

set -x
set -e

# load shared helpers (getvalue); run this script from the deployment directory
. "$(dirname "$0")/deployment-common.sh"

VERSION="$(getvalue VERSION)"
REGISTRY="$(getvalue REGISTRY)"
ADMIN_IMAGE="${REGISTRY}admin:${VERSION}"

FACE_MODEL_VERSION=${FACE_MODEL_VERSION:-53}

echo "Calling set-state-error-non-migrated-faces command to mark faces that cannot be migrated to error state"

docker run --rm --name sf_admin \
    --volume "$(pwd)/iengine.lic:/etc/innovatrics/iengine.lic" \
    --network fm-network \
    "${ADMIN_IMAGE}" \
    set-state-error-non-migrated-faces \
    --no-confirm \
    -c "$(getvalue ConnectionStrings__CoreDbContext)" \
    -dbe "$(getvalue Database__DbEngine)" \
    --face-model-version "${FACE_MODEL_VERSION}"

echo "Done"
echo "You can start the services again with docker compose up -d"
