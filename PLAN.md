# ShellQL — Implementation Plan

This plan tracks the phased build-out of ShellQL. Phase 1–4 work primarily in
fissible/shellframe. Phase 5–6 work is ShellQL-specific.

For the full component design rationale, see the shellframe PROJECT.md.

---

## Phase 1–4: Shellframe primitives (tracked in fissible/shellframe)

ShellQL cannot be built until these shellframe components exist:

| Component               | Shellframe Issue | Status  |
|-------------------------|-----------------|---------|
| Component contract      | [#1](https://github.com/fissible/shellframe/issues/1) | open |
| Layout contract         | [#2](https://github.com/fissible/shellframe/issues/2) | open |
| Focus model             | [#3](https://github.com/fissible/shellframe/issues/3) | open |
| Keyboard input module   | [#4](https://github.com/fissible/shellframe/issues/4) | open |
| Selection model         | [#5](https://github.com/fissible/shellframe/issues/5) | open |
| Cursor model            | [#6](https://github.com/fissible/shellframe/issues/6) | open |
| Clipping helpers        | [#7](https://github.com/fissible/shellframe/issues/7) | open |
| Text primitive          | [#8](https://github.com/fissible/shellframe/issues/8) | open |
| Box/Panel               | [#9](https://github.com/fissible/shellframe/issues/9) | open |
| Scroll container        | [#10](https://github.com/fissible/shellframe/issues/10) | open |
| Selectable list         | [#11](https://github.com/fissible/shellframe/issues/11) | open |
| Input field             | [#12](https://github.com/fissible/shellframe/issues/12) | open |
| Tab bar                 | [#13](https://github.com/fissible/shellframe/issues/13) | open |
| Modal/dialog            | [#14](https://github.com/fissible/shellframe/issues/14) | open |
| Tree view               | [#15](https://github.com/fissible/shellframe/issues/15) | open |
| Text editor             | [#16](https://github.com/fissible/shellframe/issues/16) | open |
| Data grid               | [#17](https://github.com/fissible/shellframe/issues/17) | open |
| App shell               | [#18](https://github.com/fissible/shellframe/issues/18) | open |

---

## Phase 5: ShellQL mock screens

Build with fake data (SHQL_MOCK=1) to validate the framework before any SQLite work.

### 5.1 Welcome screen — [shellql#1](https://github.com/fissible/shellql/issues/1)
- Recent files list (selectable list)
- Open database action
- Empty state message
- **Effort:** M (half day)

### 5.2 Schema browser — [shellql#2](https://github.com/fissible/shellql/issues/2)
- Sidebar: tree view of tables/views/indexes
- Main pane: selected object DDL/details
- **Effort:** M (half day)

### 5.3 Table view — [shellql#3](https://github.com/fissible/shellql/issues/3)
- Tab bar: Structure / Data / Query
- Data tab: data grid with mock rows
- Structure tab: schema text
- **Effort:** L (1 day)

### 5.4 Query screen — [shellql#4](https://github.com/fissible/shellql/issues/4)
- Multiline text editor (SQL input)
- Results data grid
- Status/error area below
- **Effort:** M (half day)

### 5.5 Record inspector — [shellql#5](https://github.com/fissible/shellql/issues/5)
- Modal or side panel
- Key/value layout from row data
- Scroll for long values
- **Effort:** S (1–2h)

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

**Repo is stub-stage. src/, bin/ empty. Test infrastructure wired up.**

Completed 2026-03-16:
- Added `tests/ptyunit` as git submodule (fissible/ptyunit, commit d683b90)
- Added `tests/run.sh` — shellql-level runner discovering tests/unit/ and tests/integration/
- Added `tests/unit/test-stub.sh` — placeholder (1/1 passes)
- Committed and pushed in `76bf2a3`

**Blocked on:** fissible/shellframe Phase 1–4 (shellframe primitives). ShellQL cannot be built until those shellframe issues are closed.

**Next task:** Once shellframe primitives are available, begin Phase 5 — mock screens starting with the welcome screen (shellql#1).

**Decision:** shellql's test runner is `tests/run.sh` (not `tests/ptyunit/run.sh`) because ptyunit's own `run.sh` discovers tests relative to itself. The wrapper pattern is the right approach for submodule consumers.
