# Welcome Screen: Connection Tiles

**Date:** 2026-03-28
**Status:** Design approved

## Summary

Replace the flat list-based welcome screen with a responsive grid of connection tiles. Each tile shows connection metadata (name, path, table count, file size, last opened, driver icon). Tiles are navigable via arrow keys and clickable via mouse. Shift+click (or right-click) opens a context menu with actions.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout | Responsive grid, capped at 4 columns | Compact, spatial nav with arrow keys, scales 1–20+ connections |
| Tile style | Box-drawn borders (single normal, double selected) | Clean separation, familiar TUI aesthetic |
| Tile metadata | Name, path, table count, file size, last opened, driver icon | All metadata — gives full picture at a glance |
| Column breakpoints | `min(floor(width / 26), 4)` | Extra width → wider tiles (more room for paths) |
| "New Connection" | Dashed-border tile at end of grid | Discoverable, navigable same as connections |
| Shift+click action | Context menu (reuse existing widget) | Consistent with TABLE screen, less new code |
| Mouse support | Left-click opens, Shift+click context menu | Current welcome screen has no mouse support |

## Tile Layout

```
Tile height: 6 rows (border + 4 content lines + border)
Tile min width: 24 chars (content) + 2 (borders) = 26
Columns: min(floor(available_width / 26), 4)
Tile width: floor(available_width / columns)
Gap: 1 char between tiles (taken from tile width budget)
```

### Tile anatomy (6 rows)

```
┌──────────────────────┐    ╔══════════════════════╗
│ 🗄 rosewood          │    ║ 🗄 rosewood          ║  ← selected (blue bg + double border)
│ ~/Desktop/rosewoo…   │    ║ ~/Desktop/rosewoo…   ║
│ 35 tables · 2.1 MB   │    ║ 35 tables · 2.1 MB   ║
│ Today                 │    ║ Today                 ║
└──────────────────────┘    ╚══════════════════════╝
   (neutral dark bg)           (blue-tinted bg)
```

Selected tile: blue-tinted background (dark navy, e.g. `\033[48;5;17m`) + double-line border in accent color.
Unselected tiles: neutral dark background + single-line border in gray.

┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
╎                        ╎  ← "New Connection" tile
╎     + New Connection   ╎
╎                        ╎
╎                        ╎
└╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘
```

### Content lines

1. **Driver icon + name**: `🗄 rosewood` — bold when selected, icon from theme
2. **Path**: `~/Desktop/rosewood_and_vine.db` — gray, truncated with `…` if too long
3. **Metadata**: `35 tables · 2.1 MB` — dim gray
4. **Last opened**: `Today` / `Yesterday` / `3 days ago` / `Mar 15` — dim

### Path display

- Replace `$HOME` with `~`
- Truncate from the left if too long: `…/very/long/path/db.sqlite`

## Metadata Collection

Metadata is gathered at welcome screen init time:

- **Table count**: `sqlite3 "$path" "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view')"` — fast query, no full schema load
- **File size**: `stat` call — `stat -f%z` on macOS, `stat -c%s` on Linux. Format as human-readable (KB/MB/GB)
- **Last opened**: Already in `last_accessed` table. Convert ISO8601 to relative string
- **Driver icon**: From `SHQL_THEME_TABLE_ICON` or default `🗄`

Skip metadata for files that don't exist (show `?` or `missing`).

## Navigation

### Keyboard

| Key | Action |
|-----|--------|
| `←` `→` | Move cursor between columns |
| `↑` `↓` | Move cursor between rows |
| `Enter` | Open selected connection (or "New" form) |
| `n` | Open "New Connection" form |
| `e` | Edit selected connection |
| `d` | Delete selected connection (confirmation modal) |
| `q` | Quit |
| `Home` | Jump to first tile |
| `End` | Jump to last tile |

Cursor wraps: right from last column → first column of next row. Down from last row → no-op (don't wrap to top).

### Mouse

| Action | Effect |
|--------|--------|
| Left-click on tile | Select + open (double-duty: single click) |
| Shift+click on tile | Select tile, open context menu |
| Right-click on tile | Same as Shift+click |
| Scroll wheel | Scroll grid vertically (if more rows than viewport) |

### Context Menu Items

```
Open            (Enter)
Edit            (e)
Delete          (d)
Copy Path
```

"Copy Path" writes the db path to clipboard via `pbcopy` (macOS) / `xclip` (Linux). No keyboard shortcut — menu-only action.

## Screen Layout

```
Row 1:        Header bar ("ShellQL")
Row 2:        Section label ("Recent Connections") — dim gray, left-aligned
Rows 3..N-1:  Tile grid (scrollable if tiles exceed viewport)
Row N:        Footer hints
```

## Scroll

If tiles overflow the viewport vertically, use `shellframe_scroll` for vertical paging. Scroll context: `welcome_tiles`. Arrow key navigation auto-scrolls to keep the selected tile visible.

## Theme Integration

New theme variables (with defaults):

```bash
SHQL_THEME_TILE_BG               # tile background (default: 48;5;236 — dark gray)
SHQL_THEME_TILE_BORDER           # border color (default: SHELLFRAME_GRAY)
SHQL_THEME_TILE_SELECTED_BG     # selected tile bg (default: 48;5;17 — dark navy blue)
SHQL_THEME_TILE_SELECTED_BORDER  # selected border color (default: 38;5;68 — steel blue)
```

## Empty State

No connections → show centered message + the "New Connection" tile alone:

```
                No saved databases.

          ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
          ╎     + New Connection   ╎
          ╎                        ╎
          └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘

        Press Enter or click to add a connection.
```

## Bug Fix: Unstyled fb_fill

All `shellframe_fb_fill` calls in welcome.sh and table.sh that omit the style argument must pass an explicit background (e.g., `$SHQL_THEME_CONTENT_BG` or `""`) to prevent color bleed from cursor/highlight styles. This is a separate fix applied alongside the tile refactor.

## Files Modified

- `src/screens/welcome.sh` — full rewrite of render/navigation/mouse handling
- `src/themes/basic.sh` — add tile theme variables
- `src/themes/cascade.sh` — add tile theme variables
- `src/themes/uranium.sh` — add tile theme variables

## Files NOT Modified

- `src/connections.sh` — data layer unchanged, metadata queries added to welcome.sh
- `src/screens/table.sh` — no changes (TABLE screen is separate)
- Shellframe widgets — no new widget needed; tiles are rendered directly with `shellframe_fb_put`/`shellframe_fb_fill`/`shellframe_panel_render`
