#!/usr/bin/env bash
# tests/unit/test-cli.sh — Unit tests for CLI argument parsing and formatter

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/ptyunit/assert.sh"
source "$SHQL_ROOT/src/cli.sh"

ptyunit_test_begin "cli-parse"

# ── no args → welcome ────────────────────────────────────────────────────────
shql_cli_parse
assert_eq "welcome" "$_SHQL_CLI_MODE"    "no args: mode=welcome"
assert_eq ""        "$_SHQL_CLI_DB"      "no args: DB empty"

# ── db path → open ───────────────────────────────────────────────────────────
shql_cli_parse mydb.sqlite
assert_eq "open"         "$_SHQL_CLI_MODE" "db path: mode=open"
assert_eq "mydb.sqlite"  "$_SHQL_CLI_DB"   "db path: DB set"

# ── db + table → table ───────────────────────────────────────────────────────
shql_cli_parse mydb.sqlite users
assert_eq "table"        "$_SHQL_CLI_MODE"  "db+table: mode=table"
assert_eq "mydb.sqlite"  "$_SHQL_CLI_DB"    "db+table: DB set"
assert_eq "users"        "$_SHQL_CLI_TABLE" "db+table: TABLE set"

# ── db + --query → query-tui ─────────────────────────────────────────────────
shql_cli_parse mydb.sqlite --query
assert_eq "query-tui"    "$_SHQL_CLI_MODE" "db+--query: mode=query-tui"
assert_eq "mydb.sqlite"  "$_SHQL_CLI_DB"   "db+--query: DB set"

# ── db + -q SQL → query-out ──────────────────────────────────────────────────
shql_cli_parse mydb.sqlite -q "SELECT 1"
assert_eq "query-out"    "$_SHQL_CLI_MODE" "db+-q: mode=query-out"
assert_eq "mydb.sqlite"  "$_SHQL_CLI_DB"   "db+-q: DB set"
assert_eq "SELECT 1"     "$_SHQL_CLI_SQL"  "db+-q: SQL set"

# ── databases → databases ────────────────────────────────────────────────────
shql_cli_parse databases
assert_eq "databases"    "$_SHQL_CLI_MODE" "databases: mode=databases"
assert_eq ""             "$_SHQL_CLI_DB"   "databases: DB empty"

# ── databases + extra args → extra args silently ignored ─────────────────────
shql_cli_parse databases extra.sqlite
assert_eq "databases"    "$_SHQL_CLI_MODE" "databases+extra: mode still databases"
assert_eq ""             "$_SHQL_CLI_DB"   "databases+extra: DB still empty"

# ── db.sqlite databases → table mode (db path collected first) ───────────────
shql_cli_parse mydb.sqlite databases
assert_eq "table"        "$_SHQL_CLI_MODE"  "db+databases: mode=table (not databases)"
assert_eq "databases"    "$_SHQL_CLI_TABLE" "db+databases: TABLE=databases"

# ── --porcelain sets flag (after -q) ─────────────────────────────────────────
shql_cli_parse mydb.sqlite -q "SELECT 1" --porcelain
assert_eq "1"            "$_SHQL_CLI_PORCELAIN" "--porcelain after -q: flag set"

# ── --porcelain any position (before db path) ────────────────────────────────
shql_cli_parse --porcelain mydb.sqlite -q "SELECT 1"
assert_eq "1"            "$_SHQL_CLI_PORCELAIN" "--porcelain before db: flag set"
assert_eq "query-out"    "$_SHQL_CLI_MODE"      "--porcelain before db: mode correct"

# ── --porcelain parsed for TUI mode (silently) ───────────────────────────────
shql_cli_parse mydb.sqlite --query --porcelain
assert_eq "query-tui"    "$_SHQL_CLI_MODE"      "--porcelain+TUI: mode=query-tui"
assert_eq "1"            "$_SHQL_CLI_PORCELAIN"  "--porcelain+TUI: flag set"

# ── globals reset between successive calls ───────────────────────────────────
shql_cli_parse mydb.sqlite users   # sets table mode + TABLE
shql_cli_parse                     # second call with no args
assert_eq "welcome"  "$_SHQL_CLI_MODE"  "reset: mode=welcome on second call"
assert_eq ""         "$_SHQL_CLI_TABLE" "reset: TABLE cleared on second call"
assert_eq "0"        "$_SHQL_CLI_PORCELAIN" "reset: PORCELAIN cleared"

