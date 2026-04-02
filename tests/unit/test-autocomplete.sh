#!/usr/bin/env bash
# shellql/tests/unit/test-autocomplete.sh — Autocomplete provider unit tests

_SHQL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${_SHQL_ROOT}/../shellframe}"

source "$_SHELLFRAME_DIR/shellframe.sh"
SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"
source "$_SHQL_ROOT/src/autocomplete.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Stub editor functions used by _shql_ac_sql_context
shellframe_editor_row()  { printf '%d' "${_TEST_ED_ROW:-0}"; }
shellframe_editor_col()  { printf '%d' "${_TEST_ED_COL:-0}"; }
shellframe_editor_line() { printf '%s' "${_TEST_ED_LINE:-}"; }

# Populate cache with mock schema
_setup_cache() {
    SHQL_DB_PATH="/mock/test.db"
    _shql_ac_rebuild
}

# ── Test: _shql_ac_rebuild ────────────────────────────────────────────────────

ptyunit_test_begin "ac_rebuild: no-op when SHQL_DB_PATH is empty"
SHQL_DB_PATH=""
_shql_ac_rebuild
assert_eq "0" "${#_SHQL_AC_TABLES[@]}" "rebuild: tables empty when no path"

ptyunit_test_begin "ac_rebuild: populates tables from mock"
_setup_cache
assert_eq 1 $(( ${#_SHQL_AC_TABLES[@]} > 0 )) "rebuild: tables populated"

ptyunit_test_begin "ac_rebuild: users table present"
_found=0
for _t in "${_SHQL_AC_TABLES[@]}"; do [[ "$_t" == "users" ]] && _found=1; done
assert_eq "1" "$_found" "rebuild: users table in cache"

ptyunit_test_begin "ac_rebuild: populates columns"
assert_eq 1 $(( ${#_SHQL_AC_COLS[@]} > 0 )) "rebuild: columns populated"

ptyunit_test_begin "ac_rebuild: columns contain users<TAB>id"
_found=0
for _e in "${_SHQL_AC_COLS[@]}"; do [[ "$_e" == "users"$'\t'"id" ]] && _found=1; done
assert_eq "1" "$_found" "rebuild: users.id in column cache"

# ── Test: _shql_ac_provider — table prefix matching ──────────────────────────

ptyunit_test_begin "provider: matches table name by prefix"
_setup_cache
_TEST_ED_ROW=0
_TEST_ED_LINE="SELECT * FROM us"
_TEST_ED_COL=16
_SHELLFRAME_AC_CTX="test_ed"
_shql_ac_provider "us" "_test_out"
assert_eq 1 $(( ${#_test_out[@]} > 0 )) "provider: 'us' returns matches"

_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "users" ]] && _found=1; done
assert_eq "1" "$_found" "provider: 'us' includes 'users'"

ptyunit_test_begin "provider: case-insensitive match"
_TEST_ED_LINE="SELECT * FROM US"
_TEST_ED_COL=16
_shql_ac_provider "US" "_test_out"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "users" ]] && _found=1; done
assert_eq "1" "$_found" "provider: 'US' matches 'users'"

ptyunit_test_begin "provider: no match for non-existent prefix"
_shql_ac_provider "zzz" "_test_out"
assert_eq "0" "${#_test_out[@]}" "provider: 'zzz' returns empty"

ptyunit_test_begin "provider: empty prefix returns nothing"
_shql_ac_provider "" "_test_out"
assert_eq "0" "${#_test_out[@]}" "provider: empty prefix returns nothing"

ptyunit_test_begin "provider: single-char prefix returns nothing (2-char minimum)"
_shql_ac_provider "u" "_test_out"
assert_eq "0" "${#_test_out[@]}" "provider: 1-char prefix suppressed"

# ── Test: _shql_ac_provider — keyword suggestions ────────────────────────────

ptyunit_test_begin "provider: 'SE' → keywords context → SELECT suggested"
_SHELLFRAME_AC_CTX=""
_TEST_ED_LINE=""
_TEST_ED_COL=0
_shql_ac_provider "SE" "_test_out"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "SELECT" ]] && _found=1; done
assert_eq "1" "$_found" "provider: 'SE' suggests SELECT"

ptyunit_test_begin "provider: 'SE' → keywords context → no schema names"
_found_schema=0
for _m in "${_test_out[@]}"; do
    [[ "$_m" == "users" || "$_m" == "products" ]] && _found_schema=1
done
assert_eq "0" "$_found_schema" "provider: 'SE' does not suggest table names"

# ── Test: _shql_ac_provider — column matching (established context) ────────────

ptyunit_test_begin "provider: column prefix match after SELECT keyword"
_TEST_ED_LINE="SELECT id"
_TEST_ED_COL=9
_SHELLFRAME_AC_CTX="test_ed"
_shql_ac_provider "id" "_test_out"
assert_eq 1 $(( ${#_test_out[@]} > 0 )) "provider: 'id' after SELECT returns matches"

ptyunit_test_begin "provider: column 'id' present in SELECT context results"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "id" ]] && _found=1; done
assert_eq "1" "$_found" "provider: 'id' in SELECT results"

ptyunit_test_begin "provider: column results are deduplicated"
_TEST_ED_LINE="SELECT id"
_TEST_ED_COL=9
_shql_ac_provider "id" "_test_out"
_count=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "id" ]] && (( _count++ )); done
assert_eq "1" "$_count" "provider: 'id' not duplicated"

# ── Test: _shql_ac_provider — dot-notation scoped columns ────────────────────

ptyunit_test_begin "provider: dot prefix returns scoped columns"
_SHELLFRAME_AC_CTX=""
_shql_ac_provider "users.id" "_test_out"
assert_eq 1 $(( ${#_test_out[@]} > 0 )) "provider: 'users.id' returns matches"

ptyunit_test_begin "provider: dot prefix returns qualified names"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "users.id" ]] && _found=1; done
assert_eq "1" "$_found" "provider: 'users.id' in results as qualified name"

ptyunit_test_begin "provider: dot prefix scoped — no columns from other tables"
_shql_ac_provider "users.id" "_test_out"
_other=0
for _m in "${_test_out[@]}"; do
    [[ "$_m" != "users."* ]] && _other=1
done
assert_eq "0" "$_other" "provider: dot results are table-scoped"

ptyunit_test_begin "provider: dot prefix empty column prefix returns all columns for table"
_shql_ac_provider "users." "_test_out"
assert_eq 1 $(( ${#_test_out[@]} > 0 )) "provider: 'users.' returns all user columns"

# ── Test: _shql_ac_sql_context — keyword context detection ───────────────────

ptyunit_test_begin "sql_context: FROM keyword → tables context"
_SHELLFRAME_AC_CTX="test_ed"
_TEST_ED_ROW=0
_TEST_ED_LINE="SELECT * FROM "
_TEST_ED_COL=${#_TEST_ED_LINE}
_shql_ac_sql_context "";
assert_eq "tables" "$_SHQL_AC_SQL_CTX" "sql_context: FROM → tables"

ptyunit_test_begin "sql_context: JOIN keyword → tables context"
_TEST_ED_LINE="SELECT * FROM users JOIN "
_TEST_ED_COL=${#_TEST_ED_LINE}
_shql_ac_sql_context ""
assert_eq "tables" "$_SHQL_AC_SQL_CTX" "sql_context: JOIN → tables"

ptyunit_test_begin "sql_context: SELECT keyword → cols context"
_TEST_ED_LINE="SELECT "
_TEST_ED_COL=${#_TEST_ED_LINE}
_shql_ac_sql_context ""
assert_eq "cols" "$_SHQL_AC_SQL_CTX" "sql_context: SELECT → cols"

ptyunit_test_begin "sql_context: WHERE keyword → cols context"
_TEST_ED_LINE="SELECT id FROM users WHERE "
_TEST_ED_COL=${#_TEST_ED_LINE}
_shql_ac_sql_context ""
assert_eq "cols" "$_SHQL_AC_SQL_CTX" "sql_context: WHERE → cols"

ptyunit_test_begin "sql_context: dot prefix → cols_dot + sets COL_TABLE"
_shql_ac_sql_context "users.na"
assert_eq "cols_dot" "$_SHQL_AC_SQL_CTX"   "sql_context: dot → cols_dot"
assert_eq "users"    "$_SHQL_AC_COL_TABLE" "sql_context: dot → COL_TABLE=users"

ptyunit_test_begin "sql_context: no keyword context → keywords"
_TEST_ED_LINE=""
_TEST_ED_COL=0
_shql_ac_sql_context "na"
assert_eq "keywords" "$_SHQL_AC_SQL_CTX" "sql_context: no keyword → keywords"

ptyunit_test_summary
