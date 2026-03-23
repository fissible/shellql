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

# ── Teardown ──────────────────────────────────────────────────────────────────

rm -rf "$_data_dir"
ptyunit_test_summary
