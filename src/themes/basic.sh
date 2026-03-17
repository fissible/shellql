#!/usr/bin/env bash
# src/themes/basic.sh — Default theme (current aesthetic)
#
# Sourced after shellframe, so SHELLFRAME_BOLD / SHELLFRAME_RESET /
# SHELLFRAME_REVERSE are already set by shellframe's draw.sh.
# The :- fallbacks are a safety net for test environments.

SHQL_THEME_PANEL_STYLE="single"
SHQL_THEME_KEY_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_VALUE_COLOR="${SHELLFRAME_RESET:-}"
SHQL_THEME_VALUE_ACCENT_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_HEADER_BG="${SHELLFRAME_BOLD:-$'\033[1m'}${SHELLFRAME_REVERSE:-$'\033[7m'}"
SHQL_THEME_RESET="${SHELLFRAME_RESET:-$'\033[0m'}"
SHQL_THEME_TABBAR_BG="${SHELLFRAME_BOLD:-$'\033[1m'}${SHELLFRAME_REVERSE:-$'\033[7m'}"  # bold + reverse for inactive tabs
