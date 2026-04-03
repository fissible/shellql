#!/usr/bin/env bash
# tests/unit/test-db-mock.sh — Unit tests for all db_mock.sh branches

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"

# ── mock_load_recent ──────────────────────────────────────────────────────────

describe "mock_load_recent"

test_that "populates SHQL_RECENT_FILES"
SHQL_RECENT_FILES=()
shql_mock_load_recent
assert_gt "${#SHQL_RECENT_FILES[@]}" 0

test_that "SHQL_RECENT_NAMES count matches files"
assert_eq "${#SHQL_RECENT_FILES[@]}" "${#SHQL_RECENT_NAMES[@]}"

test_that "source is always local"
assert_eq "local" "${SHQL_RECENT_SOURCES[0]}"

test_that "ref equals file path"
assert_eq "${SHQL_RECENT_FILES[0]}" "${SHQL_RECENT_REFS[0]}"

end_describe

# ── db_list_tables ─────────────────────────────────────────────────────────────

describe "db_list_tables"

test_that "returns 4 tables"
_out=$(shql_db_list_tables "")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

test_that "contains users"
assert_contains "$_out" "users"

end_describe

# ── db_list_objects ────────────────────────────────────────────────────────────

describe "db_list_objects"

test_that "includes active_users view with type label"
_out=$(shql_db_list_objects "")
assert_contains "$_out" "active_users"
assert_contains "$_out" "view"

end_describe

# ── db_describe ────────────────────────────────────────────────────────────────

describe "db_describe"

describe "orders table"

test_that "contains CREATE TABLE orders"
_out=$(shql_db_describe "" "orders")
assert_contains "$_out" "CREATE TABLE orders"

test_that "contains user_id column"
assert_contains "$_out" "user_id"

test_that "contains total column"
assert_contains "$_out" "total"

end_describe

describe "products table"

test_that "contains CREATE TABLE products"
_out=$(shql_db_describe "" "products")
assert_contains "$_out" "CREATE TABLE products"

test_that "contains sku column"
assert_contains "$_out" "sku"

test_that "contains price column"
assert_contains "$_out" "price"

end_describe

describe "categories table"

test_that "contains CREATE TABLE categories"
_out=$(shql_db_describe "" "categories")
assert_contains "$_out" "CREATE TABLE categories"

test_that "contains parent_id column"
assert_contains "$_out" "parent_id"

end_describe

describe "default branch"

test_that "uses table name in CREATE TABLE"
_out=$(shql_db_describe "" "mytable")
assert_contains "$_out" "CREATE TABLE mytable"

test_that "contains id INTEGER PRIMARY KEY"
assert_contains "$_out" "id INTEGER PRIMARY KEY"

end_describe

end_describe  # db_describe

# ── db_fetch ───────────────────────────────────────────────────────────────────

describe "db_fetch"

describe "orders"

test_that "first line is header containing user_id"
_out=$(shql_db_fetch "" "orders")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "user_id"

test_that "has 6 lines (header + 5 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "6" "$_count"

test_that "data row contains 'fulfilled' status"
assert_contains "$_out" "fulfilled"

end_describe

describe "products"

test_that "first line is header containing sku"
_out=$(shql_db_fetch "" "products")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "sku"

test_that "has 6 lines (header + 5 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "6" "$_count"

test_that "contains 'Widget Pro'"
assert_contains "$_out" "Widget Pro"

end_describe

describe "categories"

test_that "first line is header containing slug"
_out=$(shql_db_fetch "" "categories")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "slug"

test_that "has 4 lines (header + 3 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

test_that "contains 'Widgets' label"
assert_contains "$_out" "Widgets"

end_describe

describe "default branch"

test_that "returns id and value headers"
_out=$(shql_db_fetch "" "unknown_table")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "value"

test_that "has 2 lines (header + 1 mock row)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "2" "$_count"

end_describe

end_describe  # db_fetch

# ── db_columns ─────────────────────────────────────────────────────────────────

describe "db_columns"

describe "orders"

test_that "first column is id with PK flag"
_out=$(shql_db_columns "" "orders")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "PK"

test_that "has 8 columns"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "8" "$_count"

test_that "total column has NN flag"
assert_contains "$_out" "total"
assert_contains "$_out" "NN"

end_describe

describe "products"

test_that "has 8 columns"
_out=$(shql_db_columns "" "products")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "8" "$_count"

test_that "sku has NN flag"
_second=$(printf '%s\n' "$_out" | sed -n '2p')
assert_contains "$_second" "sku"
assert_contains "$_second" "NN"

test_that "price column is present"
assert_contains "$_out" "price"

end_describe

describe "categories"

test_that "has 4 columns"
_out=$(shql_db_columns "" "categories")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

test_that "slug has NN flag"
_second=$(printf '%s\n' "$_out" | sed -n '2p')
assert_contains "$_second" "slug"
assert_contains "$_second" "NN"

test_that "label column is present"
assert_contains "$_out" "label"

end_describe

describe "default branch"

test_that "returns single id PK column"
_out=$(shql_db_columns "" "unknown_table")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "1" "$_count"
assert_contains "$_out" "PK"

end_describe

end_describe  # db_columns

# ── db_query ──────────────────────────────────────────────────────────────────

describe "db_query"

test_that "first line is header with id name email"
_out=$(shql_db_query "" "SELECT * FROM users")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "name"
assert_contains "$_first" "email"

test_that "has 4 lines (header + 3 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

test_that "data contains Alice"
assert_contains "$_out" "Alice"

end_describe

ptyunit_test_summary
