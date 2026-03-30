# ShellQL v1.0 — Issue Specs (Draft)

Issue numbers are suggested starting points: shellframe #36+, shellql #13+.
PM creates issues after review. Dependency order: Tier 0 before Tier 1, etc.

---

## Tier 0 — Shellframe Primitives

### shellframe#36 — Form widget (`form.sh`)

**Effort:** M (~half day)
**Deps:** None
**Repo:** fissible/shellframe

Multi-field input form with labeled rows, Tab/Shift-Tab traversal, and vertical
scrolling when fields exceed viewport height.

**Requirements:**
- Array of field definitions: `SHELLFRAME_FORM_FIELDS[@]` — each entry is
  `"label<TAB>context<TAB>type"` where type is `text` (default), `readonly`,
  or `password`
- Each field backed by a `shellframe_field` instance (existing input-field widget)
  with its own context name
- Tab/Shift-Tab cycles between fields; Up/Down also moves between fields
- Enter on last field or a "Save" button → submit (rc=2)
- Esc → cancel (rc=1)
- Scrollable: if field count exceeds viewport, scroll to keep focused field visible
- Field labels rendered left-aligned with consistent width (max label length + 2)
- Optional per-field placeholder text
- Read result via `shellframe_form_values` → newline-separated field values

**Public API:**
```
shellframe_form_init [ctx]
shellframe_form_render top left width height
shellframe_form_on_key key → 0 handled | 1 unhandled | 2 submit
shellframe_form_on_focus focused
shellframe_form_values ctx out_array
shellframe_form_set_value ctx field_idx value
```

**Design notes:**
- Renders inside a panel (caller provides the panel border)
- Each field row: `  label:  [___input___]`
- Focused field has cursor; unfocused fields show text or placeholder
- Context-keyed state pattern (same as editor, grid, list)

---

### shellframe#37 — Toast / flash message widget (`toast.sh`)

**Effort:** S (1-2h)
**Deps:** None
**Repo:** fissible/shellframe

Transient status message rendered at a fixed screen position (bottom-right or
top-right) that auto-dismisses after N draw cycles.

**Requirements:**
- `shellframe_toast_show message [style] [duration]` — queue a toast
- Styles: `info` (gray), `success` (green), `error` (red), `warning` (yellow)
- Duration: number of render cycles before auto-dismiss (default ~30, ~3s at 10fps)
- Renders as a small floating box (panel with rounded border)
- Multiple toasts stack vertically (newest on top), max 3 visible
- Does not steal focus; does not block input
- Dismissed early by any keypress (optional, configurable)

**Integration:**
- `shellframe_toast_render` called at end of each screen render (on top of content)
- `shellframe_toast_tick` called each event loop iteration to decrement timers
- Toast state stored in module globals (not context-keyed — single global queue)

---

### shellframe#38 — Autocomplete layer for input-field

**Effort:** M (~half day)
**Deps:** input-field.sh, context-menu.sh (both exist)
**Repo:** fissible/shellframe

Composable autocomplete that layers a filtered suggestion popup on top of an
input field or editor. Not SQL-specific — the suggestion source is a callback.

**Requirements:**
- `SHELLFRAME_AC_PROVIDER` — name of a function that takes `(prefix, out_array)` and
  populates the array with matching suggestions
- `SHELLFRAME_AC_TRIGGER` — "auto" (filter on every keystroke) | "tab" (Tab triggers)
- Popup rendered as a context-menu widget anchored below the input cursor
- Typing filters the list; Enter or Tab accepts the selected suggestion
- Esc dismisses popup without accepting
- Popup auto-hides when 0 matches remain
- If only 1 match, Tab auto-completes without showing popup

**Public API:**
```
shellframe_ac_attach ctx            # attach to an input-field or editor context
shellframe_ac_detach ctx            # remove autocomplete from a context
shellframe_ac_on_key key → 0|1     # intercept keys when popup is visible
shellframe_ac_render top left w h   # render popup if visible
shellframe_ac_dismiss               # hide popup
```

**Design notes:**
- Consumer (shellql) provides the provider function that knows about SQL keywords,
  table names, column names
- Shellframe provides the UI mechanics (popup positioning, filtering, selection)
- Works with both input-field (single-line) and editor (multi-line, cursor-anchored)

---

## Tier 1 — Core DML

### shellql#13 — Insert row

**Effort:** M (~half day)
**Deps:** shellframe#36 (form widget)
**Repo:** fissible/shellql

Insert a new row into the currently viewed table via a form dialog.

