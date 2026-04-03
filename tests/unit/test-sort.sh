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

source "$SHQL_ROOT/src/screens/sort.sh"

# ── sort_count ────────────────────────────────────────────────────────────────

describe "sort_count"

test_that "returns 0 when ctx is empty"
_SHQL_SORT_t0=""
_shql_sort_count "t0"
assert_eq "0" "$_SHQL_SORT_RESULT_COUNT"

test_that "returns 1 for single entry"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_count "t0"
assert_eq "1" "$_SHQL_SORT_RESULT_COUNT"

test_that "returns 2 for two entries"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_count "t0"
assert_eq "2" "$_SHQL_SORT_RESULT_COUNT"

test_that "ignores empty lines in count"
_SHQL_SORT_t0=$'id\tASC\n\nname\tDESC'
_shql_sort_count "t0"
assert_eq "2" "$_SHQL_SORT_RESULT_COUNT"

end_describe

# ── sort_get ──────────────────────────────────────────────────────────────────

describe "sort_get"

test_that "gets entry at index 0"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_get "t0" 0
assert_eq "id"  "$_SHQL_SORT_RESULT_COL"
assert_eq "ASC" "$_SHQL_SORT_RESULT_DIR"

test_that "gets entry at index 1"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_get "t0" 1
assert_eq "name" "$_SHQL_SORT_RESULT_COL"
assert_eq "DESC" "$_SHQL_SORT_RESULT_DIR"

test_that "returns 1 for out-of-range index"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_get "t0" 5
_rc=$?
assert_eq "1" "$_rc"

test_that "clears RESULT_COL on miss"
_SHQL_SORT_RESULT_COL="leftover"
_SHQL_SORT_t0=""
_shql_sort_get "t0" 0
assert_eq "" "$_SHQL_SORT_RESULT_COL"

end_describe

# ── sort_find ─────────────────────────────────────────────────────────────────

describe "sort_find"

test_that "returns -1 when ctx is empty"
_SHQL_SORT_t0=""
_shql_sort_find "t0" "id"
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

test_that "finds column at index 0"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_find "t0" "id"
assert_eq "0"   "$_SHQL_SORT_RESULT_IDX"
assert_eq "ASC" "$_SHQL_SORT_RESULT_DIR"

test_that "finds column at index 1"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_find "t0" "name"
assert_eq "1"    "$_SHQL_SORT_RESULT_IDX"
assert_eq "DESC" "$_SHQL_SORT_RESULT_DIR"

test_that "returns -1 for missing column"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_find "t0" "email"
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

end_describe

# ── sort_toggle ───────────────────────────────────────────────────────────────

describe "sort_toggle"

test_that "absent column becomes ASC"
_SHQL_SORT_t0=""
_shql_sort_toggle "t0" "id"
assert_eq $'id\tASC' "$_SHQL_SORT_t0"

test_that "ASC column becomes DESC"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_toggle "t0" "id"
assert_eq $'id\tDESC' "$_SHQL_SORT_t0"

test_that "DESC column is removed"
_SHQL_SORT_t0=$'id\tDESC'
_shql_sort_toggle "t0" "id"
assert_eq "" "$_SHQL_SORT_t0"

test_that "new column is appended at end preserving click order"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_toggle "t0" "name"
_shql_sort_get "t0" 0; assert_eq "id"   "$_SHQL_SORT_RESULT_COL"
_shql_sort_get "t0" 1; assert_eq "name" "$_SHQL_SORT_RESULT_COL"

test_that "other columns preserved when one is removed"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC\nemail\tASC'
_shql_sort_toggle "t0" "name"
_shql_sort_count "t0"
assert_eq "2" "$_SHQL_SORT_RESULT_COUNT"
_shql_sort_get "t0" 0; assert_eq "id"    "$_SHQL_SORT_RESULT_COL"
_shql_sort_get "t0" 1; assert_eq "email" "$_SHQL_SORT_RESULT_COL"

test_that "column positions preserved when middle goes ASC→DESC"
_SHQL_SORT_t0=$'id\tASC\nname\tASC\nemail\tASC'
_shql_sort_toggle "t0" "name"
_shql_sort_get "t0" 1
assert_eq "name" "$_SHQL_SORT_RESULT_COL"
assert_eq "DESC" "$_SHQL_SORT_RESULT_DIR"

end_describe

# ── sort_build_clause ─────────────────────────────────────────────────────────

describe "sort_build_clause"

test_that "empty ctx yields empty clause"
_SHQL_SORT_t0=""
_shql_sort_build_clause "t0"
assert_eq "" "$_SHQL_SORT_RESULT_CLAUSE"

test_that "single ASC entry"
_SHQL_SORT_t0=$'id\tASC'
_shql_sort_build_clause "t0"
assert_eq '"id" ASC' "$_SHQL_SORT_RESULT_CLAUSE"

test_that "single DESC entry"
_SHQL_SORT_t0=$'name\tDESC'
_shql_sort_build_clause "t0"
assert_eq '"name" DESC' "$_SHQL_SORT_RESULT_CLAUSE"

test_that "multiple entries are comma-separated"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_build_clause "t0"
assert_eq '"id" ASC, "name" DESC' "$_SHQL_SORT_RESULT_CLAUSE"

test_that "double quotes in column name are escaped"
_SHQL_SORT_t0=$'col"name\tASC'
_shql_sort_build_clause "t0"
assert_eq '"col""name" ASC' "$_SHQL_SORT_RESULT_CLAUSE"

end_describe

# ── sort_clear ────────────────────────────────────────────────────────────────

describe "sort_clear"

test_that "clears all sort entries"
_SHQL_SORT_t0=$'id\tASC\nname\tDESC'
_shql_sort_clear "t0"
assert_eq "" "$_SHQL_SORT_t0"

test_that "no-op on already-empty ctx"
_SHQL_SORT_t0=""
_shql_sort_clear "t0"
assert_eq "" "$_SHQL_SORT_t0"

end_describe

# ── sort_col_at_x ─────────────────────────────────────────────────────────────

describe "sort_col_at_x"

test_that "returns -1 when no columns"
SHELLFRAME_GRID_COLS=0
SHELLFRAME_GRID_COL_WIDTHS=()
_shql_sort_col_at_x "t0" 5 1 40
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

test_that "finds first column"
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
shellframe_scroll_left() { printf -v "$2" '%d' 0; }
_shql_sort_col_at_x "t0" 5 1 30
assert_eq "0" "$_SHQL_SORT_RESULT_IDX"

test_that "finds second column"
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
_shql_sort_col_at_x "t0" 15 1 30
assert_eq "1" "$_SHQL_SORT_RESULT_IDX"

test_that "returns -1 outside all columns"
SHELLFRAME_GRID_COLS=2
SHELLFRAME_GRID_COL_WIDTHS=(10 10)
_shql_sort_col_at_x "t0" 50 1 15
assert_eq "-1" "$_SHQL_SORT_RESULT_IDX"

test_that "respects scroll_left offset"
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
shellframe_scroll_left() { printf -v "$2" '%d' 1; }
_shql_sort_col_at_x "t0" 5 1 30
assert_eq "1" "$_SHQL_SORT_RESULT_IDX"
shellframe_scroll_left() { printf -v "$2" '%d' 0; }

end_describe

ptyunit_test_summary
