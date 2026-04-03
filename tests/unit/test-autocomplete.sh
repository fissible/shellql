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

_setup_cache() {
    SHQL_DB_PATH="/mock/test.db"
    _shql_ac_rebuild
}

# ── rebuild ───────────────────────────────────────────────────────────────────

describe "rebuild"

test_that "no-op when SHQL_DB_PATH is empty"
SHQL_DB_PATH=""
_shql_ac_rebuild
assert_eq "0" "${#_SHQL_AC_TABLES[@]}"

test_that "populates tables from mock"
_setup_cache
assert_gt "${#_SHQL_AC_TABLES[@]}" 0

test_that "users table is present in cache"
_found=0
for _t in "${_SHQL_AC_TABLES[@]}"; do [[ "$_t" == "users" ]] && _found=1; done
assert_eq "1" "$_found"

test_that "populates columns cache"
assert_gt "${#_SHQL_AC_COLS[@]}" 0

test_that "users.id is present in column cache"
_found=0
for _e in "${_SHQL_AC_COLS[@]}"; do [[ "$_e" == "users"$'\t'"id" ]] && _found=1; done
assert_eq "1" "$_found"

end_describe

# ── provider — table context ──────────────────────────────────────────────────

describe "provider"

describe "table context" _setup_cache

test_that "matches table name by prefix"
_TEST_ED_ROW=0
_TEST_ED_LINE="SELECT * FROM us"
_TEST_ED_COL=16
_SHELLFRAME_AC_CTX="test_ed"
_shql_ac_provider "us" "_test_out"
assert_gt "${#_test_out[@]}" 0

test_that "prefix 'us' includes 'users'"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "users" ]] && _found=1; done
assert_eq "1" "$_found"

test_that "match is case-insensitive"
_TEST_ED_LINE="SELECT * FROM US"
_TEST_ED_COL=16
_shql_ac_provider "US" "_test_out"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "users" ]] && _found=1; done
assert_eq "1" "$_found"

test_that "non-existent prefix returns empty"
_shql_ac_provider "zzz" "_test_out"
assert_eq "0" "${#_test_out[@]}"

end_describe

describe "prefix length guard"

test_that "empty prefix returns nothing"
_shql_ac_provider "" "_test_out"
assert_eq "0" "${#_test_out[@]}"

test_that "single-char prefix returns nothing (2-char minimum)"
_shql_ac_provider "u" "_test_out"
assert_eq "0" "${#_test_out[@]}"

end_describe

describe "keyword context"

test_that "'SE' in empty context suggests SELECT"
_SHELLFRAME_AC_CTX=""
_TEST_ED_LINE=""
_TEST_ED_COL=0
_shql_ac_provider "SE" "_test_out"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "SELECT" ]] && _found=1; done
assert_eq "1" "$_found"

test_that "'SE' in keyword context does not suggest table names"
_found_schema=0
for _m in "${_test_out[@]}"; do
    [[ "$_m" == "users" || "$_m" == "products" ]] && _found_schema=1
done
assert_eq "0" "$_found_schema"

end_describe

describe "column context" _setup_cache

test_that "column prefix match after SELECT keyword"
_TEST_ED_LINE="SELECT id"
_TEST_ED_COL=9
_SHELLFRAME_AC_CTX="test_ed"
_shql_ac_provider "id" "_test_out"
assert_gt "${#_test_out[@]}" 0

test_that "'id' appears in SELECT context results"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "id" ]] && _found=1; done
assert_eq "1" "$_found"

test_that "column results are deduplicated"
_TEST_ED_LINE="SELECT id"
_TEST_ED_COL=9
_shql_ac_provider "id" "_test_out"
_count=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "id" ]] && (( _count++ )); done
assert_eq "1" "$_count"

end_describe

describe "dot-notation scoped columns" _setup_cache

test_that "'users.id' returns matches"
_SHELLFRAME_AC_CTX=""
_shql_ac_provider "users.id" "_test_out"
assert_gt "${#_test_out[@]}" 0

test_that "'users.id' results contain fully-qualified name"
_found=0
for _m in "${_test_out[@]}"; do [[ "$_m" == "users.id" ]] && _found=1; done
assert_eq "1" "$_found"

test_that "dot results are scoped to the named table only"
_shql_ac_provider "users.id" "_test_out"
_other=0
for _m in "${_test_out[@]}"; do
    [[ "$_m" != "users."* ]] && _other=1
done
assert_eq "0" "$_other"

test_that "'users.' (no column prefix) returns all user columns"
_shql_ac_provider "users." "_test_out"
assert_gt "${#_test_out[@]}" 0

end_describe

end_describe  # provider

# ── sql_context ───────────────────────────────────────────────────────────────

describe "sql_context"

describe "keyword-triggered table context"

_check_tables_ctx() {
    local _line="$1"
    _TEST_ED_LINE="$_line"
    _TEST_ED_COL=${#_line}
    _SHELLFRAME_AC_CTX="test_ed"
    _shql_ac_sql_context ""
    assert_eq "tables" "$_SHQL_AC_SQL_CTX" "'$_line' → tables"
}

test_each _check_tables_ctx << 'PARAMS'
SELECT * FROM
SELECT * FROM users JOIN
INSERT INTO
UPDATE users SET id=1 WHERE id IN (SELECT id FROM
PARAMS

end_describe

describe "keyword-triggered column context"

_check_cols_ctx() {
    local _line="$1"
    _TEST_ED_LINE="$_line"
    _TEST_ED_COL=${#_line}
    _SHELLFRAME_AC_CTX="test_ed"
    _shql_ac_sql_context ""
    assert_eq "cols" "$_SHQL_AC_SQL_CTX" "'$_line' → cols"
}

test_each _check_cols_ctx << 'PARAMS'
SELECT
SELECT id FROM users WHERE
SELECT id,
SELECT id FROM users ORDER BY
PARAMS

end_describe

test_that "dot prefix → cols_dot context with table set"
_shql_ac_sql_context "users.na"
assert_eq "cols_dot" "$_SHQL_AC_SQL_CTX"
assert_eq "users"    "$_SHQL_AC_COL_TABLE"

test_that "empty editor context → keywords"
_TEST_ED_LINE=""
_TEST_ED_COL=0
_shql_ac_sql_context "na"
assert_eq "keywords" "$_SHQL_AC_SQL_CTX"

end_describe

ptyunit_test_summary
