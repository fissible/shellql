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

`shql_cli_parse` sets the following `_SHQL_CLI_*` globals. All are initialised
to their zero value at the top of each call, so successive calls produce a clean
state:

| Global | Type | Description |
|--------|------|-------------|
| `_SHQL_CLI_MODE` | string | One of: `welcome`, `open`, `table`, `query-tui`, `query-out`, `pipe`, `databases` |
| `_SHQL_CLI_DB` | string | Database file path; empty for `welcome` and `databases` |
| `_SHQL_CLI_TABLE` | string | Table name; non-empty only in `table` mode |
| `_SHQL_CLI_SQL` | string | SQL string; non-empty in `query-out` and `pipe` modes |
| `_SHQL_CLI_PORCELAIN` | 0/1 | `1` if `--porcelain` flag present |

`shql_cli_parse` does **not** set `SHQL_DB_PATH` or `SHQL_DB_TABLE` — those are
application-state globals (defined in `src/state.sh`) and are assigned by
`bin/shql` in the dispatch block, after parsing is complete.

### `shql_cli_parse "$@"`

Scans arguments in a single pass. Mode resolution order (first match wins):

1. The first positional arg equals the literal string `databases` (and no db
   path has been collected yet) → `databases`; any additional positional args
   after `databases` are silently ignored. `shql mydb.sqlite databases` does
   NOT trigger this rule — `mydb.sqlite` is collected as the db path first,
   making `databases` the table name, resulting in `table` mode.
2. `-q <sql>` flag present → `query-out`; `_SHQL_CLI_SQL` = next arg (error if absent)
3. Stdin is not a TTY (`[ ! -t 0 ]`) and no `-q` given → `pipe`. When `-q` is
   also present, rule 2 wins and this rule is not reached. In the pure-pipe
   case, read SQL from stdin:
   ```bash
   _SHQL_CLI_SQL=$(cat)
   ```
4. `--query` flag + db path → `query-tui`
5. Two positional args (db path + table name) → `table`
6. One positional arg (db path) → `open`
7. No args → `welcome`

**Error cases** — print to stderr and return 1:
- Unknown flag (anything starting with `-` that is not `-q`, `--query`, `--porcelain`)
- `-q` with no following SQL argument
- `--query` with no db path
- `pipe` mode with no db path (stdin is not a TTY but no positional db arg given)

**`--porcelain`** may appear anywhere in the argument list. It does not consume
a positional slot and does not affect mode resolution.

### `shql_cli_format_table <tsv_string>`

Formats a TSV result as a MySQL-style box table to stdout.

**Input:** A single positional argument — the full multi-line TSV string with
tab (`$'\t'`) field delimiters. The first line is the header row; subsequent
lines are data rows. Trailing newlines on the last line are ignored. This is
exactly the format returned by `shql_db_query`.

**Column width:** For each column, `column_width = max(header_length, max_data_cell_length)`.
Empty cells contribute a width of 0 and are rendered as all-spaces in their
column slot. Each cell is rendered as `| {space}{content padded to column_width}{space} |`,
so the `+` separator line has `column_width + 2` dashes per column.

**Output format:**

```
+----+---------------+-------------------+
| id | name          | email             |
+----+---------------+-------------------+
| 1  | Alice Nguyen  | alice@example.com |
| 2  | Bob Okafor    | bob@example.com   |
+----+---------------+-------------------+
```

An empty result (header only, no data rows) renders as:

```
+----+------+-------+
| id | name | email |
+----+------+-------+
+----+------+-------+
```

Every line of output (including the final bottom border) is terminated by a
single newline (`\n`). No extra blank line is emitted after the bottom border.

If the input string is empty (zero-length), the function produces no output
and returns immediately. This handles the case where `shql_db_query` returns an
empty string (e.g., for a non-SELECT statement that returns nothing).

The function reads `_SHQL_CLI_PORCELAIN`. If `1`, the function does nothing —
the caller must print the raw TSV directly (see dispatch section).

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

### DB path validation

Each TUI dispatch block (`open`, `table`, `query-tui`) includes an inline
`_shql_db_check_path` call immediately after `SHQL_DB_PATH` is set. This is
done eagerly so the user gets a clear error before any TUI initialisation runs.
In mock mode the check is skipped. The check appears once, inside each
dispatch block — there is no additional shared pre-flight section.

