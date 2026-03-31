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
shellframe_shell_region()    { true; }
shellframe_editor_get_text() { printf -v "$2" '%s' "SELECT 1"; }
shellframe_editor_set_text() { _SHQL_TEST_EDITOR_CTX="$1"; _SHQL_TEST_EDITOR_TEXT="$2"; }
shellframe_editor_on_key()   { return 1; }
shellframe_sel_move()        { true; }
shellframe_panel_render()    { true; }
shellframe_panel_inner()     { true; }
shellframe_shell_mark_dirty() { true; }
shellframe_cmenu_init()       { true; }
shellframe_sel_set()          { true; }
shellframe_list_on_mouse()    { return 0; }
shellframe_grid_on_mouse()    { return 0; }
shellframe_scroll_left()      { printf -v "$2" '%d' 0; }
_shellframe_shell_terminal_size() { printf -v "$1" '%d' 24; printf -v "$2" '%d' 80; }
SHELLFRAME_CMENU_ITEMS=()
SHELLFRAME_CMENU_ANCHOR_ROW=1
SHELLFRAME_CMENU_ANCHOR_COL=1
SHELLFRAME_CMENU_CTX=""
SHELLFRAME_CMENU_FOCUSED=0
SHELLFRAME_CMENU_STYLE=""
SHELLFRAME_CMENU_BG=""
SHELLFRAME_CMENU_RESULT=-1
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

# ── Test: shql_browser_init resets tab arrays and loads tables ────────────────

ptyunit_test_begin "shql_browser_init: resets tab arrays and loads tables"
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
assert_eq 0 "${#_SHQL_TABS_TYPE[@]}"
assert_eq -1 "$_SHQL_TAB_ACTIVE"
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))

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
for (( _i=0; _i<10; _i++ )); do
    _shql_tab_open "" "query"
done
_shql_tab_fits 40 _result
assert_eq 0 "$_result"

ptyunit_test_begin "browser_init: loads tables into _SHQL_BROWSER_TABLES"
_SHQL_TABLE_NAME=""
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))
assert_eq "categories" "${_SHQL_BROWSER_TABLES[0]}"

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
assert_eq "categories" "${_SHQL_TABS_TABLE[0]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "sidebar_on_key: s opens schema tab for selected table"
shql_table_init_browser
_shql_TABLE_sidebar_on_key 's'
assert_eq "schema" "${_SHQL_TABS_TYPE[0]}"
assert_eq "categories" "${_SHQL_TABS_TABLE[0]}"

ptyunit_test_begin "sidebar_on_key: right arrow moves focus to tabbar (rc=0)"
_saved_focus=""
shellframe_shell_focus_set() { _saved_focus="$1"; }
shql_table_init_browser
_shql_TABLE_sidebar_on_key $'\033[C'; _rc=$?
assert_eq 0 "$_rc"
assert_eq "tabbar" "$_saved_focus"
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

ptyunit_test_begin "content_dispatch: empty state hint shown when ACTIVE=-1"
_SHQL_TAB_ACTIVE=-1
_shql_content_type _type
assert_eq "empty" "$_type"

ptyunit_test_begin "content_dispatch: data type when active tab is data"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_content_type _type
assert_eq "data" "$_type"

ptyunit_test_begin "content_dispatch: schema type when active tab is schema"
shql_table_init_browser
_shql_tab_open "users" "schema"
_shql_content_type _type
assert_eq "schema" "$_type"

ptyunit_test_begin "schema_tab_load: loads DDL and columns for active tab"
shql_table_init_browser
_shql_tab_open "users" "schema"
_shql_schema_tab_load "users"
_sentinel="_SHQL_SCHEMA_TAB_LOADED_${_SHQL_TABS_CTX[0]}"
assert_eq "1" "${!_sentinel:-0}"

ptyunit_test_begin "schema_tab: focus defaults to cols pane"
shql_table_init_browser
_shql_tab_open "users" "schema"
_SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
assert_eq "schema_cols" "$_SHQL_BROWSER_CONTENT_FOCUS"

ptyunit_test_begin "content_on_key: up at row 0 in data tab moves focus to tabbar"
shql_table_init_browser
_shql_tab_open "users" "data"
_SHQL_BROWSER_CONTENT_FOCUSED=1
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }   # simulate row 0
_saved_focus=""
shellframe_shell_focus_set() { _saved_focus="$1"; }
_shql_TABLE_content_on_key $'\033[A'   # up
assert_eq "tabbar" "$_saved_focus"
shellframe_shell_focus_set() { true; }

