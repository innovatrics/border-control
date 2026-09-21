#!/bin/bash

# Shared helpers for the deployment scripts (run.sh, migrate-faces.sh, finalize-non-migrated-faces.sh,
# populate-wl-update-log-stream.sh). This file is sourced, not executed.

# Reads a single value from .env: everything after the first '=', with the trailing CR
# (CRLF files), an inline ' # comment' and surrounding whitespace removed. Only whitespace-
# preceded '#' is treated as a comment so values such as a '#RRGGBB' colour survive.
getvalue() {
    local key="$1"
    grep -E "^${key}=" .env | head -n1 | cut -d '=' -f2- \
        | sed -E -e 's/\r$//' -e 's/[[:space:]]+#.*$//' -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//'
}
