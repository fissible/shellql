#!/usr/bin/env bash
# tests/unit/test-sort.sh — Unit tests for sort state helpers

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# ── Minimal shellframe stubs ──────────────────────────────────────────────────

shellframe_scroll_left() { printf -v "$2" '%d' 0; }
shellframe_scroll_move() { true; }
shellframe_fb_fill()     { true; }
shellframe_fb_print()    { true; }

# ── Source sort module ────────────────────────────────────────────────────────

source "$SHQL_ROOT/src/screens/sort.sh"

# ── _shql_sort_count ─────────────────────────────────────────────────────────

ptyunit_test_begin "sort_count: returns 0 when ctx is empty"
_SHQL_SORT_t0=""
_shql_sort_count "t0"
assert_eq "0" "$_SHQL_SORT_RESULT_COUNT"

ptyunit_test_begin "sort_count: returns 1 for single entry"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_count "t0"
assert_eq "1" "$_SHQL_SORT_RESULT_COUNT"

ptyunit_test_begin "sort_count: returns 2 for two entries"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_count "t0"
assert_eq "2" "$_SHQL_SORT_RESULT_COUNT"

ptyunit_test_begin "sort_count: ignores empty lines"
_SHQL_SORT_t0=$'id\tASC\n\nname\tDESC'
_shql_sort_count "t0"
assert_eq "2" "$_SHQL_SORT_RESULT_COUNT"

# ── _shql_sort_get ────────────────────────────────────────────────────────────

ptyunit_test_begin "sort_get: gets entry at index 0"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_get "t0" 0
assert_eq "id" "$_SHQL_SORT_RESULT_COL"
assert_eq "ASC" "$_SHQL_SORT_RESULT_DIR"

ptyunit_test_begin "sort_get: gets entry at index 1"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_get "t0" 1
assert_eq "name" "$_SHQL_SORT_RESULT_COL"
assert_eq "DESC" "$_SHQL_SORT_RESULT_DIR"

ptyunit_test_begin "sort_get: returns 1 for out-of-range index"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_get "t0" 5
_rc=$?
assert_eq "1" "$_rc"

ptyunit_test_begin "sort_get: clears output on miss"
_SHQL_SORT_RESULT_COL="leftover"
_SHQL_SORT_t0=""
_shql_sort_get "t0" 0
assert_eq "" "$_SHQL_SORT_RESULT_COL"

# ── _shql_sort_find ───────────────────────────────────────────────────────────

ptyunit_test_begin "sort_find: returns -1 when ctx is empty"
_SHQL_SORT_t0=""
_shql_sort_find "t0" "id"
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

ptyunit_test_begin "sort_find: finds column at index 0"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_find "t0" "id"
assert_eq "0" "$_SHQL_SORT_RESULT_IDX"
assert_eq "ASC" "$_SHQL_SORT_RESULT_DIR"

ptyunit_test_begin "sort_find: finds column at index 1"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_find "t0" "name"
assert_eq "1" "$_SHQL_SORT_RESULT_IDX"
assert_eq "DESC" "$_SHQL_SORT_RESULT_DIR"

ptyunit_test_begin "sort_find: returns -1 for missing column"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_find "t0" "email"
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

# ── _shql_sort_toggle ─────────────────────────────────────────────────────────

ptyunit_test_begin "sort_toggle: absent column becomes ASC"
_SHQL_SORT_t0=""
_shql_sort_toggle "t0" "id"
assert_eq $'id\tASC' "$_SHQL_SORT_t0"

ptyunit_test_begin "sort_toggle: ASC column becomes DESC"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_toggle "t0" "id"
assert_eq $'id\tDESC' "$_SHQL_SORT_t0"

ptyunit_test_begin "sort_toggle: DESC column is removed"
_SHQL_SORT_t0=$'id\tDESC'
_shql_sort_toggle "t0" "id"
assert_eq "" "$_SHQL_SORT_t0"

ptyunit_test_begin "sort_toggle: new column appended at end (click order preserved)"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_toggle "t0" "name"
_shql_sort_get "t0" 0; assert_eq "id" "$_SHQL_SORT_RESULT_COL"
_shql_sort_get "t0" 1; assert_eq "name" "$_SHQL_SORT_RESULT_COL"

