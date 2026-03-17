# Query Screen Design

**Date:** 2026-03-17
**Phase:** 5.4
**Issue:** [shellql#4](https://github.com/fissible/shellql/issues/4)

---

## Goal

Implement the Query tab within the TABLE screen: a multiline SQL editor, a results data grid, and a status footer. The user writes SQL, runs it, and sees results — all within the existing TABLE screen tab bar.

---

## Layout

The Query tab renders inside the TABLE screen's existing `body` region (rows 4..N-1). It subdivides that region at render time:

```
row 1       header     ShellQL  ›  chinook.sqlite  ›  users   [nofocus]
row 2       tabbar     Structure | Data | [Query]              [focus]
row 3       gap
rows 4..N-1 body ─────────────────────────────────────────────────────
              query_editor    floor(body_h × 0.30), min 3 rows  [focus]
              ──────────────────────────────────────────────────────
              query_results   remaining rows                    [focus]
row N       footer     status or key hints                     [nofocus]
```

- Split ratio: `editor_rows = max(3, floor(body_h * 0.30))`; `results_rows = body_h - editor_rows - 1` (1 for the divider)
- Divider is a plain `─` fill row — not focusable in this phase
- Both panes resize automatically when the terminal is resized
- Movable divider is deferred to a later phase

---

## Focus Model

The TABLE screen's `body` region is the single focus recipient. The Query tab manages an internal focus cycle between its two sub-widgets.

```
Tab:        editor ──▶ results ──▶ editor  (cycles)
Shift-Tab:  reverse
```

- On first entry to the Query tab, editor receives focus
- Focus state is preserved when switching away to another tab and back
- `_SHQL_QUERY_EDITOR_FOCUSED` and `_SHQL_QUERY_RESULTS_FOCUSED` track internal state

---

## Keybindings

| Key | Context | Action |
|-----|---------|--------|
| Ctrl-Enter / Ctrl-D | editor focused | run query |
| Tab | either | cycle focus editor ↔ results |
| Shift-Tab | either | cycle focus results ↔ editor |
| ↑ ↓ ← → | editor focused | cursor movement in editor |
| ↑ ↓ ← → | results focused | grid navigation |
| Enter | results focused | open row inspector |
| q | either | return focus to tab bar |

Note: Ctrl-Enter is detected where the terminal distinguishes it from plain Enter. Ctrl-D (shellframe editor's native submit) is the universal fallback. Footer always shows both: `[Ctrl-Enter/Ctrl-D] Run`.

---

## Footer States

The TABLE screen footer displays one of three states when the Query tab is active:

| State | Footer content |
|-------|---------------|
| Before first run | `[Ctrl-Enter/Ctrl-D] Run  [Tab] Switch pane  [q] Back` |
| After successful run | `5 rows  [Ctrl-Enter/Ctrl-D] Run  [Tab] Switch pane  [q] Back` |
| After error | `ERROR: no such table: usr  [Ctrl-Enter/Ctrl-D] Run  [q] Back` |

Status persists until the next run — does not clear on keypress, so the user can navigate the results grid while the row count remains visible.

---

## Architecture

### New file: `src/screens/query.sh`

Owns all Query tab state and logic. Called from `table.sh` via delegation.

**State globals:**

```bash
_SHQL_QUERY_EDITOR_CTX="query_sql"      # shellframe editor context name
_SHQL_QUERY_GRID_CTX="query_results"    # shellframe grid context name
_SHQL_QUERY_STATUS=""                   # last status string; empty = show key hints
_SHQL_QUERY_EDITOR_FOCUSED=1            # 1 = editor has internal focus
_SHQL_QUERY_RESULTS_FOCUSED=0           # 1 = results grid has internal focus
_SHQL_QUERY_HAS_RESULTS=0              # 0 = no results yet; 1 = grid populated
```

**Public functions:**

- `_shql_query_init` — initialises editor (`shellframe_editor_init`) and grid; called once when Query tab first becomes active
- `_shql_QUERY_render top left width height` — computes split ratio; renders editor pane, divider row, results pane (or empty-state placeholder if no results yet)
- `_shql_QUERY_on_key key` — dispatches to editor or grid; handles Tab/Shift-Tab, Ctrl-Enter/Ctrl-D (→ `_shql_query_run`), q
- `_shql_query_run` — reads editor text via `shellframe_editor_get_text`; calls `shql_db_query`; parses TSV output into `SHELLFRAME_GRID_*` globals; calls `shellframe_grid_init`; updates `_SHQL_QUERY_STATUS`
- `_shql_QUERY_footer_hints` — prints the correct footer string for current state; called by TABLE footer render

### Modifications to `src/screens/table.sh`

- Query tab `body_render`: delegate to `_shql_QUERY_render`
- Query tab `body_on_key`: delegate to `_shql_QUERY_on_key`
- Footer render: when active tab is Query, call `_shql_QUERY_footer_hints` instead of static hint string
- `shql_table_init`: call `_shql_query_init` (or lazily on first tab activation)

### Modifications to `src/db_mock.sh`

Add `shql_db_query` stub:

```bash
shql_db_query() {
    # $1 = db_path, $2 = sql — returns hardcoded TSV (header + 3 data rows)
    printf 'id\tname\temail\n'
    printf '1\tAlice\talice@example.com\n'
    printf '2\tBob\tbob@example.com\n'
    printf '3\tCarol\tcarol@example.com\n'
}
```

### New file: `tests/unit/test-query.sh`

- Query init creates editor and grid contexts
- `_shql_query_run` with mock adapter populates grid (`SHELLFRAME_GRID_ROWS > 0`) and sets `_SHQL_QUERY_STATUS`
- Footer string reflects status after run
- Tab key toggles `_SHQL_QUERY_EDITOR_FOCUSED` / `_SHQL_QUERY_RESULTS_FOCUSED`

---

## Out of Scope (this phase)

- Movable/resizable divider (deferred)
- SQL history (previous queries)
- Syntax highlighting in editor
- Query cancellation
- Export results (CSV, TSV)
