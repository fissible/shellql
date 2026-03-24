# ShellQL Browser Redesign — Design Spec

**Date:** 2026-03-24
**Status:** Approved for implementation
**Replaces:** shellql#12, #16, #17, #18, #19 (partially superseded by this broader redesign)

---

## Motivation

The current WELCOME → SCHEMA → TABLE navigation chain has several problems:

- The SCHEMA screen is a dead end — it requires navigating away to open a table.
- The TABLE screen's static "Structure / Data / Query" tabs cannot be extended or reordered.
- The record inspector is a slow modal overlay with no padding and no record navigation.
- The SCHEMA columns pane was added but is unreachable (nofocus) and has a rendering bug.
- Arrow keys do not move focus between panes; only Tab works.

This redesign evolves the TABLE screen into a persistent browser with a sidebar and dynamic tabs. It reuses all existing shellframe widgets — no widget rewrites.

---

## Strategic context

- shellql is a shellframe demo. Reusing widgets showcases shellframe's composability.
- Phase 10 rewrites in Rust/Go. This bash version proves the UX model; avoid over-engineering.
- The sidebar is the future connection aggregation surface (sigil#16). Option 2 builds that structure now.

---

## What changes

| Component | Before | After |
|-----------|--------|-------|
| SCHEMA screen | Standalone screen | Retired; replaced by Schema tab type |
| TABLE screen | Static 3-tab layout | Persistent browser with sidebar + dynamic tabs |
| Record inspector | Modal overlay, no padding | Inline content-area view with nav bar + padding |
| SCHEMA columns pane | nofocus, sometimes empty | Scrollable, focusable pane inside Schema tab |
| Tab switching | Tab key only | Tab + spatial arrow keys at pane boundaries |
| Query results placeholder | "Press [Enter] to type SQL" | "No results yet" |

---

## Layout

Five regions, always present once a database is open:

```
┌─ header ─────────────────────────────────────────────────────┐
│  breadcrumb: sqlite://chinook.sqlite                         │
├─ sidebar ──────────┬─ tabbar ───────────────────────────────┤
│  Tables            │  users·Data  │  orders·Schema  │  +SQL  │
│  ─────────────     ├─────────────────────────────────────── │
│  ▶ users           │                                         │
│    orders          │         (active tab content)            │
│    products        │                                         │
│    categories      │                                         │
├────────────────────┴─────────────────────────────────────────┤
│  footer: key hints                                           │
└──────────────────────────────────────────────────────────────┘
```

- **Header** (row 1, cols 1–W, nofocus): breadcrumb — `sqlite://dbname` or `host/dbname`
- **Sidebar** (rows 2–N-1, cols 1–`sidebar_w`, focusable): scrollable tables list, width ≈ 1/4 terminal
- **Tab bar** (row 2, cols `sidebar_w+1`–W, focusable): dynamic tabs + `+SQL` affordance at right end
- **Content** (rows 3–N-1, cols `sidebar_w+1`–W, focusable): renders the active tab
- **Footer** (row N, cols 1–W, nofocus): context-sensitive key hints

The sidebar spans the full body height. The tab bar and content share the right portion, with the tab bar consuming row 2 and content occupying rows 3 onwards.

---

## Tab model

### State globals (in `table.sh`)

```bash
_SHQL_TABS_TYPE=()    # "data" | "schema" | "query"
_SHQL_TABS_TABLE=()   # table name; empty for query tabs
_SHQL_TABS_LABEL=()   # display label: "users·Data", "Query 1"
_SHQL_TABS_CTX=()     # unique context id: "t0", "t1", …
_SHQL_TAB_ACTIVE=-1   # index of active tab (-1 = no tabs open)
_SHQL_TAB_CTX_SEQ=0   # ever-incrementing context id counter
_SHQL_TAB_QUERY_N=0   # ever-incrementing query label counter
```

### Context id namespacing

Each tab's context id prefixes all its shellframe widget contexts:

| Tab type | Widget contexts used |
|----------|---------------------|
| data | `<ctx>_grid` |
| schema | `<ctx>_ddl`, `<ctx>_cols` |
| query | `<ctx>_editor`, `<ctx>_results` |

This prevents state collision when multiple tabs are open simultaneously.

### Lifecycle

- **Open:** `_shql_tab_open <table> <type>` — searches for an existing tab matching `(table, type)`; if found, switches to it; if not, creates a new one (allocates next ctx id, initialises widget contexts, appends to arrays).
- **Close:** `_shql_tab_close [index]` — removes the tab from arrays, switches to the tab on the left (or clears to empty state if none remain). Widget contexts are reset on next open.
- **Dedup:** Opening an already-open tab switches to it silently. No duplicates.
- **Query tabs:** Always create a new tab (no dedup). Label is `Query N` where N is `_SHQL_TAB_QUERY_N` (ever-incrementing, never reused).

### Tab bar capacity

The tab bar renders as many tabs as fit in `terminal_cols − sidebar_w` columns. When a new tab would overflow:

- Footer flashes: `Tab bar full — close a tab first (w)`
- Tab is not opened

On terminal resize narrower: active tab is always visible; tabs that don't fit are hidden from the bar but remain in the arrays. They reappear when the terminal widens.

### Empty state

When `_SHQL_TAB_ACTIVE == -1` (no tabs open), the content area shows:

```
↑↓ select a table · Enter = Data · s = Schema · n = New query
```

---

## Per-tab content

### Data tab

- Grid widget, same as current `_SHQL_TABLE_TAB_DATA` implementation
- Fill-width last column (`_shql_grid_fill_width`)
- Column alignment detection (`_shql_detect_grid_align`)
- Row-range footer hint (`Rows X–Y of Z`)
- `Enter` on a row → record inspector (see below)
- Empty table: centered `(empty table)` placeholder

### Schema tab

Two panes side-by-side inside the content area, both scrollable and focusable:

```
┌─ Columns ──────────────┬─ DDL ─────────────────────────────┐
│ id        INTEGER  PK  │ CREATE TABLE users (               │
│ name      TEXT     NN  │   id    INTEGER PRIMARY KEY,       │
│ email     TEXT         │   name  TEXT NOT NULL,             │
│ …                      │   …                                │
└────────────────────────┴───────────────────────────────────┘
```

- **Columns pane** (~40% of content width): scrollable list of `name  type  flags` rows. Focusable. `↑↓` to scroll.
- **DDL pane** (~60% of content width): raw DDL text, scrollable. Focusable. `↑↓` to scroll.
- Focus cycle within schema tab: columns → DDL → (Tab exits to sidebar)
- Data is loaded once on tab open; reloads if the tab is re-opened for a different table.

### Query tab

- SQL editor pane (top 30% of content) + Results grid pane (bottom 70%)
- **Fix:** `Enter` on the editor panel in button state activates typing — no Tab-first required
- **Fix:** Results placeholder text is `No results yet` (not "Press Enter to type SQL")
- `Ctrl-D` runs the query; results appear in the grid pane
- `_shql_detect_grid_align` applied to results after each run
- Multiple Query tabs can coexist with independent editor and results state

---

## Record inspector

Triggered by `Enter` on any data grid row. Replaces the grid in the content area (no overlay):

```
┌─ users·Data ───────────────────────────────────────────────┐
│  ← Alice  (row 3 of 200) →                                 │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  id          1              │  role        user            │
│  name        Alice          │  verified    1               │
│  email       al@example…    │  created_at  2026-03-22      │
│  phone       +1-555-0101    │  updated_at  2026-03-23      │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

- **Nav bar** (first inner row): `← <first-col-value>  (row N of Total) →`
- **`←` / `→`**: step to previous/next row; wraps at ends
- **1-char padding** on all inner sides (top, bottom, left, right)
- **Two-column key/value layout** (as today)
- **Scrollable** when record has more fields than the content area height
- **`Esc`**: return to grid; cursor lands on the row that was being inspected
- **`Tab`**: close inspector and cycle focus to sidebar
- State is per active data tab (global inspector globals reset on tab switch)

### Performance

The inspector dismiss lag (shellql#18) was already addressed by the shellframe grid inline render optimisation (commit `444726b`). The new inline-content model eliminates the overlay redraw cost entirely.

---

## Keyboard model

### Focus regions

Focus cycles: **sidebar → tab bar → content → sidebar** (Tab forward, Shift-Tab backward).

### Sidebar

| Key | Action |
|-----|--------|
| `↑` / `↓` | Move table cursor |
| `Enter` | Open / switch to Data tab for selected table |
| `s` | Open / switch to Schema tab for selected table |
| `→` | Move focus to content (tab bar if no tabs open) |
| `Tab` | Cycle focus to tab bar |

### Tab bar

| Key | Action |
|-----|--------|
| `←` / `→` | Switch active tab |
| `↓` / `Enter` | Move focus to content |
| `w` | Close active tab |
| `n` | Open new Query tab |
| `Tab` / `Shift-Tab` | Cycle focus |

### Content — grid

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate rows; `↑` at row 0 → focus moves to tab bar |
| `←` / `→` | Scroll columns; `←` at column 0 → focus moves to sidebar |
| `Enter` | Open record inspector |
| `[` / `]` | Switch active tab |
| `Tab` | Cycle focus to sidebar |

### Content — record inspector

| Key | Action |
|-----|--------|
| `←` / `→` | Previous / next record |
| `↑` / `↓` | Scroll fields |
| `Esc` | Return to grid, cursor on inspected row |
| `Tab` | Close inspector, cycle focus to sidebar |

### Content — schema tab

| Key | Action |
|-----|--------|
| `↑` / `↓` | Scroll focused pane |
| `Tab` | Cycle: columns → DDL → (exit to sidebar) |
| `Shift-Tab` | Reverse |

### Content — query tab (button state)

| Key | Action |
|-----|--------|
| `Enter` | Activate editor typing |
| `Tab` | Cycle to results pane |

### Content — query tab (typing state)

| Key | Action |
|-----|--------|
| `Ctrl-D` | Run query |
| `Esc` | Deactivate editor (return to button state) |

### Global

| Key | Action |
|-----|--------|
| `q` | Back to Welcome screen (closes all tabs) |
| `n` | New Query tab (when not in editor typing state) |
| `w` | Close active tab (when not in editor typing state) |

---

## Architecture changes

### Files removed

- `src/screens/schema.sh` — retired as a standalone screen. Schema tab rendering moves inline into the content dispatch in `table.sh`.

### Files changed significantly

**`src/screens/table.sh`** — primary change surface:
- Replace `_SHQL_TABLE_TAB_STRUCTURE/DATA/QUERY` static tab constants with dynamic tab arrays
- Add `_shql_tab_open`, `_shql_tab_close`, `_shql_tab_find` functions
- Add dynamic tab bar renderer (replaces shellframe static tabbar widget)
- Add sidebar region with tables list (moved from `schema.sh`)
- Content dispatch routes to data/schema/query renderer based on `_SHQL_TABS_TYPE[$_SHQL_TAB_ACTIVE]`
- Schema tab renderer (columns + DDL side-by-side, both focusable)

**`src/screens/inspector.sh`** — replace overlay with inline content view:
- Remove panel-centered overlay positioning
- Add nav bar row at top of inner area (`← label (N/Total) →`)
- Add `←` / `→` key handling to step rows
- Add 1-char inner padding
- Keep two-column key/value layout and scroll

**`src/screens/query.sh`** — minor:
- Accept dynamic context id parameter instead of fixed globals
- Fix Results placeholder text
- Fix Enter-activates-editor regardless of which pane has focus

**`bin/shql`** — routing:
- Remove `open` → SCHEMA dispatch; replace with `open` → TABLE (browser) dispatch
- Remove `table` → SCHEMA init; `shql_schema_init` no longer called
- `query-tui` dispatch: open TABLE with a Query tab pre-opened

### Files unchanged

- `src/db.sh`, `src/db_mock.sh` — no changes needed
- `src/state.sh`, `src/cli.sh`, `src/connections.sh` — no changes needed
- `src/theme.sh` — no changes needed
- shellframe widgets (grid, editor, list, panel, scroll, tabbar) — no changes needed

---

## Testing

- Extend `tests/unit/test-table.sh` with tab open/close/dedup/capacity tests
- Extend `tests/unit/test-schema.sh` → rename/repurpose for schema tab content tests
- Extend `tests/unit/test-inspector.sh` for inline nav bar (row step, wrap, Esc return); update existing Esc dismiss test to also assert cursor-return-to-inspected-row
- Update `tests/unit/test-query.sh` for dynamic context ids and placeholder text fix
- Integration tests: full open → data tab → record inspector → navigate → close flow
