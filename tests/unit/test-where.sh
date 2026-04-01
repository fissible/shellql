#!/usr/bin/env bash
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

# ── _shql_where_build_clause ──────────────────────────────────────────────────

ptyunit_test_begin "build_clause: = operator quotes value"
_out=""
_shql_where_build_clause "name" "=" "Alice" _out
assert_eq '"name" = '"'"'Alice'"'" "$_out" "build_clause: = with string value"

ptyunit_test_begin "build_clause: <> operator"
_out=""
_shql_where_build_clause "status" "<>" "inactive" _out
assert_eq '"status" <> '"'"'inactive'"'" "$_out" "build_clause: <> operator"

ptyunit_test_begin "build_clause: > operator"
_out=""
_shql_where_build_clause "age" ">" "18" _out
assert_eq '"age" > '"'"'18'"'" "$_out" "build_clause: > operator"

ptyunit_test_begin "build_clause: LIKE operator"
_out=""
_shql_where_build_clause "email" "LIKE" "%@example.com" _out
assert_eq '"email" LIKE '"'"'%@example.com'"'" "$_out" "build_clause: LIKE"

ptyunit_test_begin "build_clause: NOT LIKE operator"
_out=""
_shql_where_build_clause "email" "NOT LIKE" "%@spam.com" _out
assert_eq '"email" NOT LIKE '"'"'%@spam.com'"'" "$_out" "build_clause: NOT LIKE"

ptyunit_test_begin "build_clause: GLOB operator"
_out=""
_shql_where_build_clause "filename" "GLOB" "*.sh" _out
assert_eq '"filename" GLOB '"'"'*.sh'"'" "$_out" "build_clause: GLOB"

ptyunit_test_begin "build_clause: IS NULL omits value"
_out=""
_shql_where_build_clause "deleted_at" "IS NULL" "" _out
assert_eq '"deleted_at" IS NULL' "$_out" "build_clause: IS NULL"

ptyunit_test_begin "build_clause: IS NOT NULL omits value"
_out=""
_shql_where_build_clause "deleted_at" "IS NOT NULL" "ignored" _out
assert_eq '"deleted_at" IS NOT NULL' "$_out" "build_clause: IS NOT NULL ignores value"

ptyunit_test_begin "build_clause: IN quotes each comma-separated value"
_out=""
_shql_where_build_clause "status" "IN" "active, pending, closed" _out
assert_eq '"status" IN ('"'"'active'"'"', '"'"'pending'"'"', '"'"'closed'"'"')' "$_out" "build_clause: IN"

ptyunit_test_begin "build_clause: NOT IN"
_out=""
_shql_where_build_clause "id" "NOT IN" "1,2,3" _out
assert_eq '"id" NOT IN ('"'"'1'"'"', '"'"'2'"'"', '"'"'3'"'"')' "$_out" "build_clause: NOT IN"

ptyunit_test_begin "build_clause: BETWEEN quotes both values"
_out=""
_shql_where_build_clause "age" "BETWEEN" $'18\t65' _out
assert_eq '"age" BETWEEN '"'"'18'"'"' AND '"'"'65'"'"'' "$_out" "build_clause: BETWEEN"

ptyunit_test_begin "build_clause: NOT BETWEEN"
_out=""
_shql_where_build_clause "score" "NOT BETWEEN" $'0\t50' _out
assert_eq '"score" NOT BETWEEN '"'"'0'"'"' AND '"'"'50'"'"'' "$_out" "build_clause: NOT BETWEEN"

ptyunit_test_begin "build_clause: escapes single quotes in value"
_out=""
_shql_where_build_clause "note" "=" "O'Brien" _out
assert_eq '"note" = '"'"'O'"'"''"'"'Brien'"'" "$_out" "build_clause: single quote escaping"

ptyunit_test_begin "build_clause: escapes double quotes in column name"
_out=""
_shql_where_build_clause 'my"col' "=" "val" _out
assert_eq '"my""col" = '"'"'val'"'" "$_out" "build_clause: double quote escaping in column"