For `query-out` and `pipe` modes, path validation is delegated to
`shql_db_query` itself (which calls `_shql_db_check_path` internally). No
explicit pre-flight check is needed in `bin/shql` for these modes.

### Dispatch

Replace the existing `case "$_shql_mode"` block with a dispatch on
`$_SHQL_CLI_MODE`. Because `bin/shql` is a script (not a function), use plain
variable declarations (not `local`):

**`welcome`**

`shql_welcome_run` handles state loading internally (`shql_state_load_recent`
or `shql_mock_load_recent`). No caller-side setup is required.

```bash
shql_welcome_run
```

**`open`**

```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
shql_state_push_recent "$SHQL_DB_PATH"
shql_schema_init
shellframe_shell "_shql" "SCHEMA"
```

**`table`**

`table.sh` uses `_SHQL_TABLE_NAME` (screen-private) for the active table name;
`SHQL_DB_TABLE` (state.sh public global) is also set for consistency with
application state. `shql_schema_init` is required so that pressing `q` in the
TABLE screen (which navigates back to `SCHEMA`) finds an initialised schema
state. `shql_table_init` (from `table.sh`) loads DDL, data grid, and query
widget — it must be called before entering the TABLE screen. `_SHQL_TABLE_NAME`
must be set before `shql_table_init` so that `_shql_table_load_ddl` and
`_shql_table_load_data` operate on the correct table.

```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
SHQL_DB_TABLE="$_SHQL_CLI_TABLE"
_SHQL_TABLE_NAME="$_SHQL_CLI_TABLE"
if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
shql_state_push_recent "$SHQL_DB_PATH"
shql_schema_init
shql_table_init
shellframe_shell "_shql" "TABLE"
```

**`query-tui`**

The QUERY view is tab index `2` (`_SHQL_TABLE_TAB_QUERY`) within the `TABLE`
shellframe state. `shql_table_init` resets `SHELLFRAME_TABBAR_ACTIVE=0`
internally, so the active-tab override must be placed **after** `shql_table_init`.
`shql_schema_init` is required for the same `q`-key back-navigation reason as
`table` mode. `_SHQL_TABLE_NAME` is left empty (`""`) for this mode — no
specific table is pre-selected; the user starts in the empty query editor.
`shql_table_init` will call `_shql_table_load_ddl` and `_shql_table_load_data`
with an empty table name: `_shql_table_load_ddl` runs a `sqlite_master` query
that matches no rows and returns an empty DDL (safe, exits 0); `_shql_table_load_data`
runs `SELECT * FROM ""` which produces a sqlite3 error redirected to
`_SHQL_STDERR_TTY`, leaving the data grid empty. Both outcomes are benign —
the query tab renders with no pre-loaded data, which is the intended state.

```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
_SHQL_TABLE_NAME=""
if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
shql_state_push_recent "$SHQL_DB_PATH"
shql_schema_init
shql_table_init
SHELLFRAME_TABBAR_ACTIVE=$_SHQL_TABLE_TAB_QUERY   # = 2; available because table.sh is already sourced
shellframe_shell "_shql" "TABLE"
```

**`query-out` and `pipe`**

Path validation is delegated to `shql_db_query` (which calls `_shql_db_check_path`
internally). The `2>/dev/tty` redirect on `shql_db_query` is intentional:
sqlite3 errors surface to the terminal even in non-TUI mode, consistent with
the project convention that error/UI output goes to `/dev/tty` and data goes
to stdout. `_SHQL_CLI_DB` is guaranteed non-empty by the parser (pipe mode with
no db path is an error case that returns 1 and causes `bin/shql` to exit before
reaching dispatch). `shql_state_push_recent` is called only on success (after
the `_rc` check) so invalid paths are never recorded in history.

```bash
SHQL_DB_PATH="$_SHQL_CLI_DB"
_tsv=$(shql_db_query "$SHQL_DB_PATH" "$_SHQL_CLI_SQL" 2>/dev/tty)
_rc=$?   # safe: $? after a bare assignment reflects the command substitution's exit code
         # (the local footgun only applies when `local` is used; bin/shql is a script)
if [ "$_rc" -ne 0 ]; then
    exit $_rc
fi
shql_state_push_recent "$SHQL_DB_PATH"
if (( ${_SHQL_CLI_PORCELAIN:-0} )); then
    printf '%s\n' "$_tsv"
else
    shql_cli_format_table "$_tsv"
fi
```

