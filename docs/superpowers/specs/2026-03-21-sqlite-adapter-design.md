# SQLite Adapter, Config, and JSON Utilities — Design Spec

**Date:** 2026-03-21
**Phase:** 6.3 (SQLite adapter) + supporting modules
**Status:** Approved for implementation planning

---

## Overview

Three new files, built leaves-first:

```
src/json.sh       ← uses sqlite3 :memory: as JSON engine
    ↓
src/config.sh     ← sources json.sh; reads/writes ${XDG_CONFIG_HOME:-$HOME/.config}/shql/.toolrc
    ↓
src/db.sh         ← sources config.sh; calls sqlite3 for real DB operations
```

### Sourcing order in `bin/shql`

`json.sh` and `config.sh` are sourced **after `state.sh` and before the
`SHQL_MOCK` guard**, unconditionally. `db.sh` is sourced inside the guard (real
mode only), as today. Both `json.sh` and `config.sh` carry an idempotency guard
at the top (`[[ -n "${_SHQL_JSON_LOADED:-}" ]] && return 0` / `_SHQL_CONFIG_LOADED`
equivalent) so re-sourcing by `db.sh` or tests is safe. `db.sh` sources
`config.sh` directly (making it self-contained for integration tests); the guard
ensures no double-evaluation when `bin/shql` has already sourced it.

---

## Module 1: `src/json.sh`

### Purpose

Core JSON get/set utilities. Used by `config.sh` and potentially by future
modules that need to read or write JSON data.

### Idempotency guard

```bash
[[ -n "${_SHQL_JSON_LOADED:-}" ]] && return 0
_SHQL_JSON_LOADED=1
```

### JSON engine

All operations use `sqlite3 :memory:` with `json_extract`, `json_set`, and
`json_each`. Single quotes in values are escaped by doubling (`''`) before
being passed to sqlite3. No `-separator` flag is used — `:memory:` queries
return single values, not multi-column rows.

### Type detection for `shql_json_set`

A value is stored as a JSON number if it matches `^-?[0-9]+([.][0-9]*)?$`;
otherwise stored as a quoted JSON string. Callers must pre-quote values that
look numeric but must be strings. **Boolean and null JSON types are out of
scope** — callers must not store `true`, `false`, or `null`; behaviour is
undefined if they appear in `.toolrc`.

### Functions

| Function | Signature | Behavior |
|----------|-----------|----------|
| `shql_json_get` | `<file> <key>` | `json_extract` from file. Prints value to stdout. **Returns 1 if file missing or if output is empty** — sqlite3 exits 0 for a missing key, returning SQL NULL as an empty string; `shql_json_get` therefore treats empty output as absent and returns 1. Callers must check exit code; `local v=$(shql_json_get ...)` swallows it. |
| `shql_json_set` | `<file> <key> <value>` | `json_set` into file. Creates `{}` if missing. Rewrites file. |
| `shql_json_get_str` | `<json_string> <key>` | Same as `shql_json_get` but on a raw JSON string. |
| `shql_json_keys` | `<file>` | `SELECT key FROM json_each(...)`, one per line. |

### Scope constraints

Flat key paths only. `$include` is an opaque string value.

### Compatibility note

ShellQL follows the `.toolrc` JSON format from fissible/macbin but does **not**
implement `$include`. `json.sh` and `config.sh` treat `$include` as an ordinary
string key with no special behaviour.

---

## Module 2: `src/config.sh`

### Idempotency guard

```bash
[[ -n "${_SHQL_CONFIG_LOADED:-}" ]] && return 0
_SHQL_CONFIG_LOADED=1
```

### Purpose and sqlite3 detection

On source (after the guard), `config.sh` checks for sqlite3:

```bash
command -v sqlite3 >/dev/null 2>&1 && _SHQL_CONFIG_HAS_SQLITE=1 || _SHQL_CONFIG_HAS_SQLITE=0
```

