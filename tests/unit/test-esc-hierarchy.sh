#!/usr/bin/env bash
_SHQL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${_SHQL_ROOT}/../shellframe}"

source "$_SHQL_ROOT/src/screens/util.sh"
source "$_SHELLFRAME_DIR/src/clip.sh"
source "$_SHELLFRAME_DIR/src/draw.sh"
source "$_SHELLFRAME_DIR/src/selection.sh"
source "$_SHELLFRAME_DIR/src/scroll.sh"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$_SHELLFRAME_DIR/src/panel.sh"
source "$_SHELLFRAME_DIR/src/widgets/list.sh"
source "$_SHQL_ROOT/src/state.sh"
SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"
SHQL_ROOT="$_SHQL_ROOT"
source "$_SHQL_ROOT/src/theme.sh"
shql_theme_load basic

# Stub shell functions for unit testing
_LAST_FOCUS_SET=""
shellframe_shell_focus_set() { _LAST_FOCUS_SET="$1"; }
shellframe_shell_mark_dirty() { :; }

# Stub confirm dialog: always returns 1 (No) so tests don't block
shellframe_confirm() { return 1; }

# Stub grid key handler
shellframe_grid_on_key() { return 1; }

# Stub _shql_TABLE_quit so tests can detect if it was called
_SHQL_QUIT_CALLED=0
_shql_TABLE_quit() { _SHQL_QUIT_CALLED=1; }

source "$_SHQL_ROOT/src/screens/inspector.sh"
source "$_SHQL_ROOT/src/screens/table.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── Setup helpers ─────────────────────────────────────────────────────────────

_setup_sidebar() {
    _LAST_FOCUS_SET=""
    _SHQL_QUIT_CALLED=0
    _SHQL_BROWSER_SIDEBAR_CTX="sidebar_test"
    shellframe_sel_init "$_SHQL_BROWSER_SIDEBAR_CTX" 1
    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    _SHQL_BROWSER_SIDEBAR_ITEMS=("users")
    _SHQL_BROWSER_TABLES=("users")
}

_setup_tabbar() {
    _LAST_FOCUS_SET=""
    _SHQL_QUIT_CALLED=0
    _SHQL_BROWSER_TABBAR_ON_SQL=0
    _SHQL_TAB_ACTIVE=0
    _SHQL_TABS_TYPE=("data")
    _SHQL_TABS_CTX=("t_test")
    _SHQL_TABS_LABEL=("users")
    _SHQL_TABS_TABLE=("users")
}

_setup_content_data() {
    _LAST_FOCUS_SET=""
    _SHQL_QUIT_CALLED=0
    _SHQL_TAB_ACTIVE=0
    _SHQL_TABS_TYPE=("data")
    _SHQL_TABS_CTX=("t_test")
    _SHQL_TABS_LABEL=("users")
    _SHQL_TABS_TABLE=("users")
    _SHQL_INSPECTOR_ACTIVE=0
    _SHQL_DML_ACTIVE=0
    SHELLFRAME_GRID_CTX="t_test_grid"
    SHELLFRAME_GRID_ROWS=2
}

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "sidebar Esc: handled (returns 0, no quit)"
_setup_sidebar
_shql_TABLE_sidebar_on_key $'\033'
_rc=$?
assert_eq "0" "$_rc" "sidebar Esc: returns 0 (handled)"
assert_eq "0" "$_SHQL_QUIT_CALLED" "sidebar Esc: _shql_TABLE_quit not called directly"

ptyunit_test_begin "sidebar q: handled (returns 0, no quit)"
_setup_sidebar
_shql_TABLE_sidebar_on_key 'q'
_rc=$?
assert_eq "0" "$_rc" "sidebar q: returns 0 (handled)"
assert_eq "0" "$_SHQL_QUIT_CALLED" "sidebar q: _shql_TABLE_quit not called directly"

ptyunit_test_begin "tabbar Esc: moves focus to sidebar"
_setup_tabbar
_shql_TABLE_tabbar_on_key $'\033'
assert_eq "sidebar" "$_LAST_FOCUS_SET" "tabbar Esc: focuses sidebar"

ptyunit_test_begin "content data q: moves focus to tabbar (not quit)"
_setup_content_data
_shql_TABLE_content_on_key 'q'
assert_eq "tabbar" "$_LAST_FOCUS_SET" "content q: focuses tabbar"
assert_eq "0" "$_SHQL_QUIT_CALLED" "content q: does not call quit"

ptyunit_test_summary
