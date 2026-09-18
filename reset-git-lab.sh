#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )); then
    printf 'Usage: bash ./reset-git-lab.sh [LAB_DIRECTORY]\n' >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-git-lab}"
exec bash "$SCRIPT_DIR/build-git-lab.sh" "$TARGET"
