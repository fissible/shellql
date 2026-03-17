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

**Before each render call**, sync to framework globals using the bash 3.2-compatible form:

```bash
[[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]]  && SHELLFRAME_EDITOR_FOCUSED=1 || SHELLFRAME_EDITOR_FOCUSED=0
[[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]] && SHELLFRAME_GRID_FOCUSED=1   || SHELLFRAME_GRID_FOCUSED=0
```

Note: `_shql_TABLE_body_on_focus` unconditionally sets `SHELLFRAME_GRID_FOCUSED=$_SHQL_TABLE_BODY_FOCUSED` when the body region gains focus. This is harmless because `_shql_query_render` always re-syncs those globals from `_SHQL_QUERY_FOCUSED_PANE` on every render. No change to `_shql_TABLE_body_on_focus` is needed.

Focus cycle:

```
Tab:        editor ──▶ results ──▶ editor  (cycles)
Shift-Tab:  reverse
```

- On first entry to the Query tab, `_SHQL_QUERY_FOCUSED_PANE="editor"`
- Focus state is preserved when switching away to another tab and back
- Up-at-top of editor does **not** return focus to the tab bar in this phase — use Escape instead. (The existing Up-at-top → tabbar path in `_shql_TABLE_body_on_key` is bypassed for the Query tab; see Architecture section.)

---

## Keybindings

| Key | Context | Action |
|-----|---------|--------|
| Ctrl-D | editor focused | run query (editor emits rc=2; `SHELLFRAME_EDITOR_RESULT` contains the SQL) |
| Ctrl-Enter | editor focused | run query where terminal distinguishes from Enter; Ctrl-D is the universal fallback |
| Ctrl-D / Ctrl-Enter | results focused | re-run (reads editor text via `shellframe_editor_get_text`) |
| Tab | either | cycle focus: editor → results → editor |
| Shift-Tab | either | cycle focus backward: editor → results → editor |
| Escape | editor focused | return focus to tab bar (`shellframe_shell_focus_set "tabbar"`) |
| ↑ ↓ ← → | editor focused | editor cursor movement (consumed by editor) |
| ↑ ↓ ← → | results focused | grid navigation |
| Enter | results focused | open row inspector |
| q | results focused | return focus to tab bar |
| q | **editor focused** | **insert 'q' into SQL — do NOT intercept** |

**Important — `q` key:** When the editor pane is focused, all keys are passed to `shellframe_editor_on_key` first. Only keys it returns unhandled (rc=1) reach the query tab's own logic. `q` is consumed by the editor. `[q] Back` must NOT appear in the footer hint when the editor pane is focused.

**Important — `[` / `]` keys:** When the Query tab is active, `_shql_query_on_key` is called before the `[`/`]` tab-switch check in `_shql_TABLE_body_on_key`. The editor consumes `[` and `]` as printable characters (returns rc=0), preventing the tab-switch logic from firing. See Architecture section for exact pseudocode.

---

## Footer States

The TABLE screen footer (`_shql_TABLE_footer_render`) sets `_hint` based on active tab. The wildcard `*)` case currently handling Query must be changed to an explicit `"$_SHQL_TABLE_TAB_QUERY"`)  case (to prevent future tabs from accidentally triggering this logic):

```bash
# In _shql_TABLE_footer_render:
"$_SHQL_TABLE_TAB_QUERY") _shql_query_footer_hint _hint ;;
```

`_shql_query_footer_hint` sets a named variable via `printf -v`, matching the existing footer pattern. The hint varies by both status and focused pane:

```bash
_shql_query_footer_hint() {
    local _out_var="$1"
    local _run="[Ctrl-Enter/Ctrl-D] Run"
    local _escape="[Esc] Tab bar"
    local _quit="[q] Back"
    local _switch="[Tab] Switch pane"

    local _back
    [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]] && _back="$_quit" || _back="$_escape"

    if [[ -n "$_SHQL_QUERY_STATUS" ]]; then
        printf -v "$_out_var" '%s  %s  %s  %s' "$_SHQL_QUERY_STATUS" "$_run" "$_switch" "$_back"
    else
        printf -v "$_out_var" '%s  %s  %s' "$_run" "$_switch" "$_back"
    fi
}
```

