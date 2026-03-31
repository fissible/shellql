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
_SHQL_QUERY_ERROR=""                    # non-empty = error message to display
_SHQL_QUERY_LAST_SQL=""                 # SQL that produced current results (for re-run on tab switch)
_SHQL_QUERY_PLACEHOLDER="No results yet"
_SHQL_QUERY_DETAIL_ACTIVE=0            # 0 = grid; 1 = row detail panel open
_SHQL_QUERY_DETAIL_PAIRS=()            # "key<TAB>value" pairs for the detail view
_SHQL_QUERY_DETAIL_CTX="qdetail_scroll" # scroll context for the detail panel
_SHQL_QUERY_DETAIL_ROW_IDX=0           # which results row is being viewed
_SHQL_QUERY_DETAIL_TOTAL_ROWS=0        # total rows in the results grid

# Cached editor viewport position (set during render, used for fast-path typing)
_SHQL_QUERY_EDITOR_CACHE_TOP=0
_SHQL_QUERY_EDITOR_CACHE_LEFT=0
_SHQL_QUERY_EDITOR_CACHE_WIDTH=0
_SHQL_QUERY_EDITOR_CACHE_HEIGHT=0

# ── _shql_query_init ──────────────────────────────────────────────────────────
# Called from shql_table_init. Sets state to initial values only.
# Widget inits (editor, grid) are deferred to first render.

_shql_query_init() {
    _SHQL_QUERY_STATUS=""
    _SHQL_QUERY_FOCUSED_PANE="editor"
    _SHQL_QUERY_HAS_RESULTS=0
    _SHQL_QUERY_INITIALIZED=0
    _SHQL_QUERY_EDITOR_ACTIVE=0
    _SHQL_QUERY_ERROR=""
    _SHQL_QUERY_LAST_SQL=""
    _SHQL_QUERY_DETAIL_ACTIVE=0
    _SHQL_QUERY_DETAIL_PAIRS=()
}

# ── _shql_query_init_ctx ──────────────────────────────────────────────────────
# Initialise per-ctx state variables for a query tab.
_shql_query_init_ctx() {
    local _ctx="$1"
    printf -v "_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"   '%d' 0
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "editor"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' ""
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' 1
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' 0
    printf -v "_SHQL_QUERY_CTX_ERROR_${_ctx}"          '%s' ""
    printf -v "_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"       '%s' ""
    printf -v "_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}" '%d' 0
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
    local _err_var="_SHQL_QUERY_CTX_ERROR_${_ctx}"
    local _lsql_var="_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"
    local _da_var="_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}"
    _SHQL_QUERY_FOCUSED_PANE="${!_fp_var:-editor}"
    _SHQL_QUERY_EDITOR_ACTIVE="${!_ea_var:-0}"
    _SHQL_QUERY_HAS_RESULTS="${!_hr_var:-0}"
    _SHQL_QUERY_STATUS="${!_st_var:-}"
    _SHQL_QUERY_INITIALIZED="${!_ini_var:-0}"
    _SHQL_QUERY_ERROR="${!_err_var:-}"
    _SHQL_QUERY_LAST_SQL="${!_lsql_var:-}"
    _SHQL_QUERY_DETAIL_ACTIVE="${!_da_var:-0}"

    # Re-run query if another tab stole the grid globals
    if (( _SHQL_QUERY_HAS_RESULTS )) && [[ "$_SHQL_BROWSER_GRID_OWNER_CTX" != "${_ctx}_results" ]] && [[ -n "$_SHQL_QUERY_LAST_SQL" ]]; then
        _shql_query_run "$_SHQL_QUERY_LAST_SQL"
    fi

    _shql_query_render "$@"

    # Save state back
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "$_SHQL_QUERY_FOCUSED_PANE"
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_EDITOR_ACTIVE"
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' "$_SHQL_QUERY_HAS_RESULTS"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' "$_SHQL_QUERY_STATUS"
    printf -v "_SHQL_QUERY_CTX_ERROR_${_ctx}"          '%s' "$_SHQL_QUERY_ERROR"
    printf -v "_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"       '%s' "$_SHQL_QUERY_LAST_SQL"
    printf -v "_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"   '%d' "$_SHQL_QUERY_INITIALIZED"
    printf -v "_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_DETAIL_ACTIVE"
}

