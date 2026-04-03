#!/usr/bin/env bash
# tests/integration/test-db.sh — Integration tests for SQLite adapter
# REQUIRES: sqlite3 binary on PATH

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
    printf 'SKIP: sqlite3 not found\n'
    ptyunit_test_summary
    exit 0
fi

# ── Temp DB setup ─────────────────────────────────────────────────────────────
_tmpdir=$(mktemp -d)
_db="$_tmpdir/test.db"

sqlite3 "$_db" << 'SQL'
CREATE TABLE users (
    id      INTEGER PRIMARY KEY,
    name    TEXT NOT NULL,
    email   TEXT
);
INSERT INTO users VALUES (1, 'Alice', 'alice@example.com');
INSERT INTO users VALUES (2, 'Bob',   'bob@example.com');
INSERT INTO users VALUES (3, 'Carol', 'carol@example.com');
CREATE VIEW active_users AS SELECT * FROM users WHERE id < 3;
SQL

# Use a temp XDG_CONFIG_HOME so tests never touch ~/.config/shql
export XDG_CONFIG_HOME="$_tmpdir/config"

source "$SHQL_ROOT/src/db.sh"

# ── shql_db_list_tables ───────────────────────────────────────────────────────

ptyunit_test_begin "db_list_tables: returns table names one per line"
_result=$(shql_db_list_tables "$_db")
assert_contains "$_result" "users"

ptyunit_test_begin "db_list_tables: does not include view names"
_result=$(shql_db_list_tables "$_db")
_count=$(printf '%s\n' "$_result" | grep -c "active_users" || true)
assert_eq 0 "$_count"

ptyunit_test_begin "db_list_tables: returns 1 for missing DB path"
_rc=0
shql_db_list_tables "/tmp/_shql_missing_db_$$" || _rc=$?
assert_eq 1 "$_rc"

# ── shql_db_describe ──────────────────────────────────────────────────────────

ptyunit_test_begin "db_describe: returns DDL containing CREATE TABLE"
_result=$(shql_db_describe "$_db" users)
assert_contains "$_result" "CREATE TABLE"

ptyunit_test_begin "db_describe: DDL contains column name"
assert_contains "$_result" "name"

ptyunit_test_begin "db_describe: returns DDL for a view"
_result=$(shql_db_describe "$_db" active_users)
assert_contains "$_result" "CREATE VIEW"

# ── shql_db_fetch ─────────────────────────────────────────────────────────────

ptyunit_test_begin "db_fetch: first line is \x1f-separated header"
_result=$(shql_db_fetch "$_db" users)
_header=$(printf '%s\n' "$_result" | head -1)
assert_contains "$_header" "id"
assert_contains "$_header" "name"

ptyunit_test_begin "db_fetch: returns correct row count (3 data rows)"
_row_count=$(printf '%s\n' "$_result" | tail -n +2 | grep -c '' || true)
assert_eq 3 "$_row_count"

ptyunit_test_begin "db_fetch: first data cell is '1'"
_first=$(printf '%s\n' "$_result" | sed -n '2p' | cut -d $'\x1f' -f1)
assert_eq "1" "$_first"

ptyunit_test_begin "db_fetch: explicit limit restricts rows"
_result=$(shql_db_fetch "$_db" users 2)
_row_count=$(printf '%s\n' "$_result" | tail -n +2 | grep -c '' || true)
assert_eq 2 "$_row_count"

ptyunit_test_begin "db_fetch: offset skips rows"
_result=$(shql_db_fetch "$_db" users 2 1)
_second_id=$(printf '%s\n' "$_result" | sed -n '2p' | cut -d $'\x1f' -f1)
assert_eq "2" "$_second_id"

ptyunit_test_begin "db_fetch: emits warning to stderr when config limit hit"
_tmpdir2=$(mktemp -d)
export XDG_CONFIG_HOME="$_tmpdir2/config"
# Force limit=2 via config file so warning fires with exactly 2 rows returned
mkdir -p "$_tmpdir2/config/shql"
printf '{"fetch_limit":2}' > "$_tmpdir2/config/shql/.toolrc"
# Reload config so new file is read
_SHQL_CONFIG_LOADED=""
source "$SHQL_ROOT/src/config.sh"
_warning_output=$(shql_db_fetch "$_db" users 2>&1 >/dev/null)
assert_contains "$_warning_output" "warning"
rm -rf "$_tmpdir2"
export XDG_CONFIG_HOME="$_tmpdir/config"
_SHQL_CONFIG_LOADED=""
source "$SHQL_ROOT/src/config.sh"

