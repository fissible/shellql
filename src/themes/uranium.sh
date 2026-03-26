#!/usr/bin/env bash
# src/themes/uranium.sh — Uranium theme (rounded borders, green/cyan palette)

SHQL_THEME_PANEL_STYLE="rounded"
SHQL_THEME_PANEL_STYLE_FOCUSED="double"
SHQL_THEME_KEY_COLOR=$'\033[32m'                   # green
SHQL_THEME_VALUE_COLOR=$'\033[96m'                 # bright cyan
SHQL_THEME_VALUE_ACCENT_COLOR=$'\033[93m'          # amber/gold
SHQL_THEME_HEADER_BG=$'\033[1;38;2;0;0;0;48;2;80;186;42m'  # bold true-black on RGB(80,186,42) green
SHQL_THEME_RESET=$'\033[0m'
SHQL_THEME_TABBAR_BG=$'\033[1;38;2;0;0;0;100m'              # bold true-black on dark grey (inactive tabs)
SHQL_THEME_SIDEBAR_CURSOR_BG=$'\033[48;2;80;186;42m\033[38;2;0;0;0m'  # green bg + black text (matches header)
