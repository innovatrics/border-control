#!/bin/bash

# Shared helpers for the deployment scripts (run.sh, migrate-*, finalize-*,
# sync-embeddings-to-vector-db.sh). This file is sourced, not executed.

# Reads a single value from .env: everything after the first '=', with the trailing CR
# (CRLF files), an inline ' # comment' and surrounding whitespace removed. Only whitespace-
# preceded '#' is treated as a comment so values such as a '#RRGGBB' colour survive.
getvalue() {
    local key="$1"
    grep -E "^${key}=" .env | head -n1 | cut -d '=' -f2- \
        | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//'
}

# Blocks until the one-shot milvus-create-user provisioning has finished and fails if it did not
# exit cleanly. `docker compose wait` only reports running containers, so it errors out once the
# one-shot has already exited; poll the container's state instead so this works whether the
# one-shot is still starting (depends on Milvus becoming healthy) or has already completed.
ensure_milvus_user_provisioned() {
    local compose_file="$1"
    local container
    container="$(docker compose -f "${compose_file}" ps -aq milvus-create-user)"
    if [ -z "${container}" ]; then
        echo "milvus-create-user container was not created" >&2
        return 1
    fi
    if ! timeout 120 sh -c 'until [ "$(docker inspect -f "{{.State.Status}}" "$1")" = exited ]; do sleep 1; done' _ "${container}"; then
        echo "Timed out waiting for milvus-create-user provisioning to finish" >&2
        return 1
    fi
    local exit_code
    exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${container}")"
    if [ "${exit_code}" != 0 ]; then
        echo "milvus-create-user provisioning failed (exit code ${exit_code})" >&2
        return 1
    fi
}
