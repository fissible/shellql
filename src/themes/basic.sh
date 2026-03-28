#!/usr/bin/env bash
# src/themes/basic.sh — Default theme (16-color ANSI, works on any terminal)
#
# Sourced after shellframe, so SHELLFRAME_BOLD / SHELLFRAME_RESET /
# SHELLFRAME_REVERSE / SHELLFRAME_GRAY are already set.

# ── Panel styling ─────────────────────────────────────────────────────────────
SHQL_THEME_PANEL_STYLE="single"
SHQL_THEME_PANEL_STYLE_FOCUSED="double"

# ── Text colors ───────────────────────────────────────────────────────────────
SHQL_THEME_KEY_COLOR=$'\033[1;36m'                    # bold cyan — keys in inspector
SHQL_THEME_VALUE_COLOR="${SHELLFRAME_RESET:-$'\033[0m'}"
SHQL_THEME_VALUE_ACCENT_COLOR=$'\033[1;33m'           # bold yellow — accent values
SHQL_THEME_RESET="${SHELLFRAME_RESET:-$'\033[0m'}"

# ── Header bar: blue background, bright white text ───────────────────────────
SHQL_THEME_HEADER_BG=$'\033[44m\033[97m'

# ── Sidebar ───────────────────────────────────────────────────────────────────
SHQL_THEME_SIDEBAR_BORDER="none"
SHQL_THEME_SIDEBAR_BG=$'\033[40m'                     # explicit black bg
SHQL_THEME_SIDEBAR_CURSOR_BG=$'\033[44m\033[97m'      # blue bg + bright white text
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "

# ── Content area ──────────────────────────────────────────────────────────────
SHQL_THEME_CONTENT_BG=$'\033[48;5;235m'               # 235 — very dark gray, slight lift from black

# ── Grid / data table ────────────────────────────────────────────────────────
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;237m'            # 237 — alternating row stripe
SHQL_THEME_CURSOR_BG=$'\033[44m\033[97m'              # blue bg + bright white text
SHQL_THEME_CURSOR_BOLD=""                             # cursor bg is enough, no extra bold
SHQL_THEME_GRID_HEADER_COLOR=$'\033[1;36m'            # bold cyan — column headers
SHQL_THEME_GRID_HEADER_BG=$'\033[48;5;236m'           # 236 — shade between content and stripe

# ── Query panel ───────────────────────────────────────────────────────────────
SHQL_THEME_QUERY_PANEL_COLOR=$'\033[36m'              # cyan — panel borders/focus indicators
SHQL_THEME_EDITOR_FOCUSED_BG=$'\033[48;5;234m'        # 234 — darker than content for editor

# ── Tab bar ───────────────────────────────────────────────────────────────────
SHQL_THEME_TAB_ACTIVE=""                              # inherits CONTENT_BG
SHQL_THEME_TAB_INACTIVE_BG=$'\033[100m\033[37m'       # dark gray bg + light gray text

# ── Footer / status bar ──────────────────────────────────────────────────────
SHQL_THEME_FOOTER_BG=$'\033[44m\033[97m'              # match header — blue bg + bright white

# ── Tiles (welcome screen) ───────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;236m'                  # neutral dark gray
SHQL_THEME_TILE_BORDER=$'\033[38;5;242m'              # medium gray borders
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;5;17m'          # dark navy blue
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;5;68m'      # steel blue border
