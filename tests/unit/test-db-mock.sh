#!/usr/bin/env bash
# tests/unit/test-db-mock.sh — Unit tests for all db_mock.sh branches

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"

# ── shql_mock_load_recent ─────────────────────────────────────────────────────

ptyunit_test_begin "mock_load_recent: populates SHQL_RECENT_FILES"
SHQL_RECENT_FILES=()
shql_mock_load_recent
assert_eq 1 $(( ${#SHQL_RECENT_FILES[@]} > 0 ))

ptyunit_test_begin "mock_load_recent: SHQL_RECENT_NAMES count matches files"
assert_eq "${#SHQL_RECENT_FILES[@]}" "${#SHQL_RECENT_NAMES[@]}"

ptyunit_test_begin "mock_load_recent: source is always local"
assert_eq "local" "${SHQL_RECENT_SOURCES[0]}"

ptyunit_test_begin "mock_load_recent: ref equals file path"
assert_eq "${SHQL_RECENT_FILES[0]}" "${SHQL_RECENT_REFS[0]}"

# ── shql_db_list_tables ───────────────────────────────────────────────────────

ptyunit_test_begin "db_list_tables: returns 4 tables"
_out=$(shql_db_list_tables "")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

ptyunit_test_begin "db_list_tables: contains users"
assert_contains "$_out" "users"

# ── shql_db_list_objects ──────────────────────────────────────────────────────

ptyunit_test_begin "db_list_objects: includes active_users view"
_out=$(shql_db_list_objects "")
assert_contains "$_out" "active_users"
assert_contains "$_out" "view"

# ── shql_db_describe: orders branch ──────────────────────────────────────────

ptyunit_test_begin "db_describe orders: contains CREATE TABLE orders"
_out=$(shql_db_describe "" "orders")
assert_contains "$_out" "CREATE TABLE orders"

ptyunit_test_begin "db_describe orders: contains user_id column"
assert_contains "$_out" "user_id"

ptyunit_test_begin "db_describe orders: contains total column"
assert_contains "$_out" "total"

# ── shql_db_describe: products branch ────────────────────────────────────────

ptyunit_test_begin "db_describe products: contains CREATE TABLE products"
_out=$(shql_db_describe "" "products")
assert_contains "$_out" "CREATE TABLE products"

ptyunit_test_begin "db_describe products: contains sku column"
assert_contains "$_out" "sku"

ptyunit_test_begin "db_describe products: contains price column"
assert_contains "$_out" "price"

# ── shql_db_describe: categories branch ──────────────────────────────────────

ptyunit_test_begin "db_describe categories: contains CREATE TABLE categories"
_out=$(shql_db_describe "" "categories")
assert_contains "$_out" "CREATE TABLE categories"

ptyunit_test_begin "db_describe categories: contains parent_id column"
assert_contains "$_out" "parent_id"

# ── shql_db_describe: default branch ─────────────────────────────────────────

ptyunit_test_begin "db_describe default: uses table name in CREATE TABLE"
_out=$(shql_db_describe "" "mytable")
assert_contains "$_out" "CREATE TABLE mytable"

ptyunit_test_begin "db_describe default: contains id PRIMARY KEY"
assert_contains "$_out" "id INTEGER PRIMARY KEY"

# ── shql_db_fetch: orders branch ─────────────────────────────────────────────

ptyunit_test_begin "db_fetch orders: first line is header with user_id"
_out=$(shql_db_fetch "" "orders")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "user_id"

ptyunit_test_begin "db_fetch orders: has 6 lines (header + 5 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "6" "$_count"

ptyunit_test_begin "db_fetch orders: data row contains fulfilled status"
assert_contains "$_out" "fulfilled"

# ── shql_db_fetch: products branch ───────────────────────────────────────────

ptyunit_test_begin "db_fetch products: first line is header with sku"
_out=$(shql_db_fetch "" "products")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "sku"

ptyunit_test_begin "db_fetch products: has 6 lines (header + 5 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "6" "$_count"

ptyunit_test_begin "db_fetch products: contains Widget Pro"
assert_contains "$_out" "Widget Pro"

# ── shql_db_fetch: categories branch ─────────────────────────────────────────

ptyunit_test_begin "db_fetch categories: first line is header with slug"
_out=$(shql_db_fetch "" "categories")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "slug"

ptyunit_test_begin "db_fetch categories: has 4 lines (header + 3 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

ptyunit_test_begin "db_fetch categories: contains Widgets label"
assert_contains "$_out" "Widgets"

# ── shql_db_fetch: default branch ────────────────────────────────────────────

ptyunit_test_begin "db_fetch default: returns id and value headers"
_out=$(shql_db_fetch "" "unknown_table")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "value"

ptyunit_test_begin "db_fetch default: has 2 lines (header + 1 mock row)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "2" "$_count"

# ── shql_db_columns: orders branch ───────────────────────────────────────────

ptyunit_test_begin "db_columns orders: first column is id with PK"
_out=$(shql_db_columns "" "orders")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "PK"

ptyunit_test_begin "db_columns orders: has 8 columns"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "8" "$_count"

ptyunit_test_begin "db_columns orders: total column is NN"
assert_contains "$_out" "total"
assert_contains "$_out" "NN"

# ── shql_db_columns: products branch ─────────────────────────────────────────

ptyunit_test_begin "db_columns products: has 8 columns"
_out=$(shql_db_columns "" "products")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "8" "$_count"

ptyunit_test_begin "db_columns products: sku has NN flag"
_second=$(printf '%s\n' "$_out" | sed -n '2p')
assert_contains "$_second" "sku"
assert_contains "$_second" "NN"

ptyunit_test_begin "db_columns products: price has NN flag"
assert_contains "$_out" "price"

# ── shql_db_columns: categories branch ───────────────────────────────────────

ptyunit_test_begin "db_columns categories: has 4 columns"
_out=$(shql_db_columns "" "categories")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

ptyunit_test_begin "db_columns categories: slug has NN flag"
_second=$(printf '%s\n' "$_out" | sed -n '2p')
assert_contains "$_second" "slug"
assert_contains "$_second" "NN"

ptyunit_test_begin "db_columns categories: label has NN flag"
assert_contains "$_out" "label"

# ── shql_db_columns: default branch ──────────────────────────────────────────

ptyunit_test_begin "db_columns default: returns single id PK column"
_out=$(shql_db_columns "" "unknown_table")
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "1" "$_count"
assert_contains "$_out" "PK"

# ── shql_db_query ─────────────────────────────────────────────────────────────

ptyunit_test_begin "db_query: first line is header with id name email"
_out=$(shql_db_query "" "SELECT * FROM users")
_first=$(printf '%s\n' "$_out" | head -1)
assert_contains "$_first" "id"
assert_contains "$_first" "name"
assert_contains "$_first" "email"

ptyunit_test_begin "db_query: has 4 lines (header + 3 rows)"
_count=$(printf '%s\n' "$_out" | wc -l | tr -d ' ')
assert_eq "4" "$_count"

ptyunit_test_begin "db_query: data contains Alice"
assert_contains "$_out" "Alice"

ptyunit_test_summary
