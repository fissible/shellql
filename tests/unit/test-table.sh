#!/usr/bin/env bash
# tests/unit/test-table.sh — Unit tests for table view state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/ptyunit/assert.sh"

# ── Minimal shellframe stubs (no tty needed) ──────────────────────────────────

shellframe_sel_init()    { true; }
shellframe_scroll_init() { true; }
shellframe_scroll_resize() { true; }
shellframe_scroll_top()  { printf -v "$2" '%d' 0; }
shellframe_sel_cursor()  { printf -v "$2" '%d' 0; }
shellframe_grid_init()   { true; }
shellframe_str_clip_ellipsis() { printf '%s' "$2"; }
shellframe_str_pad()     { printf '%s' "$2"; }
shellframe_scroll_move() { true; }

# ── Source state and mock modules ─────────────────────────────────────────────

SHQL_MOCK=1
SHQL_DB_PATH="/mock/test.db"
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/db_mock.sh"

# Source schema module (needed by sidebar_action) with list stubs
shellframe_list_init() { true; }
source "$SHQL_ROOT/src/screens/schema.sh"

# Source table module
source "$SHQL_ROOT/src/screens/table.sh"

# ── Test: load_ddl populates DDL lines ───────────────────────────────────────

ptyunit_test_begin "load_ddl: populates _SHQL_TABLE_DDL_LINES"
_SHQL_TABLE_NAME="users"
_SHQL_TABLE_DDL_LINES=()
_shql_table_load_ddl
assert_eq 1 $(( ${#_SHQL_TABLE_DDL_LINES[@]} > 0 ))

# ── Test: DDL first line contains CREATE TABLE ────────────────────────────────

ptyunit_test_begin "load_ddl: first line contains CREATE TABLE"
assert_contains "${_SHQL_TABLE_DDL_LINES[0]}" "CREATE TABLE"

# ── Test: load_data populates grid headers ────────────────────────────────────

ptyunit_test_begin "load_data: populates SHELLFRAME_GRID_HEADERS"
_SHQL_TABLE_NAME="users"
SHELLFRAME_GRID_HEADERS=()
SHELLFRAME_GRID_DATA=()
SHELLFRAME_GRID_ROWS=0
SHELLFRAME_GRID_COLS=0
SHELLFRAME_GRID_COL_WIDTHS=()
_shql_table_load_data
assert_eq 1 $(( ${#SHELLFRAME_GRID_HEADERS[@]} > 0 ))

# ── Test: grid has correct column count ───────────────────────────────────────

ptyunit_test_begin "load_data: SHELLFRAME_GRID_COLS equals header count"
assert_eq "${#SHELLFRAME_GRID_HEADERS[@]}" "$SHELLFRAME_GRID_COLS"

# ── Test: mock users table has 10 columns ─────────────────────────────────────

ptyunit_test_begin "load_data: users table has 15 columns"
assert_eq 15 "$SHELLFRAME_GRID_COLS"

# ── Test: first header is 'id' ────────────────────────────────────────────────

ptyunit_test_begin "load_data: first header is 'id'"
assert_eq "id" "${SHELLFRAME_GRID_HEADERS[0]}"

# ── Test: mock data has 10 rows ───────────────────────────────────────────────

ptyunit_test_begin "load_data: mock users table has 10 data rows"
assert_eq 10 "$SHELLFRAME_GRID_ROWS"

# ── Test: grid data array has rows*cols elements ──────────────────────────────

ptyunit_test_begin "load_data: SHELLFRAME_GRID_DATA has ROWS*COLS elements"
assert_eq $(( SHELLFRAME_GRID_ROWS * SHELLFRAME_GRID_COLS )) "${#SHELLFRAME_GRID_DATA[@]}"

# ── Test: first cell of first data row is '1' ─────────────────────────────────

ptyunit_test_begin "load_data: first data cell is '1'"
assert_eq "1" "${SHELLFRAME_GRID_DATA[0]}"

# ── Test: col widths array has COLS elements ──────────────────────────────────

ptyunit_test_begin "load_data: SHELLFRAME_GRID_COL_WIDTHS has COLS entries"
assert_eq "$SHELLFRAME_GRID_COLS" "${#SHELLFRAME_GRID_COL_WIDTHS[@]}"

# ── Test: col widths are at least 8 ──────────────────────────────────────────

ptyunit_test_begin "load_data: all col widths are at least 8"
_all_ok=1
for _w in "${SHELLFRAME_GRID_COL_WIDTHS[@]}"; do
    (( _w >= 8 )) || _all_ok=0
done
assert_eq 1 "$_all_ok"

# ── Test: shql_table_init resets focused flags ────────────────────────────────

ptyunit_test_begin "shql_table_init: resets tabbar and body focused flags"
_SHQL_TABLE_TABBAR_FOCUSED=1
_SHQL_TABLE_BODY_FOCUSED=1
SHELLFRAME_TABBAR_ACTIVE=2
_SHQL_TABLE_NAME="users"
shql_table_init
assert_eq 0 "$_SHQL_TABLE_TABBAR_FOCUSED"
assert_eq 0 "$_SHQL_TABLE_BODY_FOCUSED"

# ── Test: shql_table_init resets SHELLFRAME_TABBAR_ACTIVE to 0 ───────────────

ptyunit_test_begin "shql_table_init: resets SHELLFRAME_TABBAR_ACTIVE to 0"
assert_eq 0 "$SHELLFRAME_TABBAR_ACTIVE"

# ── Test: tab index constants ─────────────────────────────────────────────────

ptyunit_test_begin "tab constants: STRUCTURE=0, DATA=1, QUERY=2"
assert_eq 0 "$_SHQL_TABLE_TAB_STRUCTURE"
assert_eq 1 "$_SHQL_TABLE_TAB_DATA"
assert_eq 2 "$_SHQL_TABLE_TAB_QUERY"

# ── Test: schema sidebar_action sets TABLE_NAME and NEXT ─────────────────────

ptyunit_test_begin "schema sidebar_action: sets _SHQL_TABLE_NAME and NEXT=TABLE"
_SHQL_SCHEMA_TABLES=("users" "orders")
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }
_SHELLFRAME_SHELL_NEXT=""
_SHQL_TABLE_NAME=""
_shql_SCHEMA_sidebar_action
assert_eq "users" "$_SHQL_TABLE_NAME"
assert_eq "TABLE" "$_SHELLFRAME_SHELL_NEXT"

ptyunit_test_summary