# ── _shql_where_filter_count / _shql_where_filter_get ─────────────────────────

ptyunit_test_begin "filter_count: empty applied var returns 0"
_SHQL_WHERE_APPLIED_tc_count=""
_shql_where_filter_count "tc_count"
assert_eq "0" "$_SHQL_WHERE_RESULT_COUNT" "filter_count: empty"

ptyunit_test_begin "filter_count: single entry returns 1"
_SHQL_WHERE_APPLIED_tc_count1=$'col\t=\tval'
_shql_where_filter_count "tc_count1"
assert_eq "1" "$_SHQL_WHERE_RESULT_COUNT" "filter_count: single"

ptyunit_test_begin "filter_count: two entries returns 2"
_SHQL_WHERE_APPLIED_tc_count2=$'col1\t=\tv1\ncol2\tLIKE\tv2'
_shql_where_filter_count "tc_count2"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT" "filter_count: two"

ptyunit_test_begin "filter_get: retrieves first entry"
_SHQL_WHERE_APPLIED_tc_get=$'name\t=\tAlice\nage\t>\t18'
_shql_where_filter_get "tc_get" 0
assert_eq "name"  "$_SHQL_WHERE_RESULT_COL" "filter_get: col[0]"
assert_eq "="     "$_SHQL_WHERE_RESULT_OP"  "filter_get: op[0]"
assert_eq "Alice" "$_SHQL_WHERE_RESULT_VAL" "filter_get: val[0]"

ptyunit_test_begin "filter_get: retrieves second entry"
_shql_where_filter_get "tc_get" 1
assert_eq "age" "$_SHQL_WHERE_RESULT_COL" "filter_get: col[1]"
assert_eq ">"   "$_SHQL_WHERE_RESULT_OP"  "filter_get: op[1]"
assert_eq "18"  "$_SHQL_WHERE_RESULT_VAL" "filter_get: val[1]"

ptyunit_test_begin "filter_get: out of range returns 1"
_shql_where_filter_get "tc_get" 5
_rc=$?
assert_eq "1" "$_rc" "filter_get: out-of-range rc"

# ── _shql_where_filter_add / _shql_where_filter_set / _shql_where_filter_del ──

ptyunit_test_begin "filter_add: appends to empty"
_SHQL_WHERE_APPLIED_tc_add=""
_shql_where_filter_add "tc_add" "col" "=" "val"
assert_eq $'col\t=\tval' "$_SHQL_WHERE_APPLIED_tc_add" "filter_add: first entry"

ptyunit_test_begin "filter_add: appends second entry"
_shql_where_filter_add "tc_add" "col2" "LIKE" "%x%"
_shql_where_filter_count "tc_add"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT" "filter_add: count after second add"
_shql_where_filter_get "tc_add" 1
assert_eq "col2" "$_SHQL_WHERE_RESULT_COL" "filter_add: second col"
assert_eq "LIKE" "$_SHQL_WHERE_RESULT_OP"  "filter_add: second op"
assert_eq "%x%"  "$_SHQL_WHERE_RESULT_VAL" "filter_add: second val"

ptyunit_test_begin "filter_set: updates existing entry"
_SHQL_WHERE_APPLIED_tc_set=$'a\t=\t1\nb\t>\t2'
_shql_where_filter_set "tc_set" 0 "a_new" "<>" "99"
_shql_where_filter_get "tc_set" 0
assert_eq "a_new" "$_SHQL_WHERE_RESULT_COL" "filter_set: updated col"
assert_eq "<>"    "$_SHQL_WHERE_RESULT_OP"  "filter_set: updated op"
assert_eq "99"    "$_SHQL_WHERE_RESULT_VAL" "filter_set: updated val"
_shql_where_filter_get "tc_set" 1
assert_eq "b" "$_SHQL_WHERE_RESULT_COL" "filter_set: other entry unchanged"