**Requirements:**
- Trigger: `i` key in data grid, or Shift+click context menu "Insert Row"
- Opens form widget in a modal overlay (centered, 60-80% screen width)
- Fields populated from `PRAGMA table_info`: one field per column
- Field labels = column names; placeholder = column type + constraints
- Autoincrement PK fields marked readonly with placeholder "(auto)"
- NOT NULL fields indicated in label (e.g., `name *:`)
- Enter submits → `INSERT INTO <table> (...) VALUES (...)`
- On success: toast "1 row inserted", refresh grid data, close form
- On error: show error inline at bottom of form, keep form open
- Esc cancels without changes

**SQL generation:**
- Quote all values as strings (sqlite3 handles type affinity)
- Skip readonly/autoincrement fields
- Empty fields for nullable columns → `NULL`
- Empty fields for NOT NULL columns → validation error before submit

---

### shellql#14 — Update row

**Effort:** M (~half day)
**Deps:** shellframe#36 (form widget), shellql#13 (shares form patterns)
**Repo:** fissible/shellql

Edit an existing row in the currently viewed table.

**Requirements:**
- Trigger: `e` key in data grid (row must be selected), or Shift+click "Edit Row"
- Opens same form widget as insert, pre-filled with current row values
- PK columns shown as readonly (display only, not editable)
- Enter submits → `UPDATE <table> SET col1=?, col2=? WHERE pk_col=?`
- Needs PK detection: use `PRAGMA table_info` pk flag (already parsed in grid)
- Tables without a PK: warn "Cannot edit rows without a primary key" (alert)
- On success: toast "Row updated", refresh grid data, close form
- On error: show error inline, keep form open
- Esc cancels

**Edge cases:**
- Composite PKs: build WHERE with AND for all PK columns
- ROWID-only tables (no explicit PK): use `rowid` as implicit PK — requires
  fetching rowid alongside data (`SELECT rowid, * FROM ...`)

---

### shellql#15 — Delete row

**Effort:** S (1-2h)
**Deps:** confirm.sh (exists)
**Repo:** fissible/shellql

Delete the selected row from the currently viewed table.

**Requirements:**
- Trigger: `d` key in data grid (row selected), or Shift+click "Delete Row"
- Shows confirm dialog: "Delete this row from <table>?" with PK value shown
- On confirm → `DELETE FROM <table> WHERE pk_col=?`
- Tables without a PK: warn "Cannot delete rows without a primary key"
- On success: toast "Row deleted", refresh grid, adjust cursor if at end
- On error: alert with error message
- Multi-select future: if grid supports multi-select, delete all selected
  (defer to v1.1, just note the extension point)

---

### shellql#16 — Truncate table data

**Effort:** XS (<1h)
**Deps:** confirm.sh (exists)
**Repo:** fissible/shellql

Delete all rows from a table.

**Requirements:**
- Trigger: Shift+click context menu on sidebar table → "Truncate Table"
- Confirm dialog: "Delete ALL rows from <table>? This cannot be undone."
  Show row count if known.
- On confirm → `DELETE FROM <table>`
- On success: toast "<n> rows deleted", refresh grid if table is open
- On error: alert

---

## Tier 2 — DDL Operations

### shellql#17 — Drop table

**Effort:** S (1-2h)
**Deps:** confirm.sh (exists)
**Repo:** fissible/shellql

Drop a table or view from the database.

**Requirements:**
- Trigger: Shift+click context menu on sidebar → "Drop Table"
- Confirm dialog: "Drop table <name>? This cannot be undone."
  Show row count + column count for context.
- On confirm → `DROP TABLE <name>` (or `DROP VIEW` for views)
- On success: toast "Table dropped", close any open tabs for that table,
  refresh sidebar list
- On error: alert

---

### shellql#18 — Create table (template approach)

**Effort:** S (1-2h)
**Deps:** None (uses existing query editor)
**Repo:** fissible/shellql

Create a new table via a pre-filled SQL template in the query editor.

**Requirements:**
- Trigger: Shift+click context menu on sidebar → "New Table", or `c` key in sidebar
- Opens a new query tab pre-filled with:
  ```sql
  CREATE TABLE table_name (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      -- add columns here
  );
  ```
- User edits the SQL and runs with Ctrl-D (existing flow)
- On success: toast "Table created", refresh sidebar
- On error: existing query error display handles it
- Tab label: "+Table" or "New Table"

**v1.1 upgrade path:** Replace with a dedicated column-definition builder form.

---

## Tier 3 — Export

### shellql#19 — Export results as CSV

**Effort:** S-M (2-4h)
**Deps:** None
**Repo:** fissible/shellql

Export the current grid data (data tab or query results) to a CSV file.

**Requirements:**
- Trigger: `x` key in data grid or query results, or Shift+click "Export"
- Modal dialog with:
  - Format selector (v1: CSV only, but design for extensibility)
  - Output path input field (default: `~/Downloads/<table>.csv`)
  - Row count display: "Exporting 500 rows, 8 columns"