ptyunit_test_begin "sort_toggle: other columns preserved when one is removed"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC\nemail\tASC'
_shql_sort_toggle "t0" "name"  # DESC → remove
_shql_sort_count "t0"
assert_eq "2" "$_SHQL_SORT_RESULT_COUNT"
_shql_sort_get "t0" 0; assert_eq "id" "$_SHQL_SORT_RESULT_COL"
_shql_sort_get "t0" 1; assert_eq "email" "$_SHQL_SORT_RESULT_COL"

ptyunit_test_begin "sort_toggle: column positions preserved when middle goes ASC→DESC"
_SHQL_SORT_t0=$'id\tASC\nname\tASC\nemail\tASC'
_shql_sort_toggle "t0" "name"  # ASC → DESC
_shql_sort_get "t0" 1
assert_eq "name" "$_SHQL_SORT_RESULT_COL"
assert_eq "DESC" "$_SHQL_SORT_RESULT_DIR"

# ── _shql_sort_build_clause ───────────────────────────────────────────────────

ptyunit_test_begin "sort_build_clause: empty ctx yields empty clause"
_SHQL_SORT_t0=""
_shql_sort_build_clause "t0"
assert_eq "" "$_SHQL_SORT_RESULT_CLAUSE"

ptyunit_test_begin "sort_build_clause: single ASC entry"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_build_clause "t0"
assert_eq '"id" ASC' "$_SHQL_SORT_RESULT_CLAUSE"

ptyunit_test_begin "sort_build_clause: single DESC entry"
_SHQL_SORT_t0=$'name\tDESC'
_shql_sort_build_clause "t0"
assert_eq '"name" DESC' "$_SHQL_SORT_RESULT_CLAUSE"

ptyunit_test_begin "sort_build_clause: multiple entries comma-separated"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_build_clause "t0"
assert_eq '"id" ASC, "name" DESC' "$_SHQL_SORT_RESULT_CLAUSE"

ptyunit_test_begin "sort_build_clause: escapes double-quotes in column name"
_SHQL_SORT_t0=$'col"name\tASC'
_shql_sort_build_clause "t0"
assert_eq '"col""name" ASC' "$_SHQL_SORT_RESULT_CLAUSE"

# ── _shql_sort_clear ──────────────────────────────────────────────────────────

ptyunit_test_begin "sort_clear: clears all sort entries"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_clear "t0"
assert_eq "" "$_SHQL_SORT_t0"

ptyunit_test_begin "sort_clear: no-op on empty ctx"
_SHQL_SORT_t0=""
_shql_sort_clear "t0"
assert_eq "" "$_SHQL_SORT_t0"

# ── _shql_sort_col_at_x ───────────────────────────────────────────────────────

ptyunit_test_begin "sort_col_at_x: returns -1 when no columns"
SHELLFRAME_GRID_COLS=0
SHELLFRAME_GRID_COL_WIDTHS=()
_shql_sort_col_at_x "t0" 5 1 40
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

ptyunit_test_begin "sort_col_at_x: finds first column"
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
shellframe_scroll_left() { printf -v "$2" '%d' 0; }
# Region starts at col 1, width=30; screen x=5 should be in col 0 (cells at 1..10)
_shql_sort_col_at_x "t0" 5 1 30
assert_eq "0" "$_SHQL_SORT_RESULT_IDX"

ptyunit_test_begin "sort_col_at_x: finds second column"
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
# Region starts at col 1; col 0 = cols 1-10, separator at 11, col 1 = cols 12-21
_shql_sort_col_at_x "t0" 15 1 30
assert_eq "1" "$_SHQL_SORT_RESULT_IDX"

ptyunit_test_begin "sort_col_at_x: returns -1 outside all columns"
SHELLFRAME_GRID_COLS=2
SHELLFRAME_GRID_COL_WIDTHS=(10 10)
# Region starts at col 1, width=15; third col starts at 21 but width=15 clips it
# screen x=50 is past all columns
_shql_sort_col_at_x "t0" 50 1 15
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

ptyunit_test_begin "sort_col_at_x: respects scroll_left offset"
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
# scroll_left=1 means col 0 is off-screen; visible cols start at col 1
shellframe_scroll_left() { printf -v "$2" '%d' 1; }
# screen x=5 with rleft=1: first visible is col 1 at x=1..10
_shql_sort_col_at_x "t0" 5 1 30
assert_eq "1" "$_SHQL_SORT_RESULT_IDX"
shellframe_scroll_left() { printf -v "$2" '%d' 0; }

ptyunit_test_summary