ptyunit_test_begin "filter_del: removes entry and shifts remainder"
_SHQL_WHERE_APPLIED_tc_del=$'x\t=\t1\ny\t=\t2\nz\t=\t3'
_shql_where_filter_del "tc_del" 1
_shql_where_filter_count "tc_del"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT" "filter_del: count after del"
_shql_where_filter_get "tc_del" 0
assert_eq "x" "$_SHQL_WHERE_RESULT_COL" "filter_del: first entry preserved"
_shql_where_filter_get "tc_del" 1
assert_eq "z" "$_SHQL_WHERE_RESULT_COL" "filter_del: second is former third"

# ── _shql_where_open ──────────────────────────────────────────────────────────

ptyunit_test_begin "where_open: sets active flag and table"
_SHQL_WHERE_ACTIVE=0
_SHQL_WHERE_TABLE=""
_shql_where_open "users" "tab_ctx_1" -1
assert_eq "1"      "$_SHQL_WHERE_ACTIVE"   "where_open: active"
assert_eq "users"  "$_SHQL_WHERE_TABLE"    "where_open: table name"
assert_eq "tab_ctx_1" "$_SHQL_WHERE_TAB_CTX" "where_open: tab ctx"
assert_eq "-1"     "$_SHQL_WHERE_EDIT_IDX" "where_open: edit_idx -1 for new"

ptyunit_test_begin "where_open: edit_idx=-1 resets to operator 0"
_SHQL_WHERE_OP_IDX=5
_shql_where_open "orders" "tab_ctx_2" -1
assert_eq "0" "$_SHQL_WHERE_OP_IDX" "where_open: op idx reset for new filter"

ptyunit_test_begin "where_open: edit_idx>=0 pre-fills from stored filter"
_SHQL_WHERE_APPLIED_tab_ctx_3=$'status\tLIKE\t%active%'
_shql_where_open "orders" "tab_ctx_3" 0
_col=""; shellframe_cur_text "${_SHQL_WHERE_CTX}_col" _col
_val=""; shellframe_cur_text "${_SHQL_WHERE_CTX}_val" _val
assert_eq "status"   "$_col" "where_open: pre-fills column"
assert_eq "%active%" "$_val" "where_open: pre-fills value"
assert_eq "LIKE" "${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}" "where_open: pre-fills operator"
assert_eq "0"    "$_SHQL_WHERE_EDIT_IDX" "where_open: edit_idx stored"

# ── _shql_where_apply ────────────────────────────────────────────────────────

ptyunit_test_begin "where_apply: adds new filter (edit_idx=-1)"
_SHQL_WHERE_APPLIED_tab_apply1=""
_SHQL_WHERE_TAB_CTX="tab_apply1"
_SHQL_WHERE_EDIT_IDX=-1
_SHQL_WHERE_OP_IDX=0   # "="
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" "age"
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "30"
_shql_where_apply
assert_eq "0" "$_SHQL_WHERE_ACTIVE" "where_apply: deactivates overlay"
assert_eq $'age\t=\t30' "$_SHQL_WHERE_APPLIED_tab_apply1" "where_apply: stored new filter"

ptyunit_test_begin "where_apply: updates existing filter (edit_idx=0)"
_SHQL_WHERE_APPLIED_tab_apply2=$'old\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_apply2"
_SHQL_WHERE_EDIT_IDX=0
_SHQL_WHERE_OP_IDX=1   # "<>"
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" "status"
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "inactive"
_shql_where_apply
assert_eq $'status\t<>\tinactive' "$_SHQL_WHERE_APPLIED_tab_apply2" "where_apply: updated filter"

ptyunit_test_begin "where_apply: empty column with edit_idx=-1 is a no-op"
_SHQL_WHERE_APPLIED_tab_apply3=$'kept\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_apply3"
_SHQL_WHERE_EDIT_IDX=-1
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" ""
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "whatever"
_shql_where_apply
# New filter with empty col → no-op; existing filter preserved
assert_eq $'kept\t=\tval' "$_SHQL_WHERE_APPLIED_tab_apply3" "where_apply: empty col new = no-op"

