#!/usr/bin/env bash
# tests/unit/test-theme.sh — Theme loader tests

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SHQL_ROOT="$_SHQL_ROOT"

source "$PTYUNIT_HOME/assert.sh"
source "$_SHQL_ROOT/src/theme.sh"

ptyunit_test_begin "shql_theme_load basic: SHQL_THEME_PANEL_STYLE=single"
shql_theme_load basic
assert_eq "single" "$SHQL_THEME_PANEL_STYLE"

ptyunit_test_begin "shql_theme_load uranium: SHQL_THEME_PANEL_STYLE=rounded"
tput() { case "$1" in colors) printf '256' ;; *) command tput "$@" 2>/dev/null ;; esac }
shql_theme_load uranium
assert_eq "rounded" "$SHQL_THEME_PANEL_STYLE"
unset -f tput

ptyunit_test_begin "shql_theme_load nonexistent: falls back to basic"
shql_theme_load basic   # precondition: basic is loaded (sets SHQL_THEME_PANEL_STYLE=single)
shql_theme_load nonexistent 2>/dev/null
assert_eq "single" "$SHQL_THEME_PANEL_STYLE"

# ── Test: cascade theme with 256-color terminal ───────────────────────────────

# Stub tput to report 256 colors so the cascade theme activates fully
tput() {
    case "$1" in
        colors) printf '256' ;;
        *)      command tput "$@" 2>/dev/null ;;
    esac
}

ptyunit_test_begin "shql_theme_load cascade (256 colors): PANEL_STYLE=single"
SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE=''
shql_theme_load cascade
assert_eq "single" "$SHQL_THEME_PANEL_STYLE"

ptyunit_test_begin "shql_theme_load cascade (256 colors): PANEL_STYLE_FOCUSED=double"
assert_eq "double" "$SHQL_THEME_PANEL_STYLE_FOCUSED"

ptyunit_test_begin "shql_theme_load cascade (256 colors): HEADER_BG contains 256-color escape"
assert_contains "$SHQL_THEME_HEADER_BG" "48;5"

ptyunit_test_begin "shql_theme_load cascade (256 colors): CONTENT_BG is set"
assert_eq 1 $(( ${#SHQL_THEME_CONTENT_BG} > 0 ))

ptyunit_test_begin "shql_theme_load cascade (256 colors): SIDEBAR_BG is set"
assert_eq 1 $(( ${#SHQL_THEME_SIDEBAR_BG} > 0 ))

ptyunit_test_begin "shql_theme_load cascade (256 colors): CURSOR_BG is set"
assert_eq 1 $(( ${#SHQL_THEME_CURSOR_BG} > 0 ))

ptyunit_test_begin "shql_theme_load cascade (256 colors): TAB_INACTIVE_BG is set"
assert_eq 1 $(( ${#SHQL_THEME_TAB_INACTIVE_BG} > 0 ))

# ── Test: cascade theme fallback when < 256 colors ───────────────────────────

# Override tput to report only 8 colors — cascade must fall back to basic
tput() {
    case "$1" in
        colors) printf '8' ;;
        *)      command tput "$@" 2>/dev/null ;;
    esac
}

ptyunit_test_begin "shql_theme_load cascade (8 colors): falls back to basic HEADER_BG"
shql_theme_load cascade
# basic.sh sets HEADER_BG to bold+reverse (no 256-color codes)
[[ "$SHQL_THEME_HEADER_BG" != *"48;5"* ]]
assert_eq 0 $? "cascade fallback: HEADER_BG has no 256-color escape"

ptyunit_test_summary
