#!/usr/bin/env bash
# tests/unit/test-db.sh — Unit tests for src/db.sh with mocked sqlite3
#
# Tests path validation, SQL transformation (SELECT wrapping, DML rows_affected
# append, semicolon stripping), error propagation, and the \x1f separator.
# Uses ptyunit_mock to intercept sqlite3 calls so no real database is required.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# Isolate config so tests never touch ~/.config/shql
_cfg_tmpdir=$(mktemp -d)
export XDG_CONFIG_HOME="$_cfg_tmpdir/config"
source "$SHQL_ROOT/src/db.sh"

# A readable temp file serves as a "database" for path-check tests
_valid_db=$(mktemp)

# ── path validation ───────────────────────────────────────────────────────────

describe "path validation"

test_that "_shql_db_check_path returns 1 for missing file"
_rc=0; _shql_db_check_path "/nonexistent/__shql_test_$$.db" 2>/dev/null || _rc=$?
assert_eq "1" "$_rc"

test_that "_shql_db_check_path returns 0 for readable file"
_rc=0; _shql_db_check_path "$_valid_db" 2>/dev/null || _rc=$?
assert_eq "0" "$_rc"

test_that "list_tables returns 1 for missing DB"
run shql_db_list_tables "/nonexistent/__shql_test_$$.db"
assert_eq "1" "$status"

test_that "fetch returns 1 for missing DB"
run shql_db_fetch "/nonexistent/__shql_test_$$.db" users
assert_eq "1" "$status"

test_that "query returns 1 for missing DB"
run shql_db_query "/nonexistent/__shql_test_$$.db" "SELECT 1"
assert_eq "1" "$status"

end_describe

# ── SELECT wrapping ───────────────────────────────────────────────────────────

describe "db_query SELECT wrapping"

_mock_sqlite3_ok() {
    # Mock sqlite3 to capture the SQL arg and return an empty result set
    ptyunit_mock sqlite3 --output ""
}

test_that "SELECT is wrapped with LIMIT"
_mock_sqlite3_ok
shql_db_query "$_valid_db" "SELECT * FROM users" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_contains "$_args" "SELECT * FROM (SELECT * FROM users)"

test_that "select (lowercase) is also wrapped"
_mock_sqlite3_ok
shql_db_query "$_valid_db" "select id from users" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_contains "$_args" "SELECT * FROM (select id from users)"

test_that "WITH ... SELECT is wrapped"
_mock_sqlite3_ok
shql_db_query "$_valid_db" "WITH x AS (SELECT 1) SELECT * FROM x" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_contains "$_args" "SELECT * FROM (WITH x AS (SELECT 1) SELECT * FROM x)"

test_that "CREATE is NOT wrapped"
_mock_sqlite3_ok
shql_db_query "$_valid_db" "CREATE TABLE foo (id INTEGER)" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_not_contains "$_args" "SELECT * FROM ("
assert_contains "$_args" "CREATE TABLE foo"

test_that "EXPLAIN is NOT wrapped"
_mock_sqlite3_ok
shql_db_query "$_valid_db" "EXPLAIN SELECT 1" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_not_contains "$_args" "SELECT * FROM ("

end_describe

# ── DML rows_affected ─────────────────────────────────────────────────────────

describe "db_query DML rows_affected append"

_mock_sqlite3_dml() {
    # Mock returns a rows_affected result to simulate sqlite3 DML output
    ptyunit_mock sqlite3 --output $'rows_affected\n1'
}

_check_dml_appends_changes() {
    local _stmt="$1"
    _mock_sqlite3_dml
    shql_db_query "$_valid_db" "$_stmt" > /dev/null 2>&1 || true
    _args=$(mock_args sqlite3)
    assert_contains "$_args" "SELECT changes() AS rows_affected" "DML append: $_stmt"
}

test_each _check_dml_appends_changes << 'PARAMS'
INSERT INTO users VALUES (1, 'test')
UPDATE users SET name = 'x' WHERE id = 1
DELETE FROM users WHERE id = 1
REPLACE INTO users VALUES (1, 'test')
PARAMS

end_describe

# ── semicolon stripping ───────────────────────────────────────────────────────

describe "db_query semicolon stripping"

test_that "trailing semicolons are stripped before wrapping"
ptyunit_mock sqlite3 --output ""
shql_db_query "$_valid_db" "SELECT 1;" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
# The SQL passed to sqlite3 must not end with a semicolon
assert_not_contains "$_args" "SELECT 1);"
assert_contains "$_args" "SELECT * FROM (SELECT 1)"

test_that "trailing whitespace + semicolon is stripped"
ptyunit_mock sqlite3 --output ""
shql_db_query "$_valid_db" "SELECT 1 ;  " > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_not_contains "$_args" "SELECT 1 ;  )"
assert_contains "$_args" "SELECT * FROM (SELECT 1)"

end_describe

# ── \x1f separator ────────────────────────────────────────────────────────────

describe "separator"

test_that "db_fetch calls sqlite3 with \\x1f separator"
ptyunit_mock sqlite3 --output ""
shql_db_fetch "$_valid_db" users > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_contains "$_args" $'\x1f'

test_that "db_query calls sqlite3 with \\x1f separator"
ptyunit_mock sqlite3 --output ""
shql_db_query "$_valid_db" "SELECT 1" > /dev/null 2>&1 || true
_args=$(mock_args sqlite3)
assert_contains "$_args" $'\x1f'

end_describe

# ── error propagation ─────────────────────────────────────────────────────────

describe "error propagation"

test_that "db_query returns 1 when sqlite3 exits non-zero"
ptyunit_mock sqlite3 --exit 1 --output "Error: no such table"
_rc=0
shql_db_query "$_valid_db" "SELECT * FROM nonexistent" > /dev/null 2>/dev/null || _rc=$?
assert_eq "1" "$_rc"

test_that "db_fetch returns 1 when sqlite3 exits non-zero"
ptyunit_mock sqlite3 --exit 1 --output "Error: no such table"
_rc=0
shql_db_fetch "$_valid_db" nonexistent > /dev/null 2>/dev/null || _rc=$?
assert_eq "1" "$_rc"

end_describe

# ── cleanup ───────────────────────────────────────────────────────────────────

rm -f "$_valid_db"
rm -rf "$_cfg_tmpdir"

ptyunit_test_summary
