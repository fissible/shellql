#!/usr/bin/env bash
# src/themes/cascade.sh — Cascade theme (dark purple header, gray content, dim cursor)
#
# Requires 256-color terminal. Falls back to basic theme if unsupported.

# ── 256-color detection ───────────────────────────────────────────────────────
_shql_cascade_colors=$(tput colors 2>/dev/null || printf '0')
if (( _shql_cascade_colors < 256 )); then
    source "${_SHQL_ROOT}/src/themes/basic.sh"
    return 0
fi

# ── Panel styling ─────────────────────────────────────────────────────────────
SHQL_THEME_PANEL_STYLE="single"
SHQL_THEME_PANEL_STYLE_FOCUSED="double"

# ── Text colors ───────────────────────────────────────────────────────────────
SHQL_THEME_KEY_COLOR=$'\033[38;5;140m\033[1m'   # muted purple (grid header color) + bold
SHQL_THEME_VALUE_COLOR=$'\033[97m'              # bright white
SHQL_THEME_VALUE_ACCENT_COLOR=$'\033[38;5;135m\033[1m'  # bright purple + bold
SHQL_THEME_RESET=$'\033[0m'

# ── Header bar: dark purple background, white text ────────────────────────────
SHQL_THEME_HEADER_BG=$'\033[48;5;53m\033[97m'

# ── Sidebar: very dark gray (not black) ───────────────────────────────────────
SHQL_THEME_SIDEBAR_BORDER="none"
SHQL_THEME_SIDEBAR_BG=$'\033[48;5;234m'          # 234 (#1c1c1c) — dark gray, lighter than black
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "

# ── Content area: medium gray background ──────────────────────────────────────
SHQL_THEME_CONTENT_BG=$'\033[48;5;236m'

# ── Grid: alternating stripes + dim cursor ────────────────────────────────────
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;238m'
SHQL_THEME_CURSOR_BG=$'\033[48;5;54m'     # 54 (#5f0087) — dark purple, close to header bg
SHQL_THEME_CURSOR_BOLD=""

# ── Sidebar cursor: blue ──────────────────────────────────────────────────────
SHQL_THEME_SIDEBAR_CURSOR_BG=$'\033[48;5;25m\033[97m'   # dark blue bg + bright white text

# ── Query panel: bright purple accent ──────────────────────────────────────────
SHQL_THEME_QUERY_PANEL_COLOR=$'\033[38;5;135m'   # bright purple border/title
SHQL_THEME_EDITOR_FOCUSED_BG=$'\033[48;5;235m'   # 235 (#262626) — darker than content, lighter than sidebar

# ── Grid header ───────────────────────────────────────────────────────────────
SHQL_THEME_GRID_HEADER_COLOR=$'\033[38;5;140m'    # 140 (#af87d7) — muted purple, readable on dark bg
SHQL_THEME_GRID_HEADER_BG=$'\033[48;5;237m'       # 237 (#3a3a3a) — shade lighter than content (236)
SHQL_THEME_GRID_HEADER_BORDER=1                   # draw ─ border above header row

# ── Tab bar ───────────────────────────────────────────────────────────────────
SHQL_THEME_TAB_ACTIVE_COLOR=$'\033[97m\033[1m'    # bright white + bold
SHQL_THEME_TAB_INACTIVE_BG=$'\033[48;5;238m\033[37m'  # medium gray bg + light gray text

# ── Footer / status bar ───────────────────────────────────────────────────
SHQL_THEME_FOOTER_BG=$'\033[48;5;234m'            # 234 — matches sidebar, frames the content
SHQL_THEME_FOOTER_HINT_COLOR=$'\033[38;5;183m'    # 183 (#d7afff) — pale purple, readable on dark-gray footer

# ── Toast notifications ───────────────────────────────────────────────────────
SHELLFRAME_TOAST_SUCCESS_COLOR=$'\033[48;5;22m\033[97m'   # dark green bg + bright white text
SHELLFRAME_TOAST_ERROR_COLOR=$'\033[48;5;88m\033[97m'     # dark red bg + bright white text
SHELLFRAME_TOAST_WARNING_COLOR=$'\033[48;5;94m\033[97m'   # dark amber bg + bright white text
SHELLFRAME_TOAST_INFO_COLOR=$'\033[48;5;239m\033[37m'     # medium-dark gray bg + light gray text

# ── Tiles (welcome screen) ───────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;236m'
SHQL_THEME_TILE_BORDER=$'\033[38;5;242m'
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;5;54m'          # dark purple (matches cursor)
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;5;140m'     # muted purple
