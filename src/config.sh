#!/usr/bin/env bash
# shellql/src/config.sh — ShellQL user configuration
#
# Config file: ${XDG_CONFIG_HOME:-$HOME/.config}/shql/.toolrc  (JSON)
# No .toolrc.local — ShellQL config is global/personal, no project overrides.
#
# sqlite3 availability is checked once at source time. When sqlite3 is absent
# (e.g. SHQL_MOCK=1 on a machine without sqlite3), all reads return hardcoded
# defaults and writes are no-ops.

[[ -n "${_SHQL_CONFIG_LOADED:-}" ]] && return 0
_SHQL_CONFIG_LOADED=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/json.sh"

# Detect sqlite3 — sets script-level global (not module-local; bash has no module scope)
command -v sqlite3 >/dev/null 2>&1 \
    && _SHQL_CONFIG_HAS_SQLITE=1 \
    || _SHQL_CONFIG_HAS_SQLITE=0

_SHQL_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/shql/.toolrc"

# ── shql_config_get ───────────────────────────────────────────────────────────
# shql_config_get <key>
# Returns value for <key>, or empty string if key/file missing or sqlite3 absent.

shql_config_get() {
    local _key="$1"
    (( _SHQL_CONFIG_HAS_SQLITE )) || { printf ''; return 0; }
    local _val _rc
    _val=$(shql_json_get "$_SHQL_CONFIG_FILE" "$_key" 2>/dev/null)
    _rc=$?
    (( _rc == 0 )) && printf '%s\n' "$_val" || printf ''
}

# ── shql_config_set ───────────────────────────────────────────────────────────
# shql_config_set <key> <value>
# Write <key>=<value> to the config file. Creates dir and file if needed.
# No-op when sqlite3 is absent.

shql_config_set() {
    local _key="$1" _value="$2"
    (( _SHQL_CONFIG_HAS_SQLITE )) || return 0
    local _dir
    _dir=$(dirname "$_SHQL_CONFIG_FILE")
    [[ -d "$_dir" ]] || mkdir -p "$_dir"
    shql_json_set "$_SHQL_CONFIG_FILE" "$_key" "$_value"
}

# ── shql_config_get_fetch_limit ───────────────────────────────────────────────
# shql_config_get_fetch_limit
# Returns the fetch_limit config value with two-tier fallback:
#   sqlite3 absent or file absent → 1000  (permissive out-of-the-box default)
#   file present, key absent      → 500   (explicit "tool is configured" default)
#   file present, key present     → stored value

shql_config_get_fetch_limit() {
    # Case 1: sqlite3 absent
    (( _SHQL_CONFIG_HAS_SQLITE )) || { printf '1000\n'; return 0; }
    # Case 2: config file absent
    [[ -f "$_SHQL_CONFIG_FILE" ]] || { printf '1000\n'; return 0; }
    # Cases 3 & 4: file present — check key via exit code, NOT output
    # (local v=$(fn) swallows exit code in bash; use two-step assignment)
    local _val _rc
    _val=$(shql_json_get "$_SHQL_CONFIG_FILE" fetch_limit 2>/dev/null)
    _rc=$?
    if (( _rc != 0 )); then
        printf '500\n'   # Case 3: key absent
    else
        printf '%s\n' "$_val"  # Case 4: key present
    fi
}
