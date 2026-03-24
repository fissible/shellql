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
_SHQL_QUERY_EDITOR_ACTIVE=0             # 0 = button state; 1 = typing state
_SHQL_QUERY_PLACEHOLDER="No results yet"

# ── _shql_query_init ──────────────────────────────────────────────────────────
# Called from shql_table_init. Sets state to initial values only.
# Widget inits (editor, grid) are deferred to first render.

_shql_query_init() {
    _SHQL_QUERY_STATUS=""
    _SHQL_QUERY_FOCUSED_PANE="editor"
    _SHQL_QUERY_HAS_RESULTS=0
    _SHQL_QUERY_INITIALIZED=0
    _SHQL_QUERY_EDITOR_ACTIVE=0
}

# ── _shql_query_init_ctx ──────────────────────────────────────────────────────
# Initialise per-ctx state variables for a query tab.
_shql_query_init_ctx() {
    local _ctx="$1"
    printf -v "_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"   '%d' 0
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "editor"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' ""
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' 0
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' 0
}

# ── _shql_query_render_ctx ────────────────────────────────────────────────────
# Render query tab for the given ctx. Loads per-ctx state into the shared
# globals used by _shql_query_render, then delegates.
_shql_query_render_ctx() {
    local _ctx="$1"; shift

    # Initialize if not yet done
    local _init_var="_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"
    [[ "${!_init_var:-}" == "" ]] && _shql_query_init_ctx "$_ctx"

    _SHQL_QUERY_EDITOR_CTX="${_ctx}_editor"
    _SHQL_QUERY_GRID_CTX="${_ctx}_results"

    local _fp_var="_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"
    local _ea_var="_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}"
    local _hr_var="_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"
    local _st_var="_SHQL_QUERY_CTX_STATUS_${_ctx}"
    local _ini_var="_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"
    _SHQL_QUERY_FOCUSED_PANE="${!_fp_var:-editor}"
    _SHQL_QUERY_EDITOR_ACTIVE="${!_ea_var:-0}"
    _SHQL_QUERY_HAS_RESULTS="${!_hr_var:-0}"
    _SHQL_QUERY_STATUS="${!_st_var:-}"
    _SHQL_QUERY_INITIALIZED="${!_ini_var:-0}"

    _shql_query_render "$@"

    # Save state back
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "$_SHQL_QUERY_FOCUSED_PANE"
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_EDITOR_ACTIVE"
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' "$_SHQL_QUERY_HAS_RESULTS"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' "$_SHQL_QUERY_STATUS"
    printf -v "_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"   '%d' "$_SHQL_QUERY_INITIALIZED"
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

    if (( _rc != 0 )); then
        _SHQL_QUERY_STATUS="ERROR: $(head -1 "$_tmpfile")"
        rm -f "$_tmpfile"
        return 0
    fi

    local _warning=""
    [[ -s "$_tmpfile" ]] && _warning="$(head -1 "$_tmpfile")"
    rm -f "$_tmpfile"

    # Parse TSV: first line = headers, subsequent lines = data.
    # Column widths: header_width + 2, clamped 8..SHQL_MAX_COL_WIDTH, grown by data cell widths.
    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_PK_COLS=0
    local _maxcw="${SHQL_MAX_COL_WIDTH:-30}"

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
                (( _cw < 8      )) && _cw=8
                (( _cw > _maxcw )) && _cw=$_maxcw
                SHELLFRAME_GRID_COL_WIDTHS+=("$_cw")
            done
        else
            for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                _cell="${_row[$_c]:-}"
                SHELLFRAME_GRID_DATA+=("$_cell")
                _cv=$(( ${#_cell} + 2 ))
                (( _cv > _maxcw )) && _cv=$_maxcw
                (( _cv > SHELLFRAME_GRID_COL_WIDTHS[$_c] )) && \
                    SHELLFRAME_GRID_COL_WIDTHS[$_c]=$_cv
            done
            (( SHELLFRAME_GRID_ROWS++ ))
        fi
        (( _idx++ ))
    done <<< "$_out"

    _shql_detect_grid_align
    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"
    _SHQL_QUERY_HAS_RESULTS=1
    if [[ -n "$_warning" ]]; then
        _SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows — $_warning"
    else
        _SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows"
    fi
}

# ── _shql_query_footer_hint ───────────────────────────────────────────────────
# Sets named variable to the footer hint string for the current Query tab state.

_shql_query_footer_hint() {
    local _out_var="$1"
    local _status="${_SHQL_QUERY_STATUS:-}"

    if [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]]; then
        if [[ -n "$_status" ]]; then
            printf -v "$_out_var" '%s  [↑↓] Navigate  [Tab] Editor  [q] Back' "$_status"
        else
            printf -v "$_out_var" '%s' "[↑↓] Navigate  [Tab] Editor  [q] Back"
        fi
    elif (( _SHQL_QUERY_EDITOR_ACTIVE )); then
        # Typing state
        printf -v "$_out_var" '%s' "[Ctrl-D] Run  [Esc] Done editing"
    else
        # Button state
        if [[ -n "$_status" ]]; then
            printf -v "$_out_var" '%s  [Enter] Edit  [Tab] Results  [Esc] Tab bar' "$_status"
        else
            printf -v "$_out_var" '%s' "[Enter] Edit  [Tab] Results  [Esc] Tab bar"
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
    local _k_enter=$'\r'
    local _k_ctrl_d=$'\004'

    if [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]]; then
        if (( ! _SHQL_QUERY_EDITOR_ACTIVE )); then
            # Button state: Enter activates typing; Tab switches pane; Esc exits
            case "$_key" in
                "$_k_enter")
                    _SHQL_QUERY_EDITOR_ACTIVE=1
                    return 0
                    ;;
                "$_k_tab"|"$_k_shift_tab")
                    _SHQL_QUERY_FOCUSED_PANE="results"
                    return 0
                    ;;
                "$_k_escape")
                    shellframe_shell_focus_set "tabbar"
                    return 0
                    ;;
            esac
            return 1
        fi

        # Typing state: Esc returns to button state; Ctrl-D submits; else → editor
        if [[ "$_key" == "$_k_escape" ]]; then
            _SHQL_QUERY_EDITOR_ACTIVE=0
            return 0
        fi
        SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
        shellframe_editor_on_key "$_key"
        local _rc=$?
        if (( _rc == 2 )); then
            # Ctrl-D submit: SHELLFRAME_EDITOR_RESULT contains the SQL
            _shql_query_run "$SHELLFRAME_EDITOR_RESULT"
            _SHQL_QUERY_FOCUSED_PANE="results"
            _SHQL_QUERY_EDITOR_ACTIVE=0
            return 0
        fi
        if (( _rc == 0 )); then
            return 0
        fi
        # rc=1: editor did not handle it — check query-level bindings
        if [[ "$_key" == "$_k_tab" ]] || [[ "$_key" == "$_k_shift_tab" ]]; then
            _SHQL_QUERY_FOCUSED_PANE="results"
            _SHQL_QUERY_EDITOR_ACTIVE=0
            return 0
        fi
        return 1
    fi

    # results pane focused
    if   [[ "$_key" == "$_k_tab" ]] || [[ "$_key" == "$_k_shift_tab" ]]; then
        _SHQL_QUERY_FOCUSED_PANE="editor"
        return 0
    elif [[ "$_key" == "$_k_ctrl_d" ]]; then
        local _sql
        shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql
        _shql_query_run "$_sql"
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
# Renders the Query tab: editor panel / results pane.
# The editor panel uses a box border (single in button state, double in typing
# state) whose bottom edge acts as the visual divider between the two areas.
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

    # Compute split (panel consumes 2 border rows from editor budget)
    local _editor_rows=$(( _height * 30 / 100 ))
    (( _editor_rows < 5 )) && _editor_rows=5   # min: 2 border rows + 3 inner rows
    local _results_top=$(( _top + _editor_rows ))
    local _results_rows=$(( _height - _editor_rows ))
    (( _results_rows < 3 )) && _results_rows=3

    # ── Editor panel ──
    local _editor_pane_focused=0
    [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]] && _editor_pane_focused=1

    local _panel_style
    if (( _editor_pane_focused && _SHQL_QUERY_EDITOR_ACTIVE )); then
        _panel_style="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    else
        _panel_style="${SHQL_THEME_PANEL_STYLE:-single}"
    fi
    SHELLFRAME_PANEL_STYLE="$_panel_style"
    SHELLFRAME_PANEL_TITLE="SQL Query"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_editor_pane_focused
    SHELLFRAME_PANEL_MODE="framed"
    shellframe_panel_render "$_top" "$_left" "$_width" "$_editor_rows"

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_editor_rows" _it _il _iw _ih

    # Render editor content inside panel
    SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
    if (( _editor_pane_focused && _SHQL_QUERY_EDITOR_ACTIVE )); then
        SHELLFRAME_EDITOR_FOCUSED=1
    else
        SHELLFRAME_EDITOR_FOCUSED=0
    fi
    shellframe_editor_render "$_it" "$_il" "$_iw" "$_ih"

    # Button state: show placeholder hint when editor is empty
    if (( _editor_pane_focused && ! _SHQL_QUERY_EDITOR_ACTIVE )); then
        local _sql_text=""
        shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql_text 2>/dev/null || true
        if [[ -z "$_sql_text" ]]; then
            local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
            local _mid=$(( _it + _ih / 2 ))
            printf '\033[%d;%dH%sPress [Enter] to type SQL%s' \
                "$_mid" "$_il" "$_gray" "$_rst" >/dev/tty
        fi
    fi

    # ── Results panel ──
    local _results_pane_focused=0
    [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]] && _results_pane_focused=1

    local _results_panel_style
    if (( _results_pane_focused && _SHQL_QUERY_HAS_RESULTS )); then
        _results_panel_style="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    else
        _results_panel_style="${SHQL_THEME_PANEL_STYLE:-single}"
    fi
    SHELLFRAME_PANEL_STYLE="$_results_panel_style"
    SHELLFRAME_PANEL_TITLE="Results"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_results_pane_focused
    SHELLFRAME_PANEL_MODE="framed"
    shellframe_panel_render "$_results_top" "$_left" "$_width" "$_results_rows"

    local _rit _ril _riw _rih
    shellframe_panel_inner "$_results_top" "$_left" "$_width" "$_results_rows" \
        _rit _ril _riw _rih

    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    SHELLFRAME_GRID_FOCUSED=$_results_pane_focused

    if (( _SHQL_QUERY_HAS_RESULTS )); then
        _shql_grid_fill_width "$_riw"
        shellframe_grid_render "$_rit" "$_ril" "$_riw" "$_rih"
        _shql_grid_restore_last
    else
        # Empty state with instructional placeholder and examples
        local _r
        for (( _r=0; _r<_rih; _r++ )); do
            printf '\033[%d;%dH%*s' "$(( _rit + _r ))" "$_ril" "$_riw" '' >/dev/tty
        done
        local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
        local _tbl="${_SHQL_TABLE_NAME:-users}"
        local _mid=$(( _rit + _rih / 2 - 2 ))
        (( _mid < _rit )) && _mid="$_rit"
        printf '\033[%d;%dH%s%s%s' \
            "$_mid" "$_ril" "$_gray" "$_SHQL_QUERY_PLACEHOLDER" "$_rst" >/dev/tty
        if (( _rih >= 5 )); then
            printf '\033[%d;%dH%sExamples:%s' \
                "$(( _mid + 2 ))" "$_ril" "$_gray" "$_rst" >/dev/tty
            printf '\033[%d;%dH%s  SELECT * FROM %s LIMIT 10;%s' \
                "$(( _mid + 3 ))" "$_ril" "$_gray" "$_tbl" "$_rst" >/dev/tty
            printf '\033[%d;%dH%s  SELECT count(*) FROM %s;%s' \
                "$(( _mid + 4 ))" "$_ril" "$_gray" "$_tbl" "$_rst" >/dev/tty
        fi
    fi
}
