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
_rc=0
shql_conn_init || _rc=$?
assert_eq "0" "$_rc"

# ── shql_conn_push: inserts new connection ─────────────────────────────────
ptyunit_test_begin "shql_conn_push: inserts new connection"
shql_conn_push "sqlite" "/tmp/test.sqlite"
_count=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "1" "$_count"

# ── shql_conn_push: auto-derives name ─────────────────────────────────────
ptyunit_test_begin "shql_conn_push: auto-derives name from last two path segments"
_name=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT name FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "tmp/test.sqlite" "$_name"

# ── shql_conn_push: creates last_accessed ─────────────────────────────────
ptyunit_test_begin "shql_conn_push: creates last_accessed entry"
_la=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM last_accessed WHERE source='local'")
assert_eq "1" "$_la"

# ── shql_conn_push: preserves id on re-push ───────────────────────────────
ptyunit_test_begin "shql_conn_push: preserves id on re-push (no INSERT OR REPLACE)"
_id1=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT id FROM connections WHERE path='/tmp/test.sqlite'")
shql_conn_push "sqlite" "/tmp/test.sqlite"
_id2=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT id FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "$_id1" "$_id2"

# ── shql_conn_push: deduplicates ──────────────────────────────────────────
ptyunit_test_begin "shql_conn_push: same path yields one row"
_count=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "1" "$_count"

# ── shql_conn_push: fails silently ────────────────────────────────────────
ptyunit_test_begin "shql_conn_push: fails silently on unwritable db"
chmod 444 "$SHQL_DATA_DIR/shellql.db"
_out=$(shql_conn_push "sqlite" "/tmp/other.sqlite" 2>&1)
_rc=$?
chmod 644 "$SHQL_DATA_DIR/shellql.db"
assert_eq "0" "$_rc"
assert_eq "" "$_out"

# ── cleanup ────────────────────────────────────────────────────────────────
rm -rf "$_data_dir"
ptyunit_test_summary
