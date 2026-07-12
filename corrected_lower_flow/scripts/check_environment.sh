#!/usr/bin/env bash

set -euo pipefail

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: command not found: $1" >&2
        exit 1
    fi
}

require_variable() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: environment variable is not set: $name" >&2
        exit 1
    fi
}

check_colon_separated_files() {
    local name="$1"
    local value="${!name}"
    local item
    local -a items

    IFS=':' read -r -a items <<< "$value"
    for item in "${items[@]}"; do
        if [[ ! -f "$item" ]]; then
            echo "ERROR: file listed in $name does not exist: $item" >&2
            exit 1
        fi
    done
}

require_command tessent
require_command dc_shell

require_variable TESSENT_CELL_LIBRARY
require_variable DC_TARGET_LIBRARY
require_variable DC_LINK_LIBRARY

check_colon_separated_files TESSENT_CELL_LIBRARY
check_colon_separated_files DC_TARGET_LIBRARY
check_colon_separated_files DC_LINK_LIBRARY

echo "Environment check passed"
echo "  tessent: $(command -v tessent)"
echo "  dc_shell: $(command -v dc_shell)"
echo "  Tessent library: $TESSENT_CELL_LIBRARY"
echo "  DC target library: $DC_TARGET_LIBRARY"
echo "  DC link library: $DC_LINK_LIBRARY"
