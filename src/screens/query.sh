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
    _SHQL_QUERY_FOCUSED_PANE="results"
}

# ── _shql_query_footer_hint ───────────────────────────────────────────────────
# Sets named variable _out_var to the footer hint string for the Query tab.
# Varies by focused pane and whether a status string is set.

_shql_query_footer_hint() {
    local _out_var="$1"
    local _run="[Ctrl-D] Run"

    if [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]]; then
        if [[ -n "$_SHQL_QUERY_STATUS" ]]; then
            printf -v "$_out_var" '%s  %s  %s  %s' "$_SHQL_QUERY_STATUS" "$_run" "[Esc] Editor" "[q] Back"
        else
            printf -v "$_out_var" '%s  %s  %s' "$_run" "[Esc] Editor" "[q] Back"
        fi
    else
        if [[ -n "$_SHQL_QUERY_STATUS" ]]; then
            printf -v "$_out_var" '%s  %s  %s' "$_SHQL_QUERY_STATUS" "$_run" "[Esc] Tab bar"
        else
            printf -v "$_out_var" '%s  %s' "$_run" "[Esc] Tab bar"
        fi
    fi
}

# ── _shql_query_on_key ────────────────────────────────────────────────────────
# Key handler for the Query tab. Called from _shql_TABLE_body_on_key when
# SHELLFRAME_TABBAR_ACTIVE == _SHQL_TABLE_TAB_QUERY.
# Returns: 0 = handled, 1 = unhandled, 2 = action (Enter on grid row)

_shql_query_on_key() {
    local _key="$1"
    local _k_tab=$'\t'
    local _k_shift_tab=$'\033[Z'
    local _k_escape=$'\033'
    local _k_ctrl_d=$'\004'
    # Note: Ctrl-Enter is not reliably distinguishable from Enter through shellframe's
    # input layer (bash read converts \r → \n). Ctrl-D is the supported run shortcut.

    if [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]]; then
        SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
        shellframe_editor_on_key "$_key"
        local _rc=$?
        if (( _rc == 2 )); then
            # Ctrl-D submit: SHELLFRAME_EDITOR_RESULT contains the SQL
            _shql_query_run "$SHELLFRAME_EDITOR_RESULT"
            return 0
        fi
        if (( _rc == 0 )); then
            # Editor consumed the key (printable char, navigation, etc.)
            return 0
        fi
        # rc=1: editor did not handle it — check query-level bindings
        if [[ "$_key" == "$_k_tab" ]]; then
            # Tab: advance into results pane (consumed; prevents shellframe cycling to tabbar)
            _SHQL_QUERY_FOCUSED_PANE="results"
            return 0
        elif [[ "$_key" == "$_k_shift_tab" ]]; then
            # Shift+Tab: not consumed; let shellframe retreat focus to tabbar
            return 1
        elif [[ "$_key" == "$_k_escape" ]]; then
            shellframe_shell_focus_set "tabbar"
            return 0
        fi
        return 1
    fi

    # results pane focused
    if [[ "$_key" == "$_k_tab" ]]; then
        # Tab at end of focus order: stop (consume and do nothing)
        return 0
    elif [[ "$_key" == "$_k_shift_tab" ]]; then
        # Shift+Tab: retreat to editor pane
        _SHQL_QUERY_FOCUSED_PANE="editor"
        return 0
    elif [[ "$_key" == "$_k_ctrl_d" ]]; then
        local _sql
        shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql
        _shql_query_run "$_sql"
        return 0
    elif [[ "$_key" == "$_k_escape" ]]; then
        _SHQL_QUERY_FOCUSED_PANE="editor"
        return 0
    elif [[ "$_key" == "q" ]]; then
        shellframe_shell_focus_set "tabbar"
        return 0
    fi
    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    shellframe_grid_on_key "$_key"
    return $?
}

# ── _shql_query_render ────────────────────────────────────────────────────────
# Renders the Query tab: editor pane / divider / results pane.
# top left width height passed from _shql_TABLE_body_render.

_shql_query_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Lazy widget init: requires viewport dimensions, so deferred from _shql_query_init.
    if (( ! _SHQL_QUERY_INITIALIZED )); then
        SHELLFRAME_EDITOR_LINES=()
        shellframe_editor_init "$_SHQL_QUERY_EDITOR_CTX"
        SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
        shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"
        _SHQL_QUERY_INITIALIZED=1
    fi

    # Compute split
    local _editor_rows=$(( _height * 30 / 100 ))
    (( _editor_rows < 3 )) && _editor_rows=3
    local _divider_row=$(( _top + _editor_rows ))
    local _results_top=$(( _divider_row + 1 ))
    local _results_rows=$(( _height - _editor_rows - 1 ))
    (( _results_rows < 3 )) && _results_rows=3

    # Sync framework focus globals (bash 3.2-compatible)
    SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
    [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]]  && SHELLFRAME_EDITOR_FOCUSED=1 || SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]] && SHELLFRAME_GRID_FOCUSED=1   || SHELLFRAME_GRID_FOCUSED=0

    # Render editor pane
    shellframe_editor_render "$_top" "$_left" "$_width" "$_editor_rows"

    # Render divider row
    local _divider='' _i
    for (( _i=0; _i<_width; _i++ )); do _divider+='─'; done
    printf '\033[%d;%dH%s' "$_divider_row" "$_left" "$_divider" >/dev/tty

    # Render results pane
    if (( _SHQL_QUERY_HAS_RESULTS )); then
        shellframe_grid_render "$_results_top" "$_left" "$_width" "$_results_rows"
    else
        local _r
        for (( _r=0; _r<_results_rows; _r++ )); do
            printf '\033[%d;%dH\033[2K' "$(( _results_top + _r ))" "$_left" >/dev/tty
        done
        local _placeholder="Run a query to see results  [Ctrl-D]"
        local _mid=$(( _results_top + _results_rows / 2 ))
        local _pcol=$(( _left + (_width - ${#_placeholder}) / 2 ))
        (( _pcol < _left )) && _pcol=$_left
        local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
        printf '\033[%d;%dH%s%s%s' "$_mid" "$_pcol" "$_gray" "$_placeholder" "$_rst" >/dev/tty
    fi
}