# ── _shql_query_run ───────────────────────────────────────────────────────────
# Run SQL via the db adapter; parse TSV into SHELLFRAME_GRID_* globals.
# Sets _SHQL_QUERY_STATUS to "<n> rows" on success or "ERROR: ..." on failure.

_shql_query_run() {
    local _sql="$1"
    local _tmpfile="/tmp/shql_query_err.$$"

    local _t0 _t1 _elapsed_ms=0
    _t0=$SECONDS
    local _out
    _out=$(shql_db_query "$SHQL_DB_PATH" "$_sql" 2>"$_tmpfile")
    local _rc=$?
    _t1=$SECONDS
    _elapsed_ms=$(( (_t1 - _t0) * 1000 ))
    # Sub-second: if 0s elapsed, report <1ms
    (( _elapsed_ms == 0 )) && _elapsed_ms=1

    if (( _rc != 0 )); then
        _SHQL_QUERY_ERROR="$(cat "$_tmpfile" 2>/dev/null)"
        _SHQL_QUERY_STATUS="ERROR"
        _SHQL_QUERY_HAS_RESULTS=0
        rm -f "$_tmpfile"
        return 0
    fi
    _SHQL_QUERY_ERROR=""

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
    _SHQL_BROWSER_GRID_OWNER_CTX="$_SHQL_QUERY_GRID_CTX"
    _SHQL_QUERY_LAST_SQL="$_sql"
    if [[ -n "$_warning" ]]; then
        _SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows — $_warning"
    else
        _SHQL_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows"
    fi
    _SHQL_BROWSER_QUERY_STATUS="Query returned ${SHELLFRAME_GRID_ROWS} rows in ${_elapsed_ms}ms"
}

# ── _shql_query_footer_hint ───────────────────────────────────────────────────
# Sets named variable to the footer hint string for the current Query tab state.

_shql_query_footer_hint() {
    local _out_var="$1"
    local _status="${_SHQL_QUERY_STATUS:-}"

    if [[ -n "$_SHQL_QUERY_ERROR" ]]; then
        local _err_short="${_SHQL_QUERY_ERROR%%$'\n'*}"
        local _err_clipped="${_err_short:0:60}"
        printf -v "$_out_var" 'ERROR: %s  [Tab] Editor' "$_err_clipped"
        return 0
    fi

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

# ── _shql_query_detail_open ───────────────────────────────────────────────────
# Build key/value pairs from the current grid cursor row and activate the
# detail panel.  Works with any result set that has GRID_HEADERS.

_shql_query_detail_open() {
    local _nrows="${SHELLFRAME_GRID_ROWS:-0}"
    (( _nrows == 0 )) && return 0

    local _cursor=0
    shellframe_sel_cursor "$_SHQL_QUERY_GRID_CTX" _cursor 2>/dev/null || true

    _SHQL_QUERY_DETAIL_ROW_IDX=$_cursor
    _SHQL_QUERY_DETAIL_TOTAL_ROWS=$_nrows

    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_QUERY_DETAIL_PAIRS=()
    local _c _idx _key _val
    for (( _c=0; _c<_ncols; _c++ )); do
        _key="${SHELLFRAME_GRID_HEADERS[$_c]:-col$_c}"
        _idx=$(( _cursor * _ncols + _c ))
        _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        [[ -z "$_val" ]] && _val="(null)"
        _SHQL_QUERY_DETAIL_PAIRS+=("${_key}"$'\t'"${_val}")
    done

    local _n=${#_SHQL_QUERY_DETAIL_PAIRS[@]}
    shellframe_scroll_init "$_SHQL_QUERY_DETAIL_CTX" "$_n" 1 10 1
    _SHQL_QUERY_DETAIL_ACTIVE=1
}

# ── _shql_query_detail_step ─────────────────────────────────────────────────
# Move to the next (+1) or previous (-1) row in the results grid.
_shql_query_detail_step() {
    local _delta="$1"
    local _total="${_SHQL_QUERY_DETAIL_TOTAL_ROWS:-0}"
    (( _total == 0 )) && return 0

    local _new=$(( _SHQL_QUERY_DETAIL_ROW_IDX + _delta ))
    (( _new < 0 )) && _new=$(( _total - 1 ))
    (( _new >= _total )) && _new=0
    _SHQL_QUERY_DETAIL_ROW_IDX=$_new

    # Reload pairs from the grid data
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_QUERY_DETAIL_PAIRS=()
    local _c _idx _key _val
    for (( _c=0; _c<_ncols; _c++ )); do
        _key="${SHELLFRAME_GRID_HEADERS[$_c]:-col$_c}"
        _idx=$(( _new * _ncols + _c ))
        _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        [[ -z "$_val" ]] && _val="(null)"
        _SHQL_QUERY_DETAIL_PAIRS+=("${_key}"$'\t'"${_val}")
    done

    local _n=${#_SHQL_QUERY_DETAIL_PAIRS[@]}
    shellframe_scroll_init "$_SHQL_QUERY_DETAIL_CTX" "$_n" 1 10 1
}

# ── _shql_query_detail_on_key ────────────────────────────────────────────────

_shql_query_detail_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

    case "$_key" in
        "$_k_right") _shql_query_detail_step 1;  shellframe_shell_mark_dirty; return 0 ;;
        "$_k_left")  _shql_query_detail_step -1; shellframe_shell_mark_dirty; return 0 ;;
        "$_k_up")
            local _st=0; shellframe_scroll_top "$_SHQL_QUERY_DETAIL_CTX" _st 2>/dev/null || true
            if (( _st == 0 )); then
                _SHQL_QUERY_DETAIL_ACTIVE=0
                shellframe_shell_mark_dirty
            else
                shellframe_scroll_move "$_SHQL_QUERY_DETAIL_CTX" up
            fi
            return 0 ;;
        "$_k_down") shellframe_scroll_move "$_SHQL_QUERY_DETAIL_CTX" down;      return 0 ;;
        "$_k_pgup") shellframe_scroll_move "$_SHQL_QUERY_DETAIL_CTX" page_up;   return 0 ;;
        "$_k_pgdn") shellframe_scroll_move "$_SHQL_QUERY_DETAIL_CTX" page_down; return 0 ;;
        $'\033'|$'\r'|$'\n'|q)
            _SHQL_QUERY_DETAIL_ACTIVE=0
            shellframe_shell_mark_dirty
            return 0 ;;
    esac
    return 1
}

