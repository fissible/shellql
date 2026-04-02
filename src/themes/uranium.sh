#!/usr/bin/env bash
# src/themes/uranium.sh — Uranium theme (rounded borders, green/cyan palette)
#
# Requires 256-color terminal. Falls back to basic theme if unsupported.

# ── 256-color detection ───────────────────────────────────────────────────────
_shql_uranium_colors=$(tput colors 2>/dev/null || printf '0')
if (( _shql_uranium_colors < 256 )); then
    source "${_SHQL_ROOT}/src/themes/basic.sh"
    return 0
fi

# ── Panel styling ─────────────────────────────────────────────────────────────
SHQL_THEME_PANEL_STYLE="rounded"
SHQL_THEME_PANEL_STYLE_FOCUSED="double"

# ── Text colors ───────────────────────────────────────────────────────────────
SHQL_THEME_KEY_COLOR=$'\033[38;2;80;186;42m\033[1m'  # uranium green + bold
SHQL_THEME_VALUE_COLOR=$'\033[97m'                   # bright white
SHQL_THEME_VALUE_ACCENT_COLOR=$'\033[93m'            # amber/gold
SHQL_THEME_RESET=$'\033[0m'

# ── Header bar: muted green background, bright white text ────────────────────
SHQL_THEME_HEADER_BG=$'\033[48;2;40;100;20m\033[97m'

# ── Sidebar: very dark green-tinted gray ─────────────────────────────────────
SHQL_THEME_SIDEBAR_BORDER="none"
SHQL_THEME_SIDEBAR_BG=$'\033[48;5;234m'           # 234 (#1c1c1c) — dark gray
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "

# ── Content area: medium dark gray ───────────────────────────────────────────
SHQL_THEME_CONTENT_BG=$'\033[48;5;236m'

# ── Grid / data table ───────────────────────────────────────────────────────
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;238m'
SHQL_THEME_CURSOR_BG=$'\033[48;2;30;70;20m'       # dark green tint
SHQL_THEME_CURSOR_BOLD=""

# ── Sidebar cursor: uranium green bg + black text ────────────────────────────
SHQL_THEME_SIDEBAR_CURSOR_BG=$'\033[48;2;40;100;20m\033[97m'

# ── Query panel: green accent ────────────────────────────────────────────────
SHQL_THEME_QUERY_PANEL_COLOR=$'\033[38;2;80;186;42m'
SHQL_THEME_EDITOR_FOCUSED_BG=$'\033[48;5;235m'    # 235 — darker than content

# ── Grid header ──────────────────────────────────────────────────────────────
SHQL_THEME_GRID_HEADER_COLOR=$'\033[38;2;80;186;42m'  # uranium green
SHQL_THEME_GRID_HEADER_BG=$'\033[48;5;237m'           # 237 — shade lighter than content
SHQL_THEME_GRID_HEADER_BORDER=1

# ── Tab bar ──────────────────────────────────────────────────────────────────
SHQL_THEME_TAB_ACTIVE=""                              # uses CONTENT_BG
SHQL_THEME_TAB_INACTIVE_BG=$'\033[48;5;238m\033[37m'  # medium gray bg + light gray text

# ── Footer / status bar ─────────────────────────────────────────────────────
SHQL_THEME_FOOTER_BG=$'\033[48;5;234m'                # matches sidebar

# ── Tiles (welcome screen) ──────────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;236m'
SHQL_THEME_TILE_BORDER=$'\033[38;5;242m'
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;2;30;70;20m'       # dark green tint
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;2;80;186;42m'  # uranium green
