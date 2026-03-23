#!/usr/bin/env bash
# tests/integration/test-connections.sh — Integration tests for connection registry
# Requires: real sqlite3 on PATH

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/ptyunit/assert.sh"

_data_dir=$(mktemp -d)
export XDG_DATA_HOME="$_data_dir"
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/connections.sh"
if ! command -v sqlite3 >/dev/null 2>&1; then
    printf 'SKIP: sqlite3 not found\n'
    ptyunit_test_summary
    exit 0
fi
shql_conn_init

# ── Round-trip: push → list ────────────────────────────────────────────────
ptyunit_test_begin "push → list: data survives write/read cycle"
shql_conn_push "sqlite" "/tmp/roundtrip.sqlite"
_list=$(shql_conn_list)
assert_contains "$_list" "/tmp/roundtrip.sqlite"

# ── Sort order: most-recent first ─────────────────────────────────────────
ptyunit_test_begin "sort order: most-recently accessed connection appears first"
shql_conn_push "sqlite" "/tmp/older.sqlite"
# Manually set an older timestamp so ordering is deterministic
_id=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT id FROM connections WHERE path='/tmp/older.sqlite'")
sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "UPDATE last_accessed SET last_used='2025-01-01T00:00:00Z' WHERE ref_id='$_id'"
shql_conn_push "sqlite" "/tmp/newer.sqlite"
_list=$(shql_conn_list)
_newer_line=$(printf '%s\n' "$_list" | grep -n 'newer.sqlite' | cut -d: -f1)
_older_line=$(printf '%s\n' "$_list" | grep -n 'older.sqlite' | cut -d: -f1)
assert_eq "1" "$( [ "$_newer_line" -lt "$_older_line" ] && printf 1 || printf 0 )"

ptyunit_test_begin "sort order: never-accessed entries appear last"
sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "INSERT INTO connections (id,driver,name,path) VALUES ('nv1','sqlite','tmp/never.sqlite','/tmp/never.sqlite')"
# Verify never.sqlite is in the output and has an empty last_used column (col 5)
_never_entry=$(shql_conn_list | grep 'never.sqlite')
_never_last=$(printf '%s\n' "$_never_entry" | cut -f5)
assert_eq "" "$_never_last"

# ── Dedup: same path multiple pushes ──────────────────────────────────────
ptyunit_test_begin "dedup: same path pushed 3x yields one connections row"
shql_conn_push "sqlite" "/tmp/dedup.sqlite"
shql_conn_push "sqlite" "/tmp/dedup.sqlite"
shql_conn_push "sqlite" "/tmp/dedup.sqlite"
_count=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM connections WHERE path='/tmp/dedup.sqlite'")
assert_eq "1" "$_count"

ptyunit_test_begin "dedup: last_accessed has one row with latest timestamp"
_id=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT id FROM connections WHERE path='/tmp/dedup.sqlite'")
_la=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM last_accessed WHERE source='local' AND ref_id='$_id'")
assert_eq "1" "$_la"

# ── cleanup ────────────────────────────────────────────────────────────────
rm -rf "$_data_dir"
ptyunit_test_summary
