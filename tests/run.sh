#!/usr/bin/env bash
# tests/run.sh — ptyunit runner wrapper
#
# Locates the ptyunit installation and delegates to its run.sh.
# PTYUNIT_HOME may be set explicitly; otherwise resolved from Homebrew.
#
# Usage: bash tests/run.sh [--unit | --integration | --all] ...

set -u

if [[ -z "${PTYUNIT_HOME:-}" ]]; then
    # Check for sibling clone first (used in CI where ptyunit is checked out alongside the repo)
    _sibling="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/ptyunit"
    if [[ -f "$_sibling/assert.sh" ]]; then
        PTYUNIT_HOME="$_sibling"
    else
        _prefix=$(brew --prefix ptyunit 2>/dev/null) || {
            printf 'error: ptyunit not found. Run: bash bootstrap.sh\n' >&2
            exit 1
        }
        PTYUNIT_HOME="$_prefix/libexec"
    fi
fi
export PTYUNIT_HOME

exec bash "$PTYUNIT_HOME/run.sh" "$@"
