#!/usr/bin/env bash
# tests/unit/test-theme.sh — Theme loader tests

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SHQL_ROOT="$_SHQL_ROOT"

source "$TESTS_DIR/ptyunit/assert.sh"
source "$_SHQL_ROOT/src/theme.sh"

ptyunit_test_begin "shql_theme_load basic: SHQL_THEME_PANEL_STYLE=single"
shql_theme_load basic
assert_eq "single" "$SHQL_THEME_PANEL_STYLE"

ptyunit_test_begin "shql_theme_load uranium: SHQL_THEME_PANEL_STYLE=rounded"
shql_theme_load uranium
assert_eq "rounded" "$SHQL_THEME_PANEL_STYLE"

ptyunit_test_begin "shql_theme_load nonexistent: falls back to basic"
shql_theme_load basic   # precondition: basic is loaded (sets SHQL_THEME_PANEL_STYLE=single)
shql_theme_load nonexistent 2>/dev/null
assert_eq "single" "$SHQL_THEME_PANEL_STYLE"

ptyunit_test_summary
