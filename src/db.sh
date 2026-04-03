#!/usr/bin/env bash
# shellql/src/db.sh — Real SQLite adapter
#
# Implements the same four-function interface as src/db_mock.sh.
# REQUIRES: sqlite3 binary on PATH.
#
# Sources config.sh directly so this file is self-contained for integration
# tests. The idempotency guard in config.sh makes re-sourcing a no-op when
# bin/shql has already loaded it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

# ── _shql_db_check_path ───────────────────────────────────────────────────────
# Internal: verify <db_path> is a readable file before calling sqlite3.

_shql_db_check_path() {
    if [[ ! -r "$1" ]]; then
        printf 'error: database not found: %s\n' "$1" >&2
        return 1
    fi
}

# ── shql_db_list_tables ───────────────────────────────────────────────────────
# shql_db_list_tables <db_path>
# Print table names, one per line. No header row (single-column output).

shql_db_list_tables() {
    local _db="$1"
    _shql_db_check_path "$_db" || return 1
    sqlite3 "$_db" \
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
}

# ── shql_db_list_objects ──────────────────────────────────────────────────────
# shql_db_list_objects <db_path>
# Print name TAB type, one per line. type is "table" or "view".

shql_db_list_objects() {
    local _db="$1"
    _shql_db_check_path "$_db" || return 1
    sqlite3 -separator $'\t' "$_db" \
        "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY type, name"
}

# ── shql_db_describe ──────────────────────────────────────────────────────────
# shql_db_describe <db_path> <table>
# Print DDL for <table> or view. No header row. Multi-line DDL text is printed
# as-is (sqlite3 default output preserves embedded newlines in TEXT values).

shql_db_describe() {
    local _db="$1" _table="$2"
    _shql_db_check_path "$_db" || return 1
    local _safe="${_table//\'/\'\'}"
    sqlite3 "$_db" \
        "SELECT sql FROM sqlite_master WHERE type IN ('table','view') AND name='$_safe'"
}

# ── shql_db_columns ───────────────────────────────────────────────────────────
# shql_db_columns <db_path> <table>
# Print column info as TSV rows (no header): name TAB type TAB flags.
# flags is a space-separated set of PK and/or NN badges, or empty.

shql_db_columns() {
    local _db="$1" _table="$2"
    _shql_db_check_path "$_db" || return 1
    local _et="${_table//\'/\'\'}"
    sqlite3 -separator $'\t' "$_db" \
        "SELECT name, type, TRIM(CASE WHEN pk>0 THEN 'PK' ELSE '' END || CASE WHEN [notnull]=1 THEN ' NN' ELSE '' END) FROM pragma_table_info('$_et')"
}

# ── shql_db_fetch ─────────────────────────────────────────────────────────────
# shql_db_fetch <db_path> <table> [limit] [offset]
# Print TSV rows with a header row as the first line.
# If limit is absent or empty, use shql_config_get_fetch_limit.
# offset is only meaningful when limit is provided and non-empty.
# Emits a warning to stderr when the config-sourced limit is the binding
# constraint (explicit limit never triggers a warning).

shql_db_fetch() {
    local _db="$1" _table="$2" _limit="${3:-}" _offset="${4:-0}" _where="${5:-}" _order="${6:-}"
    _shql_db_check_path "$_db" || return 1

    local _use_config_limit=0
    if [[ -z "$_limit" ]]; then
        _limit=$(shql_config_get_fetch_limit)
        _use_config_limit=1
        _offset=0
    fi

    local _id="${_table//\"/\"\"}"
    local _tmpfile
    _tmpfile=$(mktemp)

    local _sql="SELECT * FROM \"${_id}\""
    [[ -n "$_where" ]] && _sql+=" WHERE ${_where}"
    [[ -n "$_order" ]] && _sql+=" ORDER BY ${_order}"
    _sql+=" LIMIT ${_limit} OFFSET ${_offset}"

    local _out
    _out=$(sqlite3 -separator $'\x1f' -header "$_db" "$_sql" 2>"$_tmpfile")
    local _rc=$?

    if (( _rc != 0 )); then
        cat "$_tmpfile" >&2
        rm -f "$_tmpfile"
        return $_rc
    fi
    rm -f "$_tmpfile"

    # Single pass: emit each line and count data rows simultaneously.
    # Avoids a second full scan of $_out for the truncation check.
    local _row_count=0 _line
    while IFS= read -r _line; do
        printf '%s\n' "$_line"
        [[ -n "$_line" ]] && (( _row_count++ ))
    done <<< "$_out"
    _out=""  # free the captured string

    # Only warn when the limit came from config, not an explicit caller arg.
    if (( _use_config_limit )); then
        (( _row_count > 0 )) && (( _row_count-- ))  # subtract header
        if (( _row_count == _limit )); then
            printf 'warning: result truncated at %d rows. Set a higher fetch limit or refine your query.\n' \
                "$_limit" >&2
        fi
    fi
}