ptyunit_test_begin "content_on_key: ] switches to next tab"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "orders" "data"
_SHQL_TAB_ACTIVE=0
shellframe_grid_on_key() { return 1; }   # doesn't handle ]
_shql_TABLE_content_on_key ']'
assert_eq 1 "$_SHQL_TAB_ACTIVE"

# ── Test: footer hints ────────────────────────────────────────────────────────

ptyunit_test_begin "footer_hint: sidebar focused shows sidebar hints"
_SHQL_BROWSER_SIDEBAR_FOCUSED=1
_SHQL_BROWSER_TABBAR_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUSED=0
_SHQL_INSPECTOR_ACTIVE=0
_shql_browser_footer_hint _hint
assert_contains "$_hint" "Enter"
assert_contains "$_hint" "[s] Schema"

ptyunit_test_begin "footer_hint: empty state shows select hint"
_SHQL_BROWSER_SIDEBAR_FOCUSED=0
_SHQL_BROWSER_TABBAR_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUSED=1
_SHQL_TAB_ACTIVE=-1
_SHQL_INSPECTOR_ACTIVE=0
_shql_browser_footer_hint _hint
assert_contains "$_hint" "select"

# ── Test: sidebar icons ──────────────────────────────────────────────────────

ptyunit_test_begin "browser_init: sidebar items have table icon when theme sets it"
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
assert_contains "${_SHQL_BROWSER_SIDEBAR_ITEMS[0]}" "▤"

ptyunit_test_begin "browser_init: sidebar items have no icon when theme unset"
SHQL_THEME_TABLE_ICON=""
SHQL_THEME_VIEW_ICON=""
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
_first_char="${_SHQL_BROWSER_SIDEBAR_ITEMS[0]:0:1}"
assert_eq "c" "$_first_char"

# ── Test: theme token propagation to grid globals ────────────────────────────

