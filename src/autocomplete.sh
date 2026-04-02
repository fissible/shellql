#!/usr/bin/env bash
# shellql/src/autocomplete.sh — Schema-aware SQL autocomplete provider
#
# REQUIRES: shellframe sourced (includes autocomplete.sh), src/db.sh or db_mock.sh.
#
# ── Schema cache ───────────────────────────────────────────────────────────────
#   _SHQL_AC_TABLES   — flat array of table/view names
#   _SHQL_AC_COLS     — flat array of "tablename<TAB>colname" strings (bash 3.2 compat)
#
# ── SQL context values (_SHQL_AC_SQL_CTX) ─────────────────────────────────────
#   "keywords"  — no established SQL context; suggest SQL keywords
#   "tables"    — after FROM/JOIN/INTO/UPDATE/TABLE; suggest table names
#   "cols"      — after SELECT/WHERE/SET/etc; suggest column names
#   "cols_dot"  — dot-notation prefix "table.col"; suggest scoped column names
#
# ── Public API ─────────────────────────────────────────────────────────────────
#   _shql_ac_rebuild          — repopulate cache from current SHQL_DB_PATH
#   _shql_ac_provider p arr   — SHELLFRAME_AC_PROVIDER callback

_SHQL_AC_TABLES=()
_SHQL_AC_COLS=()

SHELLFRAME_AC_PROVIDER="_shql_ac_provider"

# SQL keywords offered when no schema context is established.
# Ordered by frequency of use.
_SHQL_AC_KEYWORDS=(
    SELECT FROM WHERE INSERT INTO UPDATE SET DELETE
    CREATE TABLE DROP ALTER ADD COLUMN
    JOIN LEFT RIGHT INNER OUTER ON
    AND OR NOT LIKE IN IS NULL
    ORDER BY GROUP HAVING LIMIT OFFSET DISTINCT ALL VALUES
    PRIMARY KEY AUTOINCREMENT DEFAULT UNIQUE CHECK REFERENCES
    BEGIN COMMIT ROLLBACK TRANSACTION
    INTEGER TEXT REAL BLOB
)

# ── _shql_ac_rebuild ──────────────────────────────────────────────────────────
# Rebuild the schema cache.  No-op when SHQL_DB_PATH is unset.
_shql_ac_rebuild() {
    _SHQL_AC_TABLES=()
    _SHQL_AC_COLS=()
    [[ -z "${SHQL_DB_PATH:-}" ]] && return 0

    local _line _tname
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _tname="${_line%%$'\t'*}"
        [[ -n "$_tname" ]] && _SHQL_AC_TABLES+=("$_tname")
    done < <(shql_db_list_objects "$SHQL_DB_PATH" 2>/dev/null)

    local _col_line _col_name
    for _tname in "${_SHQL_AC_TABLES[@]+"${_SHQL_AC_TABLES[@]}"}"; do
        while IFS= read -r _col_line; do
            [[ -z "$_col_line" ]] && continue
            _col_name="${_col_line%%$'\t'*}"
            [[ -n "$_col_name" ]] && _SHQL_AC_COLS+=("${_tname}"$'\t'"${_col_name}")
        done < <(shql_db_columns "$SHQL_DB_PATH" "$_tname" 2>/dev/null)
    done
}

# ── _shql_ac_sql_context ──────────────────────────────────────────────────────
# Determine SQL completion context for the current cursor position.
# Sets _SHQL_AC_SQL_CTX: "keywords" | "tables" | "cols" | "cols_dot"
# Sets _SHQL_AC_COL_TABLE: table name for scoped completion (cols_dot only)
_SHQL_AC_SQL_CTX="keywords"
_SHQL_AC_COL_TABLE=""

