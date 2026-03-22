# CLI Entry Point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract argument parsing from `bin/shql` into `src/cli.sh`, implement all 7 CLI modes (welcome, open, table, query-tui, query-out, pipe, databases), and add the non-TUI formatted table output.

**Architecture:** `src/cli.sh` exports `shql_cli_parse` (sets `_SHQL_CLI_*` globals) and `shql_cli_format_table` (MySQL-style box output). `bin/shql` sources `cli.sh`, calls `shql_cli_parse "$@"`, then dispatches on `_SHQL_CLI_MODE` using existing screen init functions. No new TUI screens are needed.

**Tech Stack:** bash 3.2+, existing shellframe + ShellQL screen stack, ptyunit test harness.

---

## File Map

| File | Change |
|------|--------|
| `src/cli.sh` | **Create** — `shql_cli_parse` + `shql_cli_format_table` |
| `tests/unit/test-cli.sh` | **Create** — parser + formatter unit tests |
| `bin/shql` | **Modify** — source `cli.sh`, replace stub parser + dispatch |

---

## Key context for implementers

- **`src/cli.sh` must be sourced before the `SHQL_MOCK` guard** in `bin/shql`, immediately after `src/config.sh`.
- **`bin/shql` is a script, not a function** — use plain variable declarations (no `local`) in the dispatch block.
- **`set -uo pipefail` is active in `bin/shql`**. Use `${var:-default}` for variables that may be unset.
- **bash 3.2 compat** — no `printf -v`, no `{n}` string repeat, no `+=` on strings (only on arrays). Use loops for string repetition. Arrays are fine.
- **`local` footgun**: `local x=$(cmd); $?` is always 0. Use `local x; x=$(cmd); rc=$?` when capturing exit codes. In `bin/shql` (script level), use plain `x=$(cmd); rc=$?` — that correctly captures the cmd exit code.
- Pipe detection uses `[ -p /dev/stdin ]` (not `[ ! -t 0 ]`) inside `shql_cli_parse` at call time. `[ -p /dev/stdin ]` checks that stdin is an actual FIFO, avoiding false positives in non-interactive environments where `[ ! -t 0 ]` would incorrectly trigger pipe mode.
- See spec: `docs/superpowers/specs/2026-03-22-cli-entry-point-design.md`

---

## Task 1: `shql_cli_parse` + parser tests

**Files:**
- Create: `src/cli.sh`
- Create: `tests/unit/test-cli.sh`

### Step 1 — Write the failing parser tests

Create `tests/unit/test-cli.sh`:

```bash
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

# ── pipe mode: stdin not a TTY ───────────────────────────────────────────────
_pipe_mode=$(printf "SELECT 1" | bash -c "
    source '${SHQL_ROOT}/src/cli.sh'
    shql_cli_parse mydb.sqlite 2>/dev/null
    printf '%s' \"\$_SHQL_CLI_MODE\"
")
assert_eq "pipe" "$_pipe_mode" "pipe: mode=pipe when stdin not tty"

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

ptyunit_test_summary
```

- [ ] **Step 2 — Run tests to confirm they fail**

```bash
cd /path/to/shellql
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/ptyunit/run.sh --unit 2>&1 | grep -E "test-cli|FAIL|error"
```

