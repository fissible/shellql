#!/usr/bin/env bash
# tests/integration/test-integration.sh — End-to-end CLI integration tests
# REQUIRES: sqlite3 binary on PATH, SHELLFRAME_DIR set in environment

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

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

# ── Integration: browser open → data tab → inspector → navigate → close ──────
#
# These tests load internal screen modules with mock data so the browser open
# → inspect → close flow can be verified without a live terminal.

# Stubs needed by screen modules
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

SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE=''
_SHQL_ROOT="$SHQL_ROOT"
source "$SHQL_ROOT/src/theme.sh"
shql_theme_load basic

SHQL_MOCK=1
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/db_mock.sh"

shellframe_list_init() { true; }
source "$SHQL_ROOT/src/screens/schema.sh"
source "$SHQL_ROOT/src/screens/header.sh"
source "$SHQL_ROOT/src/screens/table.sh"
source "$SHQL_ROOT/src/screens/inspector.sh"
source "$SHQL_ROOT/src/screens/query.sh"

ptyunit_test_begin "integration: browser open populates tables list"
shql_browser_init
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))

ptyunit_test_begin "integration: Enter in sidebar opens data tab"
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }
_shql_TABLE_sidebar_action
assert_eq "data" "${_SHQL_TABS_TYPE[0]:-}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]:-}"

ptyunit_test_begin "integration: data tab content_ensure loads grid"
_shql_content_data_ensure
assert_eq 1 $(( SHELLFRAME_GRID_ROWS > 0 ))

ptyunit_test_begin "integration: inspector opens on Enter in data tab"
SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[0]}_grid"
_shql_inspector_open
assert_eq 1 "$_SHQL_INSPECTOR_ACTIVE"

ptyunit_test_begin "integration: inspector Esc restores ACTIVE=0 with ROW_IDX preserved"
_saved_idx="$_SHQL_INSPECTOR_ROW_IDX"
_shql_inspector_on_key $'\033'
assert_eq 0 "$_SHQL_INSPECTOR_ACTIVE"
assert_eq "$_saved_idx" "$_SHQL_INSPECTOR_ROW_IDX"

# ── Teardown ──────────────────────────────────────────────────────────────────

rm -rf "$_data_dir"
ptyunit_test_summary