ptyunit_test_begin "where_apply: empty column with edit_idx>=0 deletes the filter"
_SHQL_WHERE_APPLIED_tab_apply4=$'remove_me\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_apply4"
_SHQL_WHERE_EDIT_IDX=0
shellframe_cur_init "${_SHQL_WHERE_CTX}_col" ""
shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "whatever"
_shql_where_apply
assert_eq "" "$_SHQL_WHERE_APPLIED_tab_apply4" "where_apply: empty col edit = delete"

# ── _shql_where_pill_label ────────────────────────────────────────────────────

ptyunit_test_begin "pill_label: empty when no filter at idx"
_SHQL_WHERE_APPLIED_tab_pill=""
_shql_where_pill_label "tab_pill" 0 30
assert_eq "" "$_SHQL_WHERE_PILL_TEXT" "pill_label: empty when no filter"

ptyunit_test_begin "pill_label: returns expression for idx 0"
_SHQL_WHERE_APPLIED_tab_pill2=$'status\t=\tactive'
_shql_where_pill_label "tab_pill2" 0 40
assert_eq "status = active" "$_SHQL_WHERE_PILL_TEXT" "pill_label: full expr"

ptyunit_test_begin "pill_label: truncates long expressions"
_SHQL_WHERE_APPLIED_tab_pill3=$'very_long_column_name\tLIKE\t%pattern%'
_shql_where_pill_label "tab_pill3" 0 15
assert_eq 15 "${#_SHQL_WHERE_PILL_TEXT}" "pill_label: truncated to max_len"
assert_contains "$_SHQL_WHERE_PILL_TEXT" "..." "pill_label: ends with ellipsis"

ptyunit_test_begin "pill_label: IS NULL omits value"
_SHQL_WHERE_APPLIED_tab_pill4=$'deleted_at\tIS NULL\t'
_shql_where_pill_label "tab_pill4" 0 40
assert_eq "deleted_at IS NULL" "$_SHQL_WHERE_PILL_TEXT" "pill_label: IS NULL has no value"

ptyunit_test_begin "pill_label: second filter at idx 1"
_SHQL_WHERE_APPLIED_tab_pill5=$'a\t=\t1\nb\t>\t2'
_shql_where_pill_label "tab_pill5" 1 40
assert_eq "b > 2" "$_SHQL_WHERE_PILL_TEXT" "pill_label: idx 1 returns second filter"

# ── _shql_where_clear / _shql_where_clear_one ─────────────────────────────────

ptyunit_test_begin "where_clear: clears all filters"
_SHQL_WHERE_APPLIED_tab_clear=$'col\t=\tval\ncol2\t>\t5'
_SHQL_WHERE_TAB_CTX="tab_clear"
_shql_where_clear
assert_eq "" "$_SHQL_WHERE_APPLIED_tab_clear" "where_clear: all filters cleared"
assert_eq "0" "$_SHQL_WHERE_ACTIVE" "where_clear: deactivates overlay"

ptyunit_test_begin "where_clear_one: removes specific filter"
_SHQL_WHERE_APPLIED_tab_clearone=$'a\t=\t1\nb\t=\t2\nc\t=\t3'
_shql_where_clear_one "tab_clearone" 1
_shql_where_filter_count "tab_clearone"
assert_eq "2" "$_SHQL_WHERE_RESULT_COUNT" "where_clear_one: count decremented"
_shql_where_filter_get "tab_clearone" 1
assert_eq "c" "$_SHQL_WHERE_RESULT_COL" "where_clear_one: correct entry removed"

# ── operator list completeness ────────────────────────────────────────────────

ptyunit_test_begin "operators: list contains expected entries"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "=" "operators: contains ="
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "<>" "operators: contains <>"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "LIKE" "operators: contains LIKE"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "NOT LIKE" "operators: contains NOT LIKE"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "IS NULL" "operators: contains IS NULL"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "IS NOT NULL" "operators: contains IS NOT NULL"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "GLOB" "operators: contains GLOB"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "IN" "operators: contains IN"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "NOT IN" "operators: contains NOT IN"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "BETWEEN" "operators: contains BETWEEN"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "NOT BETWEEN" "operators: contains NOT BETWEEN"

ptyunit_test_summary
