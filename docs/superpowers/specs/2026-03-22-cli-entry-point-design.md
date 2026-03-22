# CLI Entry Point — Design Spec

**Date:** 2026-03-22
**Phase:** 6.2 (CLI entry point)
**Status:** Approved for implementation planning

---

## Overview

Phase 6.2 extracts argument parsing from `bin/shql` into a dedicated `src/cli.sh`
module and implements all CLI modes: TUI open/table/query, non-TUI query output,
stdin pipe mode, and database listing.

Two files change:

```
src/cli.sh    ← new: shql_cli_parse + shql_cli_format_table
bin/shql      ← modified: source cli.sh, replace stub parser with shql_cli_parse call
```

---

## Modes

| Invocation | Mode | TUI? |
|------------|------|------|
| `shql` | `welcome` | yes |
| `shql db.sqlite` | `open` | yes |
| `shql db.sqlite table_name` | `table` | yes |
| `shql db.sqlite --query` | `query-tui` | yes |
| `shql db.sqlite -q "SQL"` | `query-out` | no |
| `echo "SQL" \| shql db.sqlite` | `pipe` | no |
| `shql databases` | `databases` | no |

`--porcelain` is a global flag applicable to `query-out` and `pipe`; silently
ignored for all other modes.

---

## Module 1: `src/cli.sh`

### Idempotency guard

```bash
[[ -n "${_SHQL_CLI_LOADED:-}" ]] && return 0
_SHQL_CLI_LOADED=1
```

### Globals set by `shql_cli_parse`

| Global | Type | Description |
|--------|------|-------------|
| `_SHQL_CLI_MODE` | string | One of: `welcome`, `open`, `table`, `query-tui`, `query-out`, `pipe`, `databases` |
| `_SHQL_CLI_DB` | string | Database file path; empty for `welcome` and `databases` |
| `_SHQL_CLI_TABLE` | string | Table name; non-empty only in `table` mode |
| `_SHQL_CLI_SQL` | string | SQL string; non-empty in `query-out` and `pipe` modes |
| `_SHQL_CLI_PORCELAIN` | 0/1 | `1` if `--porcelain` flag present |

All globals are initialised to their zero value at the top of `shql_cli_parse`
before any argument scanning, so callers see a clean state on every call.

### `shql_cli_parse "$@"`

Scans arguments in a single pass. Mode resolution order (first match wins):

1. Any positional arg equals the literal string `databases` → `databases`
2. `-q <sql>` flag present → `query-out`; `_SHQL_CLI_SQL` = next arg (error if absent)
3. Stdin is not a TTY (`[ ! -t 0 ]`) and no `-q` given → `pipe`; SQL read from stdin
4. `--query` flag + db path → `query-tui`
5. Two positional args (db path + table name) → `table`
6. One positional arg (db path) → `open`
7. No args → `welcome`

**Error cases** — print to stderr and return 1:
- Unknown flag (anything starting with `-` that is not `-q`, `--query`, `--porcelain`)
- `-q` with no following SQL argument
- `--query` with no db path

**`--porcelain`** may appear anywhere in the argument list. It does not consume
a positional slot and does not affect mode resolution.

### `shql_cli_format_table <tsv_string>`

Formats a TSV result (first line = tab-separated headers, subsequent lines = rows)
as a MySQL-style box table to stdout:

```
+----+---------------+-------------------+
| id | name          | email             |
+----+---------------+-------------------+
| 1  | Alice Nguyen  | alice@example.com |
| 2  | Bob Okafor    | bob@example.com   |
+----+---------------+-------------------+
```

Column widths are the maximum of header length and all data row cell lengths.
An empty result (header line only, no data rows) prints the box with no data rows:

```
+----+------+-------+
| id | name | email |
+----+------+-------+
+----+------+-------+
```

The function reads `_SHQL_CLI_PORCELAIN`; if `1` it is a no-op — callers must
print the raw TSV instead (see `bin/shql` dispatch below).

Future extension: a `table_style` key in `.toolrc` (read via `shql_config_get`)
will select from `box` (default), `unicode`, `simple`, or `compact`. Not
implemented in this phase; `shql_cli_format_table` always uses the box style.

---

## Module 2: `bin/shql` — changes

### Source order

Add `source "$_SHQL_ROOT/src/cli.sh"` immediately after the existing
`source "$_SHQL_ROOT/src/config.sh"` line, before the `SHQL_MOCK` guard.

### Replace stub parser

Remove the existing `while (( $# > 0 ))` argument loop and the `_shql_mode` /
`_shql_db_arg` locals. Replace with:

```bash
shql_cli_parse "$@" || exit $?
```

### Dispatch

Replace the existing `case "$_shql_mode"` block with a dispatch on
`$_SHQL_CLI_MODE`:

**`welcome`**
```bash
shql_welcome_run
```

**`open`**
```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
shql_state_push_recent "$SHQL_DB_PATH"
shql_schema_init
shellframe_shell "_shql" "SCHEMA"
```

**`table`**
```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
SHQL_DB_TABLE="$_SHQL_CLI_TABLE"
shql_state_push_recent "$SHQL_DB_PATH"
shql_schema_init
shellframe_shell "_shql" "TABLE"
```

**`query-tui`**
```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
shql_state_push_recent "$SHQL_DB_PATH"
shql_schema_init
shellframe_shell "_shql" "QUERY"
```

**`query-out` and `pipe`**
```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
local _tsv _rc
_tsv=$(shql_db_query "$SHQL_DB_PATH" "$_SHQL_CLI_SQL" 2>/dev/tty)
_rc=$?
if (( _rc != 0 )); then
    exit $_rc
fi
if (( _SHQL_CLI_PORCELAIN )); then
    printf '%s\n' "$_tsv"
else
    shql_cli_format_table "$_tsv"
fi
```

**`databases`**
```bash
shql_state_load_recent
local _p
for _p in "${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}"; do
    printf '%s\n' "$_p"
done
```

### DB path validation for TUI modes

For `open`, `table`, and `query-tui`, validate the db path before entering any
screen. Use `_shql_db_check_path` from `src/db.sh` (already sourced). On
failure, exit 1 — the function has already printed the error to stderr.

Note: `_shql_db_check_path` is a private function in `db.sh`. For SHQL_MOCK=1,
skip this check (the mock adapter accepts any path). Guard with:

```bash
if ! (( SHQL_MOCK )); then
    _shql_db_check_path "$_SHQL_CLI_DB" || exit 1
fi
```

---

## Testing

### `tests/unit/test-cli.sh`

Sources `src/cli.sh` only (no shellframe, no db adapter). No real sqlite3.

**Parser tests (one assertion per case):**

| Test | Input | Expected |
|------|-------|----------|
| no args → welcome | `shql_cli_parse` | `_SHQL_CLI_MODE=welcome` |
| db path → open | `shql_cli_parse mydb.sqlite` | `_SHQL_CLI_MODE=open`, `_SHQL_CLI_DB=mydb.sqlite` |
| db + table → table | `shql_cli_parse mydb.sqlite users` | `_SHQL_CLI_MODE=table`, `_SHQL_CLI_TABLE=users` |
| db + --query → query-tui | `shql_cli_parse mydb.sqlite --query` | `_SHQL_CLI_MODE=query-tui` |
| db + -q SQL → query-out | `shql_cli_parse mydb.sqlite -q "SELECT 1"` | `_SHQL_CLI_MODE=query-out`, `_SHQL_CLI_SQL=SELECT 1` |
| databases → databases | `shql_cli_parse databases` | `_SHQL_CLI_MODE=databases` |
| pipe (stdin not tty) | `bash -c 'source cli.sh; shql_cli_parse mydb.sqlite' < /dev/null` | `_SHQL_CLI_MODE=pipe` |
| --porcelain sets flag | `shql_cli_parse mydb.sqlite -q "SELECT 1" --porcelain` | `_SHQL_CLI_PORCELAIN=1` |
| --porcelain any position | `shql_cli_parse --porcelain mydb.sqlite -q "SELECT 1"` | `_SHQL_CLI_PORCELAIN=1` |
| unknown flag → error | `shql_cli_parse --foo` | return 1, stderr non-empty |
| -q missing SQL → error | `shql_cli_parse mydb.sqlite -q` | return 1 |
| --query missing db → error | `shql_cli_parse --query` | return 1 |

**Formatter tests:**

| Test | Input | Expected |
|------|-------|----------|
| basic box | 2-col, 2-row TSV | top border + header + separator + rows + bottom border |
| column widths from data | header "id", data "1000000" | column width = 7 (data wider than header) |
| header only | 2-col, 0 data rows | box with top + header + separator + bottom, no data rows |
| single column | 1-col, 1-row TSV | valid single-column box |
| --porcelain passthrough | `_SHQL_CLI_PORCELAIN=1` set | `shql_cli_format_table` produces no output |

---

## Files changed

| File | Action |
|------|--------|
| `src/cli.sh` | Create |
| `bin/shql` | Modify — source cli.sh; replace stub parser and dispatch |
| `tests/unit/test-cli.sh` | Create |
