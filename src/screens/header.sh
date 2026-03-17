#!/usr/bin/env bash
# src/screens/header.sh — Shared header bar renderer
#
# REQUIRES: src/theme.sh sourced (SHQL_THEME_HEADER_BG set).
#
# Usage: _shql_header_render top left width crumbs
#   top    — terminal row (1-indexed)
#   left   — terminal column (1-indexed); always 1 for the header region
#   width  — full terminal width
#   crumbs — breadcrumb string, e.g. "ShellQL  ›  db.sqlite  ›  users"

_shql_header_render() {
    local _top="$1" _left="$2" _width="$3" _crumbs="$4"
    local _bg="${SHQL_THEME_HEADER_BG:-$'\033[7m'}"
    local _rst="${SHQL_THEME_RESET:-$'\033[0m'}"
    local _text=" ${_crumbs}"
    # ${#_text} counts characters (not bytes) in UTF-8 locale; › (U+203A) = 1 char = 1 column.
    # Assumes UTF-8 locale (LC_ALL=C environments will mis-count multi-byte separators).
    local _tlen=${#_text}
    local _pad=$(( _width - _tlen ))
    (( _pad < 0 )) && _pad=0
    local _spaces
    printf -v _spaces '%*s' "$_pad" ''
    printf '\033[%d;%dH%s%s%s%s' \
        "$_top" "$_left" "$_bg" "$_text" "$_spaces" "$_rst" >/dev/tty
}
