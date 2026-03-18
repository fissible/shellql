#!/usr/bin/env bash
# shellql/src/screens/query.sh — Query tab for the TABLE screen
#
# REQUIRES: shellframe sourced, src/state.sh sourced, src/db.sh or db_mock.sh.
# Sourced by bin/shql after table.sh.

# ── State globals ─────────────────────────────────────────────────────────────

_SHQL_QUERY_EDITOR_CTX="query_sql"      # shellframe editor context name
_SHQL_QUERY_GRID_CTX="query_results"    # shellframe grid context name
_SHQL_QUERY_STATUS=""                   # last status string; empty = no run yet
_SHQL_QUERY_FOCUSED_PANE="editor"       # "editor" | "results"
_SHQL_QUERY_HAS_RESULTS=0               # 0 = no results yet; 1 = grid populated
_SHQL_QUERY_INITIALIZED=0               # 0 = widget inits not yet called

# ── _shql_query_init ──────────────────────────────────────────────────────────
# Called from shql_table_init. Sets state to initial values only.
# Widget inits (editor, grid) are deferred to first render.

_shql_query_init() {
    _SHQL_QUERY_STATUS=""
    _SHQL_QUERY_FOCUSED_PANE="editor"
    _SHQL_QUERY_HAS_RESULTS=0
    _SHQL_QUERY_INITIALIZED=0
}

# ── _shql_query_run ───────────────────────────────────────────────────────────
# Run SQL via the db adapter; parse TSV into SHELLFRAME_GRID_* globals.
# Sets _SHQL_QUERY_STATUS to "<n> rows" on success or "ERROR: ..." on failure.

_shql_query_run() {
    local _sql="$1"
    local _tmpfile="/tmp/shql_query_err.$$"

    local _out
    _out=$(shql_db_query "$SHQL_DB_PATH" "$_sql" 2>"$_tmpfile")
    local _rc=$?

    if (( _rc != 0 )) || [[ -s "$_tmpfile" ]]; then
        _SHQL_QUERY_STATUS="ERROR: $(head -1 "$_tmpfile")"
        rm -f "$_tmpfile"
        return 0
    fi
    rm -f "$_tmpfile"

    # Parse TSV: first line = headers, subsequent lines = data.
    # Column widths: header_width + 2, clamped 8..30, grown by data cell widths.
    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_PK_COLS=0

    local _idx=0 _c _cell _cw _hw _cv
    local _row=()
    while IFS=$'\t' read -r -a _row; do
        [[ ${#_row[@]} -eq 0 ]] && continue
        if (( _idx == 0 )); then
            SHELLFRAME_GRID_HEADERS=("${_row[@]}")
            SHELLFRAME_GRID_COLS=${#_row[@]}
            for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                _hw=${#_row[$_c]}
                _cw=$(( _hw + 2 ))
                (( _cw < 8  )) && _cw=8
                (( _cw > 30 )) && _cw=30
                SHELLFRAME_GRID_COL_WIDTHS+=("$_cw")
            done
        else
            for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                _cell="${_row[$_c]:-}"
                SHELLFRAME_GRID_DATA+=("$_cell")
                _cv=$(( ${#_cell} + 2 ))
                (( _cv > 30 )) && _cv=30
                (( _cv > SHELLFRAME_GRID_COL_WIDTHS[$_c] )) && \
                    SHELLFRAME_GRID_COL_WIDTHS[$_c]=$_cv
            done
            (( SHELLFRAME_GRID_ROWS++ ))
        fi
        (( _idx++ ))
    done <<< "$_out"

    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"
    _SHQL_QUERY_HAS_RESULTS=1
    _SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows"
}
