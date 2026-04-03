#!/usr/bin/env bash
# tests/integration/setUp.sh — Pre-flight for all integration tests
#
# Ensures SHELLFRAME_DIR is set before each integration test runs.
# Exits 3 (ptyunit skip signal) if the dependency cannot be located so that
# the test file is marked SKIP rather than FAIL in environments where
# shellframe is not present.

set -u

if [[ -z "${SHELLFRAME_DIR:-}" ]]; then
    # Try the sibling clone layout used in CI and local development
    _candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/shellframe"
    if [[ -d "$_candidate" ]] && [[ -f "$_candidate/shellframe.sh" ]]; then
        export SHELLFRAME_DIR="$_candidate"
    else
        printf 'SKIP: SHELLFRAME_DIR not set and shellframe not found at %s\n' "$_candidate" >&2
        exit 3
    fi
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    printf 'SKIP: sqlite3 not found on PATH\n' >&2
    exit 3
fi
