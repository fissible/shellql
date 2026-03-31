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
source "$_SHELLFRAME_DIR/src/cursor.sh"
source "$_SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$_SHELLFRAME_DIR/src/widgets/form.sh"
source "$_SHELLFRAME_DIR/src/widgets/toast.sh"
source "$_SHQL_ROOT/src/state.sh"
SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"
SHQL_ROOT="$_SHQL_ROOT"
source "$_SHQL_ROOT/src/theme.sh"
shql_theme_load basic
source "$_SHQL_ROOT/src/screens/dml.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── SQL builder tests ─────────────────────────────────────────────────────────

ptyunit_test_begin "dml_build_insert: basic 3-column INSERT skips PK"
_col_defs=("id	INTEGER	PK" "name	TEXT	NN" "email	TEXT	")
_vals=("" "Alice" "alice@example.com")
_shql_dml_build_insert "users" _col_defs _vals _sql
assert_contains "$_sql" "INSERT INTO" "insert: starts with INSERT INTO"
assert_contains "$_sql" '"users"' "insert: table name quoted"
assert_contains "$_sql" '"name"' "insert: name column present"
assert_contains "$_sql" '"email"' "insert: email column present"
assert_contains "$_sql" "'Alice'" "insert: name value single-quoted"
_has_id=0; [[ "$_sql" == *'"id"'* ]] && _has_id=1
assert_eq "0" "$_has_id" "insert: PK column (id) not in INSERT"

ptyunit_test_begin "dml_build_insert: empty nullable value → NULL"
_col_defs=("name	TEXT	NN" "email	TEXT	")
_vals=("Bob" "")
_shql_dml_build_insert "users" _col_defs _vals _sql
assert_contains "$_sql" "NULL" "insert: empty nullable → NULL"
assert_contains "$_sql" "'Bob'" "insert: non-empty value quoted"

ptyunit_test_begin "dml_build_insert: single-quote in value is escaped"
_col_defs=("name	TEXT	NN")
_vals=("O'Brien")
_shql_dml_build_insert "users" _col_defs _vals _sql
assert_contains "$_sql" "O''Brien" "insert: single quote doubled for SQLite"

ptyunit_test_begin "dml_build_update: UPDATE with PK WHERE clause"
_col_defs=("id	INTEGER	PK" "name	TEXT	NN" "email	TEXT	")
_vals=("1" "Alice Updated" "alice@example.com")
_shql_dml_build_update "users" _col_defs _vals _sql
assert_contains "$_sql" "UPDATE" "update: starts with UPDATE"
assert_contains "$_sql" '"users"' "update: table name"
assert_contains "$_sql" "WHERE" "update: has WHERE"
assert_contains "$_sql" '"id"' "update: WHERE uses PK column"
assert_contains "$_sql" "'1'" "update: PK value in WHERE"
assert_contains "$_sql" "'Alice Updated'" "update: new name value"

ptyunit_test_begin "dml_build_delete: DELETE with PK WHERE clause"
_col_defs=("id	INTEGER	PK" "name	TEXT	NN")
_vals=("42" "Bob")
_shql_dml_build_delete "users" _col_defs _vals _sql
assert_contains "$_sql" "DELETE FROM" "delete: starts with DELETE FROM"
assert_contains "$_sql" '"users"' "delete: table name"
assert_contains "$_sql" "WHERE" "delete: has WHERE"
assert_contains "$_sql" '"id"' "delete: uses PK"
assert_contains "$_sql" "'42'" "delete: PK value"

ptyunit_test_begin "dml_validate: no error when all NN fields filled"
_col_defs=("id	INTEGER	PK" "name	TEXT	NN" "email	TEXT	")
_vals=("" "Alice" "")
_shql_dml_validate _col_defs _vals _err
assert_eq "" "$_err" "validate: no error when NN fields filled"

ptyunit_test_begin "dml_validate: error when NN field is empty"
_col_defs=("id	INTEGER	PK" "name	TEXT	NN" "email	TEXT	")
_vals=("" "" "alice@example.com")
_shql_dml_validate _col_defs _vals _err
assert_contains "$_err" "name" "validate: error mentions the NN field name"

ptyunit_test_begin "dml_validate: PK skipped in validation"
_col_defs=("id	INTEGER	PK")
_vals=("")
_shql_dml_validate _col_defs _vals _err
assert_eq "" "$_err" "validate: PK-only table passes validation"

ptyunit_test_begin "dml_truncate_open: sets mode and active flag"
_SHQL_DML_ACTIVE=0
_SHQL_DML_TABLE=""
_shql_dml_truncate_open "orders"
assert_eq "1" "$_SHQL_DML_ACTIVE" "truncate_open: DML active"
assert_eq "truncate" "$_SHQL_DML_MODE" "truncate_open: mode is truncate"
assert_eq "orders" "$_SHQL_DML_TABLE" "truncate_open: table name set"

ptyunit_test_begin "dml_truncate_open: does not require rows"
_SHQL_DML_ACTIVE=0
_shql_dml_truncate_open "empty_table"
assert_eq "1" "$_SHQL_DML_ACTIVE" "truncate_open: active even when no rows"
assert_eq "empty_table" "$_SHQL_DML_TABLE" "truncate_open: table name preserved"

ptyunit_test_summary
