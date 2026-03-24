#!/usr/bin/env bash
# tests/unit/test-query.sh — Unit tests for Query tab logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

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

# ── Test 1b: _shql_query_init resets EDITOR_ACTIVE to 0 ──────────────────────

ptyunit_test_begin "query_init: EDITOR_ACTIVE=0 (button state)"
_SHQL_QUERY_EDITOR_ACTIVE=1   # simulate leftover state
_shql_query_init
assert_eq 0 "$_SHQL_QUERY_EDITOR_ACTIVE"

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

# ── Test 6: footer hint — button state shows [Esc] Tab bar, no [q] Back ──────

ptyunit_test_begin "footer_hint: button state shows [Esc] Tab bar, no [q] Back"
_SHQL_QUERY_STATUS=""
_SHQL_QUERY_FOCUSED_PANE="editor"
_SHQL_QUERY_EDITOR_ACTIVE=0
_shql_query_footer_hint _hint
assert_contains "$_hint" "[Esc] Tab bar"
assert_eq 0 $(printf '%s' "$_hint" | grep -c "\[q\] Back" || true)

# ── Test 6b: footer hint — typing state shows [Ctrl-D] Run and [Esc] Done ────

ptyunit_test_begin "footer_hint: typing state shows [Ctrl-D] Run and [Esc] Done editing"
_SHQL_QUERY_FOCUSED_PANE="editor"
_SHQL_QUERY_EDITOR_ACTIVE=1
_shql_query_footer_hint _hint
assert_contains "$_hint" "[Ctrl-D] Run"
assert_contains "$_hint" "[Esc] Done editing"

# ── Test 7: Tab key from button state → results ───────────────────────────────

ptyunit_test_begin "on_key: Tab from editor button state switches to results"
_shql_query_init
_SHQL_QUERY_FOCUSED_PANE="editor"
_SHQL_QUERY_EDITOR_ACTIVE=0
_k_tab=$'\t'
_shql_query_on_key "$_k_tab"
assert_eq "results" "$_SHQL_QUERY_FOCUSED_PANE"

# ── Test 8: Tab key cycles results → editor ───────────────────────────────────

ptyunit_test_begin "on_key: Tab from results switches to editor"
_shql_query_on_key "$_k_tab"
assert_eq "editor" "$_SHQL_QUERY_FOCUSED_PANE"

# ── Test 9: Enter from button state activates typing mode ─────────────────────

ptyunit_test_begin "on_key: Enter from button state activates typing mode"
_shql_query_init
_SHQL_QUERY_FOCUSED_PANE="editor"
_SHQL_QUERY_EDITOR_ACTIVE=0
_shql_query_on_key $'\r'
assert_eq 1 "$_SHQL_QUERY_EDITOR_ACTIVE"

# ── Test 10: Esc from typing state returns to button state ────────────────────

ptyunit_test_begin "on_key: Esc from typing state returns to button state (not tabbar)"
_SHQL_QUERY_FOCUSED_PANE="editor"
_SHQL_QUERY_EDITOR_ACTIVE=1
_shql_query_on_key $'\033'
assert_eq 0 "$_SHQL_QUERY_EDITOR_ACTIVE"
assert_eq "editor" "$_SHQL_QUERY_FOCUSED_PANE"

# ── Test 11: Ctrl-D submit focuses results and exits typing mode ──────────────

ptyunit_test_begin "on_key: Ctrl-D submit (editor rc=2) → results focused, ACTIVE=0"
_shql_query_init
_SHQL_QUERY_FOCUSED_PANE="editor"
_SHQL_QUERY_EDITOR_ACTIVE=1
# Override editor stub to simulate Ctrl-D submit (rc=2)
shellframe_editor_on_key() { SHELLFRAME_EDITOR_RESULT="SELECT 1"; return 2; }
_shql_query_on_key $'\004'
shellframe_editor_on_key() { return 1; }   # restore stub
assert_eq "results" "$_SHQL_QUERY_FOCUSED_PANE"
assert_eq 0 "$_SHQL_QUERY_EDITOR_ACTIVE"

ptyunit_test_begin "query_init_ctx: initializes state for given ctx"
_shql_query_init_ctx "t2"
assert_eq 0 "$_SHQL_QUERY_CTX_INITIALIZED_t2"
assert_eq "editor" "$_SHQL_QUERY_CTX_FOCUSED_PANE_t2"
assert_eq "" "$_SHQL_QUERY_CTX_STATUS_t2"

ptyunit_test_begin "query: placeholder text is 'No results yet'"
# The placeholder is in _shql_query_render_ctx — check the constant
assert_contains "${_SHQL_QUERY_PLACEHOLDER:-No results yet}" "No results yet"

ptyunit_test_summary