Status persists until the next run — does not clear on keypress. Example values of `_SHQL_QUERY_STATUS`:

- `""` (empty) — before first run
- `"5 rows"` — after successful run
- `"ERROR: no such table: usr"` — after error (first line of stderr)
- `"ERROR: "` — if `shql_db_query` exits non-zero with no stderr output (acceptable; implementor need not add a secondary guard)

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

---

### `_shql_query_init`

Called from `shql_table_init` (eagerly, at TABLE screen startup). Sets state globals to initial values only. Does NOT call `shellframe_editor_init` or `shellframe_grid_init` — those require viewport dimensions and are deferred to first render.

---

### `_shql_query_render top left width height`

```
1. On first call (_SHQL_QUERY_INITIALIZED=0):
   - Set SHELLFRAME_EDITOR_LINES=()  ← clear any stale content before init
   - Call shellframe_editor_init "$_SHQL_QUERY_EDITOR_CTX"
   - Set SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
   - Call shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"
   - Set _SHQL_QUERY_INITIALIZED=1

2. Compute split (see Layout section).

3. Sync framework focus globals (bash 3.2-compatible):
   SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
   [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]]  && SHELLFRAME_EDITOR_FOCUSED=1 || SHELLFRAME_EDITOR_FOCUSED=0
   SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
   [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]] && SHELLFRAME_GRID_FOCUSED=1   || SHELLFRAME_GRID_FOCUSED=0

4. Render editor pane:
   shellframe_editor_render _top _left _width _editor_rows

5. Render divider row:
   printf '\033[%d;%dH' _divider_row _left >/dev/tty
   print _width ─ characters >/dev/tty

6. Render results pane:
   if _SHQL_QUERY_HAS_RESULTS=1:
     shellframe_grid_render _results_top _left _width _results_rows
   else:
     clear _results_rows rows
     print centered placeholder: "Run a query to see results  [Ctrl-Enter/Ctrl-D]"
```

---

### `_shql_query_on_key key`

```
if _SHQL_QUERY_FOCUSED_PANE = "editor":
    SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
    shellframe_editor_on_key "$_key" → rc
    if rc=2 (Ctrl-D submit):
        # SHELLFRAME_EDITOR_RESULT already contains the SQL text (set by editor on Ctrl-D)
        _shql_query_run "$SHELLFRAME_EDITOR_RESULT"
        return 0
    if rc=0 (handled by editor, including q, [, ]):
        return 0
    # rc=1: key not handled by editor — check query-level bindings
    if key=Tab:       _SHQL_QUERY_FOCUSED_PANE="results"; return 0
    if key=Shift-Tab: _SHQL_QUERY_FOCUSED_PANE="results"; return 0  # wraps to end of cycle
    if key=Escape:    shellframe_shell_focus_set "tabbar"; return 0
    return 1

if _SHQL_QUERY_FOCUSED_PANE = "results":
    if key=Tab:       _SHQL_QUERY_FOCUSED_PANE="editor"; return 0
    if key=Shift-Tab: _SHQL_QUERY_FOCUSED_PANE="editor"; return 0
    if key=Ctrl-D or Ctrl-Enter:
        shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql
        _shql_query_run "$_sql"
        return 0
    if key=q: shellframe_shell_focus_set "tabbar"; return 0
    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    shellframe_grid_on_key "$_key"
    return $?   # rc=2 (Enter on row) bubbles up to _shql_TABLE_body_action
```

---

### `_shql_query_run sql`

