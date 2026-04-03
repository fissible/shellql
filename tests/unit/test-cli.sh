#!/usr/bin/env bash
# tests/unit/test-cli.sh — Unit tests for CLI argument parsing and formatter

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"
source "$SHQL_ROOT/src/cli.sh"

# ── cli-parse ─────────────────────────────────────────────────────────────────

describe "cli parse"

describe "mode dispatch"

test_that "no args → welcome"
shql_cli_parse
assert_eq "welcome" "$_SHQL_CLI_MODE"
assert_eq ""        "$_SHQL_CLI_DB"

test_that "db path only → open"
shql_cli_parse mydb.sqlite
assert_eq "open"        "$_SHQL_CLI_MODE"
assert_eq "mydb.sqlite" "$_SHQL_CLI_DB"

test_that "db + table → table"
shql_cli_parse mydb.sqlite users
assert_eq "table"       "$_SHQL_CLI_MODE"
assert_eq "mydb.sqlite" "$_SHQL_CLI_DB"
assert_eq "users"       "$_SHQL_CLI_TABLE"

test_that "db + --query → query-tui"
shql_cli_parse mydb.sqlite --query
assert_eq "query-tui"   "$_SHQL_CLI_MODE"
assert_eq "mydb.sqlite" "$_SHQL_CLI_DB"

test_that "db + -q SQL → query-out"
shql_cli_parse mydb.sqlite -q "SELECT 1"
assert_eq "query-out"   "$_SHQL_CLI_MODE"
assert_eq "mydb.sqlite" "$_SHQL_CLI_DB"
assert_eq "SELECT 1"    "$_SHQL_CLI_SQL"

test_that "'databases' keyword → databases mode"
shql_cli_parse databases
assert_eq "databases" "$_SHQL_CLI_MODE"
assert_eq ""          "$_SHQL_CLI_DB"

test_that "'databases' + extra arg → extra arg ignored"
shql_cli_parse databases extra.sqlite
assert_eq "databases" "$_SHQL_CLI_MODE"
assert_eq ""          "$_SHQL_CLI_DB"

test_that "db + 'databases' → table mode (db collected first)"
shql_cli_parse mydb.sqlite databases
assert_eq "table"     "$_SHQL_CLI_MODE"
assert_eq "databases" "$_SHQL_CLI_TABLE"

test_that "-h → help"
shql_cli_parse -h
assert_eq "help" "$_SHQL_CLI_MODE"

test_that "--help → help"
shql_cli_parse --help
assert_eq "help" "$_SHQL_CLI_MODE"

test_that "--help + other args → help (short-circuits)"
shql_cli_parse mydb.sqlite --help -q "SELECT 1"
assert_eq "help" "$_SHQL_CLI_MODE"

end_describe

describe "--porcelain flag"

test_that "--porcelain after -q sets flag"
shql_cli_parse mydb.sqlite -q "SELECT 1" --porcelain
assert_eq "1" "$_SHQL_CLI_PORCELAIN"

test_that "--porcelain before db path sets flag"
shql_cli_parse --porcelain mydb.sqlite -q "SELECT 1"
assert_eq "1"         "$_SHQL_CLI_PORCELAIN"
assert_eq "query-out" "$_SHQL_CLI_MODE"

test_that "--porcelain parsed silently in TUI mode"
shql_cli_parse mydb.sqlite --query --porcelain
assert_eq "query-tui" "$_SHQL_CLI_MODE"
assert_eq "1"         "$_SHQL_CLI_PORCELAIN"

end_describe

describe "globals reset between calls"

test_that "successive calls reset mode and table"
shql_cli_parse mydb.sqlite users
shql_cli_parse
assert_eq "welcome" "$_SHQL_CLI_MODE"
assert_eq ""        "$_SHQL_CLI_TABLE"
assert_eq "0"       "$_SHQL_CLI_PORCELAIN"

end_describe

describe "pipe mode"

test_that "stdin pipe → mode=pipe"
_pipe_mode=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_MODE\"
")
assert_eq "pipe" "$_pipe_mode"

test_that "stdin pipe → SQL read from stdin"
_pipe_sql=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_SQL\"
")
assert_eq "SELECT 1" "$_pipe_sql"

test_that "-q wins over piped stdin (mode)"
_q_mode=$(printf "STDIN SQL" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite -q 'ARG SQL' 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_MODE\"
")
assert_eq "query-out" "$_q_mode"

test_that "-q wins over piped stdin (SQL)"
_q_sql=$(printf "STDIN SQL" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite -q 'ARG SQL' 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_SQL\"
")
assert_eq "ARG SQL" "$_q_sql"

end_describe

describe "error handling"

test_that "unknown flag returns 1 with 'unknown' in stderr"
_err=$(shql_cli_parse --foo 2>&1); _rc=$?
assert_eq "1" "$_rc"
assert_contains "$_err" "unknown"

test_that "-q without SQL arg returns 1"
shql_cli_parse mydb.sqlite -q 2>/dev/null; _rc=$?
assert_eq "1" "$_rc"

test_that "--query without db path returns 1"
shql_cli_parse --query 2>/dev/null; _rc=$?
assert_eq "1" "$_rc"

test_that "pipe mode without db path returns 1"
_pipe_rc=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse 2>/dev/null
    printf '%d' \$?
")
assert_eq "1" "$_pipe_rc"

end_describe

describe "help text"

test_that "shql_cli_help output is non-empty"
_help_out="$(shql_cli_help)"
assert_contains "$_help_out" "shql"
assert_contains "$_help_out" "Usage"

end_describe

end_describe  # cli parse

# ── cli-format ────────────────────────────────────────────────────────────────

describe "cli format"

test_that "basic box: 2 columns, 2 rows"
_tsv="$(printf 'id\tname\n1\tAlice\n2\tBob')"
_expected="$(printf '+----+-------+\n| id | name  |\n+----+-------+\n| 1  | Alice |\n| 2  | Bob   |\n+----+-------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual"

test_that "column width driven by data wider than header"
_tsv="$(printf 'id\n1000000')"
_expected="$(printf '+---------+\n| id      |\n+---------+\n| 1000000 |\n+---------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual"

test_that "header-only input produces double separator"
_tsv="$(printf 'id\tname\temail')"
_expected="$(printf '+----+------+-------+\n| id | name | email |\n+----+------+-------+\n+----+------+-------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual"

test_that "single column table"
_tsv="$(printf 'val\nhello')"
_expected="$(printf '+-------+\n| val   |\n+-------+\n| hello |\n+-------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual"

test_that "empty cell renders as spaces filling column width"
_tsv=$'name\n'
_expected="$(printf '+------+\n| name |\n+------+\n|      |\n+------+')"
_actual="$(shql_cli_format_table "$_tsv")"
assert_eq "$_expected" "$_actual"

test_that "empty input produces no output"
_actual="$(shql_cli_format_table "")"
assert_eq "" "$_actual"

test_that "porcelain=1 suppresses box formatting"
_SHQL_CLI_PORCELAIN=1
_actual="$(shql_cli_format_table "$(printf 'id\n1')")"
assert_eq "" "$_actual"
_SHQL_CLI_PORCELAIN=0

end_describe

ptyunit_test_summary
