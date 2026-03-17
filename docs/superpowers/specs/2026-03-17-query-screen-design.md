# Query Screen Design

**Date:** 2026-03-17
**Phase:** 5.4
**Issue:** [shellql#4](https://github.com/fissible/shellql/issues/4)

---

## Goal

Implement the Query tab within the TABLE screen: a multiline SQL editor, a results data grid, and a status footer. The user writes SQL, runs it, and sees results — all within the existing TABLE screen tab bar.

---

## Layout

The Query tab renders inside the TABLE screen's existing `body` region. The body region starts at row 4 (`_body_top=4`); the gap row (row 3) is rendered separately by `_shql_TABLE_gap_render` and is not part of the body. The query render function receives `top=4`.

The body is subdivided at render time into three sub-areas:

```
row 1       header     ShellQL  ›  chinook.sqlite  ›  users   [nofocus]
row 2       tabbar     Structure | Data | [Query]              [focus]
row 3       gap        (rendered by _shql_TABLE_gap_render)    [nofocus]
rows 4..N-1 body ─────────────────────────────────────────────────────
              editor pane    floor(body_h × 0.30), min 3 rows  [focus]
              divider row    1 row: plain ─ fill                [nofocus]
              results pane   remaining rows                     [focus]
row N       footer     status or key hints                     [nofocus]
```

Split calculation (performed inside `_shql_query_render`):

```bash
local _editor_rows=$(( _height * 30 / 100 ))
(( _editor_rows < 3 )) && _editor_rows=3
local _divider_row=$(( _top + _editor_rows ))
local _results_top=$(( _divider_row + 1 ))
local _results_rows=$(( _height - _editor_rows - 1 ))
(( _results_rows < 3 )) && _results_rows=3
```

The split ratio adjusts automatically on terminal resize. The divider is a plain `─` fill row — not focusable in this phase. Movable divider is deferred to a later phase.

---

## Focus Model

The TABLE screen's `body` region is the single focus recipient. The Query tab manages an internal two-pane focus cycle tracked by a single variable:

```bash
_SHQL_QUERY_FOCUSED_PANE="editor"   # "editor" | "results"
```

Before each render call, sync to framework globals:

```bash
SHELLFRAME_EDITOR_FOCUSED=$(( _SHQL_QUERY_FOCUSED_PANE == "editor" ? 1 : 0 ))
SHELLFRAME_GRID_FOCUSED=$(( _SHQL_QUERY_FOCUSED_PANE == "results" ? 1 : 0 ))
```

Focus cycle:

```
Tab:        editor ──▶ results ──▶ editor  (cycles)
Shift-Tab:  reverse
```

- On first entry to the Query tab, `_SHQL_QUERY_FOCUSED_PANE="editor"`
- Focus state is preserved when switching away to another tab and back
- `SHELLFRAME_EDITOR_FOCUSED` and `SHELLFRAME_GRID_FOCUSED` must be set before each render call

---

## Keybindings

| Key | Context | Action |
|-----|---------|--------|
| Ctrl-Enter / Ctrl-D | editor focused | run query (editor emits rc=2 on Ctrl-D; Ctrl-Enter detected where terminal supports it) |
| Tab | either | cycle focus: editor → results → editor |
| Shift-Tab | either | cycle focus: results → editor → results |
| Escape | editor focused | return focus to tab bar (`shellframe_shell_focus_set "tabbar"`) |
| ↑ ↓ ← → | editor focused | editor cursor movement (consumed by editor) |
| ↑ ↓ ← → | results focused | grid navigation |
| Enter | results focused | open row inspector |
| q | results focused | return focus to tab bar |
| q | editor focused | **insert 'q' into SQL** — do NOT intercept |

**Important — `q` key:** When the editor pane is focused, `q` is a valid SQL character and must not be intercepted. All keys are passed to `shellframe_editor_on_key` first when editor is focused; only keys it does not handle (rc=1) reach the query tab's own logic. The `q` escape only applies when `_SHQL_QUERY_FOCUSED_PANE="results"`.

**Important — `[` / `]` keys in `_shql_TABLE_body_on_key`:** The current `[`/`]` tab-switch check in `_shql_TABLE_body_on_key` runs *before* tab delegation (lines 247–250). When the Query tab is active and the editor is focused, `[` and `]` must reach the editor (they are valid SQL characters). Fix: when active tab is Query, delegate to `_shql_query_on_key` before the `[`/`]` check; if it returns 0 (handled), skip the `[`/`]` switch.

---

## Footer States

The TABLE screen footer (`_shql_TABLE_footer_render`) sets `_hint` based on active tab. When the Query tab is active, it calls `_shql_query_footer_hint _hint` to populate the variable:

```bash
# In _shql_TABLE_footer_render, replace the QUERY case:
"$_SHQL_TABLE_TAB_QUERY") _shql_query_footer_hint _hint ;;
```

`_shql_query_footer_hint` signature:

```bash
_shql_query_footer_hint() {
    local _out_var="$1"
    if [[ -n "$_SHQL_QUERY_STATUS" ]]; then
        printf -v "$_out_var" '%s  [Ctrl-Enter/Ctrl-D] Run  [q] Back' "$_SHQL_QUERY_STATUS"
    else
        printf -v "$_out_var" '%s' "[Ctrl-Enter/Ctrl-D] Run  [Tab] Switch pane  [q] Back"
    fi
}
```

Status persists until the next run — does not clear on keypress. This lets the user navigate the results grid while seeing the row count. Example values of `_SHQL_QUERY_STATUS`:

- `""` (empty) — before first run
- `"5 rows"` — after successful run
- `"ERROR: no such table: usr"` — after error (stderr from `shql_db_query`)

---

## Architecture

### New file: `src/screens/query.sh`

Owns all Query tab state and logic. Sourced by `bin/shql` alongside other screens.

**State globals:**

```bash
_SHQL_QUERY_EDITOR_CTX="query_sql"      # shellframe editor context name
_SHQL_QUERY_GRID_CTX="query_results"    # shellframe grid context name
_SHQL_QUERY_STATUS=""                   # last status string; empty = show key hints
_SHQL_QUERY_FOCUSED_PANE="editor"       # "editor" | "results"
_SHQL_QUERY_HAS_RESULTS=0               # 0 = no results yet; 1 = grid populated
_SHQL_QUERY_INITIALIZED=0               # 0 = widget inits not yet called
```

**Public functions:**

`_shql_query_init`
- Called from `shql_table_init` (eagerly)
- Sets state globals to their initial values only
- Does NOT call `shellframe_editor_init` or `shellframe_grid_init` — those require viewport dimensions and are deferred to first render

`_shql_query_render top left width height`
- On first call (`_SHQL_QUERY_INITIALIZED=0`): calls `shellframe_editor_init "$_SHQL_QUERY_EDITOR_CTX"` and `shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"`; sets `_SHQL_QUERY_INITIALIZED=1`
- Computes split (editor rows, divider row, results rows)
- Sets `SHELLFRAME_EDITOR_FOCUSED` and `SHELLFRAME_GRID_FOCUSED` from `_SHQL_QUERY_FOCUSED_PANE`
- Renders editor pane: `SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"; shellframe_editor_render ...`
- Renders divider row: fills with `─` characters across full width
- Renders results pane: if `_SHQL_QUERY_HAS_RESULTS=1`, renders grid; otherwise renders a centered placeholder: `"Run a query to see results  [Ctrl-Enter/Ctrl-D]"`

`_shql_query_on_key key`
- When `_SHQL_QUERY_FOCUSED_PANE="editor"`: pass key to `shellframe_editor_on_key` first
  - rc=2 (Ctrl-D / submit): call `_shql_query_run`; return 0
  - rc=0 (handled by editor): return 0
  - rc=1 (not handled): check for Tab, Shift-Tab, Escape; return 1 for anything else
- When `_SHQL_QUERY_FOCUSED_PANE="results"`: check for Ctrl-D/Ctrl-Enter (→ `_shql_query_run`), Tab, Shift-Tab, q; pass navigation keys to `shellframe_grid_on_key`

`_shql_query_run`
- Gets SQL text: `shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql`
- Captures stdout and stderr: `_out=$(shql_db_query "$SHQL_DB_PATH" "$_sql" 2>/tmp/shql_query_err)`
- On non-zero exit or non-empty stderr: `_SHQL_QUERY_STATUS="ERROR: $(cat /tmp/shql_query_err | head -1)"`; return
- Parses TSV into `SHELLFRAME_GRID_*` globals (same logic as `_shql_table_load_data`; first line is the header row, subsequent lines are data rows)
- Calls `shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"`
- Sets `_SHQL_QUERY_HAS_RESULTS=1`
- Sets `_SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows"`

`_shql_query_footer_hint out_var`
- Sets the named variable to the correct footer hint string (see Footer States above)

### Modifications to `src/screens/table.sh`

1. **`_shql_TABLE_body_render`**: replace `_shql_table_query_render` call with `_shql_query_render`
2. **`_shql_TABLE_body_on_key`**: when active tab is Query, delegate to `_shql_query_on_key` *before* the `[`/`]` check; skip `[`/`]` switch if `_shql_query_on_key` returns 0
3. **`_shql_TABLE_footer_render`**: replace `_hint="$_SHQL_TABLE_FOOTER_HINTS_QUERY"` with `_shql_query_footer_hint _hint`
4. **`shql_table_init`**: call `_shql_query_init`
5. Remove `_shql_table_query_render` stub function (replaced by `src/screens/query.sh`)

### Modifications to `src/db_mock.sh`

Update the existing `shql_db_query` stub (currently returns 2 columns: `count`/`result`) to return 3 columns with 3 data rows — matching the `shql_db_fetch` contract (first line = header row, subsequent lines = data rows):

```bash
# shql_db_query <db_path> <sql>
shql_db_query() {
    printf 'id\tname\temail\n'
    printf '1\tAlice\talice@example.com\n'
    printf '2\tBob\tbob@example.com\n'
    printf '3\tCarol\tcarol@example.com\n'
}
```

### New file: `tests/unit/test-query.sh`

Concrete assertions (based on the mock stub above):

1. After `_shql_query_init`: `_SHQL_QUERY_INITIALIZED` is `0`, `_SHQL_QUERY_FOCUSED_PANE` is `"editor"`, `_SHQL_QUERY_STATUS` is `""`
2. After `_shql_query_run` with mock adapter: `_SHQL_QUERY_HAS_RESULTS` is `1`, `SHELLFRAME_GRID_ROWS` is `3`, `SHELLFRAME_GRID_COLS` is `3`
3. After `_shql_query_run`: `_SHQL_QUERY_STATUS` is `"3 rows"`
4. After `_shql_query_footer_hint _hint` with non-empty status: `_hint` contains `"3 rows"`
5. After `_shql_query_footer_hint _hint` with empty status: `_hint` contains `"[Ctrl-Enter/Ctrl-D] Run"`
6. Simulating Tab key in `_shql_query_on_key` when `_SHQL_QUERY_FOCUSED_PANE="editor"`: `_SHQL_QUERY_FOCUSED_PANE` becomes `"results"`
7. Simulating Tab key again: `_SHQL_QUERY_FOCUSED_PANE` becomes `"editor"`

### `bin/shql`

- Add `source "$_SHQL_ROOT/src/screens/query.sh"` after `table.sh`

---

## `shql_db_query` contract

`shql_db_query <db_path> <sql>` outputs TSV to stdout:
- First line: tab-separated column names (header row)
- Subsequent lines: tab-separated data rows
- Errors: written to stderr; exit code non-zero on failure

This is the same contract as `shql_db_fetch`.

---

## Out of Scope (this phase)

- Movable/resizable divider (deferred)
- SQL history (previous queries)
- Syntax highlighting in editor
- Query cancellation
- Export results (CSV, TSV)