**`databases`**

```bash
shql_state_load_recent
_p=""
for _p in "${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}"; do
    printf '%s\n' "$_p"
done
```

---

## Testing

### `tests/unit/test-cli.sh`

Sources `src/cli.sh` only (no shellframe, no db adapter). No real sqlite3.

**Parser tests:**

| Test | Input | Expected |
|------|-------|----------|
| no args → welcome | `shql_cli_parse` | `_SHQL_CLI_MODE=welcome` |
| db path → open | `shql_cli_parse mydb.sqlite` | `_SHQL_CLI_MODE=open`, `_SHQL_CLI_DB=mydb.sqlite` |
| db + table → table | `shql_cli_parse mydb.sqlite users` | `_SHQL_CLI_MODE=table`, `_SHQL_CLI_TABLE=users` |
| db + --query → query-tui | `shql_cli_parse mydb.sqlite --query` | `_SHQL_CLI_MODE=query-tui` |
| db + -q SQL → query-out | `shql_cli_parse mydb.sqlite -q "SELECT 1"` | `_SHQL_CLI_MODE=query-out`, `_SHQL_CLI_DB=mydb.sqlite`, `_SHQL_CLI_SQL=SELECT 1` |
| databases → databases | `shql_cli_parse databases` | `_SHQL_CLI_MODE=databases` |
| pipe (stdin not tty) | `printf "SELECT 1" \| bash -c 'source cli.sh; shql_cli_parse mydb.sqlite'` | `_SHQL_CLI_MODE=pipe`, `_SHQL_CLI_SQL=SELECT 1` |
| --porcelain sets flag | `shql_cli_parse mydb.sqlite -q "SELECT 1" --porcelain` | `_SHQL_CLI_PORCELAIN=1` |
| --porcelain any position | `shql_cli_parse --porcelain mydb.sqlite -q "SELECT 1"` | `_SHQL_CLI_PORCELAIN=1` |
| globals reset between calls | call with db+table, then call with no args | second call: `_SHQL_CLI_TABLE` is empty, `_SHQL_CLI_MODE=welcome` |
| --porcelain parsed for TUI mode | `shql_cli_parse mydb.sqlite --query --porcelain` | `_SHQL_CLI_MODE=query-tui`, `_SHQL_CLI_PORCELAIN=1` (flag parsed, ignored by dispatch) |
| databases + extra args ignored | `shql_cli_parse databases extra.sqlite` | `_SHQL_CLI_MODE=databases`, `_SHQL_CLI_DB` empty |
| -q wins over piped stdin | `printf "STDIN SQL" \| bash -c 'source cli.sh; shql_cli_parse mydb.sqlite -q "ARG SQL"'` | `_SHQL_CLI_MODE=query-out`, `_SHQL_CLI_SQL=ARG SQL` (stdin ignored) |
| unknown flag → error | `shql_cli_parse --foo` | return 1, stderr non-empty |
| -q missing SQL → error | `shql_cli_parse mydb.sqlite -q` | return 1 |
| --query missing db → error | `shql_cli_parse --query` | return 1 |
| pipe missing db → error | `printf "SELECT 1" \| bash -c 'source cli.sh; shql_cli_parse'` | return 1 |

**Formatter tests:**

| Test | Input | Expected |
|------|-------|----------|
| basic box | 2-col, 2-row TSV | top border + header + separator + data rows + bottom border |
| column width from data | header `id`, data `1000000` | column width = 7 (data wider than header) |
| header only | 2-col, 0 data rows | box with top + header + separator + bottom, no data rows |
| single column | 1-col, 1-row TSV | valid single-column box |
| --porcelain passthrough | `_SHQL_CLI_PORCELAIN=1` set | `shql_cli_format_table` produces no output |
| empty cell | row with an empty field | empty cell renders as spaces filling its column width |
| empty input | `shql_cli_format_table ""` | produces no output |
| pipe + --porcelain | `_SHQL_CLI_PORCELAIN=1` set; call `shql_cli_format_table` | produces no output (caller prints TSV) |

---

## Files changed

| File | Action |
|------|--------|
| `src/cli.sh` | Create |
| `bin/shql` | Modify — source cli.sh; replace stub parser and dispatch |
| `tests/unit/test-cli.sh` | Create |
