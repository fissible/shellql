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

### 5.4 Query screen — [shellql#4](https://github.com/fissible/shellql/issues/4)
- Multiline text editor (SQL input)
- Results data grid
- Status/error area below
- **Effort:** M (half day)

### 5.5 Record inspector — [shellql#5](https://github.com/fissible/shellql/issues/5) ✓ closed
- Modal or side panel
- Key/value layout from row data
- Scroll for long values
- **Effort:** S (1–2h)
- **Status:** Done — `src/screens/inspector.sh`; Enter on data row → centered "Row Inspector" overlay; ↑/↓/PgUp/PgDn scroll; Esc/Enter/q dismiss

---

## Phase 6: SQLite integration

Wire real sqlite3 behind the adapter seam defined in db.sh.

### 6.1 Mock adapter — [shellql#6](https://github.com/fissible/shellql/issues/6)
- `src/db_mock.sh` with fixture data for all adapter functions
- **Effort:** S (1–2h)

### 6.2 CLI entry point (`bin/shql`) — [shellql#8](https://github.com/fissible/shellql/issues/8)
- Argument parsing for all modes (open, -q, --query, table, pipe, databases)
- **Effort:** M (half day)

### 6.3 SQLite adapter (`src/db.sh`) — [shellql#7](https://github.com/fissible/shellql/issues/7)
- `shql_db_list_tables`
- `shql_db_describe`
- `shql_db_fetch`
- `shql_db_query`
- Error handling and output formatting
- **Effort:** L (1 day)

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

_Last updated: 2026-03-16_

**Phases 5.1–5.3 complete. App navigates welcome → schema → table → schema.**

Completed 2026-03-16 (Phase 5.3):
- `src/screens/table.sh` — TABLE screen; tab bar (Structure/Data/Query); `[`/`]` switch tabs from anywhere; `↓` from tab bar focuses body; `↑` at top of body returns focus to tab bar; q → SCHEMA
- `src/screens/schema.sh` — added `_shql_SCHEMA_sidebar_action`; Enter on table → TABLE
- `src/db_mock.sh` — expanded to 15-column users table and richer fixture data for all 4 tables
- `bin/shql` — sources `table.sh`
- `tests/unit/test-table.sh` — 19/19 assertions passing (34/34 total)

Shellframe bugs fixed and polish applied this session (shellframe repo, not yet committed there):
- `widgets/grid.sh`: H-scroll viewport was `_ncols` (total), making `_max_left=0`; fixed to `_n_vis_cols`
- `widgets/grid.sh`: `_trailing_vis_cols` right-to-left pixel scan ensures last column fully visible at max scroll
- `widgets/grid.sh`: 1-char left padding per cell; right end-of-data `│`/`┘` border when last column in view
- `widgets/grid.sh`: cursor highlight suppressed when grid not focused
- `widgets/tab-bar.sh`: persistent white bar (reverse video) on inactive tabs + fill; active tab bold + clear bg; focused/unfocused style separated
- `src/screens/table.sh`: 1-row gap below tab bar; down-arrow tab→body focus handoff; up-arrow-at-top body→tab focus handoff

**Run:** `SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql`
**Run tests:** `bash tests/ptyunit/run.sh --unit`

**Next task:** Phase 5.5 — Record inspector ([shellql#5](https://github.com/fissible/shellql/issues/5))
- Modal or side panel
- Key/value layout from row data (read grid cursor row)
- Scroll for long values
- Effort: S (1–2h)
- Dependency: Enter on data grid row → `_shql_TABLE_body_action` (hook already in place)

After that: Phase 5.4 — Query screen ([shellql#4](https://github.com/fissible/shellql/issues/4))
