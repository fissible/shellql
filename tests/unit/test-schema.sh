#!/usr/bin/env bash
# tests/unit/test-schema.sh — Unit tests for schema browser state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/ptyunit/assert.sh"

# ── Minimal shellframe stubs (no tty needed) ──────────────────────────────────

# Stub only the shellframe functions the schema module calls at init time.
shellframe_sel_init()    { true; }
shellframe_scroll_init() { true; }
shellframe_sel_cursor()  { printf -v "$2" '%d' 0; }

# Theme preamble
SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE=''
_SHQL_ROOT="$SHQL_ROOT"
source "$SHQL_ROOT/src/theme.sh"
shql_theme_load basic

# ── Source state and mock modules ─────────────────────────────────────────────

SHQL_MOCK=1
SHQL_DB_PATH="/mock/test.db"
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/db_mock.sh"

# Source schema module (skipping the shellframe_list_init call by stubbing it)
shellframe_list_init() { true; }
source "$SHQL_ROOT/src/screens/schema.sh"
source "$SHQL_ROOT/src/screens/header.sh"

# ── Test: _shql_breadcrumb — sqlite driver ────────────────────────────────────

ptyunit_test_begin "breadcrumb: sqlite driver with table"
SHQL_DRIVER=sqlite SHQL_DB_PATH="/data/chinook.sqlite"
result="$(_shql_breadcrumb "users")"
assert_eq "sqlite://chinook.sqlite → users" "$result"

ptyunit_test_begin "breadcrumb: sqlite driver without table"
result="$(_shql_breadcrumb)"
assert_eq "sqlite://chinook.sqlite" "$result"

ptyunit_test_begin "breadcrumb: mysql driver with table"
SHQL_DRIVER=mysql SHQL_DB_HOST=localhost SHQL_DB_NAME=chinook
result="$(_shql_breadcrumb "users")"
assert_eq "mysql://localhost/chinook → users" "$result"

ptyunit_test_begin "breadcrumb: default driver with table"
SHQL_DRIVER="" SHQL_DB_HOST=localhost SHQL_DB_NAME=chinook
result="$(_shql_breadcrumb "users")"
assert_eq "localhost › chinook › users" "$result"

ptyunit_test_begin "breadcrumb: default driver without table"
result="$(_shql_breadcrumb)"
assert_eq "localhost › chinook" "$result"

# ── Test: _shql_schema_load_tables populates array ───────────────────────────

ptyunit_test_begin "load_tables: populates _SHQL_SCHEMA_TABLES from mock"
_SHQL_SCHEMA_TABLES=()
_shql_schema_load_tables
assert_eq 4 "${#_SHQL_SCHEMA_TABLES[@]}"

# ── Test: first table is 'users' ──────────────────────────────────────────────

ptyunit_test_begin "load_tables: first table is 'users'"
assert_eq "users" "${_SHQL_SCHEMA_TABLES[0]}"

# ── Test: _shql_schema_load_ddl populates DDL lines ──────────────────────────

ptyunit_test_begin "load_ddl: populates _SHQL_SCHEMA_DDL_LINES for users"
_SHQL_SCHEMA_DDL_LINES=()
_SHQL_SCHEMA_PREV_TABLE=""
_shql_schema_load_ddl "users"
assert_eq 1 $(( ${#_SHQL_SCHEMA_DDL_LINES[@]} > 0 ))

# ── Test: _shql_schema_load_ddl sets PREV_TABLE ───────────────────────────────

ptyunit_test_begin "load_ddl: sets _SHQL_SCHEMA_PREV_TABLE"
assert_eq "users" "$_SHQL_SCHEMA_PREV_TABLE"

# ── Test: DDL contains CREATE TABLE ───────────────────────────────────────────

ptyunit_test_begin "load_ddl: first line contains CREATE TABLE"
assert_contains "${_SHQL_SCHEMA_DDL_LINES[0]}" "CREATE TABLE"

# ── Test: _shql_schema_sidebar_width respects minimum ────────────────────────

ptyunit_test_begin "sidebar_width: respects minimum of 20"
_w=""
_shql_schema_sidebar_width 40 _w
assert_eq 1 $(( _w >= _SHQL_SCHEMA_SIDEBAR_WIDTH_MIN ))

# ── Test: _shql_schema_sidebar_width scales with terminal ────────────────────

ptyunit_test_begin "sidebar_width: 90-col terminal yields 30"
_w=""
_shql_schema_sidebar_width 90 _w
assert_eq 30 "$_w"

ptyunit_test_summary
