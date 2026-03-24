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

ptyunit_test_summary