```bash
_shql_query_run() {
    local _sql="$1"
    local _tmpfile="/tmp/shql_query_err.$$"   # $$ = current PID, avoids collisions

    local _out
    _out=$(shql_db_query "$SHQL_DB_PATH" "$_sql" 2>"$_tmpfile")
    local _rc=$?

    if (( _rc != 0 )) || [[ -s "$_tmpfile" ]]; then
        _SHQL_QUERY_STATUS="ERROR: $(head -1 "$_tmpfile")"
        # Note: if exit is non-zero with no stderr, status = "ERROR: " (empty msg) — acceptable
        rm -f "$_tmpfile"
        return 0
    fi
    rm -f "$_tmpfile"

    # Parse TSV: first line = header row, subsequent lines = data rows.
    # Identical logic to _shql_table_load_data in table.sh — copy that implementation directly.
    # Column widths: header_width + 2, clamped 8..30, grown by data cell widths.
    # Set SHELLFRAME_GRID_PK_COLS=0 (no PK highlight for ad-hoc query results).
    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_PK_COLS=0
    local _idx=0
    while IFS=$'\t' read -r -a _row; do
        [[ ${#_row[@]} -eq 0 ]] && continue
        if (( _idx == 0 )); then
            # header row — copy sizing logic from _shql_table_load_data
            ...
        else
            # data row — copy append logic from _shql_table_load_data
            ...
            (( SHELLFRAME_GRID_ROWS++ ))
        fi
        (( _idx++ ))
    done <<< "$_out"

    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"
    _SHQL_QUERY_HAS_RESULTS=1
    _SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows"
}
```

The `...` blocks are a direct copy of `_shql_table_load_data` in `table.sh` — do not rewrite them; copy exactly to preserve tested behaviour.

---

### Body Action — Enter on results grid

When `shellframe_grid_on_key` returns rc=2 (Enter on a row) from within `_shql_query_on_key`, the value propagates to `_shql_TABLE_body_action`. That function's guard must be extended:

```bash
_shql_TABLE_body_action() {
    local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    if [[ "$_tab" == "$_SHQL_TABLE_TAB_DATA" ]]; then
        SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
        _shql_inspector_open
    elif [[ "$_tab" == "$_SHQL_TABLE_TAB_QUERY" ]]; then
        SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
        _shql_inspector_open
    fi
}
```

---

### Modified `_shql_TABLE_body_on_key`

The Query tab must be handled before the `[`/`]` switch check and before the Up-at-top check. The following replaces the top of the function:

```bash
_shql_TABLE_body_on_key() {
    # Inspector intercepts all keys when active
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _shql_inspector_on_key "$1"; return $?
    fi

    # Query tab: delegate first. The editor consumes printable chars (including
    # [ and ]) before they reach the tab-switch logic. Up-at-top is not handled
    # for the Query tab in this phase — users use Escape to return to the tab bar.
    if [[ "${SHELLFRAME_TABBAR_ACTIVE:-0}" == "$_SHQL_TABLE_TAB_QUERY" ]]; then
        _shql_query_on_key "$1"
        return $?
    fi

    # [ / ] switch tabs from body for Structure and Data tabs only.
    case "$1" in
        '[') (( SHELLFRAME_TABBAR_ACTIVE > 0 )) && (( SHELLFRAME_TABBAR_ACTIVE-- )) || true; return 0 ;;
        ']') (( SHELLFRAME_TABBAR_ACTIVE < _SHQL_TABLE_TAB_QUERY )) && (( SHELLFRAME_TABBAR_ACTIVE++ )) || true; return 0 ;;
    esac

    # ... rest of existing on_key logic (Up-at-top check, Structure/Data dispatch) unchanged ...
}
```

Behavioral note: the existing `*) _at_top=1 ;;` fallthrough that fired for the Query tab (when Up was pressed on the placeholder) is now unreachable for the Query tab. This is intentional — Up-at-top → tabbar for the Query tab is deferred to a later phase. Users use Escape from the editor or `q` from the results pane.

---

### Other modifications to `src/screens/table.sh`