Expected: `test-cli.sh` fails (source of `src/cli.sh` errors — file doesn't exist yet).

- [ ] **Step 3 — Create `src/cli.sh` with idempotency guard and `shql_cli_parse`**

Create `src/cli.sh`:

```bash
#!/usr/bin/env bash
# shellql/src/cli.sh — CLI argument parsing and non-TUI output formatting
#
# Provides:
#   shql_cli_parse "$@"         — parse args, set _SHQL_CLI_* globals
#   shql_cli_format_table <tsv> — print MySQL-style box table to stdout

[[ -n "${_SHQL_CLI_LOADED:-}" ]] && return 0
_SHQL_CLI_LOADED=1

# ── Globals (set by shql_cli_parse) ───────────────────────────────────────────

_SHQL_CLI_MODE=""
_SHQL_CLI_DB=""
_SHQL_CLI_TABLE=""
_SHQL_CLI_SQL=""
_SHQL_CLI_PORCELAIN=0

# ── shql_cli_parse ────────────────────────────────────────────────────────────
#
# Parse $@ and set _SHQL_CLI_* globals. All globals are reset at the top of
# each call, so successive calls produce a clean state.
#
# Mode resolution order (first match wins):
#   1. First positional = "databases" (no db yet) → databases
#   2. -q <sql> flag                              → query-out
#   3. Stdin not a TTY and no -q                  → pipe (reads stdin)
#   4. --query flag + db path                     → query-tui
#   5. Two positionals (db + table)               → table
#   6. One positional (db)                        → open
#   7. No args                                    → welcome
#
# Returns 1 and prints to stderr on: unknown flag, -q without SQL,
#   --query without db path, pipe mode without db path.

shql_cli_parse() {
    # Reset all globals
    _SHQL_CLI_MODE="welcome"
    _SHQL_CLI_DB=""
    _SHQL_CLI_TABLE=""
    _SHQL_CLI_SQL=""
    _SHQL_CLI_PORCELAIN=0

    local _pos=()
    local _has_q=0
    local _q_sql=""
    local _has_query=0

    # Single-pass argument scan: collect flags and positionals
    while (( $# > 0 )); do
        case "$1" in
            --porcelain)
                _SHQL_CLI_PORCELAIN=1
                shift ;;
            -q)
                if (( $# < 2 )); then
                    printf 'error: -q requires a SQL argument\n' >&2
                    return 1
                fi
                _has_q=1
                _q_sql="$2"
                shift 2 ;;
            --query)
                _has_query=1
                shift ;;
            -*)
                printf 'error: unknown option: %s\n' "$1" >&2
                return 1 ;;
            *)
                _pos+=("$1")
                shift ;;
        esac
    done

    local _first_pos="${_pos[0]:-}"
    local _second_pos="${_pos[1]:-}"

    # Rule 1: "databases" as first positional (before db path)
    if [[ "$_first_pos" == "databases" ]]; then
        _SHQL_CLI_MODE="databases"
        return 0
    fi

    # Collect db and (optional) table from positionals
    local _db="${_first_pos}"
    local _table="${_second_pos}"

    # Rule 2: -q flag present
    if (( _has_q )); then
        _SHQL_CLI_MODE="query-out"
        _SHQL_CLI_DB="$_db"
        _SHQL_CLI_SQL="$_q_sql"
        return 0
    fi

    # Rule 3: stdin not a TTY (and no -q)
    if [ ! -t 0 ]; then
        if [[ -z "$_db" ]]; then
            printf 'error: a database path is required when reading SQL from stdin\n' >&2
            return 1
        fi
        _SHQL_CLI_MODE="pipe"
        _SHQL_CLI_DB="$_db"
        _SHQL_CLI_SQL=$(cat)
        return 0
    fi

    # Rule 4: --query flag
    if (( _has_query )); then
        if [[ -z "$_db" ]]; then
            printf 'error: --query requires a database path\n' >&2
            return 1
        fi
        _SHQL_CLI_MODE="query-tui"
        _SHQL_CLI_DB="$_db"
        return 0
    fi

    # Rule 5: two positionals (db + table)
    if [[ -n "$_table" ]]; then
        _SHQL_CLI_MODE="table"
        _SHQL_CLI_DB="$_db"
        _SHQL_CLI_TABLE="$_table"
        return 0
    fi

    # Rule 6: one positional (db)
    if [[ -n "$_db" ]]; then
        _SHQL_CLI_MODE="open"
        _SHQL_CLI_DB="$_db"
        return 0
    fi

    # Rule 7: no args
    _SHQL_CLI_MODE="welcome"
    return 0
}
```

- [ ] **Step 4 — Run parser tests to confirm they pass**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/ptyunit/run.sh --unit 2>&1 | grep -E "test-cli|OK|FAIL"
```

Expected: `test-cli.sh ... OK (?/?)` (only the parser assertions run so far).

- [ ] **Step 5 — Commit**

```bash
git add src/cli.sh tests/unit/test-cli.sh
git commit -m "feat(cli): add shql_cli_parse with 7-mode argument resolution"
```

---

## Task 2: `shql_cli_format_table` + formatter tests

**Files:**
- Modify: `src/cli.sh` (append `shql_cli_format_table`)
- Modify: `tests/unit/test-cli.sh` (append formatter tests)

### Step 1 — Append formatter tests to `tests/unit/test-cli.sh`

Add the following **after** `ptyunit_test_summary` at the end of the file — but first, move `ptyunit_test_summary` down past the new tests (or use a second `ptyunit_test_begin`). The simplest approach: replace the existing `ptyunit_test_summary` call with the new test block + summary.

**Replace** the final `ptyunit_test_summary` line with:

```bash
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
_tsv="$(printf 'name\n')"
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
```

- [ ] **Step 2 — Run tests to confirm formatter tests fail**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/ptyunit/run.sh --unit 2>&1 | grep -E "test-cli|FAIL|cli-format"
```

Expected: formatter tests fail (`shql_cli_format_table: command not found` or similar).

- [ ] **Step 3 — Append `shql_cli_format_table` to `src/cli.sh`**

Add after `shql_cli_parse` in `src/cli.sh`:

```bash
# ── shql_cli_format_table ─────────────────────────────────────────────────────
#
# Print a TSV result as a MySQL-style box table to stdout.
#
# Usage: shql_cli_format_table <tsv_string>
#
#   <tsv_string>  Full multi-line TSV. First line = tab-separated headers.
#                 Subsequent lines = data rows. Trailing newlines ignored.
#                 If empty: no output. If _SHQL_CLI_PORCELAIN=1: no output.
#
# Output format:
#   +----+-------+
#   | id | name  |
#   +----+-------+
#   | 1  | Alice |
#   +----+-------+
#
# Column width = max(header_length, max_data_cell_length).
# Each cell: | {space}{content padded to column_width}{space} |
# Separator dashes per column = column_width + 2.

shql_cli_format_table() {
    local _tsv="$1"
    [[ -z "$_tsv" ]] && return 0
    (( ${_SHQL_CLI_PORCELAIN:-0} )) && return 0

    # Split TSV into header line and data lines
    local _header="" _rows=() _line _first=1
    while IFS= read -r _line; do
        if (( _first )); then
            _header="$_line"
            _first=0
        else
            [[ -n "$_line" ]] && _rows+=("$_line")
        fi
    done <<< "$_tsv"

    # Parse header into column array (tab-delimited)
    local _headers=() _IFS_SAVE="$IFS"
    IFS=$'\t' read -ra _headers <<< "$_header"
    IFS="$_IFS_SAVE"
    local _ncols=${#_headers[@]}

    # Initialise column widths from header lengths
    local _widths=() _i
    for (( _i = 0; _i < _ncols; _i++ )); do
        _widths+=( "${#_headers[$_i]}" )
    done

    # Expand widths from data cell lengths
    local _row _cells=() _cell _clen
    for _row in "${_rows[@]+"${_rows[@]}"}"; do
        _cells=()
        IFS=$'\t' read -ra _cells <<< "$_row"
        IFS="$_IFS_SAVE"
        for (( _i = 0; _i < _ncols; _i++ )); do
            _cell="${_cells[$_i]:-}"
            _clen=${#_cell}
            (( _clen > _widths[$_i] )) && _widths[$_i]=$_clen
        done
    done

    # Build separator line: +---+---+
    local _sep="+" _j _dashes _w
    for (( _i = 0; _i < _ncols; _i++ )); do
        _dashes=""
        _w=$(( _widths[$_i] + 2 ))
        for (( _j = 0; _j < _w; _j++ )); do _dashes="${_dashes}-"; done
        _sep="${_sep}${_dashes}+"
    done

    # Print top border
    printf '%s\n' "$_sep"

    # Print header row: | col1 | col2 |
    local _row_str="|" _v _pad _sp _m
    for (( _i = 0; _i < _ncols; _i++ )); do
        _v="${_headers[$_i]}"
        _pad=$(( _widths[$_i] - ${#_v} ))
        _sp=""
        for (( _m = 0; _m < _pad; _m++ )); do _sp="${_sp} "; done
        _row_str="${_row_str} ${_v}${_sp} |"
    done
    printf '%s\n' "$_row_str"

    # Print header separator
    printf '%s\n' "$_sep"

    # Print data rows
    for _row in "${_rows[@]+"${_rows[@]}"}"; do
        _cells=()
        IFS=$'\t' read -ra _cells <<< "$_row"
        IFS="$_IFS_SAVE"
        _row_str="|"
        for (( _i = 0; _i < _ncols; _i++ )); do
            _v="${_cells[$_i]:-}"
            _pad=$(( _widths[$_i] - ${#_v} ))
            _sp=""
            for (( _m = 0; _m < _pad; _m++ )); do _sp="${_sp} "; done
            _row_str="${_row_str} ${_v}${_sp} |"
        done
        printf '%s\n' "$_row_str"
    done

    # Print bottom border
    printf '%s\n' "$_sep"
}
```

- [ ] **Step 4 — Run all unit tests to confirm they pass**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/ptyunit/run.sh --unit
```

Expected: `test-cli.sh ... OK (?/?)` with all other suites still passing.

- [ ] **Step 5 — Commit**

```bash
git add src/cli.sh tests/unit/test-cli.sh
git commit -m "feat(cli): add shql_cli_format_table with MySQL-style box output"
```

---

## Task 3: Wire `bin/shql`

**Files:**
- Modify: `bin/shql`

### Step 1 — Read the current `bin/shql` to understand what to replace

Current stub sections (lines 56–92):
```bash
# ── Argument parsing (minimal — Phase 6 expands this) ────────────────────────
_shql_mode="welcome"
_shql_db_arg=""

while (( $# > 0 )); do
    case "$1" in
        databases) _shql_mode="databases"; shift ;;
        --query|-q) _shql_mode="query"; shift ;;
        -*)
            printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
        *)
            if [[ -z "$_shql_db_arg" ]]; then
                _shql_db_arg="$1"
                _shql_mode="open"
            fi
            shift ;;
    esac
