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
SHQL_THEME_KEY_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_VALUE_COLOR="${SHELLFRAME_RESET:-}"
SHQL_THEME_VALUE_ACCENT_COLOR="${SHELLFRAME_BOLD:-}"
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
SHQL_THEME_CURSOR_BG=$'\033[48;5;54m'     # 54 (#5f0087) — muted purple, matches focus accent
SHQL_THEME_CURSOR_BOLD=$'\033[1m'

# ── Sidebar cursor: blue ──────────────────────────────────────────────────────
SHQL_THEME_SIDEBAR_CURSOR_BG=$'\033[48;5;25m\033[97m'   # dark blue bg + bright white text

# ── Query panel: bright purple accent ──────────────────────────────────────────
SHQL_THEME_QUERY_PANEL_COLOR=$'\033[38;5;135m'   # bright purple border/title
SHQL_THEME_EDITOR_FOCUSED_BG=$'\033[48;5;235m'   # 235 (#262626) — darker than content, lighter than sidebar

# ── Grid header color ─────────────────────────────────────────────────────────
SHQL_THEME_GRID_HEADER_COLOR=$'\033[38;5;110m'    # muted blue/cyan column headers

# ── Tab bar ───────────────────────────────────────────────────────────────────
SHQL_THEME_TAB_ACTIVE=""                          # uses CONTENT_BG (set at render time)
SHQL_THEME_TAB_INACTIVE_BG=$'\033[48;5;238m\033[37m'  # medium gray bg + light gray text
