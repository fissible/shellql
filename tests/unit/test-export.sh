#!/usr/bin/env bash
# tests/unit/test-export.sh — Unit tests for export helpers

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# ── Minimal stubs ─────────────────────────────────────────────────────────────

shellframe_field_init()    { true; }
shellframe_field_on_key()  { true; }
shellframe_field_render()  { true; }
shellframe_cur_init()      { true; }
shellframe_cur_set()       { true; }
shellframe_cur_text()      { printf -v "$2" '%s' ""; }
shellframe_shell_mark_dirty() { true; }
shellframe_toast_show()    { true; }
shellframe_panel_render()  { true; }
shellframe_panel_inner()   {
    # Returns dummy inner dimensions: top left w h
    printf -v "$5" '%d' "$(( $1 + 1 ))"
    printf -v "$6" '%d' "$(( $2 + 1 ))"
    printf -v "$7" '%d' "$(( $3 - 2 ))"
    printf -v "$8" '%d' "$(( $4 - 2 ))"
}
shellframe_fb_fill()       { true; }
shellframe_fb_print()      { true; }
shql_config_get_fetch_limit() { printf '500\n'; }
shql_db_fetch()            { true; }

# ── Minimal global state expected by export.sh ────────────────────────────────

_SHQL_TAB_ACTIVE=0
_SHQL_TABS_CTX=("t0")
_SHQL_TABS_TABLE=("users")
_SHQL_TABS_TYPE=("data")

SHQL_DB_PATH="/tmp/test.db"
SHELLFRAME_FIELD_CTX=""
SHELLFRAME_FIELD_FOCUSED=0
SHELLFRAME_FIELD_BG=""
SHELLFRAME_REVERSE=""
SHELLFRAME_GRAY=""
SHELLFRAME_GRID_HEADERS=()
SHELLFRAME_GRID_DATA=()
SHELLFRAME_GRID_ROWS=0
SHELLFRAME_GRID_COLS=0
SHQL_THEME_CONTENT_BG=""
SHQL_THEME_QUERY_PANEL_COLOR=""
SHQL_THEME_EDITOR_FOCUSED_BG=""
SHQL_THEME_ERROR_COLOR=""
SHQL_THEME_PANEL_STYLE_FOCUSED="double"
SHELLFRAME_PANEL_CELL_ATTRS=""
SHELLFRAME_PANEL_STYLE=""
SHELLFRAME_PANEL_TITLE=""
SHELLFRAME_PANEL_TITLE_ALIGN=""
SHELLFRAME_PANEL_FOCUSED=0

# ── Source export module ──────────────────────────────────────────────────────

source "$SHQL_ROOT/src/screens/export.sh"

# ── _shql_csv_quote_field ─────────────────────────────────────────────────────

ptyunit_test_begin "csv_quote_field: plain value passes through unquoted"
result="$(_shql_csv_quote_field "hello")"
assert_eq "hello" "$result"

ptyunit_test_begin "csv_quote_field: empty value passes through unquoted"
result="$(_shql_csv_quote_field "")"
assert_eq "" "$result"

ptyunit_test_begin "csv_quote_field: value with comma is quoted"
result="$(_shql_csv_quote_field "hello,world")"
assert_eq '"hello,world"' "$result"

ptyunit_test_begin "csv_quote_field: value with double-quote is quoted and doubled"
result="$(_shql_csv_quote_field 'say "hi"')"
assert_eq '"say ""hi"""' "$result"

ptyunit_test_begin "csv_quote_field: value with embedded newline is quoted"
result="$(_shql_csv_quote_field $'line1\nline2')"
assert_eq "\"$(printf 'line1\nline2')\"" "$result"

ptyunit_test_begin "csv_quote_field: value with carriage return is quoted"
result="$(_shql_csv_quote_field $'val\rmore')"
assert_eq "\"$(printf 'val\rmore')\"" "$result"

ptyunit_test_begin "csv_quote_field: numeric value passes through unquoted"
result="$(_shql_csv_quote_field "42")"
assert_eq "42" "$result"

ptyunit_test_begin "csv_quote_field: value with only spaces passes through unquoted"
result="$(_shql_csv_quote_field "   ")"
assert_eq "   " "$result"

ptyunit_test_begin "csv_quote_field: double-quote only is quoted and doubled"
result="$(_shql_csv_quote_field '"')"
assert_eq '""""' "$result"

# ── _shql_export_default_path ─────────────────────────────────────────────────

ptyunit_test_begin "export_default_path: csv with data tab uses table name"
_SHQL_EXPORT_FORMAT="csv"
_SHQL_EXPORT_TABLE="orders"
_shql_export_default_path _out
assert_eq "${HOME}/Downloads/orders.csv" "$_out"

ptyunit_test_begin "export_default_path: csv with query tab uses query.csv"
_SHQL_EXPORT_FORMAT="csv"
_SHQL_EXPORT_TABLE=""
_shql_export_default_path _out
assert_eq "${HOME}/Downloads/query.csv" "$_out"

ptyunit_test_begin "export_default_path: sql dump uses db basename"
_SHQL_EXPORT_FORMAT="sql"
_SHQL_EXPORT_TABLE="orders"
SHQL_DB_PATH="/home/user/databases/myapp.sqlite"
_shql_export_default_path _out
assert_eq "${HOME}/Downloads/myapp_dump.sql" "$_out"

ptyunit_test_begin "export_default_path: sql dump strips .db extension"
_SHQL_EXPORT_FORMAT="sql"
SHQL_DB_PATH="/tmp/test.db"
_shql_export_default_path _out
assert_eq "${HOME}/Downloads/test_dump.sql" "$_out"

ptyunit_test_begin "export_default_path: sql dump with no recognized extension"
_SHQL_EXPORT_FORMAT="sql"
SHQL_DB_PATH="/tmp/myfile"
_shql_export_default_path _out
assert_eq "${HOME}/Downloads/myfile_dump.sql" "$_out"

# ── _shql_export_open / _shql_export_close ────────────────────────────────────

ptyunit_test_begin "export_open: sets ACTIVE=1"
_SHQL_EXPORT_ACTIVE=0
_SHQL_TAB_ACTIVE=0
_SHQL_TABS_CTX=("t0")
_SHQL_TABS_TABLE=("users")
_shql_export_open
assert_eq "1" "$_SHQL_EXPORT_ACTIVE"

ptyunit_test_begin "export_open: captures table and ctx"
_shql_export_open
assert_eq "t0" "$_SHQL_EXPORT_CTX"
assert_eq "users" "$_SHQL_EXPORT_TABLE"

ptyunit_test_begin "export_open: defaults format to csv"
_shql_export_open
assert_eq "csv" "$_SHQL_EXPORT_FORMAT"

ptyunit_test_begin "export_open: is no-op when no active tab"
_SHQL_EXPORT_ACTIVE=0
_SHQL_TAB_ACTIVE=-1
_shql_export_open
assert_eq "0" "$_SHQL_EXPORT_ACTIVE"
_SHQL_TAB_ACTIVE=0   # restore

ptyunit_test_begin "export_close: resets ACTIVE to 0"
_SHQL_EXPORT_ACTIVE=1
_shql_export_close
assert_eq "0" "$_SHQL_EXPORT_ACTIVE"

ptyunit_test_begin "export_close: clears status"
_SHQL_EXPORT_STATUS="ok:/some/path"
_shql_export_close
assert_eq "" "$_SHQL_EXPORT_STATUS"

ptyunit_test_summary
