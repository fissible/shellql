#!/usr/bin/env bash
# shellql/src/json.sh — JSON get/set utilities using sqlite3 :memory:
#
# REQUIRES: sqlite3 on PATH (used as the JSON engine for all operations).
# Flat top-level keys only. Nested paths are not supported.
# Boolean/null types are out of scope; behaviour is undefined if present.

[[ -n "${_SHQL_JSON_LOADED:-}" ]] && return 0
_SHQL_JSON_LOADED=1

# ── shql_json_get ─────────────────────────────────────────────────────────────
# shql_json_get <file> <key>
# Extract top-level <key> from JSON file. Print value to stdout.
# Returns 1 if file missing OR if sqlite3 output is empty (key absent = SQL NULL).
# IMPORTANT: callers must check exit code, not output — sqlite3 exits 0 for a
# missing key and prints nothing. Use: fn ...; rc=$?  NOT  local v=$(fn ...)

shql_json_get() {
    local _file="$1" _key="$2"
    [[ ! -f "$_file" ]] && return 1
    local _json _escaped _out
    _json=$(cat "$_file")
    _escaped="${_json//\'/\'\'}"
    _out=$(printf "SELECT json_extract('%s', '$.%s');" "$_escaped" "$_key" | sqlite3 :memory:)
    [[ -z "$_out" ]] && return 1
    printf '%s\n' "$_out"
}

# ── shql_json_get_str ─────────────────────────────────────────────────────────
# shql_json_get_str <json_string> <key>
# Same as shql_json_get but operates on a raw JSON string instead of a file.

shql_json_get_str() {
    local _json="$1" _key="$2"
    local _escaped _out
    _escaped="${_json//\'/\'\'}"
    _out=$(printf "SELECT json_extract('%s', '$.%s');" "$_escaped" "$_key" | sqlite3 :memory:)
    [[ -z "$_out" ]] && return 1
    printf '%s\n' "$_out"
}

# ── shql_json_set ─────────────────────────────────────────────────────────────
# shql_json_set <file> <key> <value>
# Add or update <key> in JSON file. Creates file with {} if it does not exist.
# Numbers matching ^-?[0-9]+([.][0-9]*)?$ are stored as JSON numbers; all
# other values are stored as quoted JSON strings.

shql_json_set() {
    local _file="$1" _key="$2" _value="$3"
    local _json='{}'
    [[ -f "$_file" ]] && _json=$(cat "$_file")
    local _escaped="${_json//\'/\'\'}"
    local _sql_value
    if [[ "$_value" =~ ^-?[0-9]+([.][0-9]*)?$ ]]; then
        _sql_value="$_value"
    else
        local _vesc="${_value//\'/\'\'}"
        _sql_value="'$_vesc'"
    fi
    local _new_json
    _new_json=$(printf "SELECT json_set('%s', '$.%s', %s);" \
        "$_escaped" "$_key" "$_sql_value" | sqlite3 :memory:)
    printf '%s' "$_new_json" > "$_file"
}

# ── shql_json_keys ────────────────────────────────────────────────────────────
# shql_json_keys <file>
# Print all top-level keys, one per line.

shql_json_keys() {
    local _file="$1"
    [[ ! -f "$_file" ]] && return 1
    local _json _escaped
    _json=$(cat "$_file")
    _escaped="${_json//\'/\'\'}"
    printf "SELECT key FROM json_each('%s');" "$_escaped" | sqlite3 :memory:
}
