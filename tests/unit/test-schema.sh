#!/usr/bin/env bash
# tests/unit/test-schema.sh — Unit tests for schema browser state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

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

# ── Test: shql_db_columns mock returns columns for users ─────────────────────

ptyunit_test_begin "db_columns: mock returns 15 columns for users"
_cols_out=$(shql_db_columns "/mock/test.db" "users")
_col_count=$(printf '%s\n' "$_cols_out" | wc -l | tr -d ' ')
assert_eq 15 "$_col_count"

ptyunit_test_begin "db_columns: first column is id with PK flag"
_first=$(printf '%s\n' "$_cols_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "PK"

ptyunit_test_begin "db_columns: second column is name with NN flag"
_second=$(printf '%s\n' "$_cols_out" | sed -n '2p')
assert_contains "$_second" "name"
assert_contains "$_second" "NN"

# ── Test: _shql_schema_load_columns populates array ──────────────────────────

ptyunit_test_begin "load_columns: populates _SHQL_SCHEMA_COLUMNS for users"
_SHQL_SCHEMA_COLUMNS=()
_shql_schema_load_columns "users"
assert_eq 1 $(( ${#_SHQL_SCHEMA_COLUMNS[@]} > 0 ))

ptyunit_test_begin "load_columns: first entry contains id and PK"
assert_contains "${_SHQL_SCHEMA_COLUMNS[0]}" "id"
assert_contains "${_SHQL_SCHEMA_COLUMNS[0]}" "PK"

ptyunit_test_begin "load_columns: load_ddl triggers column reload"
_SHQL_SCHEMA_COLUMNS=()
_shql_schema_load_ddl "orders"
assert_eq 1 $(( ${#_SHQL_SCHEMA_COLUMNS[@]} > 0 ))
assert_contains "${_SHQL_SCHEMA_COLUMNS[0]}" "id"

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

# ── Test: shql_db_list_objects mock returns name and type ─────────────────────

ptyunit_test_begin "db_list_objects: mock returns at least 4 objects"
_objs=$(shql_db_list_objects "/mock/test.db")
_obj_count=$(printf '%s\n' "$_objs" | wc -l | tr -d ' ')
assert_eq 1 $(( _obj_count >= 4 ))

ptyunit_test_begin "db_list_objects: first object is a table"
_first=$(printf '%s\n' "$_objs" | head -1)
assert_contains "$_first" "table"

# ── Additional logic and render tests ─────────────────────────────────────────

_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${SHQL_ROOT}/../shellframe}"
source "$_SHELLFRAME_DIR/src/scroll.sh"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$_SHELLFRAME_DIR/src/clip.sh"

# Stub panel/list functions for render tests
shellframe_panel_render() { true; }
shellframe_panel_inner() {
    printf -v "$5" '%d' "$(( $1 + 1 ))"
    printf -v "$6" '%d' "$(( $2 + 1 ))"
    printf -v "$7" '%d' "$(( $3 - 2 ))"
    printf -v "$8" '%d' "$(( $4 - 2 ))"
}
shellframe_list_render() { true; }
shellframe_list_on_key() { return 1; }

# Helper: extract stripped text from a framebuffer row
_fb_schema_row_text() {
    local _row="$1" _out="" _i _cols="${_SF_FRAME_COLS:-80}"
    for (( _i=0; _i<_cols; _i++ )); do
        local _idx=$(( (_row-1)*_cols + _i ))
        _out+="${_SF_FRAME_CURR[${_idx}]:-}"
    done
    printf '%s' "$_out" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g' | tr -d $'\033'
}

# ── Test: _shql_schema_current_table ─────────────────────────────────────────

ptyunit_test_begin "schema_current_table: returns first table via out var"
_SHQL_SCHEMA_TABLES=("users" "orders")
_t=""
_shql_schema_current_table _t
assert_eq "users" "$_t"

ptyunit_test_begin "schema_current_table: returns first table to stdout"
_SHQL_SCHEMA_TABLES=("users" "orders")
_t=$(_shql_schema_current_table)
assert_eq "users" "$_t"

ptyunit_test_begin "schema_current_table: empty tables returns empty string"
_SHQL_SCHEMA_TABLES=()
_t="nonempty"
_shql_schema_current_table _t
assert_eq "" "$_t"

# ── Test: _shql_SCHEMA_footer_render ─────────────────────────────────────────

ptyunit_test_begin "schema_footer_render: sidebar focused — contains 'Select table'"
shellframe_fb_frame_start 24 80
_SHQL_SCHEMA_DETAIL_FOCUSED=0
_shql_SCHEMA_footer_render 1 1 80
_text=$(_fb_schema_row_text 1)
assert_contains "$_text" "Select table"

ptyunit_test_begin "schema_footer_render: detail focused — contains 'Scroll DDL'"
shellframe_fb_frame_start 24 80
_SHQL_SCHEMA_DETAIL_FOCUSED=1
_shql_SCHEMA_footer_render 2 1 80
_text=$(_fb_schema_row_text 2)
assert_contains "$_text" "Scroll DDL"

# ── Test: _shql_SCHEMA_detail_on_key ─────────────────────────────────────────

ptyunit_test_begin "detail_on_key: down moves scroll top to 1"
shellframe_scroll_init "$_SHQL_SCHEMA_DDL_CTX" 20 1 5 1
_shql_SCHEMA_detail_on_key $'\033[B'
_st=0; shellframe_scroll_top "$_SHQL_SCHEMA_DDL_CTX" _st
assert_eq "1" "$_st"

ptyunit_test_begin "detail_on_key: up moves scroll top back to 0"
_shql_SCHEMA_detail_on_key $'\033[A'
shellframe_scroll_top "$_SHQL_SCHEMA_DDL_CTX" _st
assert_eq "0" "$_st"

ptyunit_test_begin "detail_on_key: page_down returns 0"
_shql_SCHEMA_detail_on_key $'\033[6~'; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "detail_on_key: page_up returns 0"
_shql_SCHEMA_detail_on_key $'\033[5~'; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "detail_on_key: home returns 0"
_shql_SCHEMA_detail_on_key $'\033[H'; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "detail_on_key: end returns 0"
_shql_SCHEMA_detail_on_key $'\033[F'; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "detail_on_key: unknown key returns 1"
_shql_SCHEMA_detail_on_key 'x'; _rc=$?
assert_eq "1" "$_rc"

# ── Test: _shql_SCHEMA_detail_on_focus ───────────────────────────────────────

ptyunit_test_begin "detail_on_focus: sets DETAIL_FOCUSED=1"
_SHQL_SCHEMA_DETAIL_FOCUSED=0
_shql_SCHEMA_detail_on_focus 1
assert_eq "1" "$_SHQL_SCHEMA_DETAIL_FOCUSED"

ptyunit_test_begin "detail_on_focus: sets DETAIL_FOCUSED=0"
_SHQL_SCHEMA_DETAIL_FOCUSED=1
_shql_SCHEMA_detail_on_focus 0
assert_eq "0" "$_SHQL_SCHEMA_DETAIL_FOCUSED"

# ── Test: _shql_SCHEMA_sidebar_on_focus ──────────────────────────────────────

ptyunit_test_begin "sidebar_on_focus: sets SIDEBAR_FOCUSED=1"
_SHQL_SCHEMA_SIDEBAR_FOCUSED=0
_shql_SCHEMA_sidebar_on_focus 1
assert_eq "1" "$_SHQL_SCHEMA_SIDEBAR_FOCUSED"

# ── Test: _shql_SCHEMA_quit ───────────────────────────────────────────────────

ptyunit_test_begin "schema_quit: sets NEXT=WELCOME"
_SHELLFRAME_SHELL_NEXT=""
_shql_SCHEMA_quit
assert_eq "WELCOME" "$_SHELLFRAME_SHELL_NEXT"

# ── Test: shql_schema_init ────────────────────────────────────────────────────

ptyunit_test_begin "shql_schema_init: populates tables array from mock"
_SHQL_SCHEMA_TABLES=()
_SHQL_SCHEMA_DDL_LINES=()
shql_schema_init
assert_eq 1 $(( ${#_SHQL_SCHEMA_TABLES[@]} > 0 ))

ptyunit_test_begin "shql_schema_init: loads DDL for first table"
assert_eq 1 $(( ${#_SHQL_SCHEMA_DDL_LINES[@]} > 0 ))

ptyunit_test_begin "shql_schema_init: resets PREV_TABLE to first table"
assert_eq "users" "$_SHQL_SCHEMA_PREV_TABLE"

# ── Test: _shql_SCHEMA_sidebar_action ────────────────────────────────────────

shql_table_init() { true; }

ptyunit_test_begin "sidebar_action: empty table list is no-op"
_SHQL_SCHEMA_TABLES=()
_SHELLFRAME_SHELL_NEXT=""
_shql_SCHEMA_sidebar_action
assert_eq "" "$_SHELLFRAME_SHELL_NEXT"

ptyunit_test_begin "sidebar_action: valid table sets TABLE_NAME and navigates to TABLE"
_SHQL_SCHEMA_TABLES=("users" "orders")
_SHELLFRAME_SHELL_NEXT=""
_SHQL_TABLE_NAME=""
_shql_SCHEMA_sidebar_action
assert_eq "TABLE" "$_SHELLFRAME_SHELL_NEXT"
assert_eq "users" "$_SHQL_TABLE_NAME"

# ── Test: _shql_SCHEMA_sidebar_on_key ─────────────────────────────────────────

ptyunit_test_begin "sidebar_on_key: delegates to shellframe_list_on_key"
_shql_SCHEMA_sidebar_on_key 'x'; _rc=$?
assert_eq "1" "$_rc"

# ── Test: _shql_SCHEMA_header_render (fb render) ─────────────────────────────

ptyunit_test_begin "schema_header_render: writes cells to framebuffer"
shellframe_fb_frame_start 24 80
SHQL_DRIVER=sqlite SHQL_DB_PATH="/data/test.db"
_shql_SCHEMA_header_render 1 1 80
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 ))

# ── Test: _shql_SCHEMA_sidebar_render (fb render) ─────────────────────────────

ptyunit_test_begin "schema_sidebar_render: unfocused — sets single panel style"
_SHQL_SCHEMA_TABLES=("users" "orders")
_SHQL_SCHEMA_SIDEBAR_FOCUSED=0
SHELLFRAME_PANEL_STYLE=""
_shql_SCHEMA_sidebar_render 1 1 20 20
assert_eq "single" "$SHELLFRAME_PANEL_STYLE"

ptyunit_test_begin "schema_sidebar_render: focused — sets focused panel style"
shellframe_fb_frame_start 24 40
_SHQL_SCHEMA_SIDEBAR_FOCUSED=1
_shql_SCHEMA_sidebar_render 1 1 20 20
assert_eq "${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}" "$SHELLFRAME_PANEL_STYLE"

# ── Test: _shql_SCHEMA_columns_render (fb render) ────────────────────────────

ptyunit_test_begin "schema_columns_render: renders columns to framebuffer"
shellframe_fb_frame_start 24 80
_SHQL_SCHEMA_COLUMNS=("id	INTEGER	PK" "name	TEXT	NN")
_shql_SCHEMA_columns_render 1 1 30 20
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 ))

# ── Test: _shql_SCHEMA_detail_render (fb render) ──────────────────────────────

ptyunit_test_begin "schema_detail_render: renders DDL to framebuffer"
shellframe_fb_frame_start 24 80
_SHQL_SCHEMA_TABLES=("users")
_SHQL_SCHEMA_PREV_TABLE="users"
_SHQL_SCHEMA_DDL_LINES=("CREATE TABLE users (" "  id INTEGER PRIMARY KEY" ");")
shellframe_scroll_init "$_SHQL_SCHEMA_DDL_CTX" 3 1 5 1
_SHQL_SCHEMA_DETAIL_FOCUSED=0
_shql_SCHEMA_detail_render 1 1 40 20
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 ))

ptyunit_test_summary
