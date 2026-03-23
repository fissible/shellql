#!/usr/bin/env bash
# tests/integration/test-integration.sh — End-to-end CLI integration tests
# REQUIRES: sqlite3 binary on PATH, SHELLFRAME_DIR set in environment

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/ptyunit/assert.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
    printf 'SKIP: sqlite3 not found\n'
    ptyunit_test_summary
    exit 0
fi

# ── Setup ─────────────────────────────────────────────────────────────────────

_data_dir=$(mktemp -d)
_db="$SHQL_ROOT/tests/fixtures/demo.sqlite"

_shql() {
    SHELLFRAME_DIR="$SHELLFRAME_DIR" \
    XDG_DATA_HOME="$_data_dir" \
    bash "$SHQL_ROOT/bin/shql" "$@"
}

# ── query-out mode ────────────────────────────────────────────────────────────

ptyunit_test_begin "query-out: exit 0 on valid query"
_rc=0; _out=$(_shql "$_db" -q "SELECT id, name FROM users" 2>/dev/null) || _rc=$?
assert_eq 0 "$_rc"

ptyunit_test_begin "query-out: formatted table output + real data"
assert_contains "$_out" "+"
assert_contains "$_out" "Alice"

ptyunit_test_begin "query-out: --porcelain suppresses box formatting, data present"
_rc=0; _out=$(_shql "$_db" -q "SELECT name FROM users" --porcelain 2>/dev/null) || _rc=$?
assert_eq 0 "$_rc"
assert_contains "$_out" "Alice"
_found=0; [[ "$_out" == *"+"* ]] && _found=1
assert_eq 0 "$_found"

# ── pipe mode ─────────────────────────────────────────────────────────────────

ptyunit_test_begin "pipe: exit 0 and data present"
_rc=0
_out=$(printf 'SELECT name FROM users LIMIT 1' | _shql "$_db" 2>/dev/null) || _rc=$?
assert_eq 0 "$_rc"
assert_contains "$_out" "Alice"

ptyunit_test_begin "pipe: --porcelain suppresses box formatting, data present"
_rc=0
_out=$(printf 'SELECT name FROM users LIMIT 1' | _shql "$_db" --porcelain 2>/dev/null) || _rc=$?
assert_eq 0 "$_rc"
assert_contains "$_out" "Alice"
_found=0; [[ "$_out" == *"+"* ]] && _found=1
assert_eq 0 "$_found"

# ── databases mode (round-trip) ───────────────────────────────────────────────

# Push a connection to the registry via a successful query-out call
_shql "$_db" -q "SELECT 1" >/dev/null 2>&1

ptyunit_test_begin "databases: path appears in output after query-out push"
_rc=0; _out=$(_shql databases 2>/dev/null) || _rc=$?
assert_eq 0 "$_rc"
assert_contains "$_out" "$_db"

ptyunit_test_begin "databases: --porcelain output contains path"
_rc=0; _out=$(_shql databases --porcelain 2>/dev/null) || _rc=$?
assert_eq 0 "$_rc"
assert_contains "$_out" "$_db"

# ── Error paths ───────────────────────────────────────────────────────────────

ptyunit_test_begin "error: missing DB file returns exit 1 with path in stderr"
_rc=0; _err=$(_shql /tmp/_shql_no_such_db -q "SELECT 1" 2>&1 >/dev/null) || _rc=$?
assert_eq 1 "$_rc"
assert_contains "$_err" "/tmp/_shql_no_such_db"

ptyunit_test_begin "error: bad SQL returns exit 1 with table name in stderr"
_rc=0; _err=$(_shql "$_db" -q "SELECT * FROM nonexistent_table" 2>&1 >/dev/null) || _rc=$?
assert_eq 1 "$_rc"
assert_contains "$_err" "nonexistent_table"

# ── Teardown ──────────────────────────────────────────────────────────────────

rm -rf "$_data_dir"
ptyunit_test_summary
