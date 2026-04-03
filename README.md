# ShellQL

A terminal database workbench for SQLite, built on [shellframe](https://github.com/fissible/shellframe).

Browse schemas, query data, insert/edit/delete rows, sort, filter, and export
-- all from your terminal. Pure bash, no dependencies beyond `sqlite3`.

## Installation

```bash
# Homebrew (recommended)
brew tap fissible/tap
brew install shellql
```

```bash
# From source
git clone https://github.com/fissible/shellql
git clone https://github.com/fissible/shellframe  # sibling directory
cd shellql
bash bootstrap.sh   # installs ptyunit (test runner) via Homebrew
```

### Requirements

- bash 3.2+ (macOS compatible)
- sqlite3
- [shellframe](https://github.com/fissible/shellframe) (sibling checkout or `SHELLFRAME_DIR`)

## Usage

```bash
shql my.db                        # Open a database in the browser
shql my.db users                  # Jump straight to a table
shql my.db --query                # Open with a blank SQL query tab
shql my.db -q "SELECT * FROM users LIMIT 10"   # Run a query and exit
cat query.sql | shql my.db        # Pipe SQL from stdin
shql databases                    # List known/recent databases
shql --help                       # Full usage reference
```

### Non-interactive output

By default, `-q` and pipe modes print MySQL-style box tables:

```
+----+-------+-------------------+
| id | name  | email             |
+----+-------+-------------------+
| 1  | Alice | alice@example.com |
| 2  | Bob   | bob@example.com   |
+----+-------+-------------------+
```

Add `--porcelain` for machine-readable TSV output.

## Features

### Schema browser

Sidebar lists all tables and views. Select one to see its columns, types,
constraints, and full DDL.

### Data browser

Tabbed interface -- open multiple tables and query tabs simultaneously.
Scrollable data grid with automatic column alignment (right-align numbers,
center booleans).

### Query editor

Multiline SQL editor with a results grid below. Ctrl-D executes. Errors
display inline. Each query tab maintains its own SQL and result state.

### Row inspector

Press Enter on any data row to open a full key/value view with word-wrapped
values -- useful for TEXT and JSON columns that don't fit in the grid.

### DML operations

- `i` -- Insert a new row (form with column types and constraints)
- `e` -- Edit the selected row
- `d` -- Delete the selected row (with confirmation)
- `T` -- Truncate table (with confirmation)

### DDL operations

- Create table (SQL template opened in query tab)
- Drop table/view (with confirmation)

### Filtering and sorting

- `f` -- Add a WHERE filter (supports `=`, `!=`, `LIKE`, `IN`, `BETWEEN`, and more)
- Click or Enter on column headers to toggle ORDER BY (ASC/DESC)
- Multiple filters stack as AND conditions, shown as pills below the tab bar

### Export

- `x` -- Export the current data or query result as CSV (RFC 4180) or SQL dump
- Tab to toggle format, Enter to execute

### Connection registry

ShellQL remembers recently opened databases. The welcome screen shows them as
a tile grid with file size and table count metadata. Named connections are
stored in `~/.local/share/shellql/shellql.db`.

## Themes

```bash
SHQL_THEME=basic   shql my.db   # Default: reverse-video header, single borders
SHQL_THEME=cascade shql my.db   # Dark purple header, gray content, alternating stripes
SHQL_THEME=uranium shql my.db   # Neon green header, rounded borders, cyan values
```

## Architecture

```
bin/shql                 CLI entry point + mode dispatch
src/
  cli.sh                 Argument parsing, box-table formatter
  connections.sh         Connection registry (SQLite-backed)
  db.sh                  SQLite adapter (list, describe, fetch, query)
  db_mock.sh             Mock adapter for UI development
  config.sh              User configuration
  state.sh               Application globals
  theme.sh               Theme loader
  themes/
    basic.sh             Default theme
    cascade.sh           Dark purple theme
    uranium.sh           Neon green theme
  screens/
    welcome.sh           Recent files tile grid
    table.sh             Main browser (sidebar + tabs + content)
    query.sh             SQL editor + results grid
    inspector.sh         Row detail key/value view
    dml.sh               Insert/edit/delete/truncate overlays
    where.sh             WHERE filter overlay + pills
    sort.sh              Column sort state + header overlay
    export.sh            CSV/SQL dump export overlay
    header.sh            App header bar
    util.sh              Shared screen utilities
```

The UI depends entirely on shellframe widget interfaces -- no raw terminal
calls in ShellQL itself. All rendering goes through shellframe's framebuffer.

## Running tests

```bash
bash bootstrap.sh                              # first time: install ptyunit
SHELLFRAME_DIR=../shellframe bash tests/run.sh          # all tests
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit   # unit only
```

## License

MIT
