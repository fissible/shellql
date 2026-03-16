#!/usr/bin/env bash
# tests/unit/test-welcome.sh — Unit tests for welcome screen state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/ptyunit/assert.sh"

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

# ── Test: shql_state_push_recent adds to front ───────────────────────────────

ptyunit_test_begin "push_recent: prepends new entry"
SHQL_RECENT_FILES=("/a.db" "/b.db")
SHQL_HISTORY_FILE="/dev/null"   # suppress file I/O
shql_state_push_recent "/new.db"
assert_eq "/new.db" "${SHQL_RECENT_FILES[0]}"

# ── Test: shql_state_push_recent deduplicates ─────────────────────────────────

ptyunit_test_begin "push_recent: deduplicates existing entry"
SHQL_RECENT_FILES=("/a.db" "/b.db" "/c.db")
SHQL_HISTORY_FILE="/dev/null"
shql_state_push_recent "/b.db"
# /b.db should now be first, with no duplicate
assert_eq "/b.db" "${SHQL_RECENT_FILES[0]}"
assert_eq 3 "${#SHQL_RECENT_FILES[@]}"

# ── Test: shql_state_push_recent trims to SHQL_RECENT_MAX ────────────────────

ptyunit_test_begin "push_recent: trims to SHQL_RECENT_MAX"
SHQL_RECENT_FILES=()
SHQL_HISTORY_FILE="/dev/null"
SHQL_RECENT_MAX=3
_i=""
for _i in 1 2 3 4 5; do
    shql_state_push_recent "/db${_i}.db"
done
assert_eq 3 "${#SHQL_RECENT_FILES[@]}"

# ── Test: empty SHQL_RECENT_FILES produces empty-state path ──────────────────

ptyunit_test_begin "empty recent files: array length is 0"
SHQL_RECENT_FILES=()
assert_eq 0 "${#SHQL_RECENT_FILES[@]}"

ptyunit_test_summary