# ── shql_db_query ─────────────────────────────────────────────────────────────
# shql_db_query <db_path> <sql>
# Run arbitrary SQL. Applies config fetch_limit to SELECT/WITH queries.
# Prints TSV with header row to stdout.
# Errors (non-zero sqlite3 exit) → stderr + returns sqlite3's exit code.
# Truncation warning (exit 0, rows == limit) → stderr only, results still printed.
# Callers distinguish error from warning by checking exit code:
#   non-zero exit = error (do not use results)
#   zero exit + non-empty stderr = warning (results are valid)

shql_db_query() {
    local _db="$1" _sql="$2"
    _shql_db_check_path "$_db" || return 1

    # Strip trailing whitespace and semicolons (a semicolon inside the
    # SELECT * FROM (...) wrapper causes a sqlite3 parse error).
    # Use parameter expansion (bash 3.2 compatible) rather than =~ with a
    # character class containing ';', which confuses bash 3.2's [[ parser.
    local _prev
    while true; do
        _prev="$_sql"
        _sql="${_sql%[[:space:]]}"
        _sql="${_sql%;}"
        [[ "$_sql" == "$_prev" ]] && break
    done

    local _limit
    _limit=$(shql_config_get_fetch_limit)

    # Wrap SELECT/WITH queries; pass others through unwrapped (DDL, DML, EXPLAIN).
    # For DML (INSERT/UPDATE/DELETE/REPLACE), append SELECT changes() so the
    # caller can report affected row count.
    if [[ "$_sql" =~ ^[[:space:]]*([Ss][Ee][Ll][Ee][Cc][Tt]|[Ww][Ii][Tt][Hh])[[:space:]] ]]; then
        _sql="SELECT * FROM ($_sql) LIMIT $_limit"
    elif [[ "$_sql" =~ ^[[:space:]]*([Ii][Nn][Ss][Ee][Rr][Tt]|[Uu][Pp][Dd][Aa][Tt][Ee]|[Dd][Ee][Ll][Ee][Tt][Ee]|[Rr][Ee][Pp][Ll][Aa][Cc][Ee])[[:space:]] ]]; then
        _sql="${_sql}; SELECT changes() AS rows_affected"
    fi

    local _tmpfile
    _tmpfile=$(mktemp)

    local _out
    _out=$(sqlite3 -separator $'\x1f' -header "$_db" "$_sql" 2>"$_tmpfile")
    local _rc=$?

    if (( _rc != 0 )); then
        cat "$_tmpfile" >&2
        rm -f "$_tmpfile"
        return $_rc
    fi

    local _stderr_content
    _stderr_content=$(cat "$_tmpfile")
    rm -f "$_tmpfile"

    if [[ -n "$_stderr_content" ]]; then
        printf '%s\n' "$_stderr_content" >&2
    fi

    # Single pass: emit each line and count data rows simultaneously.
    local _row_count=0 _line
    while IFS= read -r _line; do
        printf '%s\n' "$_line"
        [[ -n "$_line" ]] && (( _row_count++ ))
    done <<< "$_out"
    _out=""  # free the captured string

    (( _row_count > 0 )) && (( _row_count-- ))  # subtract header
    if (( _row_count == _limit )); then
        printf 'warning: result truncated at %d rows. Set a higher fetch limit or refine your query.\n' \
            "$_limit" >&2
    fi
}
