#!/usr/bin/env bash
# shellql/tests/unit/test-where.sh — WHERE builder / filter helpers unit tests

_SHQL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${_SHQL_ROOT}/../shellframe}"

source "$_SHELLFRAME_DIR/src/clip.sh"
source "$_SHELLFRAME_DIR/src/draw.sh"
source "$_SHELLFRAME_DIR/src/selection.sh"
source "$_SHELLFRAME_DIR/src/scroll.sh"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$_SHELLFRAME_DIR/src/cursor.sh"
source "$_SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$_SHQL_ROOT/src/state.sh"
source "$_SHQL_ROOT/src/screens/where.sh"

source "$PTYUNIT_HOME/assert.sh"

# ── build_clause ──────────────────────────────────────────────────────────────

describe "build_clause"

_check_build_clause() {
    local _col="$1" _op="$2" _val="$3" _expected="$4"
    local _out=""
    _shql_where_build_clause "$_col" "$_op" "$_val" _out
    assert_eq "$_expected" "$_out"
}

test_each _check_build_clause << 'PARAMS'
name|=|Alice|"name" = 'Alice'
status|<>|inactive|"status" <> 'inactive'
age|>|18|"age" > '18'
email|LIKE|%@example.com|"email" LIKE '%@example.com'
email|NOT LIKE|%@spam.com|"email" NOT LIKE '%@spam.com'
filename|GLOB|*.sh|"filename" GLOB '*.sh'
PARAMS

test_that "IS NULL omits value"
_out=""
_shql_where_build_clause "deleted_at" "IS NULL" "" _out
assert_eq '"deleted_at" IS NULL' "$_out"

test_that "IS NOT NULL ignores value"
_out=""
_shql_where_build_clause "deleted_at" "IS NOT NULL" "ignored" _out
assert_eq '"deleted_at" IS NOT NULL' "$_out"

test_that "IN quotes each comma-separated value"
_out=""
_shql_where_build_clause "status" "IN" "active, pending, closed" _out
assert_eq '"status" IN ('"'"'active'"'"', '"'"'pending'"'"', '"'"'closed'"'"')' "$_out"

test_that "NOT IN quotes each value"
_out=""
_shql_where_build_clause "id" "NOT IN" "1,2,3" _out
assert_eq '"id" NOT IN ('"'"'1'"'"', '"'"'2'"'"', '"'"'3'"'"')' "$_out"

test_that "BETWEEN quotes both tab-separated values"
_out=""
_shql_where_build_clause "age" "BETWEEN" $'18\t65' _out
assert_eq '"age" BETWEEN '"'"'18'"'"' AND '"'"'65'"'"'' "$_out"

test_that "NOT BETWEEN quotes both tab-separated values"
_out=""
_shql_where_build_clause "score" "NOT BETWEEN" $'0\t50' _out
assert_eq '"score" NOT BETWEEN '"'"'0'"'"' AND '"'"'50'"'"'' "$_out"

test_that "single quotes in value are escaped"
_out=""
_shql_where_build_clause "note" "=" "O'Brien" _out
assert_eq '"note" = '"'"'O'"'"''"'"'Brien'"'" "$_out"

test_that "double quotes in column name are escaped"
_out=""
_shql_where_build_clause 'my"col' "=" "val" _out
assert_eq '"my""col" = '"'"'val'"'" "$_out"

end_describe

# ── filter_count ──────────────────────────────────────────────────────────────

describe "filter_count"

test_that "returns 0 when applied var is empty"
_SHQL_WHERE_APPLIED_tc_count=""
_shql_where_filter_count "tc_count"
assert_eq "0" "$_SHQL_WHERE_RESULT_COUNT"

test_that "returns 1 for single entry"
_SHQL_WHERE_APPLIED_tc_count1=$'col\t=\tval'
_shql_where_filter_count "tc_count1"
assert_eq "1" "$_SHQL_WHERE_RESULT_COUNT"

test_that "returns 2 for two entries"
_SHQL_WHERE_APPLIED_tc_count2=$'col1\t=\tv1\ncol2\tLIKE\tv2'
_shql_where_filter_count "tc_count2"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT"

end_describe

# ── filter_get ────────────────────────────────────────────────────────────────

describe "filter_get"

test_that "retrieves first entry (index 0)"
_SHQL_WHERE_APPLIED_tc_get=$'name\t=\tAlice\nage\t>\t18'
_shql_where_filter_get "tc_get" 0
assert_eq "name"  "$_SHQL_WHERE_RESULT_COL"
assert_eq "="     "$_SHQL_WHERE_RESULT_OP"
assert_eq "Alice" "$_SHQL_WHERE_RESULT_VAL"

