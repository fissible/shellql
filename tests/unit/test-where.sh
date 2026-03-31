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

ptyunit_test_begin "build_clause: escapes single quotes in value"
_out=""
_shql_where_build_clause "note" "=" "O'Brien" _out
assert_eq '"note" = '"'"'O'"'"''"'"'Brien'"'" "$_out" "build_clause: single quote escaping"

ptyunit_test_begin "build_clause: escapes double quotes in column name"
_out=""
_shql_where_build_clause 'my"col' "=" "val" _out
assert_eq '"my""col" = '"'"'val'"'" "$_out" "build_clause: double quote escaping in column"

# ── _shql_where_open ──────────────────────────────────────────────────────────

ptyunit_test_begin "where_open: sets active flag and table"
_SHQL_WHERE_ACTIVE=0
_SHQL_WHERE_TABLE=""
_shql_where_open "users" "tab_ctx_1"
assert_eq "1" "$_SHQL_WHERE_ACTIVE" "where_open: active"
assert_eq "users" "$_SHQL_WHERE_TABLE" "where_open: table name"
assert_eq "tab_ctx_1" "$_SHQL_WHERE_TAB_CTX" "where_open: tab ctx"

ptyunit_test_begin "where_open: resets to operator 0 when no applied filter"
_SHQL_WHERE_OP_IDX=5
_SHQL_WHERE_APPLIED_tab_ctx_2=""
_shql_where_open "orders" "tab_ctx_2"
assert_eq "0" "$_SHQL_WHERE_OP_IDX" "where_open: op idx reset when no filter"

ptyunit_test_begin "where_open: pre-fills from applied filter"
_SHQL_WHERE_APPLIED_tab_ctx_3=$'status\tLIKE\t%active%'
_shql_where_open "orders" "tab_ctx_3"
_col=""; shellframe_cur_text "${_SHQL_WHERE_CTX}_col" _col
_val=""; shellframe_cur_text "${_SHQL_WHERE_CTX}_val" _val
assert_eq "status" "$_col" "where_open: pre-fills column"
assert_eq "%active%" "$_val" "where_open: pre-fills value"
assert_eq "LIKE" "${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}" "where_open: pre-fills operator"

# ── _shql_where_clear ────────────────────────────────────────────────────────

ptyunit_test_begin "where_clear: clears applied filter var"
_SHQL_WHERE_APPLIED_tab_clear=$'col\t=\tval'
_SHQL_WHERE_TAB_CTX="tab_clear"
_shql_where_clear
assert_eq "" "$_SHQL_WHERE_APPLIED_tab_clear" "where_clear: applied var is empty"
assert_eq "0" "$_SHQL_WHERE_ACTIVE" "where_clear: deactivates overlay"

# ── operator list completeness ────────────────────────────────────────────────

ptyunit_test_begin "operators: list contains expected entries"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "=" "operators: contains ="
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "<>" "operators: contains <>"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "LIKE" "operators: contains LIKE"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "NOT LIKE" "operators: contains NOT LIKE"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "IS NULL" "operators: contains IS NULL"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "IS NOT NULL" "operators: contains IS NOT NULL"
assert_contains "${_SHQL_WHERE_OPERATORS[*]}" "GLOB" "operators: contains GLOB"

ptyunit_test_summary
