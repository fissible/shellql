# ShellQL — Implementation Plan

This plan tracks the phased build-out of ShellQL. Phase 1–4 work primarily in
fissible/shellframe. Phase 5–6 work is ShellQL-specific.

For the full component design rationale, see the shellframe PROJECT.md.

---

## Phase 1–4: Shellframe primitives (tracked in fissible/shellframe)

ShellQL cannot be built until these shellframe components exist:

| Component               | Shellframe Issue | Status  |
|-------------------------|-----------------|---------|
| Component contract      | #TBD            | open    |
| Layout contract         | #TBD            | open    |
| Focus model             | #TBD            | open    |
| Text primitive          | #TBD            | open    |
| Box/Panel               | #TBD            | open    |
| Scroll container        | #TBD            | open    |
| Selectable list         | #TBD            | open    |
| Tree view               | #TBD            | open    |
| Input field             | #TBD            | open    |
| Text editor             | #TBD            | open    |
| Data grid               | #TBD            | open    |
| Tab bar                 | #TBD            | open    |
| Modal/dialog            | #TBD            | open    |
| Keyboard input module   | #TBD            | open    |
| Selection model         | #TBD            | open    |
| Cursor model            | #TBD            | open    |
| Clipping helpers        | #TBD            | open    |
| App shell               | #TBD            | open    |

---

## Phase 5: ShellQL mock screens

Build with fake data (SHQL_MOCK=1) to validate the framework before any SQLite work.

### 5.1 Welcome screen
- Recent files list (selectable list)
- Open database action
- Empty state message
- **Effort:** M (half day)

### 5.2 Schema browser
- Sidebar: tree view of tables/views/indexes
- Main pane: selected object DDL/details
- **Effort:** M (half day)

### 5.3 Table view
- Tab bar: Structure / Data / Query
- Data tab: data grid with mock rows
- Structure tab: schema text
- **Effort:** L (1 day)

### 5.4 Query screen
- Multiline text editor (SQL input)
- Results data grid
- Status/error area below
- **Effort:** M (half day)

### 5.5 Record inspector
- Modal or side panel
- Key/value layout from row data
- Scroll for long values
- **Effort:** S (1–2h)

---

## Phase 6: SQLite integration

Wire real sqlite3 behind the adapter seam defined in db.sh.

### 6.1 CLI entry point (`bin/shql`)
- Argument parsing for all modes (open, -q, --query, table, pipe, databases)
- **Effort:** M (half day)

### 6.2 SQLite adapter (`src/db.sh`)
- `shql_db_list_tables`
- `shql_db_describe`
- `shql_db_fetch`
- `shql_db_query`
- Error handling and output formatting
- **Effort:** L (1 day)

### 6.3 Discovery mode
- List recent/known databases
- Resolve database path from name
- **Effort:** S (1–2h)

### 6.4 Integration tests
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