test_that "retrieves second entry (index 1)"
_shql_where_filter_get "tc_get" 1
assert_eq "age" "$_SHQL_WHERE_RESULT_COL"
assert_eq ">"   "$_SHQL_WHERE_RESULT_OP"
assert_eq "18"  "$_SHQL_WHERE_RESULT_VAL"

test_that "returns 1 for out-of-range index"
_shql_where_filter_get "tc_get" 5
_rc=$?
assert_eq "1" "$_rc"

end_describe

# ── filter_add / filter_set / filter_del ──────────────────────────────────────

describe "filter_add"

test_that "appends to empty applied var"
_SHQL_WHERE_APPLIED_tc_add=""
_shql_where_filter_add "tc_add" "col" "=" "val"
assert_eq $'col\t=\tval' "$_SHQL_WHERE_APPLIED_tc_add"

test_that "appends second entry correctly"
_shql_where_filter_add "tc_add" "col2" "LIKE" "%x%"
_shql_where_filter_count "tc_add"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT"
_shql_where_filter_get "tc_add" 1
assert_eq "col2" "$_SHQL_WHERE_RESULT_COL"
assert_eq "LIKE" "$_SHQL_WHERE_RESULT_OP"
assert_eq "%x%"  "$_SHQL_WHERE_RESULT_VAL"

end_describe

describe "filter_set"

test_that "updates existing entry at index 0"
_SHQL_WHERE_APPLIED_tc_set=$'a\t=\t1\nb\t>\t2'
_shql_where_filter_set "tc_set" 0 "a_new" "<>" "99"
_shql_where_filter_get "tc_set" 0
assert_eq "a_new" "$_SHQL_WHERE_RESULT_COL"
assert_eq "<>"    "$_SHQL_WHERE_RESULT_OP"
assert_eq "99"    "$_SHQL_WHERE_RESULT_VAL"

test_that "leaves other entries unchanged"
_shql_where_filter_get "tc_set" 1
assert_eq "b" "$_SHQL_WHERE_RESULT_COL"

end_describe

describe "filter_del"

test_that "removes entry and shifts remainder"
_SHQL_WHERE_APPLIED_tc_del=$'x\t=\t1\ny\t=\t2\nz\t=\t3'
_shql_where_filter_del "tc_del" 1
_shql_where_filter_count "tc_del"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT"
_shql_where_filter_get "tc_del" 0
assert_eq "x" "$_SHQL_WHERE_RESULT_COL"
_shql_where_filter_get "tc_del" 1
assert_eq "z" "$_SHQL_WHERE_RESULT_COL"

end_describe

# ── where_open ────────────────────────────────────────────────────────────────

describe "where_open"

test_that "sets active flag, table, and tab ctx"
_SHQL_WHERE_ACTIVE=0
_SHQL_WHERE_TABLE=""
_shql_where_open "users" "tab_ctx_1" -1
assert_eq "1"         "$_SHQL_WHERE_ACTIVE"
assert_eq "users"     "$_SHQL_WHERE_TABLE"
assert_eq "tab_ctx_1" "$_SHQL_WHERE_TAB_CTX"
assert_eq "-1"        "$_SHQL_WHERE_EDIT_IDX"

test_that "edit_idx=-1 resets operator index to 0"
_SHQL_WHERE_OP_IDX=5
_shql_where_open "orders" "tab_ctx_2" -1
assert_eq "0" "$_SHQL_WHERE_OP_IDX"

test_that "edit_idx>=0 pre-fills column, value, and operator"
_SHQL_WHERE_APPLIED_tab_ctx_3=$'status\tLIKE\t%active%'
_shql_where_open "orders" "tab_ctx_3" 0
_col=""; shellframe_cur_text "${_SHQL_WHERE_CTX}_col" _col
_val=""; shellframe_cur_text "${_SHQL_WHERE_CTX}_val" _val
assert_eq "status"   "$_col"
assert_eq "%active%" "$_val"
assert_eq "LIKE" "${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}"
assert_eq "0"    "$_SHQL_WHERE_EDIT_IDX"

end_describe

# ── where_apply ───────────────────────────────────────────────────────────────

describe "where_apply"