_shql_ac_sql_context() {
    local _prefix="$1"
    _SHQL_AC_SQL_CTX="keywords"
    _SHQL_AC_COL_TABLE=""

    # Dot-notation "table.col_prefix" → scoped column completion
    if [[ "$_prefix" == *"."* ]]; then
        _SHQL_AC_COL_TABLE="${_prefix%%.*}"
        _SHQL_AC_SQL_CTX="cols_dot"
        return 0
    fi

    local _ctx="$_SHELLFRAME_AC_CTX"
    [[ -z "$_ctx" ]] && return 0

    local _row _col _line _before
    _row="$(shellframe_editor_row "$_ctx" 2>/dev/null)" || _row=0
    _col="$(shellframe_editor_col "$_ctx" 2>/dev/null)" || _col=0
    _line="$(shellframe_editor_line "$_ctx" "$_row" 2>/dev/null)" || _line=""

    # Text before the start of the current prefix
    local _pstart=$(( _col - ${#_prefix} ))
    (( _pstart < 0 )) && _pstart=0
    _before="${_line:0:$_pstart}"

    # Uppercase for keyword matching (no subprocess — use case-insensitive grep)
    local _ub
    _ub=$(printf '%s' "$_before" | tr '[:lower:]' '[:upper:]')

    # Keywords that suggest table names follow
    if printf '%s' "$_ub" | grep -qE \
        '(FROM|JOIN|INTO|UPDATE|TABLE|DROP[[:space:]]+(TABLE|VIEW))[[:space:]]*$'; then
        _SHQL_AC_SQL_CTX="tables"
        return 0
    fi

    # Keywords that suggest column names follow
    if printf '%s' "$_ub" | grep -qE \
        '(SELECT|WHERE|SET|ON|AND|OR|BY|HAVING|,)[[:space:]]*$'; then
        _SHQL_AC_SQL_CTX="cols"
        return 0
    fi

    # Default: no established schema context → keywords
}

# ── _shql_ac_provider ─────────────────────────────────────────────────────────
# SHELLFRAME_AC_PROVIDER callback.
# Usage: _shql_ac_provider prefix out_array_name
_shql_ac_provider() {
    local _prefix="$1"
    local _out="$2"

    eval "${_out}=()"

    # Require at least 2 characters to avoid triggering on single keystrokes.
    # This also prevents the context-detection subshell calls on every key.
    [[ ${#_prefix} -lt 2 ]] && return 0

    _shql_ac_sql_context "$_prefix"

    local _lcp
    _lcp=$(printf '%s' "$_prefix" | tr '[:upper:]' '[:lower:]')

    local _lc _entry

    # Dot-notation: scoped columns → return "table.col" completions
    if [[ "$_SHQL_AC_SQL_CTX" == "cols_dot" ]]; then
        local _col_prefix="${_prefix#*.}"
        local _lcc
        _lcc=$(printf '%s' "$_col_prefix" | tr '[:upper:]' '[:lower:]')
        for _entry in "${_SHQL_AC_COLS[@]+"${_SHQL_AC_COLS[@]}"}"; do
            local _et="${_entry%%$'\t'*}"
            local _ec="${_entry#*$'\t'}"
            if [[ "$_et" == "$_SHQL_AC_COL_TABLE" ]]; then
                _lc=$(printf '%s' "$_ec" | tr '[:upper:]' '[:lower:]')
                if [[ "$_lc" == "$_lcc"* ]]; then
                    eval "${_out}+=(\"${_et}.${_ec}\")"
                fi
            fi
        done
        return 0
    fi

    # Table name suggestions
    if [[ "$_SHQL_AC_SQL_CTX" == "tables" ]]; then
        local _t
        for _t in "${_SHQL_AC_TABLES[@]+"${_SHQL_AC_TABLES[@]}"}"; do
            _lc=$(printf '%s' "$_t" | tr '[:upper:]' '[:lower:]')
            if [[ "$_lc" == "$_lcp"* ]]; then
                eval "${_out}+=(\"${_t}\")"
            fi
        done
        return 0
    fi

    # Column name suggestions (unscoped — deduplicated across tables)
    if [[ "$_SHQL_AC_SQL_CTX" == "cols" ]]; then
        local _seen=() _col _already _s
        for _entry in "${_SHQL_AC_COLS[@]+"${_SHQL_AC_COLS[@]}"}"; do
            _col="${_entry#*$'\t'}"
            _already=0
            for _s in "${_seen[@]+"${_seen[@]}"}"; do
                [[ "$_s" == "$_col" ]] && _already=1 && break
            done
            (( _already )) && continue
            _lc=$(printf '%s' "$_col" | tr '[:upper:]' '[:lower:]')
            if [[ "$_lc" == "$_lcp"* ]]; then
                eval "${_out}+=(\"${_col}\")"
                _seen+=("$_col")
            fi
        done
        return 0
    fi

    # No schema context — suggest SQL keywords
    local _kw _lkw
    for _kw in "${_SHQL_AC_KEYWORDS[@]}"; do
        _lkw=$(printf '%s' "$_kw" | tr '[:upper:]' '[:lower:]')
        if [[ "$_lkw" == "$_lcp"* ]]; then
            eval "${_out}+=(\"${_kw}\")"
        fi
    done
}