`_SHQL_CONFIG_HAS_SQLITE` is a script-level global (private by convention via
the leading underscore — bash has no module scope). **Every call site in
`config.sh` that would invoke a `shql_json_*` function must first check this
flag.** When 0: gets return hardcoded defaults, set is a no-op. `json.sh`
functions do not guard themselves.

### Config file path

`${XDG_CONFIG_HOME:-$HOME/.config}/shql/.toolrc`

The config directory is created automatically on first `shql_config_set`. No
`.toolrc.local`.

### Functions

| Function | Signature | Behavior |
|----------|-----------|----------|
| `shql_config_get` | `<key>` | Returns value or empty string if key/file missing or sqlite3 absent. |
| `shql_config_set` | `<key> <value>` | Writes key; creates dir/file if needed; no-op if sqlite3 absent. |
| `shql_config_get_fetch_limit` | _(none)_ | See logic below. |

### `shql_config_get_fetch_limit` logic

The function directly tests `[ -f "$_config_file" ]` (not `shql_config_get`)
to distinguish the two no-file cases. For the "file present" case it calls
`shql_json_get` and **checks its exit code** (not its output) to distinguish
key-absent from key-present-with-value — `local v=$(fn)` swallows exit codes
in bash and must not be used here:

```
1. sqlite3 absent         → return 1000
2. config file absent     → return 1000
3. file present, key absent (shql_json_get returns 1)   → return 500
4. file present, key present (shql_json_get returns 0)  → return captured value
```

---

## Module 3: `src/db.sh`

### Purpose

Real SQLite adapter. Implements the same four-function interface as `db_mock.sh`
so screens require no changes when switching modes.

### Sourcing

`db.sh` sources `config.sh` directly at the top (after idempotency guards are
in place, the re-source is a no-op when called from `bin/shql`). This makes
`db.sh` self-contained for integration tests.

### sqlite3 invocation — split by function

- `shql_db_list_tables`, `shql_db_describe`: no `-header`, no `-separator`.
  Single-column output; the separator flag is irrelevant and omitted
  intentionally. `shql_db_describe` relies on sqlite3's default multi-line
  text output for embedded newlines in DDL values.
- `shql_db_fetch`, `shql_db_query`: `-separator $'\t'` and `-header`.

### Table/identifier escaping

When interpolating table names into SQL, single quotes in the value are
escaped by doubling for use in string literals:

```bash
_safe="${_table//\'/\'\'}"   # for: ... AND name='$_safe'
```

For `SELECT * FROM <table>`, the identifier is double-quoted:

```bash
_id="${_table//\"/\"\"}"     # for: SELECT * FROM "$_id"
```

### Functions

| Function | Signature | SQL |
|----------|-----------|-----|
| `shql_db_list_tables` | `<db_path>` | `SELECT name FROM sqlite_master WHERE type='table' ORDER BY name` |
| `shql_db_describe` | `<db_path> <table>` | `SELECT sql FROM sqlite_master WHERE type IN ('table','view') AND name='<escaped_table>'` |
| `shql_db_fetch` | `<db_path> <table> [limit] [offset]` | `SELECT * FROM "<escaped_table>" LIMIT <limit> OFFSET <offset>` |
| `shql_db_query` | `<db_path> <sql>` | SELECT/WITH-class wrapped; others pass through — see below |

### `shql_db_fetch` — limit and offset defaults

If `limit` is absent or empty, use `shql_config_get_fetch_limit`. `offset`
may only be provided when `limit` is also provided and non-empty; passing an
empty `limit` with a non-empty `offset` is treated the same as both absent
(config limit, offset 0).

### `shql_db_query` — SELECT detection and wrapping

A query is SELECT-class if its text, after stripping leading `[[:space:]]`
(including tabs and newlines), begins with `SELECT` or `WITH`
(case-insensitive). The bash test:

```bash
[[ "$_sql" =~ ^[[:space:]]*([Ss][Ee][Ll][Ee][Cc][Tt]|[Ww][Ii][Tt][Hh])[[:space:]] ]]
```

Before wrapping or passing through, trailing semicolons and whitespace are
stripped from `_sql`:

```bash
while [[ "$_sql" =~ [[:space:];]$ ]]; do _sql="${_sql%?}"; done
```

