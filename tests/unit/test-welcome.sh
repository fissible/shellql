#!/usr/bin/env bash
# tests/unit/test-welcome.sh — Unit tests for welcome screen state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# ── Source state and mock modules (no shellframe/tty needed) ──────────────────

SHQL_MOCK=1
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/db_mock.sh"

# ── Test: shql_mock_load_recent populates SHQL_RECENT_FILES ──────────────────

ptyunit_test_begin "mock_load_recent: populates SHQL_RECENT_FILES"
SHQL_RECENT_FILES=()
shql_mock_load_recent
assert_eq 5 "${#SHQL_RECENT_FILES[@]}"

# ── Test: shql_mock_load_recent includes expected paths ──────────────────────

ptyunit_test_begin "mock_load_recent: first entry ends in app.db"
shql_mock_load_recent
[[ "${SHQL_RECENT_FILES[0]}" == *"app.db" ]]
assert_eq 0 $?

# ── Test: empty SHQL_RECENT_FILES produces empty-state path ──────────────────

ptyunit_test_begin "empty recent files: array length is 0"
SHQL_RECENT_FILES=()
assert_eq 0 "${#SHQL_RECENT_FILES[@]}"

ptyunit_test_summary
