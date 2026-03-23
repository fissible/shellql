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

### 6.4 Discovery mode ✓ done
- Connection registry backed by `$SHQL_DATA_DIR/shellql.db`
- `src/connections.sh`: `shql_conn_init`, `shql_conn_push`, `shql_conn_migrate`, `shql_conn_list`, `shql_conn_load_recent`
- sigil aggregation (graceful no-op until `sigil list --type database --porcelain` is available)
- **Effort:** L (1 day actual)

### 6.5 Integration tests — [shellql#9](https://github.com/fissible/shellql/issues/9) ✓ done
- Real sqlite3 round-trips
- All CLI modes
- **Effort:** M (half day)
- **Status:** Done — `tests/integration/test-integration.sh`; 19 assertions (query-out, pipe, databases round-trip, error paths)

### 6.6 Name resolution — [shellql#10](https://github.com/fissible/shellql/issues/10) ✓ done
- `shql_conn_resolve_name` in `src/connections.sh`
- Pre-dispatch guard in `bin/shql`
- **Effort:** S (1–2h)
- **Status:** Done — 9 unit assertions added to `tests/unit/test-connections.sh`

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

_Last updated: 2026-03-23_

**v0.3.0 released. Phases 6.1–6.6 complete. M3 milestone (ShellQL v0.1 alpha) reached — 226/226 assertions passing.**

Completed 2026-03-22 (Phase 6.1):
- `src/db_mock.sh` — fixture data for all adapter functions (`shql_mock_load_recent`, `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query`)

Completed 2026-03-22 (Phase 6.2):
- `src/cli.sh` — `shql_cli_parse` (7-mode arg resolution: welcome/open/table/query-tui/query-out/pipe/databases); `shql_cli_format_table` (MySQL-style box output); idempotency guard; pipe detection via `[ -p /dev/stdin ]`
- `bin/shql` — Sources `cli.sh`; replaces stub parser + dispatch with full 7-mode `case` statement; TTY probe (`exec 9>/dev/tty`) with `/dev/stderr` fallback for non-TUI error routing
- `tests/unit/test-cli.sh` — 42 assertions (35 parser + 7 formatter)

Completed 2026-03-22 (Phase 6.3):
- `src/json.sh` — JSON get/set backed by `sqlite3 :memory:`; idempotency guard
- `src/config.sh` — Config read/write via json.sh; two-tier `fetch_limit` default (1000 no-file / 500 key-absent); sqlite3 detection guard
- `src/db.sh` — Real SQLite adapter: `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query`; DB path validation; row buffering + truncation warning; SELECT wrapping
- `tests/unit/test-json.sh`, `tests/unit/test-config.sh` — PATH-stub sqlite3; 20 unit tests
- `tests/integration/test-db.sh` — Real sqlite3, 24 integration tests

Also 2026-03-22:
- `tests/fixtures/demo.sqlite` — test database matching mock schema (users, orders, products, categories)
- shellframe#24 (windowed panel mode) — implemented and merged to shellframe main; issue closed

Completed 2026-03-22 (Phase 6.4 — branch `feature/phase-6.4-discovery`):
- `src/connections.sh` — full connection registry: `shql_conn_init` (schema bootstrap, shellql.db), `shql_conn_push` (id-preserving upsert + last_accessed update), `shql_conn_migrate` (one-time flat-file migration), `shql_conn_list` (local + sigil aggregate, sorted by last_used), `shql_conn_load_recent` (populates SHQL_RECENT_* arrays)
- `src/db_mock.sh` — extended `shql_mock_load_recent` to populate SHQL_RECENT_NAMES/DETAILS/SOURCES/REFS
- `src/state.sh` — removed old `shql_state_load_recent`, `shql_state_push_recent`, `SHQL_HISTORY_FILE`, `SHQL_RECENT_MAX`; added 4 new SHQL_RECENT_* array globals
- `bin/shql` — sources connections.sh; calls shql_conn_init + shql_conn_migrate at startup; replaces shql_state_push_recent with shql_conn_push; databases dispatch now shows 5-column table with header
- `src/screens/welcome.sh` — uses SHQL_RECENT_NAMES for display; resolves path via connections.id (local) or sigil (sigil source) on Enter
- `tests/unit/test-connections.sh` — 30 unit tests covering all 5 public functions
- `tests/integration/test-connections.sh` — 5 integration tests (push/list/sort/dedup round-trips)
- **Total: 174/174 assertions passing (169 unit + 5 integration)**
- **Cross-repo dependency:** `sigil list --type database --porcelain` not yet implemented; graceful no-op until added

**Run (real mode):** `SHELLFRAME_DIR=../shellframe bash bin/shql tests/fixtures/demo.sqlite`
**Run (query):** `SHELLFRAME_DIR=../shellframe bash bin/shql tests/fixtures/demo.sqlite -q "SELECT * FROM users"`
**Run (databases):** `SHELLFRAME_DIR=../shellframe bash bin/shql databases`
**Run tests:** `SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh`

Completed 2026-03-22 (Phase 6.5):
- `tests/integration/test-integration.sh` — 19 assertions: query-out (exit 0, formatted table + Alice, porcelain), pipe (exit 0 + data, porcelain), databases round-trip (path appears, porcelain variant), error paths (missing DB file, bad SQL)
- ptyunit submodule updated to v1.0.0
- **Total: 217/217 assertions passing (198 unit + 19 integration)**

Completed 2026-03-23 (Phase 6.6):
- `src/connections.sh` — `shql_conn_resolve_name`: loops `SHQL_RECENT_DETAILS`/`SHQL_RECENT_SOURCES`, three basename-matching rules (exact, strip `.sqlite`, strip `.db`), local-source-only gate
- `bin/shql` — pre-dispatch resolution block: fires when `_SHQL_CLI_DB` is set but not an existing file, skips in mock mode
- `tests/unit/test-connections.sh` — 9 new assertions (6 test cases)
- **Total: 226/226 assertions passing (187 unit + 39... see below)**

**Cross-repo:** `sigil list --type database --porcelain` — filed as [fissible/sigil-workspace#16](https://github.com/fissible/sigil-workspace/issues/16). ShellQL gracefully no-ops until this lands.

**Follow-up tickets (self-nominated):**
- UI fixes — data tab perf, row highlight, focus indicators, query tab layout

**Next task:** PM decision — v0.1.0 alpha release or UI polish first.