1. **`_shql_TABLE_body_render`**: replace `_shql_table_query_render "$@"` with `_shql_query_render "$@"`
2. **`_shql_TABLE_footer_render`**: replace `*) _hint="$_SHQL_TABLE_FOOTER_HINTS_QUERY" ;;` with the explicit case `"$_SHQL_TABLE_TAB_QUERY") _shql_query_footer_hint _hint ;;` followed by `*) _hint="" ;;`
3. **`shql_table_init`**: call `_shql_query_init`
4. Remove the `_shql_table_query_render` stub function

### `bin/shql`

Add `source "$_SHQL_ROOT/src/screens/query.sh"` after `table.sh`.

### Modifications to `src/db_mock.sh`

**Replace** (do not add a second definition) the existing `shql_db_query` stub. The current stub returns 2 columns/1 row; replace it with 3 columns/3 rows to match test assertions:

```bash
# shql_db_query <db_path> <sql>
# First line: tab-separated column headers. Subsequent lines: data rows.
shql_db_query() {
    printf 'id\tname\temail\n'
    printf '1\tAlice\talice@example.com\n'
    printf '2\tBob\tbob@example.com\n'
    printf '3\tCarol\tcarol@example.com\n'
}
```

---

## Test file: `tests/unit/test-query.sh`

**Prerequisites:** The `db_mock.sh` stub must be updated as described above (3 columns, 3 rows) before writing or running these tests. The assertions are calibrated to that mock output.

**Stub requirements:** `shellframe_editor_init`, `shellframe_grid_init`, `shellframe_grid_on_key`, `shellframe_shell_focus_set` (all no-ops). `shellframe_editor_get_text` stub: sets the named out-variable to any non-empty string (e.g. `"SELECT 1"`) — the value is passed to `_shql_query_run` but is irrelevant to the assertions below since the mock ignores SQL input.

**Concrete assertions:**

1. After `_shql_query_init`: `_SHQL_QUERY_INITIALIZED` equals `0`, `_SHQL_QUERY_FOCUSED_PANE` equals `"editor"`, `_SHQL_QUERY_STATUS` equals `""`
2. After `_shql_query_run "SELECT 1"` with mock adapter: `_SHQL_QUERY_HAS_RESULTS` equals `1`, `SHELLFRAME_GRID_ROWS` equals `3`, `SHELLFRAME_GRID_COLS` equals `3`
3. After `_shql_query_run`: `SHELLFRAME_GRID_HEADERS[0]` equals `"id"`, `SHELLFRAME_GRID_HEADERS[1]` equals `"name"`, `SHELLFRAME_GRID_HEADERS[2]` equals `"email"`
4. After `_shql_query_run`: `_SHQL_QUERY_STATUS` equals `"3 rows"`
5. After `_shql_query_footer_hint _hint` with `_SHQL_QUERY_STATUS="3 rows"` and `_SHQL_QUERY_FOCUSED_PANE="results"`: `_hint` contains `"3 rows"` and contains `"[q] Back"`
6. After `_shql_query_footer_hint _hint` with `_SHQL_QUERY_STATUS=""` and `_SHQL_QUERY_FOCUSED_PANE="editor"`: `_hint` does NOT contain `"[q] Back"`, contains `"[Esc] Tab bar"`
7. Simulating Tab key via `_shql_query_on_key "$k_tab"` when `_SHQL_QUERY_FOCUSED_PANE="editor"`: `_SHQL_QUERY_FOCUSED_PANE` becomes `"results"`
8. Simulating Tab key again: `_SHQL_QUERY_FOCUSED_PANE` becomes `"editor"`

---

## `shql_db_query` contract

`shql_db_query <db_path> <sql>` outputs TSV to stdout:
- First line: tab-separated column names (header row)
- Subsequent lines: tab-separated data rows
- Errors written to stderr; non-zero exit code on failure

Same contract as `shql_db_fetch`.

---

## Out of Scope (this phase)

- Movable/resizable divider
- Up-at-top of editor → tab bar focus (use Escape instead)
- SQL history (previous queries)
- Syntax highlighting in editor
- Query cancellation
- Export results (CSV, TSV)
