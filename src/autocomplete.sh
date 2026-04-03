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

# ── _shql_tolower / _shql_toupper ─────────────────────────────────────────────
# Pure-bash case conversion — no subshell at the call site.
# Usage: _shql_tolower "$string" outvar   (sets outvar to lowercase string)
#        _shql_toupper "$string" outvar   (sets outvar to uppercase string)

_shql_tolower() {
    local _s="$1" _v="$2" _r="" _i _c
    for (( _i=0; _i < ${#_s}; _i++ )); do
        _c="${_s:_i:1}"
        case "$_c" in
            A) _r+=a ;; B) _r+=b ;; C) _r+=c ;; D) _r+=d ;; E) _r+=e ;;
            F) _r+=f ;; G) _r+=g ;; H) _r+=h ;; I) _r+=i ;; J) _r+=j ;;
            K) _r+=k ;; L) _r+=l ;; M) _r+=m ;; N) _r+=n ;; O) _r+=o ;;
            P) _r+=p ;; Q) _r+=q ;; R) _r+=r ;; S) _r+=s ;; T) _r+=t ;;
            U) _r+=u ;; V) _r+=v ;; W) _r+=w ;; X) _r+=x ;; Y) _r+=y ;;
            Z) _r+=z ;; *) _r+=$_c ;;
        esac
    done
    printf -v "$_v" '%s' "$_r"
}

_shql_toupper() {
    local _s="$1" _v="$2" _r="" _i _c
    for (( _i=0; _i < ${#_s}; _i++ )); do
        _c="${_s:_i:1}"
        case "$_c" in
            a) _r+=A ;; b) _r+=B ;; c) _r+=C ;; d) _r+=D ;; e) _r+=E ;;
            f) _r+=F ;; g) _r+=G ;; h) _r+=H ;; i) _r+=I ;; j) _r+=J ;;
            k) _r+=K ;; l) _r+=L ;; m) _r+=M ;; n) _r+=N ;; o) _r+=O ;;
            p) _r+=P ;; q) _r+=Q ;; r) _r+=R ;; s) _r+=S ;; t) _r+=T ;;
            u) _r+=U ;; v) _r+=V ;; w) _r+=W ;; x) _r+=X ;; y) _r+=Y ;;
            z) _r+=Z ;; *) _r+=$_c ;;
        esac
    done
    printf -v "$_v" '%s' "$_r"
}

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

    # Uppercase for keyword matching — pure bash, no subshell
    local _ub
    _shql_toupper "$_before" _ub

    # Keywords that suggest table names follow — use [[ =~ ]] (no subshell)
    local _tables_pat='(FROM|JOIN|INTO|UPDATE|TABLE|DROP[[:space:]]+(TABLE|VIEW))[[:space:]]*$'
    if [[ "$_ub" =~ $_tables_pat ]]; then
        _SHQL_AC_SQL_CTX="tables"
        return 0
    fi

    # Keywords that suggest column names follow
    local _cols_pat='(SELECT|WHERE|SET|ON|AND|OR|BY|HAVING|,)[[:space:]]*$'
    if [[ "$_ub" =~ $_cols_pat ]]; then
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
    [[ ${#_prefix} -lt 2 ]] && return 0

    _shql_ac_sql_context "$_prefix"

    local _lcp
    _shql_tolower "$_prefix" _lcp

    local _lc _entry

    # Dot-notation: scoped columns → return "table.col" completions
    if [[ "$_SHQL_AC_SQL_CTX" == "cols_dot" ]]; then
        local _col_prefix="${_prefix#*.}"
        local _lcc
        _shql_tolower "$_col_prefix" _lcc
        for _entry in "${_SHQL_AC_COLS[@]+"${_SHQL_AC_COLS[@]}"}"; do
            local _et="${_entry%%$'\t'*}"
            local _ec="${_entry#*$'\t'}"
            if [[ "$_et" == "$_SHQL_AC_COL_TABLE" ]]; then
                _shql_tolower "$_ec" _lc
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
            _shql_tolower "$_t" _lc
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
            _shql_tolower "$_col" _lc
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
        _shql_tolower "$_kw" _lkw
        if [[ "$_lkw" == "$_lcp"* ]]; then
            eval "${_out}+=(\"${_kw}\")"
        fi
    done
}
