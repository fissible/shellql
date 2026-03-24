# Cascade Theme — Design Spec

**Date:** 2026-03-24
**Status:** Draft — awaiting user review

---

## Motivation

The default "basic" theme uses high-contrast reverse video for row selection and monochrome styling throughout. The "cascade" theme introduces a richer color palette with reduced highlight contrast, alternating row stripes, background tinting, and iconography — making ShellQL feel more like a polished database GUI while remaining terminal-native.

---

## Theme tokens

These are the new `SHQL_THEME_*` globals that `cascade.sh` will set. Existing tokens are preserved; new ones are added. The theme file is self-contained — no shellframe changes required unless noted.

### New tokens (cascade-specific)

| Token | Value | Purpose |
|-------|-------|---------|
| `SHQL_THEME_HEADER_BG` | `\033[48;5;53m\033[37m` (dark purple bg, white text) | Header bar background |
| `SHQL_THEME_CONTENT_BG` | `\033[48;5;236m` (dark gray, #303030) | Content area + tabbar background |
| `SHQL_THEME_SIDEBAR_BG` | _(terminal default / black)_ | Tables pane stays black |
| `SHQL_THEME_SIDEBAR_BORDER` | `"none"` | No border on tables pane |
| `SHQL_THEME_ROW_STRIPE_BG` | `\033[48;5;238m` (lighter gray, #444444) | Alternating data row background |
| `SHQL_THEME_CURSOR_BG` | `\033[48;5;240m` (subtle gray, #585858) | Dimmer row highlight |
| `SHQL_THEME_CURSOR_BOLD` | `\033[1m` | Bold text on cursor row (pairs with dim bg) |
| `SHQL_THEME_TABLE_ICON` | `▤ ` | Prepended to table names in sidebar |
| `SHQL_THEME_VIEW_ICON` | `◉ ` | Prepended to view names in sidebar |
| ~~`SHQL_THEME_GRID_ROW_BORDER`~~ | ~~`1`~~ | ~~Dropped — stripes provide row separation without consuming screen space~~ |
| `SHQL_THEME_TAB_ACTIVE` | _(normal text)_ | Active tab label style |
| `SHQL_THEME_TAB_INACTIVE_BG` | `\033[7m` (inverted) | Inactive tab label style |

### Color palette rationale

```
Terminal default bg (black)  ← sidebar stays here
  ↓
236 (#303030) ← content area / tab bar background
238 (#444444) ← alternating stripe rows (lighter than 236, won't merge with sidebar)
240 (#585858) ← cursor highlight (dim, readable)
 53 (#5f005f) ← header bar (dark purple)
```

The three grays (236, 238, 240) are visually distinct from each other and from the black sidebar. Stripe rows at 238 will NOT merge with the sidebar (which is black / terminal default).

---

## Visual changes

### 1. Header bar
- Dark purple background (`48;5;53`), white text
- Already controlled by `SHQL_THEME_HEADER_BG` — just set the token

### 2. Sidebar (tables pane)
- **Remove border** — when `SHQL_THEME_SIDEBAR_BORDER == "none"`, skip `shellframe_panel_render` and render the table list directly
- Background stays terminal default (black)
- **Table icons** — prepend `▤ ` to table names, `◉ ` to view names
  - Requires: `shql_db_list_tables` returns type info, OR query `sqlite_master.type` to distinguish tables from views
  - Simpler: new function `shql_db_list_objects` that returns `name\ttype` (table/view)

### 3. Content area background
- Fill content region with `SHQL_THEME_CONTENT_BG` before rendering grid/schema/query
- This makes the active tab (normal text on gray bg) visually "connected" to the content below

### 4. Data grid — alternating row stripes
- Odd rows: content bg (236)
- Even rows: stripe bg (238)
- **Requires shellframe change:** `shellframe_grid_render` needs to support `SHELLFRAME_GRID_STRIPE_BG` — when set, apply it to even-numbered data rows
- **Cross-repo: shellframe XS change** — add 4 lines to the grid render loop

### 5. ~~Data grid — row borders~~ (DROPPED)
- Dropped in favor of alternating stripes only. Stripes provide row separation without halving visible rows. This matches industry standard (DataGrip, TablePlus, pgAdmin).

### 6. Dimmer cursor highlight
- Replace `SHELLFRAME_REVERSE` (full inversion) with `SHQL_THEME_CURSOR_BG` + `SHQL_THEME_CURSOR_BOLD`
- **Requires shellframe change:** `shellframe_grid_render` needs `SHELLFRAME_GRID_CURSOR_STYLE` — when set, use it instead of `$_rev`
- **Cross-repo: shellframe XS change** — 2-line conditional

### 7. Tab styling
- Already implemented: active=normal, inactive=inverted, +SQL=button
- Cascade theme just sets the token values

---

## Implementation breakdown

### Phase A — shellql-only (no shellframe changes)

| Task | Effort | Description |
|------|--------|-------------|
| A1 | XS | Create `src/themes/cascade.sh` with all new tokens |
| A2 | XS | Header bar: already works via `SHQL_THEME_HEADER_BG` |
| A3 | S | Sidebar: conditional border removal, apply sidebar bg |
| A4 | S | Sidebar: table/view icons — query `sqlite_master.type`, update mock |
| A5 | XS | Content area: fill bg before content render |
| A6 | XS | Tab bar: apply content bg to tab row background |

### Phase B — shellframe grid enhancements (cross-repo)

| Task | Effort | Description |
|------|--------|-------------|
| B1 | XS | Grid: `SHELLFRAME_GRID_STRIPE_BG` — alternating row background |
| ~~B2~~ | — | ~~Dropped — row borders consume too much space~~ |
| B3 | XS | Grid: `SHELLFRAME_GRID_CURSOR_STYLE` — custom cursor highlight |

### Phase C — wire theme tokens to grid

| Task | Effort | Description |
|------|--------|-------------|
| C1 | XS | Set `SHELLFRAME_GRID_STRIPE_BG` / `ROW_BORDER` / `CURSOR_STYLE` from theme tokens before grid render |

---

## Files changed

| File | Phase | Change |
|------|-------|--------|
| `src/themes/cascade.sh` | A1 | New file — all token definitions |
| `src/screens/table.sh` | A3–A6 | Sidebar border conditional, content bg fill, tab bar bg |
| `src/screens/table.sh` | C1 | Set grid globals from theme tokens |
| `src/db.sh` | A4 | New `shql_db_list_objects` (returns name + type) |
| `src/db_mock.sh` | A4 | Mock `shql_db_list_objects` |
| `shellframe/src/widgets/grid.sh` | B1–B3 | Stripe, row border, cursor style support |

---

## Testing

- A1–A6: visual smoke test with `SHQL_THEME=cascade SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql`
- B1–B3: add unit tests in shellframe for stripe/border/cursor globals
- C1: integration test verifying theme tokens propagate to grid globals

---

## Resolved questions

1. **256-color requirement** — Yes, detect capability (`$TERM` / `tput colors`) and fall back to basic theme.
2. **Row borders** — Dropped. Alternating stripes provide row separation without consuming screen space.
3. **Icons** — Use standard Unicode (`▤` / `◉`). Works in all modern terminals. Nerd font icons can be an opt-in config later.