# ── pipe mode: stdin is a pipe (FIFO) ───────────────────────────────────────
_pipe_mode=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_MODE\"
")
assert_eq "pipe" "$_pipe_mode" "pipe: mode=pipe when stdin is a pipe"

_pipe_sql=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_SQL\"
")
assert_eq "SELECT 1" "$_pipe_sql" "pipe: SQL read from stdin"

# ── -q wins over piped stdin ─────────────────────────────────────────────────
_q_mode=$(printf "STDIN SQL" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite -q 'ARG SQL' 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_MODE\"
")
assert_eq "query-out" "$_q_mode" "-q wins over pipe: mode=query-out"

_q_sql=$(printf "STDIN SQL" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite -q 'ARG SQL' 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_SQL\"
")
assert_eq "ARG SQL" "$_q_sql" "-q wins over pipe: SQL from arg not stdin"

# ── error: unknown flag ───────────────────────────────────────────────────────
_err=$(shql_cli_parse --foo 2>&1); _rc=$?
assert_eq "1" "$_rc" "unknown flag: returns 1"
assert_contains "$_err" "unknown" "unknown flag: stderr mentions unknown"

# ── error: -q with no SQL arg ────────────────────────────────────────────────
shql_cli_parse mydb.sqlite -q 2>/dev/null; _rc=$?
assert_eq "1" "$_rc" "-q missing SQL: returns 1"

# ── error: --query with no db path ───────────────────────────────────────────
shql_cli_parse --query 2>/dev/null; _rc=$?
assert_eq "1" "$_rc" "--query no db: returns 1"

# ── error: pipe mode with no db path ─────────────────────────────────────────
_pipe_rc=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse 2>/dev/null
    printf '%d' \$?
")
assert_eq "1" "$_pipe_rc" "pipe no db: returns 1"

ptyunit_test_begin "cli-format"

# ── basic box: 2 columns, 2 rows ─────────────────────────────────────────────
# id width=2, name width=5 ("Alice"), separator=+----+-------+
_tsv="$(printf 'id\tname\n1\tAlice\n2\tBob')"
_expected="$(printf '+----+-------+\n| id | name  |\n+----+-------+\n| 1  | Alice |\n| 2  | Bob   |\n+----+-------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual" "basic box: 2-col 2-row"

# ── column width driven by data (wider than header) ──────────────────────────
# header "id" (len 2), data "1000000" (len 7) → column_width=7
# separator: +---------+  (7+2=9 dashes)
_tsv="$(printf 'id\n1000000')"
_expected="$(printf '+---------+\n| id      |\n+---------+\n| 1000000 |\n+---------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual" "column width from data"

# ── header only (no data rows): double separator ─────────────────────────────
_tsv="$(printf 'id\tname\temail')"
_expected="$(printf '+----+------+-------+\n| id | name | email |\n+----+------+-------+\n+----+------+-------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual" "header only: double separator"

# ── single column ─────────────────────────────────────────────────────────────
_tsv="$(printf 'val\nhello')"
_expected="$(printf '+-------+\n| val   |\n+-------+\n| hello |\n+-------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual" "single column"

# ── empty cell: renders as spaces filling column width ───────────────────────
# header "name" (len 4), data: "" (len 0) → column_width=4
# Use $'name\n' to preserve the trailing newline ($(printf...) strips it).
_tsv=$'name\n'
_expected="$(printf '+------+\n| name |\n+------+\n|      |\n+------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual" "empty cell"

# ── empty input: no output ────────────────────────────────────────────────────
_actual="$(shql_cli_format_table "")"
assert_eq "" "$_actual" "empty input: no output"

# ── --porcelain=1: format_table produces no output ───────────────────────────
_SHQL_CLI_PORCELAIN=1
_actual="$(shql_cli_format_table "$(printf 'id\n1')")"
assert_eq "" "$_actual" "porcelain=1: no output from format_table"
_SHQL_CLI_PORCELAIN=0

ptyunit_test_summary
