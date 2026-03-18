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
- **Status:** Done — `src/screens/query.sh`; editor 30 % / divider / results grid split; Ctrl-D runs query; Tab cycles editor → results (stops); Shift-Tab reverses; auto-focuses editor on Query tab entry

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

_Last updated: 2026-03-17_

**Phases 5.1–5.5 complete. Phase 5.4 Query screen complete. All mock screens done.**

Completed 2026-03-17 (Phase 5.4 — Query screen, shellql#4):
- `src/screens/query.sh` — state globals, `_shql_query_init`, `_shql_query_run` (TSV parser), `_shql_query_footer_hint`, `_shql_query_on_key`, `_shql_query_render`
- `src/screens/table.sh` — wired Query tab: `_shql_query_render`, `_shql_query_footer_hint`, `_shql_query_on_key` delegation; auto-focus editor on tab entry via `]/[` and focus transition
- `bin/shql` — added `source query.sh`
- `src/db_mock.sh` — updated `shql_db_query` fixture to 3-col/3-row (id/name/email)
- `tests/unit/test-query.sh` — 19 assertions; covers init, run, footer hints, Tab/Shift-Tab cycling, no-results stop
- `shellframe/src/shell.sh` — allow `on_key` handlers to consume Tab/Shift-Tab (backward-compatible); committed to fissible/shellframe main
- Layout: editor 30% / `─` divider / results grid; Ctrl-D runs query; auto-focuses results after run; Tab: editor→results→stop; Shift-Tab: results→editor→tabbar→stop

**Run:** `SHQL_MOCK=1 SHELLFRAME_DIR=/path/to/shellframe bash bin/shql`
**Run from worktree:** `SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe SHQL_MOCK=1 bash .worktrees/feature-query-screen/bin/shql`
**Run tests:** `bash tests/ptyunit/run.sh --unit`
**Test counts:** 62/62 unit assertions pass (2 test-inspector.sh failures are pre-existing submodule path issue in worktree)

**Next task:** Phase 6 — SQLite integration ([shellql#6](https://github.com/fissible/shellql/issues/6), [shellql#7](https://github.com/fissible/shellql/issues/7), [shellql#8](https://github.com/fissible/shellql/issues/8))
- 6.1 Mock adapter cleanup (shql_db_query already done; verify shql_db_fetch, shql_db_list_tables, shql_db_describe)
- 6.2 CLI entry point argument parsing (bin/shql: open, -q, --query, table, pipe, databases modes)
- 6.3 Real sqlite3 adapter (src/db.sh — all four adapter functions with error handling)

**Pending (not ShellQL):** File `docs/shellframe-panel-mode-issue.md` as a GitHub issue at fissible/shellframe
**Pending (branch):** Merge or PR `feature/query-screen` → `main` once tested
