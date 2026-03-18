# ShellQL

A terminal database workbench for SQLite, built on [shellframe](https://github.com/fissible/shellframe).

## Usage

```bash
# Open a database interactively
shql my.db

# Run a quick query and exit
shql my.db -q "SELECT * FROM users LIMIT 10"

# Open in query/REPL mode
shql my.db --query

# Open directly to a table view
shql my.db users

# Pipe a SQL file
cat query.sql | shql my.db

# Discovery mode — list known/recent databases
shql databases
```

## Installation

```bash
# From source
git clone https://github.com/fissible/shellql
cd shellql
./install.sh
```

The `shql` binary is also distributed via [fissible/macbin](https://github.com/fissible/macbin).

## Requirements

- bash 3.2+ (macOS compatible)
- sqlite3
- [shellframe](https://github.com/fissible/shellframe) (bundled or sourced)

## Themes

Set `SHQL_THEME` before launching to choose a colour scheme:

```bash
SHQL_THEME=uranium shql my.db   # neon green header, rounded borders, cyan values
SHQL_THEME=basic   shql my.db   # default: reverse-video header, single borders
```

Available themes: `basic` (default), `uranium`.

## Architecture

ShellQL is a thin application layer on top of shellframe's TUI primitives:

```
shql (CLI entry point)
└── src/
    ├── cli.sh        # argument parsing, mode dispatch
    ├── db.sh         # sqlite3 adapter (list tables, run query, describe, fetch rows)
    ├── screens/      # shellframe_app screen definitions
    │   ├── welcome.sh
    │   ├── schema.sh
    │   ├── table.sh   # Structure / Data / Query tabs
    │   ├── query.sh   # SQL editor + results grid (Query tab)
    │   └── inspector.sh  # row inspector overlay
    └── state.sh      # application globals
```

The UI depends entirely on shellframe interfaces — no raw tput/stty calls in ShellQL itself.

## Development (mock mode)

All screens can be exercised without a real database:

```bash
SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```

## Status

All mock screens complete (Phases 5.1–5.5): welcome, schema browser, table view
(Structure / Data / Query tabs), row inspector. SQLite integration is Phase 6.

See [PLAN.md](./PLAN.md) for the roadmap.
