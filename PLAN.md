# ShellQL — Implementation Plan

This plan tracks the phased build-out of ShellQL. Phase 1–4 work primarily in
fissible/shellframe. Phase 5–6 work is ShellQL-specific.

For the full component design rationale, see the shellframe PROJECT.md.

---

## Phase 1–4: Shellframe primitives (tracked in fissible/shellframe)

ShellQL cannot be built until these shellframe components exist:

| Component               | Shellframe Issue | Status  |
|-------------------------|-----------------|---------|
| Component contract      | [#1](https://github.com/fissible/shellframe/issues/1) | ✓ closed |
| Layout contract         | [#2](https://github.com/fissible/shellframe/issues/2) | ✓ closed |
| Focus model             | [#3](https://github.com/fissible/shellframe/issues/3) | ✓ closed |
| Keyboard input module   | [#4](https://github.com/fissible/shellframe/issues/4) | ✓ closed |
| Selection model         | [#5](https://github.com/fissible/shellframe/issues/5) | ✓ closed |
| Cursor model            | [#6](https://github.com/fissible/shellframe/issues/6) | ✓ closed |
| Clipping helpers        | [#7](https://github.com/fissible/shellframe/issues/7) | ✓ closed |
| Text primitive          | [#8](https://github.com/fissible/shellframe/issues/8) | ✓ closed |
| Box/Panel               | [#9](https://github.com/fissible/shellframe/issues/9) | ✓ closed |
| Scroll container        | [#10](https://github.com/fissible/shellframe/issues/10) | ✓ closed |
| Selectable list         | [#11](https://github.com/fissible/shellframe/issues/11) | ✓ closed |
| Input field             | [#12](https://github.com/fissible/shellframe/issues/12) | ✓ closed |
| Tab bar                 | [#13](https://github.com/fissible/shellframe/issues/13) | ✓ closed |
| Modal/dialog            | [#14](https://github.com/fissible/shellframe/issues/14) | ✓ closed |
| Tree view               | [#15](https://github.com/fissible/shellframe/issues/15) | open |
| Text editor             | [#16](https://github.com/fissible/shellframe/issues/16) | open |
| Data grid               | [#17](https://github.com/fissible/shellframe/issues/17) | open |
| App shell               | [#18](https://github.com/fissible/shellframe/issues/18) | ✓ closed |

---

## Phase 5: ShellQL mock screens

Build with fake data (SHQL_MOCK=1) to validate the framework before any SQLite work.

### 5.1 Welcome screen — [shellql#1](https://github.com/fissible/shellql/issues/1) ✓ closed
- Recent files list (selectable list)
- Open database action
- Empty state message
- **Effort:** M (half day)
- **Status:** Done — `src/screens/welcome.sh`, `src/state.sh`, `src/db_mock.sh`, `bin/shql` (minimal)

### 5.2 Schema browser — [shellql#2](https://github.com/fissible/shellql/issues/2) ✓ closed
- Sidebar: tree view of tables/views/indexes
- Main pane: selected object DDL/details
- **Effort:** M (half day)
- **Status:** Done — `src/screens/schema.sh`; Tab switches panes, q returns to welcome

### 5.3 Table view — [shellql#3](https://github.com/fissible/shellql/issues/3) ✓ closed
- Tab bar: Structure / Data / Query
- Data tab: data grid with mock rows
- Structure tab: schema DDL text (scrollable)
- Query tab: placeholder ("coming in Phase 5.4")
- **Effort:** L (1 day)
- **Status:** Done — `src/screens/table.sh`; Enter on schema table → TABLE; q → SCHEMA

### 5.4 Query screen — [shellql#4](https://github.com/fissible/shellql/issues/4) ✓ closed
- Multiline text editor (SQL input)
- Results data grid
- Status/error area below
- **Effort:** M (half day)
- **Status:** Done — `src/screens/query.sh`; Ctrl-D runs SQL, results grid appears, Tab switches panes, Esc/q returns to tab bar

### 5.5 Record inspector — [shellql#5](https://github.com/fissible/shellql/issues/5) ✓ closed
- Modal or side panel
- Key/value layout from row data
- Scroll for long values
- **Effort:** S (1–2h)
- **Status:** Done — `src/screens/inspector.sh`; Enter on data row → centered "Row Inspector" overlay; ↑/↓/PgUp/PgDn scroll; Esc/Enter/q dismiss

---

## Phase 6: SQLite integration

Wire real sqlite3 behind the adapter seam defined in db.sh.

### 6.1 Mock adapter — [shellql#6](https://github.com/fissible/shellql/issues/6) ✓ done
- `src/db_mock.sh` with fixture data for all adapter functions
- **Effort:** S (1–2h)
- **Status:** Done — `src/db_mock.sh`; implements `shql_mock_load_recent`, `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query` with fixture data

### 6.2 CLI entry point (`bin/shql`) — [shellql#8](https://github.com/fissible/shellql/issues/8) ✓ done
- Argument parsing for all modes (open, -q, --query, table, pipe, databases)
- **Effort:** M (half day)
- **Status:** Done — `src/cli.sh` (`shql_cli_parse` + `shql_cli_format_table`), `bin/shql` (7-mode dispatch), `tests/unit/test-cli.sh` (42 assertions)

### 6.3 SQLite adapter (`src/db.sh`) — [shellql#7](https://github.com/fissible/shellql/issues/7) ✓ done
- `shql_db_list_tables`
- `shql_db_describe`
- `shql_db_fetch`
- `shql_db_query`
- Error handling and output formatting
- **Effort:** L (1 day)
- **Status:** Done — `src/json.sh`, `src/config.sh`, `src/db.sh`, unit + integration tests

### 6.4 Discovery mode
- List recent/known databases
- Resolve database path from name
- **Effort:** S (1–2h)

### 6.5 Integration tests — [shellql#9](https://github.com/fissible/shellql/issues/9)
- Real sqlite3 round-trips
- All CLI modes
- **Effort:** M (half day)

---

## Dependency graph

```
shellframe primitives (P1–P4)
       │
       ├── Mock screens (P5) ─────→ validate framework
       │
       └── SQLite adapter (P6.2)
               │
               └── CLI entry point (P6.1) + Discovery (P6.3)
                          │
                          └── Integration tests (P6.4)
```

---

## Milestone targets

| Milestone                       | Condition                                        |
|---------------------------------|--------------------------------------------------|
| M1: Shellframe ready for ShellQL | All Phase 1–4 shellframe issues closed           |
| M2: Mock app complete           | All Phase 5 screens working with mock adapter    |
| M3: ShellQL v0.1 alpha          | Phase 6 complete; all integration tests passing  |

---

## Session handoff notes
> Update this section at the end of each session.

_Last updated: 2026-03-22_

**Phase 6.2 (CLI entry point) complete. UI issues filed. Phase 6.4 Discovery mode or UI fixes are next.**

Completed 2026-03-22 (Phase 6.2):
- `src/cli.sh` — `shql_cli_parse` (7-mode arg resolution: welcome/open/table/query-tui/query-out/pipe/databases); `shql_cli_format_table` (MySQL-style box output); idempotency guard; pipe detection via `[ -p /dev/stdin ]`
- `bin/shql` — Sources `cli.sh`; replaces stub parser + dispatch with full 7-mode `case` statement; TTY probe (`exec 9>/dev/tty`) with `/dev/stderr` fallback for non-TUI error routing
- `tests/unit/test-cli.sh` — 42 assertions (35 parser + 7 formatter)
- **Total: 143/143 assertions passing**

Completed 2026-03-22 (Phase 6.3):
- `src/json.sh` — JSON get/set backed by `sqlite3 :memory:`; idempotency guard
- `src/config.sh` — Config read/write via json.sh; two-tier `fetch_limit` default (1000 no-file / 500 key-absent); sqlite3 detection guard
- `src/db.sh` — Real SQLite adapter: `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query`; DB path validation; row buffering + truncation warning; SELECT wrapping
- `tests/unit/test-json.sh`, `tests/unit/test-config.sh` — PATH-stub sqlite3; 20 unit tests
- `tests/integration/test-db.sh` — Real sqlite3, 24 integration tests

Also 2026-03-22:
- `.gitignore` — added `.superpowers/`
- `tests/fixtures/` — added `demo.sqlite` + `.gitkeep`
- UI issues filed on GitHub (shellql): data tab row nav perf, row highlight rendering, focus visibility / tab order, query tab layout

**Run (mock):** `SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql`
**Run (real):** `SHELLFRAME_DIR=../shellframe bash bin/shql path/to/db.sqlite`
**Run (query):** `SHELLFRAME_DIR=../shellframe bash bin/shql db.sqlite -q "SELECT 1"`
**Run tests:** `SHELLFRAME_DIR=/path/to/shellframe bash tests/ptyunit/run.sh --unit`

**Next task (choose one):**
- Phase 6.4 — Discovery mode — list recent/known databases, resolve path from name
- UI fixes — data tab perf, row highlight, focus indicators, query tab layout (shellql issues filed 2026-03-22)

**Pending (not ShellQL):** [fissible/shellframe#24](https://github.com/fissible/shellframe/issues/24) — Panel rendering modes: add `windowed` mode with dedicated title bar row
