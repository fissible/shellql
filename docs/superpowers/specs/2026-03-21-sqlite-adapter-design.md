# SQLite Adapter, Config, and JSON Utilities — Design Spec

**Date:** 2026-03-21
**Phase:** 6.3 (SQLite adapter) + supporting modules
**Status:** Approved for implementation planning

---

## Overview

This spec covers three new source files introduced together as a dependency-ordered
unit. The modules are built leaves-first: `json.sh` has no ShellQL dependencies,
`config.sh` depends on `json.sh`, and `db.sh` depends on both.

```
src/json.sh       ← no deps (uses sqlite3 :memory: as JSON engine)
    ↓
src/config.sh     ← sources json.sh; reads/writes ~/.config/shql/.toolrc
    ↓
src/db.sh         ← sources config.sh; calls sqlite3 for real DB operations
```

`bin/shql` sources them in this order, after `state.sh` and before screens.
Mock mode (`SHQL_MOCK=1`) continues to work without sqlite3 — `config.sh`
falls back to hardcoded defaults when sqlite3 is unavailable.

---

## Module 1: `src/json.sh`

### Purpose

Core JSON get/set utilities. Used by `config.sh` and potentially by future
modules that need to read or write JSON data (e.g. displaying JSON column
values in the grid).

### JSON engine

All operations use `sqlite3 :memory:` with the built-in JSON1 functions
(`json_extract`, `json_set`). Single quotes in values are escaped by doubling
(`''`) before being passed to sqlite3. Numbers are stored as JSON numbers;
all other values are stored as JSON strings.

### Functions

| Function | Signature | Behavior |
|----------|-----------|----------|
| `shql_json_get` | `<file> <key>` | Extracts top-level scalar `key` from JSON file. Prints value to stdout. Returns 1 if file or key is missing. |
| `shql_json_set` | `<file> <key> <value>` | Adds or updates `key` in JSON file. Creates file with `{}` if it does not exist. Rewrites file with result. |
| `shql_json_get_str` | `<json_string> <key>` | Same as `shql_json_get` but operates on a raw JSON string rather than a file. Used internally by `config.sh`. |
| `shql_json_keys` | `<file>` | Prints all top-level keys, one per line. Used by future `shql config show`. |

### Scope constraints

- Flat key paths only. No nested key access (e.g. `db.fetch_limit`) in this phase.
- `$include` is treated as an opaque string value. `json.sh` has no knowledge
  of the macbin `.toolrc` include convention; that logic belongs to the caller.

### Compatibility note

ShellQL's `.toolrc` file follows the JSON format established by
[fissible/macbin](https://github.com/fissible/macbin) `config` tool. However,
ShellQL does **not** implement the `$include` override mechanism from that tool.
That convention exists to support per-project multi-environment overrides
(`.toolrc` committed, `.toolrc.local` gitignored). ShellQL's config is a
global personal tool config — there is no project context and no need for
local machine overrides.

---

## Module 2: `src/config.sh`

### Purpose

Reads and writes ShellQL's user configuration. Provides typed getters for
known config keys with documented defaults.

### Config file

| Path | Role |
|------|------|
| `~/.config/shql/.toolrc` | Single config file. Committed format (JSON). |

The `~/.config/shql/` directory is created automatically on first write.
There is no `.toolrc.local` — see compatibility note above.

### Functions

| Function | Signature | Behavior |
|----------|-----------|----------|
| `shql_config_get` | `<key>` | Returns value from config file, or empty string if key/file missing. |
| `shql_config_set` | `<key> <value>` | Writes key to config file. Creates dir and file if needed. |
| `shql_config_get_fetch_limit` | _(none)_ | Returns `fetch_limit` from config (default **500** if key missing but file exists), or **1000** if no config file at all. |

### Default values

| Key | Default (file exists, key missing) | Default (no file) |
|-----|------------------------------------|-------------------|
| `fetch_limit` | 500 | 1000 |

The two-tier default is intentional: 1000 is a permissive out-of-the-box
experience; 500 is the explicit "I have configured this tool" default.

---

## Module 3: `src/db.sh`

### Purpose

The real SQLite adapter. Implements the same four-function interface as
`src/db_mock.sh` so screens require no changes when switching from mock to
real mode.

### sqlite3 invocation

All queries use:
```
sqlite3 -separator $'\t' -header <db_path> <sql>
```

This produces TSV output with a header row as the first line — identical to
the mock adapter's output format.

### Functions

| Function | Signature | SQL / approach |
|----------|-----------|----------------|
| `shql_db_list_tables` | `<db_path>` | `SELECT name FROM sqlite_master WHERE type='table' ORDER BY name` |
| `shql_db_describe` | `<db_path> <table>` | `SELECT sql FROM sqlite_master WHERE type IN ('table','view','index') AND name='<table>'` |
| `shql_db_fetch` | `<db_path> <table> [limit] [offset]` | `SELECT * FROM <table> LIMIT <limit> OFFSET <offset>`. Uses `shql_config_get_fetch_limit` when limit is omitted. |
| `shql_db_query` | `<db_path> <sql>` | Runs arbitrary SQL. Applies the same limit/warn logic. |

### Limit and warning behaviour

`shql_db_fetch` and `shql_db_query` apply a row limit:

1. If a limit argument is passed explicitly, use it as-is (no warning).
2. If no limit is passed, call `shql_config_get_fetch_limit` to get the limit.
3. After query execution, if the number of returned rows equals the limit,
   emit a warning to stderr:
   ```
   warning: result truncated at <N> rows (fetch_limit). Set a higher limit or refine your query.
   ```

### DB path validation

All four functions check that `<db_path>` is a readable file before invoking
sqlite3. On failure:
```
error: database not found: <db_path>
```
printed to stderr, function returns 1.

### Error handling

sqlite3 errors are captured from stderr and re-emitted on ShellQL's stderr.
The function returns sqlite3's exit code.

---

## Testing

### Unit tests

`tests/unit/test-json.sh` and `tests/unit/test-config.sh` use mock JSON
fixtures (inline strings / temp files). No sqlite3 required for json.sh
tests — the sqlite3 call is stubbed. config.sh tests use a temp dir for
`XDG_CONFIG_HOME`.

### Integration tests

`tests/unit/test-db.sh` uses a real sqlite3 database created in a temp
directory. Covers:
- All four adapter functions against a known schema + data
- Limit/warn behaviour at boundary
- DB path validation (missing file → error)
- Error propagation from invalid SQL

---

## Files changed

| File | Action |
|------|--------|
| `src/json.sh` | Create |
| `src/config.sh` | Create |
| `src/db.sh` | Create |
| `tests/unit/test-json.sh` | Create |
| `tests/unit/test-config.sh` | Create |
| `tests/unit/test-db.sh` | Create |
| `bin/shql` | Modify — source json.sh, config.sh, db.sh in order |
| `.gitignore` | Modify — add `~/.config/shql/.toolrc.local` note (documentation only; path is outside repo) |