- On confirm: write CSV with proper quoting (RFC 4180)
  - Header row from `SHELLFRAME_GRID_HEADERS`
  - Data rows from `SHELLFRAME_GRID_DATA`
  - Commas in values → quote field; quotes in values → double-quote
- On success: toast "Exported to ~/Downloads/users.csv"
- On error: alert
- For query results: export whatever is currently in the grid
- For data tabs: export current data (may be limited by fetch_limit —
  show warning if truncated)

**v1.1:** Add JSON, TSV, SQL INSERT formats. Add "Export All" that bypasses
fetch_limit.

---

## Tier 4 — Type-ahead

### shellql#20 — SQL autocomplete in query editor

**Effort:** L (~1 day)
**Deps:** shellframe#38 (autocomplete layer)
**Repo:** fissible/shellql

Schema-aware autocomplete for the SQL query editor.

**Requirements:**
- v1 scope: table names + column names only (no keyword completion)
- Build schema metadata cache on database open:
  - All table/view names from `sqlite_master`
  - Column names per table from `PRAGMA table_info`
  - Store in associative arrays (bash 4+) or flat arrays (bash 3.2)
- Tokenizer: extract word-under-cursor from editor content
  - After `FROM`, `JOIN`, `INTO`, `UPDATE`, `TABLE`: suggest table names
  - After `SELECT`, `WHERE`, `SET`, `ON`, `AND`, `OR`, or after `<table>.`:
    suggest column names (scoped to table if detectable)
  - Default (ambiguous context): suggest all table names + all column names
- Provider function for shellframe#38: `_shql_ac_provider prefix out_array`
- Trigger: automatic (filter on every keystroke while typing)
- Tab accepts suggestion; Esc dismisses; continue typing narrows list

**Edge cases:**
- Quoted identifiers (`"table name"`) — don't autocomplete inside quotes
- Subqueries — scope column suggestions to innermost FROM clause (v1.1)
- Aliases (`AS`) — track alias→table mapping (v1.1)

---

## Enriched Context Menus

### shellql#21 — Add DML/DDL actions to context menus

**Effort:** XS (<1h)
**Deps:** Tier 1 + Tier 2 features implemented
**Repo:** fissible/shellql

Update Shift+click context menus to expose all new actions with keyboard
shortcut hints.

**Sidebar context menu:**
```
Open Data        (Enter)
Open Schema      (s)
New Query        (n)
─────────────────
New Table        (c)
Truncate Table
Drop Table
```

**Data grid context menu:**
```
Inspect Row      (Enter)
Edit Row         (e)
Delete Row       (d)
─────────────────
Insert Row       (i)
Filter           (f)
Export           (x)
```

**Query results context menu:**
```
View Details     (Enter)
─────────────────
Export           (x)
```

---

## UX Fixes (bundle with any release)

### shellql#22 — Fix Esc hierarchy

**Effort:** S (1-2h)
**Deps:** None
**Repo:** fissible/shellql

Esc and `q` should always mean "one step back", never quit the app unexpectedly.

**Changes:**
- Schema tab `on_key`: handle Esc → focus tabbar (currently falls through to quit)
- Tabbar `on_key`: handle Esc → focus sidebar (currently falls through to quit)
- Sidebar `on_key`: handle Esc/q → show quit confirmation modal
- Data grid: `q` → focus tabbar (currently falls through to quit)
- Global quit handler: only fires when no region handles the key

---

## Dependency Graph

```
shellframe#36 (form) ──→ shellql#13 (insert) ──→ shellql#14 (update)
                                                       │
shellframe#37 (toast) ──→ all DML/DDL feedback         │
                                                       │
confirm.sh (exists) ────→ shellql#15 (delete) ─────────┤
                     ├──→ shellql#16 (truncate)        │
                     └──→ shellql#17 (drop table)      │
                                                       │
(no deps) ──────────→ shellql#18 (create table template)
(no deps) ──────────→ shellql#19 (export CSV)
                                                       │
shellframe#38 (autocomplete) ──→ shellql#20 (SQL type-ahead)
                                                       │
Tier 1+2 complete ──→ shellql#21 (enrich context menus)
(no deps) ──────────→ shellql#22 (fix Esc hierarchy)
```

## Suggested Build Order

1. shellframe#36 (form) + shellframe#37 (toast) — parallel
2. shellql#22 (Esc fix) — quick win, ship anytime
3. shellql#13 (insert) → shellql#14 (update) → shellql#15 (delete) — sequential
4. shellql#16 (truncate) + shellql#17 (drop) + shellql#18 (create template) — parallel
5. shellql#19 (export CSV) — independent
6. shellframe#38 (autocomplete) → shellql#20 (type-ahead) — sequential
7. shellql#21 (enrich menus) — last, after all actions exist