done

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$_shql_mode" in
    welcome)
        shql_welcome_run
        ;;
    open)
        SHQL_DB_PATH="$_shql_db_arg"
        printf 'TODO: open %s\n' "$SHQL_DB_PATH"
        ;;
    query)
        printf 'TODO: query mode\n'
        ;;
    databases)
        printf 'TODO: list databases\n'
        ;;
esac
```

- [ ] **Step 2 — Add `source "$_SHQL_ROOT/src/cli.sh"` to source block**

In `bin/shql`, after the line `source "$_SHQL_ROOT/src/config.sh"` and before the `if (( SHQL_MOCK ));` guard, add:

```bash
source "$_SHQL_ROOT/src/cli.sh"
```

The source block should then read:
```bash
source "$_SHQL_ROOT/src/state.sh"
source "$_SHQL_ROOT/src/json.sh"
source "$_SHQL_ROOT/src/config.sh"
source "$_SHQL_ROOT/src/cli.sh"

if (( SHQL_MOCK )); then
    source "$_SHQL_ROOT/src/db_mock.sh"
else
    source "$_SHQL_ROOT/src/db.sh"
fi
```

- [ ] **Step 3 — Replace the stub argument parsing and dispatch**

Replace everything from the `# ── Argument parsing` comment through the final `esac` with:

```bash
# ── Argument parsing ──────────────────────────────────────────────────────────

shql_cli_parse "$@" || exit $?

# ── Dispatch ──────────────────────────────────────────────────────────────────

case "$_SHQL_CLI_MODE" in
    welcome)
        shql_welcome_run
        ;;

    open)
        SHQL_DB_PATH="$_SHQL_CLI_DB"
        if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
        shql_state_push_recent "$SHQL_DB_PATH"
        shql_schema_init
        shellframe_shell "_shql" "SCHEMA"
        ;;

    table)
        # _SHQL_TABLE_NAME is the screen-private name used by table.sh;
        # SHQL_DB_TABLE is the public state global — set both.
        # shql_schema_init is needed so pressing q in TABLE navigates back to SCHEMA.
        # shql_table_init must be called after _SHQL_TABLE_NAME is set.
        SHQL_DB_PATH="$_SHQL_CLI_DB"
        SHQL_DB_TABLE="$_SHQL_CLI_TABLE"
        _SHQL_TABLE_NAME="$_SHQL_CLI_TABLE"
        if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
        shql_state_push_recent "$SHQL_DB_PATH"
        shql_schema_init
        shql_table_init
        shellframe_shell "_shql" "TABLE"
        ;;

    query-tui)
        # Open TABLE screen with the QUERY tab (index 2) pre-selected.
        # _SHQL_TABLE_NAME is left empty — no table pre-selected; user starts
        # in the query editor. shql_table_init resets SHELLFRAME_TABBAR_ACTIVE=0,
        # so the tab override must come AFTER shql_table_init.
        SHQL_DB_PATH="$_SHQL_CLI_DB"
        _SHQL_TABLE_NAME=""
        if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
        shql_state_push_recent "$SHQL_DB_PATH"
        shql_schema_init
        shql_table_init
        SHELLFRAME_TABBAR_ACTIVE=$_SHQL_TABLE_TAB_QUERY
        shellframe_shell "_shql" "TABLE"
        ;;

    query-out|pipe)
        # Path validation delegated to shql_db_query (_shql_db_check_path inside).
        # Record to recent history only on success so invalid paths are never saved.
        SHQL_DB_PATH="$_SHQL_CLI_DB"
        _tsv=$(shql_db_query "$SHQL_DB_PATH" "$_SHQL_CLI_SQL" 2>/dev/tty)
        _rc=$?
        if [ "$_rc" -ne 0 ]; then
            exit $_rc
        fi
        shql_state_push_recent "$SHQL_DB_PATH"
        if (( ${_SHQL_CLI_PORCELAIN:-0} )); then
            printf '%s\n' "$_tsv"
        else
            shql_cli_format_table "$_tsv"
        fi
        ;;

    databases)
        shql_state_load_recent
        _p=""
        for _p in "${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}"; do
            printf '%s\n' "$_p"
        done
        ;;
esac
```

