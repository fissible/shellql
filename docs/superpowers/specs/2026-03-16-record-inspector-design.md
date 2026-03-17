# Record Inspector — Design Spec

**Date:** 2026-03-16
**Issue:** [shellql#5](https://github.com/fissible/shellql/issues/5)
**Phase:** 5.5
**Effort:** S (1–2h)

---

## Overview

A centered overlay panel that appears on the TABLE screen when the user presses Enter
on a data grid row. Shows all columns of the selected row as scrollable key/value pairs.
Dismissed with Enter, Esc, or q.

---

## Trigger

`_shql_TABLE_body_action` is called by shellframe shell when the body region's `on_key`
returns 2 (action). This fires on Enter. The action function:
1. Checks that the Data tab is active (`SHELLFRAME_TABBAR_ACTIVE == _SHQL_TABLE_TAB_DATA`).
2. Calls `_shql_inspector_open`.

`_shql_inspector_open` itself guards against an empty grid: if `SHELLFRAME_GRID_ROWS == 0`
it returns early without setting `_SHQL_INSPECTOR_ACTIVE=1`. This keeps the guard in the
function that owns the state, so future callers are also protected.

---

## State

All state is module-level globals in `src/screens/inspector.sh`:

| Global | Type | Purpose |
|--------|------|---------|
| `_SHQL_INSPECTOR_ACTIVE` | 0/1 | Whether the inspector overlay is visible |
| `_SHQL_INSPECTOR_PAIRS` | array | `"key\tvalue"` strings, one per column of the selected row |
| `_SHQL_INSPECTOR_CTX` | string | Scroll context name (`"inspector_scroll"`) |

---

## Open sequence

`_shql_inspector_open`:
1. Read cursor row index using the out-var form (avoids subshell):
   `shellframe_sel_cursor "$_SHQL_TABLE_GRID_CTX" _cursor`
2. Build `_SHQL_INSPECTOR_PAIRS`: for each column `c` in `0..<SHELLFRAME_GRID_COLS>`,
   compute cell index as `$(( _cursor * SHELLFRAME_GRID_COLS + _c ))` and push
   `"${SHELLFRAME_GRID_HEADERS[$_c]}\t${SHELLFRAME_GRID_DATA[$_idx]}"`.
   Empty cells render as `(null)`.
3. Initialise scroll — signature is `shellframe_scroll_init ctx total_rows total_cols viewport_rows viewport_cols`:
   `shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_n" 1 10 1`
4. Set `_SHQL_INSPECTOR_ACTIVE=1`.

---

## Rendering

`_shql_inspector_render top left width height` is called from `_shql_TABLE_body_render`
after drawing the underlying tab content, so the inspector overlays it.

**Panel sizing:**
- Width: ⅔ of body width, min 40, max `width - 4`
- Height: ¾ of body height, min 10, max `height - 2`
- Centered: `_panel_top = top + (height - panel_h) / 2`,
            `_panel_left = left + (width - panel_w) / 2`

**Panel border:** Set globals then call:
```bash
SHELLFRAME_PANEL_TITLE="Row Inspector"
SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_FOCUSED=1
shellframe_panel_render "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h"
shellframe_panel_inner "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h" \
    _inner_top _inner_left _inner_w _inner_h
```
Using `shellframe_panel_inner` to obtain content bounds is required so that the
implementation remains correct if the border style changes.

**Key column width:** `max(${#key} for all keys in _SHQL_INSPECTOR_PAIRS)`, bounded
to `[8, 20]`.

**Scroll resize** — signature is `shellframe_scroll_resize ctx viewport_rows viewport_cols`:
```bash
shellframe_scroll_resize "$_SHQL_INSPECTOR_CTX" "$_inner_h" 1
```

**Scroll top** — use out-var form:
```bash
shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _scroll_top
```

**Inner content:** For each visible row `r` from `0..<_inner_h>`:
```
  <bold>left-padded-key<reset>  value (clipped with ellipsis)
```
Value available width = `_inner_w - _key_w - 2` (2-char gap after key).
Clear each row with `\033[2K` before writing.

---

## Key handling

`_shql_TABLE_body_on_key` checks `_SHQL_INSPECTOR_ACTIVE` **first**. If set, all keys
are routed to `_shql_inspector_on_key` and its return code is returned directly
(bypassing all grid and tab-switch logic).

`_shql_inspector_on_key key`:
- `↑` / `↓` — `shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" up/down`, return 0
- `PgUp` / `PgDn` — `shellframe_scroll_move … page_up/page_down`, return 0
- Enter / Esc / `q` — `_SHQL_INSPECTOR_ACTIVE=0`, return 0

  **Note:** Returning **0** (not 1) for `q` is intentional. Returning 1 would allow
  the key to fall through to the global quit handler, navigating back to SCHEMA while
  the inspector is still logically open. Returning 0 triggers a redraw with
  `_SHQL_INSPECTOR_ACTIVE=0`, correctly dismissing the overlay.

- All other keys — return 1

---

## Footer

`_shql_TABLE_footer_render` checks `_SHQL_INSPECTOR_ACTIVE` before the tabbar/body
focus branches. If set, shows:
```
[↑↓] Scroll  [PgUp/PgDn] Page  [Enter/Esc] Close
```
Otherwise shows the existing per-focus/per-tab hints.

---

## File layout

| File | Change |
|------|--------|
| `src/screens/inspector.sh` | New. Inspector state globals + `_shql_inspector_open`, `_shql_inspector_render`, `_shql_inspector_on_key`. |
| `src/screens/table.sh` | Add `_shql_TABLE_body_action`; call `_shql_inspector_render` at end of `_shql_TABLE_body_render` when active; add inspector guard at top of `_shql_TABLE_body_on_key`; add inspector hint branch in `_shql_TABLE_footer_render`. |
| `bin/shql` | `source "$_SHQL_ROOT/src/screens/inspector.sh"` |

---

## Tests

`tests/unit/test-inspector.sh`:
- `_shql_inspector_open` builds correct pairs from mock grid state
- `_shql_inspector_open` does not set `_SHQL_INSPECTOR_ACTIVE=1` when `SHELLFRAME_GRID_ROWS == 0`
- `_shql_inspector_open` stores empty cell values as `(null)`
- `_shql_inspector_on_key` ↑/↓ moves scroll (scroll_top changes)
- `_shql_inspector_on_key` Esc sets `_SHQL_INSPECTOR_ACTIVE=0` and returns 0
- `_shql_inspector_on_key` Enter sets `_SHQL_INSPECTOR_ACTIVE=0` and returns 0
- `_shql_inspector_on_key` q sets `_SHQL_INSPECTOR_ACTIVE=0` and returns 0 (not 1)
- Key column width computed as max key length, min 8, max 20
- Footer hint is the inspector hint string when `_SHQL_INSPECTOR_ACTIVE=1`

---

## Out of scope

- Multi-line value wrapping (clip + ellipsis is sufficient for Phase 5.5)
- Edit-in-place
- Copy to clipboard
- Inspector from query result grid (Phase 6 concern)
