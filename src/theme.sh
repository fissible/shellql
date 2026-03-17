#!/usr/bin/env bash
# src/theme.sh — ShellQL theme loader
#
# Call shql_theme_load <name> after sourcing shellframe so that SHELLFRAME_*
# globals are populated before basic.sh references them.

SHQL_THEME="${SHQL_THEME:-basic}"

shql_theme_load() {
    local _name="${1:-basic}"
    local _file="${_SHQL_ROOT}/src/themes/${_name}.sh"
    if [[ ! -f "$_file" ]]; then
        printf 'shql: unknown theme "%s", falling back to basic\n' "$_name" >&2
        _file="${_SHQL_ROOT}/src/themes/basic.sh"
    fi
    source "$_file" || true
}