test_that "adds new filter when edit_idx=-1"
_SHQL_WHERE_APPLIED_tab_apply1=""
_SHQL_WHERE_TAB_CTX="tab_apply1"
_SHQL_WHERE_EDIT_IDX=-1
_SHQL_WHERE_OP_IDX=0
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" "age"
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "30"
_shql_where_apply
assert_eq "0" "$_SHQL_WHERE_ACTIVE"
assert_eq $'age\t=\t30' "$_SHQL_WHERE_APPLIED_tab_apply1"

test_that "updates existing filter when edit_idx=0"
_SHQL_WHERE_APPLIED_tab_apply2=$'old\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_apply2"
_SHQL_WHERE_EDIT_IDX=0
_SHQL_WHERE_OP_IDX=1
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" "status"
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "inactive"
_shql_where_apply
assert_eq $'status\t<>\tinactive' "$_SHQL_WHERE_APPLIED_tab_apply2"

test_that "empty column with edit_idx=-1 is a no-op"
_SHQL_WHERE_APPLIED_tab_apply3=$'kept\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_apply3"
_SHQL_WHERE_EDIT_IDX=-1
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" ""
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "whatever"
_shql_where_apply
assert_eq $'kept\t=\tval' "$_SHQL_WHERE_APPLIED_tab_apply3"

test_that "empty column with edit_idx>=0 deletes the filter"
_SHQL_WHERE_APPLIED_tab_apply4=$'remove_me\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_apply4"
_SHQL_WHERE_EDIT_IDX=0
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" ""
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "whatever"
_shql_where_apply
assert_eq "" "$_SHQL_WHERE_APPLIED_tab_apply4"

end_describe

# ── pill_label ────────────────────────────────────────────────────────────────

describe "pill_label"

test_that "returns empty string when no filter at idx"
_SHQL_WHERE_APPLIED_tab_pill=""
_shql_where_pill_label "tab_pill" 0 30
assert_eq "" "$_SHQL_WHERE_PILL_TEXT"

test_that "returns full expression for idx 0"
_SHQL_WHERE_APPLIED_tab_pill2=$'status\t=\tactive'
_shql_where_pill_label "tab_pill2" 0 40
assert_eq "status = active" "$_SHQL_WHERE_PILL_TEXT"

test_that "truncates long expressions to max_len"
_SHQL_WHERE_APPLIED_tab_pill3=$'very_long_column_name\tLIKE\t%pattern%'
_shql_where_pill_label "tab_pill3" 0 15
assert_eq 15 "${#_SHQL_WHERE_PILL_TEXT}"
assert_contains "$_SHQL_WHERE_PILL_TEXT" "..."

test_that "IS NULL omits value in pill text"
_SHQL_WHERE_APPLIED_tab_pill4=$'deleted_at\tIS NULL\t'
_shql_where_pill_label "tab_pill4" 0 40
assert_eq "deleted_at IS NULL" "$_SHQL_WHERE_PILL_TEXT"

test_that "returns second filter at idx 1"
_SHQL_WHERE_APPLIED_tab_pill5=$'a\t=\t1\nb\t>\t2'
_shql_where_pill_label "tab_pill5" 1 40
assert_eq "b > 2" "$_SHQL_WHERE_PILL_TEXT"

end_describe

# ── where_clear ───────────────────────────────────────────────────────────────

describe "where_clear"

test_that "clears all filters and deactivates overlay"
_SHQL_WHERE_APPLIED_tab_clear=$'col\t=\tval\ncol2\t>\t5'
_SHQL_WHERE_TAB_CTX="tab_clear"
_shql_where_clear
assert_eq "" "$_SHQL_WHERE_APPLIED_tab_clear"
assert_eq "0" "$_SHQL_WHERE_ACTIVE"

test_that "where_clear_one removes specific filter by index"
_SHQL_WHERE_APPLIED_tab_clearone=$'a\t=\t1\nb\t=\t2\nc\t=\t3'
_shql_where_clear_one "tab_clearone" 1
_shql_where_filter_count "tab_clearone"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT"
_shql_where_filter_get "tab_clearone" 1
assert_eq "c" "$_SHQL_WHERE_RESULT_COL"

end_describe

# ── operator list completeness ────────────────────────────────────────────────

describe "operators"

_check_operator_present() {
    assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "$1" "contains $1"
}

test_each _check_operator_present << 'PARAMS'
=
<>
LIKE
NOT LIKE
IS NULL
IS NOT NULL
GLOB
IN
NOT IN
BETWEEN
NOT BETWEEN
PARAMS

end_describe

ptyunit_test_summary