SELECT-class queries are then wrapped:

```sql
SELECT * FROM (<user_sql>) LIMIT <N>
```

Non-SELECT statements pass through unwrapped (no limit applied).

The outer limit is applied regardless of any `LIMIT` already present in the
user's SQL. The truncation warning fires only when the outer limit is the
binding constraint (rows returned equals `N`).

### Limit/warn — row buffering

Both `shql_db_fetch` and `shql_db_query` must count output rows to apply the
warning. Since the result set is already bounded by `fetch_limit`, buffering
is acceptable: capture sqlite3 output to a variable, count lines minus the
header, emit to stdout via `printf`, then emit the warning to stderr if the
count equals the limit.

**`shql_db_fetch`:**
- Explicit limit → use as-is, no warning ever.
- Config limit → warn if rows == limit.

**`shql_db_query`:**
- Always config limit; warn if rows == limit.

**Warning** (stderr):
```
warning: result truncated at <N> rows. Set a higher fetch limit or refine your query.
```

> **Caller note — `table.sh`:** Line 104 passes `2>/dev/null`; update to surface
> warnings (e.g. redirect stderr to `/dev/tty`).
>
> **Caller note — `query.sh`:** `_shql_query_run` currently treats any non-empty
> stderr as an error (discarding the result set). It must distinguish three cases
> by exit code:
> - exit non-zero → error: set `_SHQL_QUERY_STATUS="ERROR: ..."`, do not populate grid
> - exit 0, non-empty stderr → success with warning: populate grid normally, set
>   `_SHQL_QUERY_STATUS="<N> rows — $(head -1 <stderr>)"`
> - exit 0, empty stderr → normal: set `_SHQL_QUERY_STATUS="<N> rows"`

### DB path validation

All four functions check `[ -r "$1" ]` (readable file) before invoking
sqlite3. On failure, print to stderr and return 1:

```
error: database not found: <db_path>
```

### Error handling

sqlite3 stderr is captured and re-emitted on ShellQL's stderr. The function
returns sqlite3's exit code.

---

## Testing

### Unit tests (`tests/unit/`)

`test-json.sh` and `test-config.sh` stub sqlite3 by prepending a temp
directory to `PATH` containing a minimal `sqlite3` shell script. The stub
inspects its arguments (the SQL string is the last positional argument when
sqlite3 is called as `sqlite3 :memory: "SQL"`) using a `case` statement on
substrings:

```bash
case "$*" in
  *json_extract*) printf '%s\n' "$STUB_EXTRACT_RESULT" ;;
  *json_set*)     printf '%s\n' "$STUB_SET_RESULT" ;;
  *json_each*)    printf '%s\n' "$STUB_KEYS_RESULT" ;;
  *)              printf '' ;;
esac
```

Each test sets the appropriate `STUB_*` variable before calling the function
under test. `test-config.sh` also sets `XDG_CONFIG_HOME` to a temp directory.

### Integration tests (`tests/integration/`)

`test-db.sh` uses real sqlite3 and creates a temp database with a known
schema and fixture rows. Covers:
- All four adapter functions
- Limit/warn boundary (exactly `fetch_limit` rows returned)
- DB path validation (non-existent file → error on stderr, return 1)
- Invalid SQL → sqlite3 error propagated to stderr, non-zero return

---

## Files changed

| File | Action |
|------|--------|
| `src/json.sh` | Create |
| `src/config.sh` | Create |
| `src/db.sh` | Create |
| `tests/unit/test-json.sh` | Create |
| `tests/unit/test-config.sh` | Create |
| `tests/integration/test-db.sh` | Create |
| `bin/shql` | Modify — source json.sh and config.sh after state.sh, before SHQL_MOCK guard; db.sh sources config.sh directly |
| `src/screens/table.sh` | Modify — update `2>/dev/null` on db fetch calls to surface warnings |
| `src/screens/query.sh` | Modify — update `_shql_query_run` to distinguish exit-0/stderr (warning + results) from exit-nonzero/stderr (error, no results) |
