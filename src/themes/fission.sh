#!/usr/bin/env bash
# src/themes/fission.sh — Fission theme (near-black bg, electric sky-blue accents)
#
# Inspired by fissible.dev: dark void background, bright #00afff sky blue,
# white text. Celebrates the ShellQL v1.0 launch.
#
# Requires 256-color terminal. Falls back to basic theme if unsupported.

# ── 256-color detection ───────────────────────────────────────────────────────
_shql_fission_colors=$(tput colors 2>/dev/null || printf '0')
if (( _shql_fission_colors < 256 )); then
    source "${_SHQL_ROOT}/src/themes/basic.sh"
    return 0
fi

# Color reference (256-color):
#   232 = #080808  near-black (main bg)
#   233 = #121212  dark void (sidebar)
#   234 = #1c1c1c  lifted dark (content area / editor)
#   235 = #262626  grid header strip
#   236 = #303030  row stripe
#    24 = #005f87  deep steel blue (header / footer bar)
#    25 = #005faf  dark blue (cursor highlight)
#    31 = #0087af  medium steel blue (sidebar cursor)
#    39 = #00afff  electric sky blue (primary accent — matches fissible.dev CTA)
#    75 = #5fafff  soft sky blue (secondary labels)

# ── Panel styling ─────────────────────────────────────────────────────────────
SHQL_THEME_PANEL_STYLE="single"
SHQL_THEME_PANEL_STYLE_FOCUSED="double"

# ── Text colors ───────────────────────────────────────────────────────────────
SHQL_THEME_KEY_COLOR=$'\033[38;5;75m\033[1m'            # soft sky blue + bold (inspector keys)
SHQL_THEME_VALUE_COLOR=$'\033[97m'                      # bright white
SHQL_THEME_VALUE_ACCENT_COLOR=$'\033[38;5;39m\033[1m'   # electric sky blue + bold
SHQL_THEME_RESET=$'\033[0m'

# ── Header bar: deep steel blue bg, bright white text ────────────────────────
SHQL_THEME_HEADER_BG=$'\033[48;5;24m\033[97m'

# ── Sidebar: near-void dark ───────────────────────────────────────────────────
SHQL_THEME_SIDEBAR_BORDER="none"
SHQL_THEME_SIDEBAR_BG=$'\033[48;5;233m'                 # 233 (#121212) — dark void
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "

# ── Content area: lifted dark ─────────────────────────────────────────────────
SHQL_THEME_CONTENT_BG=$'\033[48;5;234m'                 # 234 (#1c1c1c)

# ── Grid: subtle stripe + electric blue cursor ────────────────────────────────
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;236m'              # 236 (#303030) — muted stripe
SHQL_THEME_CURSOR_BG=$'\033[48;5;25m'                   # 25 (#005faf) — deep blue cursor
SHQL_THEME_CURSOR_BOLD=""

# ── Sidebar cursor: medium steel blue ────────────────────────────────────────
SHQL_THEME_SIDEBAR_CURSOR_BG=$'\033[48;5;31m\033[97m'   # 31 (#0087af) + bright white text

# ── Query panel: electric sky blue accent ────────────────────────────────────
SHQL_THEME_QUERY_PANEL_COLOR=$'\033[38;5;39m'           # 39 (#00afff) — panel borders/focus
SHQL_THEME_EDITOR_FOCUSED_BG=$'\033[48;5;233m'          # 233 — darker than content for contrast

# ── Grid header ───────────────────────────────────────────────────────────────
SHQL_THEME_GRID_HEADER_COLOR=$'\033[38;5;75m'           # 75 (#5fafff) — soft sky blue labels
SHQL_THEME_GRID_HEADER_BG=$'\033[48;5;235m'             # 235 (#262626) — distinct strip
SHQL_THEME_GRID_HEADER_BORDER=1                         # draw ─ border above header row

# ── Tab bar ───────────────────────────────────────────────────────────────────
SHQL_THEME_TAB_ACTIVE_COLOR=$'\033[97m\033[1m'          # bright white + bold
SHQL_THEME_TAB_INACTIVE_BG=$'\033[48;5;236m\033[38;5;245m'  # dark stripe bg + muted text

# ── Footer / status bar ───────────────────────────────────────────────────────
SHQL_THEME_FOOTER_BG=$'\033[48;5;24m\033[97m'           # matches header — deep steel blue
SHQL_THEME_FOOTER_HINT_COLOR=$'\033[38;5;117m'          # 117 (#87d7ff) — light sky blue, readable on steel-blue bg

# ── Toast notifications ───────────────────────────────────────────────────────
SHELLFRAME_TOAST_SUCCESS_COLOR=$'\033[48;5;22m\033[97m'   # dark green bg + white text
SHELLFRAME_TOAST_ERROR_COLOR=$'\033[48;5;88m\033[97m'     # dark red bg + white text
SHELLFRAME_TOAST_WARNING_COLOR=$'\033[48;5;130m\033[97m'  # dark amber bg + white text
SHELLFRAME_TOAST_INFO_COLOR=$'\033[48;5;25m\033[38;5;75m' # deep blue bg + sky blue text

# ── Tiles (welcome screen) ────────────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;234m'
SHQL_THEME_TILE_BORDER=$'\033[38;5;238m'
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;5;24m'            # deep steel blue (matches header)
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;5;39m'        # electric sky blue (accent pop)