- [ ] **Step 4 — Run the full test suite to confirm no regressions**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/ptyunit/run.sh --unit
```

Expected: all suites pass, including `test-cli.sh`.

- [ ] **Step 5 — Smoke test: welcome mode still works**

```bash
SHQL_MOCK=1 SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash bin/shql
```

Expected: welcome screen opens (press `q` to exit).

- [ ] **Step 6 — Smoke test: databases mode**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash bin/shql databases
```

Expected: prints recent database paths (may be empty list if no history), exits 0.

- [ ] **Step 7 — Smoke test: query-out mode with a real database**

```bash
# Create a tiny test database
sqlite3 /tmp/shql-smoke.db "CREATE TABLE t (id INTEGER, v TEXT); INSERT INTO t VALUES (1,'hello'),(2,'world');"

# Non-TUI query output (formatted table)
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash bin/shql /tmp/shql-smoke.db -q "SELECT * FROM t"
```

Expected:
```
+----+-------+
| id | v     |
+----+-------+
| 1  | hello |
| 2  | world |
+----+-------+
```

- [ ] **Step 8 — Smoke test: porcelain output**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash bin/shql /tmp/shql-smoke.db -q "SELECT * FROM t" --porcelain
```

Expected: raw TSV (id\tv header row + data rows), no box borders.

- [ ] **Step 9 — Commit**

```bash
git add bin/shql
git commit -m "feat(shql): wire cli.sh; implement all 7 dispatch modes"
```

---

## Final check

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/ptyunit/run.sh --unit
```

All suites must pass before declaring done.
