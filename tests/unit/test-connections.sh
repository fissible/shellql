#!/usr/bin/env bash
# tests/unit/test-connections.sh — Unit tests for connections module

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── Setup: temp data dir ───────────────────────────────────────────────────
_data_dir=$(mktemp -d)
export XDG_DATA_HOME="$_data_dir"
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/connections.sh"

# ── shql_conn_init: creates schema ─────────────────────────────────────────
ptyunit_test_begin "shql_conn_init: creates schema"
shql_conn_init
_tables=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
assert_eq "connections
last_accessed" "$_tables"

# ── shql_conn_init: idempotent ─────────────────────────────────────────────
ptyunit_test_begin "shql_conn_init: is idempotent"
shql_conn_init
assert_eq "0" "$?"

# ── cleanup ────────────────────────────────────────────────────────────────
rm -rf "$_data_dir"
ptyunit_test_summary