ptyunit_test_begin "db_fetch: explicit limit emits no warning even when equal to config limit"
# Set config limit=2 so config path would warn, but explicit limit=2 must not warn
_tmpdir4=$(mktemp -d)
export XDG_CONFIG_HOME="$_tmpdir4/config"
mkdir -p "$_tmpdir4/config/shql"
printf '{"fetch_limit":2}' > "$_tmpdir4/config/shql/.toolrc"
_SHQL_CONFIG_LOADED=""
source "$SHQL_ROOT/src/config.sh"
_no_warn=$(shql_db_fetch "$_db" users 2 0 2>&1 >/dev/null)
assert_eq "" "$_no_warn"
rm -rf "$_tmpdir4"
export XDG_CONFIG_HOME="$_tmpdir/config"
_SHQL_CONFIG_LOADED=""
source "$SHQL_ROOT/src/config.sh"

ptyunit_test_begin "db_fetch: returns 1 for missing DB path"
_rc=0
shql_db_fetch "/tmp/_shql_missing_db_$$" users || _rc=$?
assert_eq 1 "$_rc"

# ── shql_db_query ─────────────────────────────────────────────────────────────

ptyunit_test_begin "db_query: runs arbitrary SQL, first line is header"
_result=$(shql_db_query "$_db" "SELECT id, name FROM users")
_header=$(printf '%s\n' "$_result" | head -1)
assert_contains "$_header" "id"
assert_contains "$_header" "name"

ptyunit_test_begin "db_query: returns correct row count"
_row_count=$(printf '%s\n' "$_result" | tail -n +2 | grep -c '' || true)
assert_eq 3 "$_row_count"

ptyunit_test_begin "db_query: strips trailing semicolon without error"
_rc=0
_result=$(shql_db_query "$_db" "SELECT id FROM users;") || _rc=$?
assert_eq 0 "$_rc"

ptyunit_test_begin "db_query: propagates sqlite3 error to stderr, returns non-zero"
_rc=0
_err=$(shql_db_query "$_db" "SELECT * FROM nonexistent_table" 2>&1 >/dev/null) || _rc=$?
assert_eq 1 "$_rc"

ptyunit_test_begin "db_query: returns 1 for missing DB path"
_rc=0
shql_db_query "/tmp/_shql_missing_db_$$" "SELECT 1" || _rc=$?
assert_eq 1 "$_rc"

ptyunit_test_begin "db_query: non-SELECT statement passes through unwrapped"
_rc=0
shql_db_query "$_db" "INSERT INTO users VALUES (4, 'Dave', 'dave@example.com')" || _rc=$?
assert_eq 0 "$_rc"
_count_result=$(shql_db_query "$_db" "SELECT COUNT(*) FROM users")
_count=$(printf '%s\n' "$_count_result" | tail -n +2)
assert_eq "4" "$_count"

ptyunit_test_begin "db_query: emits warning to stderr when config limit hit"
_tmpdir3=$(mktemp -d)
export XDG_CONFIG_HOME="$_tmpdir3/config"
mkdir -p "$_tmpdir3/config/shql"
# users table has 4 rows now (Dave was inserted above); set limit=4 so query hits the boundary
printf '{"fetch_limit":4}' > "$_tmpdir3/config/shql/.toolrc"
_SHQL_CONFIG_LOADED=""
source "$SHQL_ROOT/src/config.sh"
_warning_output=$(shql_db_query "$_db" "SELECT * FROM users" 2>&1 >/dev/null)
assert_contains "$_warning_output" "warning"
rm -rf "$_tmpdir3"
export XDG_CONFIG_HOME="$_tmpdir/config"
_SHQL_CONFIG_LOADED=""
source "$SHQL_ROOT/src/config.sh"

# ── cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$_tmpdir"
ptyunit_test_summary