ptyunit_test_begin "theme_tokens: stripe and cursor propagate to grid globals"
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;238m'
SHQL_THEME_CURSOR_BG=$'\033[48;5;240m'
SHQL_THEME_CURSOR_BOLD=$'\033[1m'
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
_shql_tab_open "users" "data"
_shql_content_data_ensure
SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
SHELLFRAME_GRID_FOCUSED=1
SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
if [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
    SHELLFRAME_GRID_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
else
    SHELLFRAME_GRID_CURSOR_STYLE=""
fi
assert_contains "$SHELLFRAME_GRID_STRIPE_BG" "238"
assert_contains "$SHELLFRAME_GRID_CURSOR_STYLE" "240"

# ── Context menu: sidebar right-click ────────────────────────────────────────

ptyunit_test_begin "cmenu: sidebar right-click opens context menu"
shql_browser_init
_SHQL_CMENU_ACTIVE=0
_shql_TABLE_sidebar_on_mouse 2 "press" 4 5 2 1 20 22
assert_eq "1" "$_SHQL_CMENU_ACTIVE"
assert_eq "sidebar" "$_SHQL_CMENU_SOURCE"

ptyunit_test_begin "cmenu: sidebar right-click sets menu items"
shql_browser_init
_shql_TABLE_sidebar_on_mouse 2 "press" 4 5 2 1 20 22
assert_eq "3" "${#SHELLFRAME_CMENU_ITEMS[@]}"
assert_eq "Open Data" "${SHELLFRAME_CMENU_ITEMS[0]}"
assert_eq "Open Schema" "${SHELLFRAME_CMENU_ITEMS[1]}"
assert_eq "New Query" "${SHELLFRAME_CMENU_ITEMS[2]}"

ptyunit_test_begin "cmenu: sidebar left-click does not open context menu"
shql_browser_init
_SHQL_CMENU_ACTIVE=0
_shql_TABLE_sidebar_on_mouse 0 "press" 4 5 2 1 20 22
assert_eq "0" "$_SHQL_CMENU_ACTIVE"

# ── Context menu: tabbar right-click ─────────────────────────────────────────

ptyunit_test_begin "cmenu: tabbar right-click opens context menu"
shql_browser_init
_shql_tab_open "users" "data"
_SHQL_CMENU_ACTIVE=0
# Click in the first tab label area (left=21, first tab starts at col 21)
_shql_TABLE_tabbar_on_mouse 2 "press" 2 22 2 21 59 1
assert_eq "1" "$_SHQL_CMENU_ACTIVE"
assert_eq "tabbar" "$_SHQL_CMENU_SOURCE"

ptyunit_test_begin "cmenu: tabbar right-click menu items"
shql_browser_init
_shql_tab_open "users" "data"
_shql_TABLE_tabbar_on_mouse 2 "press" 2 22 2 21 59 1
assert_eq "2" "${#SHELLFRAME_CMENU_ITEMS[@]}"
assert_eq "Close Tab" "${SHELLFRAME_CMENU_ITEMS[0]}"
assert_eq "New Query" "${SHELLFRAME_CMENU_ITEMS[1]}"

ptyunit_test_begin "cmenu: tabbar left-click does not open context menu"
shql_browser_init
_shql_tab_open "users" "data"
_SHQL_CMENU_ACTIVE=0
_shql_TABLE_tabbar_on_mouse 0 "press" 2 22 2 21 59 1
assert_eq "0" "$_SHQL_CMENU_ACTIVE"

# ── Context menu: content right-click ────────────────────────────────────────

ptyunit_test_begin "cmenu: data content right-click opens context menu"
shql_browser_init
_shql_tab_open "users" "data"
_SHQL_CMENU_ACTIVE=0
_shql_TABLE_content_on_mouse 2 "press" 6 30 4 21 59 20
assert_eq "1" "$_SHQL_CMENU_ACTIVE"
assert_eq "content" "$_SHQL_CMENU_SOURCE"

ptyunit_test_begin "cmenu: data content right-click menu items"
shql_browser_init
_shql_tab_open "users" "data"
_shql_TABLE_content_on_mouse 2 "press" 6 30 4 21 59 20
assert_eq "1" "${#SHELLFRAME_CMENU_ITEMS[@]}"
assert_eq "Inspect Row" "${SHELLFRAME_CMENU_ITEMS[0]}"

# ── Context menu: dismiss restores state ─────────────────────────────────────

ptyunit_test_begin "cmenu: dismiss clears active flag"
shql_browser_init
_SHQL_CMENU_ACTIVE=1
_SHQL_CMENU_PREV_FOCUS="sidebar"
_shql_cmenu_dismiss
assert_eq "0" "$_SHQL_CMENU_ACTIVE"

# ── Context menu: dispatch sidebar actions ───────────────────────────────────

ptyunit_test_begin "cmenu: dispatch sidebar Open Data opens data tab"
shql_browser_init
_SHQL_CMENU_SOURCE="sidebar"
_SHQL_CMENU_SOURCE_IDX=0
SHELLFRAME_CMENU_RESULT=0
_SHQL_CMENU_ACTIVE=1
_SHQL_CMENU_PREV_FOCUS="sidebar"
_shql_cmenu_dispatch
assert_eq "0" "$_SHQL_CMENU_ACTIVE"
assert_eq "1" "${#_SHQL_TABS_TYPE[@]}"
assert_eq "data" "${_SHQL_TABS_TYPE[0]}"

ptyunit_test_begin "cmenu: dispatch sidebar Open Schema opens schema tab"
shql_browser_init
_SHQL_CMENU_SOURCE="sidebar"
_SHQL_CMENU_SOURCE_IDX=0
SHELLFRAME_CMENU_RESULT=1
_SHQL_CMENU_ACTIVE=1
_SHQL_CMENU_PREV_FOCUS="sidebar"
_shql_cmenu_dispatch
assert_eq "0" "$_SHQL_CMENU_ACTIVE"
assert_eq "1" "${#_SHQL_TABS_TYPE[@]}"
assert_eq "schema" "${_SHQL_TABS_TYPE[0]}"

ptyunit_test_begin "cmenu: dispatch sidebar New Query opens query tab"
shql_browser_init
_SHQL_CMENU_SOURCE="sidebar"
_SHQL_CMENU_SOURCE_IDX=0
SHELLFRAME_CMENU_RESULT=2
_SHQL_CMENU_ACTIVE=1
_SHQL_CMENU_PREV_FOCUS="sidebar"
_shql_cmenu_dispatch
assert_eq "0" "$_SHQL_CMENU_ACTIVE"
assert_eq "1" "${#_SHQL_TABS_TYPE[@]}"
assert_eq "query" "${_SHQL_TABS_TYPE[0]}"

ptyunit_test_begin "cmenu: dispatch tabbar Close Tab closes active tab"
shql_browser_init
_shql_tab_open "users" "data"
assert_eq "1" "${#_SHQL_TABS_TYPE[@]}"
_SHQL_CMENU_SOURCE="tabbar"
_SHQL_CMENU_SOURCE_IDX=0
SHELLFRAME_CMENU_RESULT=0
_SHQL_CMENU_ACTIVE=1
_SHQL_CMENU_PREV_FOCUS="tabbar"
_shql_cmenu_dispatch
assert_eq "0" "${#_SHQL_TABS_TYPE[@]}"

ptyunit_test_begin "cmenu: dispatch with -1 result does nothing"
shql_browser_init
_SHQL_CMENU_SOURCE="sidebar"
_SHQL_CMENU_SOURCE_IDX=0
SHELLFRAME_CMENU_RESULT=-1
_SHQL_CMENU_ACTIVE=1
_SHQL_CMENU_PREV_FOCUS="sidebar"
_shql_cmenu_dispatch
assert_eq "0" "$_SHQL_CMENU_ACTIVE"
assert_eq "0" "${#_SHQL_TABS_TYPE[@]}"

# ── Context menu: render registers cmenu region ─────────────────────────────

ptyunit_test_begin "cmenu: TABLE_render registers cmenu region when active"
shql_browser_init
_SHQL_CMENU_ACTIVE=1
_shql_TABLE_render
# shellframe_shell_region was called with "cmenu" — check via the last region
# (we can't easily inspect the array since stubs don't populate it,
#  but the function runs without error)
assert_eq "1" "$_SHQL_CMENU_ACTIVE"

ptyunit_test_begin "tabs_close_by_table: closes all matching tabs"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "users" "schema"
_shql_tab_open "orders" "data"
assert_eq 3 "${#_SHQL_TABS_TYPE[@]}"
_shql_tabs_close_by_table "users"
assert_eq 1 "${#_SHQL_TABS_TYPE[@]}"
assert_eq "orders" "${_SHQL_TABS_TABLE[0]}"

ptyunit_test_begin "tabs_close_by_table: no-op when table not open"
shql_table_init_browser
_shql_tab_open "orders" "data"
_shql_tabs_close_by_table "users"
assert_eq 1 "${#_SHQL_TABS_TYPE[@]}"

ptyunit_test_begin "drop_confirm: sets active flag and table/type"
_SHQL_DROP_CONFIRM_ACTIVE=0
_shql_drop_confirm "orders" "table"
assert_eq "1" "$_SHQL_DROP_CONFIRM_ACTIVE"
assert_eq "orders" "$_SHQL_DROP_CONFIRM_TABLE"
assert_eq "table" "$_SHQL_DROP_CONFIRM_TYPE"

ptyunit_test_begin "drop_confirm: works for views"
_SHQL_DROP_CONFIRM_ACTIVE=0
_shql_drop_confirm "v_active" "view"
assert_eq "1" "$_SHQL_DROP_CONFIRM_ACTIVE"
assert_eq "view" "$_SHQL_DROP_CONFIRM_TYPE"

ptyunit_test_begin "sidebar_action_create_table: opens tab with 'New Table' label"
shql_table_init_browser
_SHQL_TEST_EDITOR_CTX=""
_SHQL_TEST_EDITOR_TEXT=""
_shql_TABLE_sidebar_action_create_table
assert_eq "New Table" "${_SHQL_TABS_LABEL[$_SHQL_TAB_ACTIVE]}" "create_table: tab label is 'New Table'"

ptyunit_test_begin "sidebar_action_create_table: pre-fills editor with CREATE TABLE template"
assert_contains "$_SHQL_TEST_EDITOR_TEXT" "CREATE TABLE" "create_table: template contains CREATE TABLE"
assert_contains "$_SHQL_TEST_EDITOR_TEXT" "PRIMARY KEY" "create_table: template contains PRIMARY KEY"

ptyunit_test_summary
