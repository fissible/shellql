#!/usr/bin/env bash
# src/screens/header.sh — Shared header bar renderer
#
# REQUIRES: src/theme.sh sourced (SHQL_THEME_HEADER_BG set).
#           src/state.sh sourced (SHQL_DRIVER, SHQL_DB_PATH, etc.).
#
# Public functions:
#   _shql_breadcrumb [table]   — print driver-aware breadcrumb string
#   _shql_header_render top left width crumbs

# ── _shql_breadcrumb ──────────────────────────────────────────────────────────
#
# Prints a breadcrumb string reflecting the active driver and optional table.
#
#   SHQL_DRIVER=sqlite        →  sqlite://chinook.sqlite [→ users]
#   SHQL_DRIVER=mysql         →  mysql://localhost/chinook [→ users]
#   SHQL_DRIVER=postgresql    →  postgresql://localhost/chinook [→ users]
#   SHQL_DRIVER="" (default)  →  localhost › chinook [› users]
#
# The "→" separator is used in URI-style breadcrumbs; "›" in the default style.

_shql_breadcrumb() {
    local _table="${1:-}"
    local _driver="${SHQL_DRIVER:-}"

    case "$_driver" in
        sqlite)
            local _file; _file="$(basename "${SHQL_DB_PATH:-}")"
            if [[ -n "$_table" ]]; then
                printf 'sqlite://%s → %s' "$_file" "$_table"
            else
                printf 'sqlite://%s' "$_file"
            fi
            ;;
        mysql|postgresql|postgres)
            local _host="${SHQL_DB_HOST:-localhost}"
            local _dbname="${SHQL_DB_NAME:-}"
            if [[ -n "$_table" ]]; then
                printf '%s://%s/%s → %s' "$_driver" "$_host" "$_dbname" "$_table"
            else
                printf '%s://%s/%s' "$_driver" "$_host" "$_dbname"
            fi
            ;;
        *)
            local _host="${SHQL_DB_HOST:-localhost}"
            local _dbname="${SHQL_DB_NAME:-$(basename "${SHQL_DB_PATH:-}")}"
            if [[ -n "$_table" ]]; then
                printf '%s › %s › %s' "$_host" "$_dbname" "$_table"
            else
                printf '%s › %s' "$_host" "$_dbname"
            fi
            ;;
    esac
}

# ── _shql_header_render ───────────────────────────────────────────────────────

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
    shellframe_fb_print "$_top" "$_left" "$_text" "$_bg"
    shellframe_fb_fill  "$_top" "$(( _left + _tlen ))" "$_pad" " " "$_bg"
}
