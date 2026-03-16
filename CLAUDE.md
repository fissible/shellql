# ShellQL — Development Guidelines

## What this repo is

ShellQL is a terminal database workbench for SQLite. It is a **consumer** of shellframe,
not a contributor to it. New TUI primitives belong in shellframe; ShellQL-specific
screens and DB integration belong here.

## Architecture rule

```
shellframe (TUI library)  ←  ShellQL sources shellframe.sh
       ↓
ShellQL screens (src/screens/*.sh)
       ↓
SQLite adapter (src/db.sh)  →  sqlite3 binary
```

ShellQL screens must depend on shellframe widget interfaces, not raw terminal calls.

## The adapter seam

All SQLite interaction is routed through `src/db.sh`. No `sqlite3` calls outside
of that file. This makes it possible to swap in a mock adapter for UI development.

Functions in `db.sh` follow the interface:
- `shql_db_list_tables <db_path>` — prints table names, one per line
- `shql_db_describe <db_path> <table>` — prints schema
- `shql_db_fetch <db_path> <table> [limit] [offset]` — prints TSV rows
- `shql_db_query <db_path> <sql>` — prints TSV result + error on stderr

## CLI entry point

`bin/shql` parses arguments and dispatches to the correct screen or mode.
Argument parsing lives entirely in `src/cli.sh`.

## Globals

Application state globals are prefixed `SHQL_`. They must not conflict with
shellframe's `SHELLFRAME_` namespace.

## Coding conventions

Follow shellframe's conventions:
- `printf` not `echo`
- `local` for all function-scoped variables
- bash 3.2 compatible syntax
- UI to `/dev/tty`, data to stdout

## Mock adapter

During UI development, set `SHQL_MOCK=1` to source `src/db_mock.sh` instead of
`src/db.sh`. Mock functions return static fixture data so screens can be built
and tested without a real database.

## Development order

See [PLAN.md](./PLAN.md) for phased build order. In short:
1. Complete shellframe primitives first
2. Build mock screens against mock adapter
3. Wire real sqlite3 adapter last

## Running tests

```bash
bash tests/ptyunit/run.sh          # all suites
bash tests/ptyunit/run.sh --unit   # unit only (no Python needed)
```

Tests live in `tests/unit/test-*.sh` and `tests/integration/test-*.sh`.
Each file sources `tests/ptyunit/assert.sh` and ends with `ptyunit_test_summary`.

## Related

- shellframe: https://github.com/fissible/shellframe
- macbin: https://github.com/fissible/macbin (binary distribution)
