#!/usr/bin/env bash
# tests/unit/test-table.sh — Unit tests for table view state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

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
shellframe_editor_init()  { true; }
shellframe_grid_on_key()  { return 1; }
shellframe_shell_focus_set() { true; }
shellframe_editor_get_text() { printf -v "$2" '%s' "SELECT 1"; }
shellframe_editor_on_key()   { return 1; }
shellframe_sel_move()        { true; }
shellframe_panel_render()    { true; }
shellframe_panel_inner()     { true; }
_shellframe_shell_terminal_size() { printf -v "$1" '%d' 24; printf -v "$2" '%d' 80; }
SHELLFRAME_EDITOR_RESULT=""

# Theme preamble — declare shellframe color globals so basic.sh :- expansions
# work under set -u (stubs don't set these variables)
SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE=''
_SHQL_ROOT="$SHQL_ROOT"
source "$SHQL_ROOT/src/theme.sh"
shql_theme_load basic

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
source "$SHQL_ROOT/src/screens/query.sh"

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

# ── Test: inspector footer hint constant ──────────────────────────────────────

ptyunit_test_begin "inspector footer hint constant defined with correct text"
assert_eq "$_SHQL_TABLE_FOOTER_HINTS_INSPECTOR" \
    "[↑↓] Scroll  [PgUp/PgDn] Page  [Enter/Esc/q] Close" \
    "footer: inspector hint string"

# ── Tab state model ───────────────────────────────────────────────────────────

ptyunit_test_begin "tab_arrays: globals exist and are empty after shql_table_init_browser"
shql_table_init_browser
assert_eq 0 "${#_SHQL_TABS_TYPE[@]}"
assert_eq 0 "${#_SHQL_TABS_LABEL[@]}"
assert_eq -1 "$_SHQL_TAB_ACTIVE"
assert_eq 0 "$_SHQL_TAB_CTX_SEQ"

ptyunit_test_begin "tab_find: returns -1 when no tabs open"
_result=-99
_shql_tab_find "users" "data" _result
assert_eq -1 "$_result"

ptyunit_test_begin "tab_find: returns -1 for wrong type"
_SHQL_TABS_TYPE=("data")
_SHQL_TABS_TABLE=("users")
_SHQL_TABS_LABEL=("users·Data")
_SHQL_TABS_CTX=("t0")
_shql_tab_find "users" "schema" _result
assert_eq -1 "$_result"

ptyunit_test_begin "tab_find: finds correct index"
_SHQL_TABS_TYPE=("data" "schema")
_SHQL_TABS_TABLE=("users" "users")
_SHQL_TABS_LABEL=("users·Data" "users·Schema")
_SHQL_TABS_CTX=("t0" "t1")
_shql_tab_find "users" "schema" _result
assert_eq 1 "$_result"

ptyunit_test_begin "tab_open: creates new data tab"
shql_table_init_browser
_shql_tab_open "users" "data"
assert_eq 1 "${#_SHQL_TABS_TYPE[@]}"
assert_eq "data" "${_SHQL_TABS_TYPE[0]}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]}"
assert_eq "users·Data" "${_SHQL_TABS_LABEL[0]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_open: deduplicates — switches to existing tab"
_shql_tab_open "users" "schema"   # second tab
_shql_tab_open "users" "data"    # should switch back, not create
assert_eq 2 "${#_SHQL_TABS_TYPE[@]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_open: query tabs never deduplicate"
shql_table_init_browser
_shql_tab_open "" "query"
_shql_tab_open "" "query"
assert_eq 2 "${#_SHQL_TABS_TYPE[@]}"
assert_eq "query" "${_SHQL_TABS_TYPE[0]}"
assert_contains "${_SHQL_TABS_LABEL[0]}" "Query"

ptyunit_test_begin "tab_open: query tab labels increment"
assert_eq "Query 2" "${_SHQL_TABS_LABEL[1]}"

ptyunit_test_begin "tab_close: removes active tab and moves left"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "orders" "data"
_SHQL_TAB_ACTIVE=1
_shql_tab_close
assert_eq 1 "${#_SHQL_TABS_TYPE[@]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_close: sets ACTIVE=-1 when last tab closed"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_close
assert_eq 0 "${#_SHQL_TABS_TYPE[@]}"
assert_eq -1 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_capacity: fits within available width"
shql_table_init_browser
_shql_tab_open "users" "data"     # label "users·Data" = 10 chars + 2 padding = 12
_shql_tab_open "orders" "schema"  # label "orders·Schema" = 13 + 2 = 15
# +SQL = 5; separators = 2
# total used: 12+1+15+1+5 = 34 → fits in width 80
_result=-1
_shql_tab_fits 80 _result
assert_eq 1 "$_result"

ptyunit_test_begin "tab_capacity: detects overflow"
shql_table_init_browser
local _i; for (( _i=0; _i<10; _i++ )); do
    _shql_tab_open "" "query"
done
_shql_tab_fits 40 _result
assert_eq 0 "$_result"

ptyunit_test_begin "browser_init: loads tables into _SHQL_BROWSER_TABLES"
_SHQL_TABLE_NAME=""
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))
assert_eq "users" "${_SHQL_BROWSER_TABLES[0]}"

ptyunit_test_begin "browser_sidebar_width: is approx 1/4 terminal width"
_w=""
_shql_browser_sidebar_width 80 _w
assert_eq 1 $(( _w >= 15 && _w <= 25 ))

ptyunit_test_begin "sidebar_on_key: Enter opens data tab for selected table"
shql_browser_init
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }   # override: cursor at 0
shql_table_init_browser
_shql_TABLE_sidebar_on_key $'\r'
assert_eq "data" "${_SHQL_TABS_TYPE[0]}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "sidebar_on_key: s opens schema tab for selected table"
shql_table_init_browser
_shql_TABLE_sidebar_on_key 's'
assert_eq "schema" "${_SHQL_TABS_TYPE[0]}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]}"

ptyunit_test_begin "sidebar_on_key: right arrow moves focus to content (rc=0)"
_saved_focus=""
shellframe_shell_focus_set() { _saved_focus="$1"; }
shql_table_init_browser
_shql_TABLE_sidebar_on_key $'\033[C'; _rc=$?
assert_eq 0 "$_rc"
assert_eq "content" "$_saved_focus"
shellframe_shell_focus_set() { true; }   # restore

ptyunit_test_begin "tabbar_labels: no tabs shows empty with +SQL hint"
shql_table_init_browser
_shql_tabbar_build_line 40 _line
assert_contains "$_line" "+SQL"

ptyunit_test_begin "tabbar_labels: active tab label highlighted in output"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "orders" "schema"
_SHQL_TAB_ACTIVE=0
_shql_tabbar_build_line 80 _line
assert_contains "$_line" "users·Data"
assert_contains "$_line" "orders·Schema"

ptyunit_test_summary
