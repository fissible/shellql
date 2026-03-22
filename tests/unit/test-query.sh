#!/usr/bin/env bash
# tests/unit/test-query.sh — Unit tests for Query tab logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/ptyunit/assert.sh"

# ── Minimal shellframe stubs ──────────────────────────────────────────────────

shellframe_sel_init()     { true; }
shellframe_scroll_init()  { true; }
shellframe_sel_cursor()   { printf -v "$2" '%d' 0; }
shellframe_editor_init()  { true; }
shellframe_grid_init()    { true; }
shellframe_grid_on_key()  { return 1; }
shellframe_shell_focus_set() { true; }
shellframe_editor_get_text() {
    # stub: sets out-var to a non-empty SQL string
    printf -v "$2" '%s' "SELECT 1"
}
# editor_on_key: return 1 (unhandled) so query-level Tab/Escape bindings fire in tests
shellframe_editor_on_key()   { return 1; }
SHELLFRAME_EDITOR_RESULT=""

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
source "$SHQL_ROOT/src/screens/query.sh"

# ── Test 1: _shql_query_init sets initial globals ────────────────────────────

ptyunit_test_begin "query_init: INITIALIZED=0, FOCUSED_PANE=editor, STATUS empty"
_shql_query_init
assert_eq 0 "$_SHQL_QUERY_INITIALIZED"
assert_eq "editor" "$_SHQL_QUERY_FOCUSED_PANE"
assert_eq "" "$_SHQL_QUERY_STATUS"

# ── Test 2: _shql_query_run populates grid globals ───────────────────────────

ptyunit_test_begin "query_run: HAS_RESULTS=1, GRID_ROWS=3, GRID_COLS=3"
_shql_query_run "SELECT 1"
assert_eq 1 "$_SHQL_QUERY_HAS_RESULTS"
assert_eq 3 "$SHELLFRAME_GRID_ROWS"
assert_eq 3 "$SHELLFRAME_GRID_COLS"

# ── Test 3: _shql_query_run sets correct headers ─────────────────────────────

ptyunit_test_begin "query_run: headers are id, name, email"
assert_eq "id"    "${SHELLFRAME_GRID_HEADERS[0]}"
assert_eq "name"  "${SHELLFRAME_GRID_HEADERS[1]}"
assert_eq "email" "${SHELLFRAME_GRID_HEADERS[2]}"

# ── Test 4: _shql_query_run sets STATUS to row count ─────────────────────────

ptyunit_test_begin "query_run: STATUS is '3 rows'"
assert_eq "3 rows" "$_SHQL_QUERY_STATUS"

# ── Test 5: footer hint with status + results pane ───────────────────────────

ptyunit_test_begin "footer_hint: status + results pane shows status and [q] Back"
_SHQL_QUERY_STATUS="3 rows"
_SHQL_QUERY_FOCUSED_PANE="results"
_shql_query_footer_hint _hint
assert_contains "$_hint" "3 rows"
assert_contains "$_hint" "[q] Back"

# ── Test 6: footer hint with no status + editor pane ─────────────────────────

ptyunit_test_begin "footer_hint: no status + editor pane shows [Esc] Tab bar, no [q] Back"
_SHQL_QUERY_STATUS=""
_SHQL_QUERY_FOCUSED_PANE="editor"
_shql_query_footer_hint _hint
assert_contains "$_hint" "[Esc] Tab bar"
assert_eq 0 $(echo "$_hint" | grep -c "\[q\] Back" || true)

# ── Test 7: Tab key cycles editor → results ───────────────────────────────────

ptyunit_test_begin "on_key: Tab from editor switches to results"
_SHQL_QUERY_FOCUSED_PANE="editor"
_k_tab=$'\t'
_shql_query_on_key "$_k_tab"
assert_eq "results" "$_SHQL_QUERY_FOCUSED_PANE"

# ── Test 8: Tab key cycles results → editor ───────────────────────────────────

ptyunit_test_begin "on_key: Tab from results switches to editor"
_shql_query_on_key "$_k_tab"
assert_eq "editor" "$_SHQL_QUERY_FOCUSED_PANE"

ptyunit_test_summary