# ── _shql_query_detail_render ────────────────────────────────────────────────
# Render a key-value detail view for a query result row, similar to the table
# inspector but without schema metadata or row stepping.

_shql_query_detail_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    SHELLFRAME_PANEL_TITLE="Row Detail"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    # Clear inner area
    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    # Nav bar — row counter with ←→ navigation
    local _gray="${SHELLFRAME_GRAY:-}"
    local _nav_bg="${SHQL_THEME_ROW_STRIPE_BG:-$_cbg}"
    local _n_row=$(( _SHQL_QUERY_DETAIL_ROW_IDX + 1 ))
    local _n_total="$_SHQL_QUERY_DETAIL_TOTAL_ROWS"
    local _first_val=""
    if [[ ${#_SHQL_QUERY_DETAIL_PAIRS[@]} -gt 0 ]]; then
        _first_val="${_SHQL_QUERY_DETAIL_PAIRS[0]#*	}"
    fi
    local _nav_label
    printf -v _nav_label '← %s  (%d/%d) →' "$_first_val" "$_n_row" "$_n_total"
    local _nav_clipped
    shellframe_str_clip_ellipsis "$_nav_label" "$_nav_label" "$(( _iw - 2 ))" _nav_clipped
    shellframe_fb_fill  "$_it" "$_il" "$_iw" " " "$_nav_bg"
    shellframe_fb_print "$_it" "$(( _il + 1 ))" "$_nav_clipped" "$_nav_bg"

    # Separator line
    local _sep_row=$(( _it + 1 ))
    local _si=0
    while (( _si < _iw )); do
        shellframe_fb_put "$_sep_row" "$(( _il + _si ))" "${_ibg}${_gray}─"
        (( _si++ ))
    done

    # Adjust content area below nav + separator
    local _kv_top=$(( _it + 2 ))
    local _kv_h=$(( _ih - 2 ))
    (( _kv_h < 1 )) && _kv_h=1

    # Compute key column width: max key length, bounded [8, 20]
    local _max_kw=0 _pair _pkey _klen
    for _pair in "${_SHQL_QUERY_DETAIL_PAIRS[@]+"${_SHQL_QUERY_DETAIL_PAIRS[@]}"}"; do
        _pkey="${_pair%%	*}"
        _klen=${#_pkey}
        (( _klen > _max_kw )) && _max_kw=$_klen
    done
    (( _max_kw < 8  )) && _max_kw=8
    (( _max_kw > 20 )) && _max_kw=20

    local _kc="${SHQL_THEME_KEY_COLOR:-}"
    local _val_avail=$(( _iw - _max_kw - 3 ))  # key + "  " gap
    (( _val_avail < 1 )) && _val_avail=1

    local _n=${#_SHQL_QUERY_DETAIL_PAIRS[@]}

    # Build display-row map: word-wrap values; each wrapped line = one display row.
    local _dr_pair=() _dr_text=() _dr_line=() _total_drows=0
    local _i _j _pair_i _val_i
    for (( _i=0; _i<_n; _i++ )); do
        _pair_i="${_SHQL_QUERY_DETAIL_PAIRS[$_i]}"
        _val_i="${_pair_i#*	}"
        _shql_word_wrap "$_val_i" "$_val_avail"
        for (( _j=0; _j<${#_SHQL_WRAP_LINES[@]}; _j++ )); do
            _dr_pair[$_total_drows]=$_i
            _dr_text[$_total_drows]="${_SHQL_WRAP_LINES[$_j]}"
            _dr_line[$_total_drows]=$_j
            (( _total_drows++ ))
        done
    done

    # Update scroll total without resetting position, then re-clamp
    printf -v "_SHELLFRAME_SCROLL_${_SHQL_QUERY_DETAIL_CTX}_ROWS" '%d' "$_total_drows"
    shellframe_scroll_resize "$_SHQL_QUERY_DETAIL_CTX" "$_kv_h" 1
    local _scroll_top=0
    shellframe_scroll_top "$_SHQL_QUERY_DETAIL_CTX" _scroll_top

    local _r _dr _pi _ldr _row _key_padded _val_chunk
    for (( _r=0; _r<_kv_h; _r++ )); do
        _dr=$(( _scroll_top + _r ))
        (( _dr >= _total_drows )) && continue
        _row=$(( _kv_top + _r ))
        _pi=${_dr_pair[$_dr]}
        _ldr=${_dr_line[$_dr]}
        _val_chunk="${_dr_text[$_dr]}"
        if (( _ldr == 0 )); then
            _pair="${_SHQL_QUERY_DETAIL_PAIRS[$_pi]}"
            _pkey="${_pair%%	*}"
            printf -v _key_padded '%-*s' "$_max_kw" "$_pkey"
        else
            printf -v _key_padded '%-*s' "$_max_kw" ""
        fi
        shellframe_fb_print "$_row" "$(( _il + 1 ))" "$_key_padded" "${_ibg}${_kc}"
        shellframe_fb_fill  "$_row" "$(( _il + 1 + _max_kw ))" 2 " " "$_ibg"
        shellframe_fb_print "$_row" "$(( _il + 1 + _max_kw + 2 ))" "$_val_chunk" "$_ibg"
    done
}

# ── _shql_query_on_key ────────────────────────────────────────────────────────
# Key handler for the Query tab. Called from _shql_TABLE_body_on_key when
# SHELLFRAME_TABBAR_ACTIVE == _SHQL_TABLE_TAB_QUERY.
# Returns: 0 = handled, 1 = unhandled, 2 = action (Enter on grid row)

_shql_query_on_key() {
    local _key="$1"

    # Route to detail panel when active
    if (( _SHQL_QUERY_DETAIL_ACTIVE )); then
        _shql_query_detail_on_key "$_key"
        return $?
    fi

    local _k_tab=$'\t'
    local _k_shift_tab=$'\033[Z'
    local _k_escape=$'\033'
    local _k_enter=$'\r'
    local _k_newline=$'\n'
    local _k_ctrl_d=$'\004'
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"

    if [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]]; then
        if (( ! _SHQL_QUERY_EDITOR_ACTIVE )); then
            # Button state: arrow keys for spatial nav
            case "$_key" in
                "$_k_enter"|"$_k_newline")
                    _SHQL_QUERY_EDITOR_ACTIVE=1
                    shellframe_shell_mark_dirty
                    return 0
                    ;;
                "$_k_up"|"$_k_escape")
                    shellframe_shell_focus_set "tabbar"
                    shellframe_shell_mark_dirty
                    return 0
                    ;;
                "$_k_down"|"$_k_tab"|"$_k_shift_tab")
                    _SHQL_QUERY_FOCUSED_PANE="results"
                    shellframe_shell_mark_dirty
                    return 0
                    ;;
                "$_k_left")
                    shellframe_shell_focus_set "sidebar"
                    shellframe_shell_mark_dirty
                    return 0
                    ;;
            esac
            return 1
        fi

        # Typing state: Esc returns to button state; Ctrl-D submits; else → editor
        if [[ "$_key" == "$_k_escape" ]]; then
            _SHQL_QUERY_EDITOR_ACTIVE=0
            shellframe_shell_mark_dirty
            return 0
        fi
        SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
        shellframe_editor_on_key "$_key"
        local _rc=$?
        if (( _rc == 2 )); then
            # Ctrl-D submit: SHELLFRAME_EDITOR_RESULT contains the SQL
            _shql_query_run "$SHELLFRAME_EDITOR_RESULT"
            if [[ -n "$_SHQL_QUERY_ERROR" ]]; then
                # Error: stay in typing mode so user can fix immediately
                _SHQL_QUERY_EDITOR_ACTIVE=1
            else
                _SHQL_QUERY_FOCUSED_PANE="results"
                _SHQL_QUERY_EDITOR_ACTIVE=0
            fi
            shellframe_shell_mark_dirty
            return 0
        fi
        if (( _rc == 0 )); then
            # Fast-path: re-render editor directly to fd3, skip full draw cycle.
            # The editor already called mark_dirty — suppress it so the shell
            # event loop doesn't trigger an expensive full-screen redraw.
            if (( _SHQL_QUERY_EDITOR_CACHE_WIDTH > 0 )); then
                SHELLFRAME_EDITOR_FOCUSED=1
                SHELLFRAME_EDITOR_BG="${SHQL_THEME_EDITOR_FOCUSED_BG:-}"
                SHELLFRAME_EDITOR_DIRECT_RENDER=1
                shellframe_editor_render "$_SHQL_QUERY_EDITOR_CACHE_TOP" \
                    "$_SHQL_QUERY_EDITOR_CACHE_LEFT" \
                    "$_SHQL_QUERY_EDITOR_CACHE_WIDTH" \
                    "$_SHQL_QUERY_EDITOR_CACHE_HEIGHT"
                SHELLFRAME_EDITOR_DIRECT_RENDER=0
                _SHELLFRAME_SHELL_DIRTY=0
            fi
            return 0
        fi
        # rc=1: editor did not handle it — check query-level bindings
        if [[ "$_key" == "$_k_tab" ]] || [[ "$_key" == "$_k_shift_tab" ]]; then
            _SHQL_QUERY_FOCUSED_PANE="results"
            _SHQL_QUERY_EDITOR_ACTIVE=0
            shellframe_shell_mark_dirty
            return 0
        fi
        return 1
    fi

    # results pane focused
    if   [[ "$_key" == "$_k_tab" ]] || [[ "$_key" == "$_k_shift_tab" ]]; then
        _SHQL_QUERY_FOCUSED_PANE="editor"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_ctrl_d" ]]; then
        local _sql
        shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql
        _shql_query_run "$_sql"
        if [[ -n "$_SHQL_QUERY_ERROR" ]]; then
            _SHQL_QUERY_FOCUSED_PANE="editor"
            _SHQL_QUERY_EDITOR_ACTIVE=1
        fi
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_escape" || "$_key" == "q" ]]; then
        shellframe_shell_focus_set "tabbar"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_left" ]]; then
        local _scroll_left=0
        shellframe_scroll_left "$_SHQL_QUERY_GRID_CTX" _scroll_left 2>/dev/null || true
        if (( _scroll_left == 0 )); then
            shellframe_shell_focus_set "sidebar"
            shellframe_shell_mark_dirty
            return 0
        fi
    elif [[ "$_key" == "$_k_up" ]]; then
        local _cursor=0
        shellframe_sel_cursor "$_SHQL_QUERY_GRID_CTX" _cursor 2>/dev/null || true
        if (( _cursor == 0 )); then
            _SHQL_QUERY_FOCUSED_PANE="editor"
            shellframe_shell_mark_dirty
            return 0
        fi
    fi
    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    shellframe_grid_on_key "$_key"
    local _rc=$?
    # Enter on grid row → open detail panel
    if (( _rc == 2 )); then
        _shql_query_detail_open
        shellframe_shell_mark_dirty
        return 0
    fi
    return $_rc
}

# ── _shql_query_render ────────────────────────────────────────────────────────
# Renders the Query tab: editor panel / results pane.
# The editor panel uses a box border (single in button state, double in typing
# state) whose bottom edge acts as the visual divider between the two areas.
# top left width height passed from _shql_TABLE_body_render.

_shql_query_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _gray="${SHELLFRAME_GRAY:-}"

    # Lazy widget init: requires viewport dimensions, so deferred from _shql_query_init.
    if (( ! _SHQL_QUERY_INITIALIZED )); then
        SHELLFRAME_EDITOR_LINES=()
        shellframe_editor_init "$_SHQL_QUERY_EDITOR_CTX"
        SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
        shellframe_grid_init "$_SHQL_QUERY_GRID_CTX"
        _SHQL_QUERY_INITIALIZED=1
        # Apply any pre-fill template (set before first render; consumed here).
        local _tab_ctx="${_SHQL_QUERY_EDITOR_CTX%_editor}"
        local _pf_var="_SHQL_QUERY_CTX_PREFILL_${_tab_ctx}"
        if [[ -n "${!_pf_var:-}" ]]; then
            shellframe_editor_set_text "$_SHQL_QUERY_EDITOR_CTX" "${!_pf_var}"
            printf -v "$_pf_var" '%s' ""
        fi
    fi

    # Compute split (panel consumes 2 border rows from editor budget)
    local _editor_rows=$(( _height * 30 / 100 ))
    (( _editor_rows < 5 )) && _editor_rows=5   # min: 2 border rows + 3 inner rows
    local _results_top=$(( _top + _editor_rows ))
    local _results_rows=$(( _height - _editor_rows ))
    (( _results_rows < 3 )) && _results_rows=3

    # ── Editor panel ──
    # Sub-pane focus requires content region to be focused too
    local _content_focused="${_SHQL_BROWSER_CONTENT_FOCUSED:-0}"
    local _editor_pane_focused=0
    (( _content_focused )) && [[ "$_SHQL_QUERY_FOCUSED_PANE" == "editor" ]] && _editor_pane_focused=1
    local _cbg="${SHQL_THEME_CONTENT_BG:-}"

    local _panel_style
    if (( _editor_pane_focused )); then
        _panel_style="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    else
        _panel_style="${SHQL_THEME_PANEL_STYLE:-single}"
    fi
    SHELLFRAME_PANEL_STYLE="$_panel_style"
    SHELLFRAME_PANEL_TITLE="SQL Query"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_editor_pane_focused
    SHELLFRAME_PANEL_MODE="framed"
    # Set content bg + accent color for panel border cells
    SHELLFRAME_PANEL_CELL_ATTRS="$_cbg"
    if (( _editor_pane_focused )) && [[ -n "${SHQL_THEME_QUERY_PANEL_COLOR:-}" ]]; then
        SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${SHQL_THEME_QUERY_PANEL_COLOR}"
    fi
    shellframe_panel_render "$_top" "$_left" "$_width" "$_editor_rows"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_editor_rows" _it _il _iw _ih

    # Cache editor position for fast-path typing render
    _SHQL_QUERY_EDITOR_CACHE_TOP="$_it"
    _SHQL_QUERY_EDITOR_CACHE_LEFT="$_il"
    _SHQL_QUERY_EDITOR_CACHE_WIDTH="$_iw"
    _SHQL_QUERY_EDITOR_CACHE_HEIGHT="$_ih"

    # Render editor content inside panel
    SHELLFRAME_EDITOR_CTX="$_SHQL_QUERY_EDITOR_CTX"
    if (( _editor_pane_focused && _SHQL_QUERY_EDITOR_ACTIVE )); then
        SHELLFRAME_EDITOR_FOCUSED=1
        # Typing mode: dark gray bg (between sidebar and content)
        SHELLFRAME_EDITOR_BG="${SHQL_THEME_EDITOR_FOCUSED_BG:-}"
        SHELLFRAME_EDITOR_FG=""
    else
        SHELLFRAME_EDITOR_FOCUSED=0
        # Not typing: disabled look — content bg + dim text
        SHELLFRAME_EDITOR_BG="${_cbg}"
        SHELLFRAME_EDITOR_FG=$'\033[38;5;245m'   # muted gray — visually "disabled"
    fi
    shellframe_editor_render "$_it" "$_il" "$_iw" "$_ih"

    # Button state: show placeholder hint when editor is empty
    if (( _editor_pane_focused && ! _SHQL_QUERY_EDITOR_ACTIVE )); then
        local _sql_text=""
        shellframe_editor_get_text "$_SHQL_QUERY_EDITOR_CTX" _sql_text 2>/dev/null || true
        if [[ -z "$_sql_text" ]]; then
            local _mid=$(( _it + _ih / 2 ))
            local _ph_text="Press [Enter] to type SQL"
            local _ph_len=${#_ph_text}
            local _ph_col=$(( _il + (_iw - _ph_len) / 2 ))
            (( _ph_col < _il )) && _ph_col=$_il
            shellframe_fb_print "$_mid" "$_ph_col" "$_ph_text" "${_cbg}${_gray}"
            # Also append to deferred buf — the editor's deferred content would
            # otherwise overwrite these cells when it's flushed after screen_flush.
            local _ph_esc
            printf -v _ph_esc '\033[%d;%dH%s%s' "$_mid" "$_ph_col" "${_cbg}${_gray}" "$_ph_text"
            _SHELLFRAME_EDITOR_DEFERRED_BUF+="$_ph_esc"
        fi
    fi

    # ── Results panel ──
    local _results_pane_focused=0
    (( _content_focused )) && [[ "$_SHQL_QUERY_FOCUSED_PANE" == "results" ]] && _results_pane_focused=1

    local _results_panel_style
    if (( _SHQL_QUERY_DETAIL_ACTIVE )); then
        # Detail panel is open — results demoted to unfocused single border
        _results_panel_style="${SHQL_THEME_PANEL_STYLE:-single}"
        _results_pane_focused=0
    elif (( _results_pane_focused )); then
        _results_panel_style="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    else
        _results_panel_style="${SHQL_THEME_PANEL_STYLE:-single}"
    fi
    SHELLFRAME_PANEL_STYLE="$_results_panel_style"
    SHELLFRAME_PANEL_TITLE="Results"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_results_pane_focused
    SHELLFRAME_PANEL_MODE="framed"
    # Set content bg + accent color for panel border cells
    SHELLFRAME_PANEL_CELL_ATTRS="$_cbg"
    if (( _results_pane_focused )) && [[ -n "${SHQL_THEME_QUERY_PANEL_COLOR:-}" ]]; then
        SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${SHQL_THEME_QUERY_PANEL_COLOR}"
    fi
    shellframe_panel_render "$_results_top" "$_left" "$_width" "$_results_rows"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _rit _ril _riw _rih
    shellframe_panel_inner "$_results_top" "$_left" "$_width" "$_results_rows" \
        _rit _ril _riw _rih

    SHELLFRAME_GRID_CTX="$_SHQL_QUERY_GRID_CTX"
    SHELLFRAME_GRID_FOCUSED=$_results_pane_focused
    SHELLFRAME_GRID_BG="${SHQL_THEME_EDITOR_FOCUSED_BG:-${SHQL_THEME_CONTENT_BG:-}}"
    SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
    SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
    SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
    if [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
        SHELLFRAME_GRID_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
    else
        SHELLFRAME_GRID_CURSOR_STYLE=""
    fi

    if [[ -n "$_SHQL_QUERY_ERROR" ]]; then
        # Error page — styled error display
        local _rbg="${SHQL_THEME_EDITOR_FOCUSED_BG:-${SHQL_THEME_CONTENT_BG:-}}"
        local _err_color=$'\033[38;5;196m'   # bright red
        local _err_dim=$'\033[38;5;174m'     # muted red/pink for detail text
        local _r
        for (( _r=0; _r<_rih; _r++ )); do
            shellframe_fb_fill "$(( _rit + _r ))" "$_ril" "$_riw" " " "$_rbg"
        done
        # Error header
        local _err_title="  ERROR"
        local _err_row=$(( _rit + 1 ))
        (( _err_row >= _rit + _rih )) && _err_row=$_rit
        shellframe_fb_print "$_err_row" "$(( _ril + 1 ))" "$_err_title" "${_rbg}${_err_color}"
        # Separator — ─ is 3-byte UTF-8; use shellframe_fb_put per cell
        local _sep_row=$(( _err_row + 1 ))
        if (( _sep_row < _rit + _rih )); then
            local _si=0
            while (( _si < _riw - 2 )); do
                shellframe_fb_put "$_sep_row" "$(( _ril + 1 + _si ))" "${SHELLFRAME_GRAY:-}─"
                (( _si++ ))
            done
        fi
        # Error detail lines
        local _detail_top=$(( _sep_row + 1 ))
        local _line_num=0
        while IFS= read -r _err_line; do
            [[ -z "$_err_line" ]] && continue
            local _draw_row=$(( _detail_top + _line_num ))
            (( _draw_row >= _rit + _rih - 1 )) && break
            local _eclipped
            shellframe_str_clip_ellipsis "$_err_line" "$_err_line" "$(( _riw - 4 ))" _eclipped
            shellframe_fb_print "$_draw_row" "$(( _ril + 2 ))" "$_eclipped" "${_rbg}${_err_dim}"
            (( _line_num++ ))
        done <<< "$_SHQL_QUERY_ERROR"
    elif (( _SHQL_QUERY_DETAIL_ACTIVE )); then
        # Show grid header rows above the detail panel (like data tab inspector)
        SHELLFRAME_GRID_FOCUSED=0
        SHELLFRAME_GRID_BG="${SHQL_THEME_CONTENT_BG:-}"
        SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
        SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
        SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
        SHELLFRAME_GRID_CURSOR_STYLE=""
        _shql_grid_fill_width "$_riw"
        shellframe_grid_render "$_rit" "$_ril" "$_riw" 3
        _shql_grid_restore_last
        local _det_top=$(( _rit + 3 ))
        local _det_h=$(( _rih - 3 ))
        (( _det_h < 3 )) && _det_h=3
        _shql_query_detail_render "$_det_top" "$_ril" "$_riw" "$_det_h"
    elif (( _SHQL_QUERY_HAS_RESULTS )); then
        # Reserve 1 column for scrollbar when there's enough space
        local _qgrid_w="$_riw"
        local _qsb_col=0
        if (( _riw > 10 && _rih > 3 )); then
            _qgrid_w=$(( _riw - 1 ))
            _qsb_col=$(( _ril + _qgrid_w ))
        fi
        _shql_grid_fill_width "$_qgrid_w"
        shellframe_grid_render "$_rit" "$_ril" "$_qgrid_w" "$_rih"
        _shql_grid_restore_last
        # Scrollbar in rightmost column (data rows start 2 below _rit)
        if (( _qsb_col > 0 )); then
            local _qsb_top=$(( _rit + 2 ))
            local _qsb_h=$(( _rih - 2 ))
            SHELLFRAME_SCROLLBAR_STYLE="${SHQL_THEME_CONTENT_BG:-}${SHELLFRAME_GRAY:-$'\033[2m'}"
            SHELLFRAME_SCROLLBAR_THUMB_STYLE="${SHQL_THEME_CONTENT_BG:-}"
            if ! shellframe_scrollbar_render "${SHELLFRAME_GRID_CTX:-grid}" \
                    "$_qsb_col" "$_qsb_top" "$_qsb_h"; then
                local _qsb_r
                for (( _qsb_r=0; _qsb_r<_qsb_h; _qsb_r++ )); do
                    shellframe_fb_put "$(( _qsb_top + _qsb_r ))" "$_qsb_col" "${SHQL_THEME_CONTENT_BG:-} "
                done
            fi
            # Header rows in scrollbar column
            shellframe_fb_put "$_rit" "$_qsb_col" "${SHQL_THEME_GRID_HEADER_BG:-} "
            shellframe_fb_put "$(( _rit + 1 ))" "$_qsb_col" "${SHQL_THEME_CONTENT_BG:-} "
        fi
    else
        # Empty state — centered placeholder (darker bg like editor)
        local _rbg="${SHQL_THEME_EDITOR_FOCUSED_BG:-${SHQL_THEME_CONTENT_BG:-}}"
        local _r
        for (( _r=0; _r<_rih; _r++ )); do
            shellframe_fb_fill "$(( _rit + _r ))" "$_ril" "$_riw" " " "$_rbg"
        done
        local _mid=$(( _rit + _rih / 2 ))
        (( _mid < _rit )) && _mid="$_rit"
        local _plen=${#_SHQL_QUERY_PLACEHOLDER}
        local _pcol=$(( _ril + (_riw - _plen) / 2 ))
        (( _pcol < _ril )) && _pcol=$_ril
        shellframe_fb_print "$_mid" "$_pcol" "$_SHQL_QUERY_PLACEHOLDER" "${_rbg}${_gray}"
    fi
}
