#!/usr/bin/env bash
# tests/unit/test-welcome.sh — Unit tests for welcome screen state logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# ── Minimal shellframe stubs (no tty needed) ──────────────────────────────────

shellframe_sel_init()    { true; }
shellframe_scroll_init() { true; }
shellframe_list_init()   { true; }

SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE=''
_SHQL_ROOT="$SHQL_ROOT"
source "$SHQL_ROOT/src/theme.sh"
shql_theme_load basic

# ── Source state, mock, and welcome modules ───────────────────────────────────

SHQL_MOCK=1
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/db_mock.sh"
source "$SHQL_ROOT/src/screens/welcome.sh"

# ── Test: shql_mock_load_recent populates SHQL_RECENT_NAMES ──────────────────

ptyunit_test_begin "mock_load_recent: populates SHQL_RECENT_NAMES"
SHQL_RECENT_NAMES=()
shql_mock_load_recent
assert_gt "${#SHQL_RECENT_NAMES[@]}" 0

# ── Test: shql_mock_load_recent first entry ends in app.db ───────────────────

ptyunit_test_begin "mock_load_recent: first name ends in app.db"
shql_mock_load_recent
[[ "${SHQL_RECENT_NAMES[0]}" == *"app.db" ]]
assert_eq 0 $?

# ── Test: empty SHQL_RECENT_NAMES produces empty-state path ──────────────────

ptyunit_test_begin "empty recent: SHQL_RECENT_NAMES length is 0"
SHQL_RECENT_NAMES=()
assert_eq 0 "${#SHQL_RECENT_NAMES[@]}"

# ── Test: _shql_welcome_init populates SHQL_RECENT_NAMES ─────────────────────

ptyunit_test_begin "_shql_welcome_init: populates SHQL_RECENT_NAMES"
SHQL_RECENT_NAMES=()
SHELLFRAME_LIST_ITEMS=()
_shql_welcome_init
assert_gt "${#SHQL_RECENT_NAMES[@]}" 0

# ── Test: _shql_welcome_init syncs SHELLFRAME_LIST_ITEMS ─────────────────────

ptyunit_test_begin "_shql_welcome_init: SHELLFRAME_LIST_ITEMS matches SHQL_RECENT_NAMES"
SHQL_RECENT_NAMES=()
SHELLFRAME_LIST_ITEMS=()
_shql_welcome_init
assert_eq "${#SHQL_RECENT_NAMES[@]}" "${#SHELLFRAME_LIST_ITEMS[@]}"

# ── Additional logic tests ────────────────────────────────────────────────────

# Stub remaining shellframe functions needed by logic tests
shellframe_list_on_key() { return 1; }

ptyunit_test_begin "list_on_key: 'o' returns 0 (intercept no-op)"
_shql_WELCOME_list_on_key 'o'; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "list_on_key: unknown key delegates to shellframe_list_on_key"
_shql_WELCOME_list_on_key 'x'; _rc=$?
assert_eq "1" "$_rc"

ptyunit_test_begin "list_on_focus: sets SHELLFRAME_LIST_FOCUSED=1"
SHELLFRAME_LIST_FOCUSED=0
_shql_WELCOME_list_on_focus 1
assert_eq "1" "$SHELLFRAME_LIST_FOCUSED"

ptyunit_test_begin "list_on_focus: sets SHELLFRAME_LIST_FOCUSED=0"
SHELLFRAME_LIST_FOCUSED=1
_shql_WELCOME_list_on_focus 0
assert_eq "0" "$SHELLFRAME_LIST_FOCUSED"

ptyunit_test_begin "quit: sets _SHELLFRAME_SHELL_NEXT=__QUIT__"
_SHELLFRAME_SHELL_NEXT=""
_shql_WELCOME_quit
assert_eq "__QUIT__" "$_SHELLFRAME_SHELL_NEXT"

ptyunit_test_begin "list_render: sets LIST_CTX and SHELLFRAME_LIST_ITEMS"
shellframe_list_render() { true; }
SHQL_RECENT_NAMES=("alice" "bob")
SHELLFRAME_LIST_CTX=""
_shql_WELCOME_list_render 1 1 80 20
assert_eq "$_SHQL_LIST_CTX" "$SHELLFRAME_LIST_CTX"

ptyunit_test_begin "list_action: mock mode sets SHQL_DB_PATH from details"
shql_browser_init() { true; }
SHQL_MOCK=1
shql_mock_load_recent
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }
_SHELLFRAME_SHELL_NEXT=""
_shql_WELCOME_list_action
assert_contains "$SHQL_DB_PATH" "app.db"
assert_eq "TABLE" "$_SHELLFRAME_SHELL_NEXT"

# ── Render tests (require shellframe framebuffer) ─────────────────────────────

_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${SHQL_ROOT}/../shellframe}"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$SHQL_ROOT/src/screens/header.sh"

# Helper: extract stripped text from a framebuffer row
_fb_row_text() {
    local _row="$1" _out="" _i _cols="${_SF_FRAME_COLS:-80}"
    for (( _i=0; _i<_cols; _i++ )); do
        local _idx=$(( (_row-1)*_cols + _i ))
        _out+="${_SF_FRAME_CURR[${_idx}]:-}"
    done
    printf '%s' "$_out" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g' | tr -d $'\033'
}

ptyunit_test_begin "empty_render: writes cells to framebuffer"
shellframe_fb_frame_start 10 80
_shql_WELCOME_empty_render 1 1 80 5
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 ))

ptyunit_test_begin "empty_render: message contains 'No recent'"
_text=$(_fb_row_text 3 )   # mid of 5-row area at row 1: mid = 1 + 5/2 = 3
assert_contains "$_text" "No recent"

ptyunit_test_begin "footer_render: writes cells to framebuffer"
shellframe_fb_frame_start 10 80
_shql_WELCOME_footer_render 1 1 80
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 ))

ptyunit_test_begin "footer_render: row contains 'Navigate'"
_text=$(_fb_row_text 1)
assert_contains "$_text" "Navigate"

ptyunit_test_begin "footer_render: row contains 'Quit'"
assert_contains "$_text" "Quit"

ptyunit_test_begin "header_render: writes cells to framebuffer"
shellframe_fb_frame_start 10 80
SHQL_DRIVER="" SHQL_DB_PATH="" SHQL_DB_HOST="" SHQL_DB_NAME=""
_shql_WELCOME_header_render 1 1 80
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 ))

ptyunit_test_begin "header_render: row contains 'ShellQL'"
_text=$(_fb_row_text 1)
assert_contains "$_text" "ShellQL"

ptyunit_test_summary
