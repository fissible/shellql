#!/usr/bin/env bash
# shellql/src/screens/table.sh — Table view screen
#
# REQUIRES: shellframe sourced, src/state.sh sourced, src/db.sh or db_mock.sh.
#
# ── Layout ────────────────────────────────────────────────────────────────────
#
#   row 1        : header (db path + table name, nofocus)
#   row 2        : tab bar (Structure | Data | Query, focus)
#   rows 3..N-1  : body (content depends on active tab, focus)
#   row N        : footer (key hints, nofocus)
#
# ── Screens ───────────────────────────────────────────────────────────────────
#
#   TABLE  — table browser with Structure / Data / Query tabs
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#
#   source src/screens/table.sh
#   # Set SHQL_DB_PATH and _SHQL_TABLE_NAME, then call shql_table_init
#   # before shellframe_shell transitions to "TABLE".

# ── Context names ─────────────────────────────────────────────────────────────

_SHQL_TABLE_GRID_CTX="table_data"
_SHQL_TABLE_DDL_CTX="table_ddl"

# ── Mutable state ─────────────────────────────────────────────────────────────

_SHQL_TABLE_NAME=""
_SHQL_TABLE_DDL_LINES=()
_SHQL_TABLE_TABBAR_FOCUSED=0
_SHQL_TABLE_BODY_FOCUSED=0

# ── Tab state arrays ──────────────────────────────────────────────────────────
# Dynamic tab model. Each tab occupies the same index across all arrays.

_SHQL_TABS_TYPE=()    # "data" | "schema" | "query"
_SHQL_TABS_TABLE=()   # table name; empty string for query tabs
_SHQL_TABS_LABEL=()   # display label: "users·Data", "Query 1"
_SHQL_TABS_CTX=()     # unique context id: "t0", "t1", …
_SHQL_TAB_ACTIVE=-1   # index of active tab (-1 = no tabs open)
_SHQL_TAB_CTX_SEQ=0   # ever-incrementing; never reused
_SHQL_TAB_QUERY_N=0   # ever-incrementing query label counter

# Keep legacy constants for backward compatibility with test-table.sh
_SHQL_TABLE_TAB_STRUCTURE=0
_SHQL_TABLE_TAB_DATA=1
_SHQL_TABLE_TAB_QUERY=2

# ── Browser state ─────────────────────────────────────────────────────────────

_SHQL_BROWSER_TABLES=()      # loaded from db on shql_browser_init
_SHQL_BROWSER_SIDEBAR_CTX="browser_sidebar"
_SHQL_BROWSER_SIDEBAR_FOCUSED=0
_SHQL_BROWSER_TABBAR_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUS="data"  # "data" | "schema_cols" | "schema_ddl" | "query_editor" | "query_results"

# ── TTY for stderr passthrough ────────────────────────────────────────────────
# Use /dev/tty when available (interactive terminal); fall back to /dev/null in
# test environments where no controlling terminal exists.

if ( exec 9>/dev/tty ) 2>/dev/null; then
    _SHQL_STDERR_TTY=/dev/tty
else
    _SHQL_STDERR_TTY=/dev/null
fi

# ── Footer hint strings ────────────────────────────────────────────────────────

_SHQL_TABLE_FOOTER_HINTS_TABBAR="[←→] Switch tab  [Tab] Body  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_DATA="[↑↓] Navigate  [←→] Scroll  [Enter] Inspect  [Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_STRUCTURE="[↑↓] Scroll  [Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_INSPECTOR="[↑↓] Scroll  [PgUp/PgDn] Page  [Enter/Esc/q] Close"

# ── _shql_table_load_ddl ──────────────────────────────────────────────────────

_shql_table_load_ddl() {
    _SHQL_TABLE_DDL_LINES=()
    local _line
    while IFS= read -r _line; do
        _SHQL_TABLE_DDL_LINES+=("$_line")
    done < <(shql_db_describe "$SHQL_DB_PATH" "$_SHQL_TABLE_NAME" 2>"$_SHQL_STDERR_TTY")
    local _n=${#_SHQL_TABLE_DDL_LINES[@]}
    shellframe_scroll_init "$_SHQL_TABLE_DDL_CTX" "$_n" 1 10 1
}

# ── _shql_table_load_data ─────────────────────────────────────────────────────
#
# Parse TSV output of shql_db_fetch into SHELLFRAME_GRID_* globals.
# First output line is the header row; subsequent lines are data rows.
# Column widths are sized to fit header + content (bounded 8..30).

_shql_table_load_data() {
    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
    SHELLFRAME_GRID_PK_COLS=1

    local _maxcw="${SHQL_MAX_COL_WIDTH:-30}"
    local _idx=0 _c _cell _cw _hw _cv
    local _row=()
    while IFS=$'\t' read -r -a _row; do
        [[ ${#_row[@]} -eq 0 ]] && continue
        if (( _idx == 0 )); then
            # Header row: set up column metadata
            SHELLFRAME_GRID_HEADERS=("${_row[@]}")
            SHELLFRAME_GRID_COLS=${#_row[@]}
            for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                _hw=${#_row[$_c]}
                _cw=$(( _hw + 2 ))
                (( _cw < 8       )) && _cw=8
                (( _cw > _maxcw  )) && _cw=$_maxcw
                SHELLFRAME_GRID_COL_WIDTHS+=("$_cw")
            done
        else
            # Data row: append cells and grow column widths as needed
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
    done < <(shql_db_fetch "$SHQL_DB_PATH" "$_SHQL_TABLE_NAME" 2>"$_SHQL_STDERR_TTY")

    _shql_detect_grid_align
    shellframe_grid_init "$_SHQL_TABLE_GRID_CTX"
}

# ── shql_table_init_browser ───────────────────────────────────────────────────
# Reset all tab state to empty (called on browser entry).
shql_table_init_browser() {
    _SHQL_TABS_TYPE=()
    _SHQL_TABS_TABLE=()
    _SHQL_TABS_LABEL=()
    _SHQL_TABS_CTX=()
    _SHQL_TAB_ACTIVE=-1
    _SHQL_TAB_CTX_SEQ=0
    _SHQL_TAB_QUERY_N=0
}

# ── _shql_tab_find ────────────────────────────────────────────────────────────
# _shql_tab_find <table> <type> <out_var>
# Sets out_var to the index of the matching tab, or -1 if not found.
# Query tabs are never found by this function (use _shql_tab_open for them).
_shql_tab_find() {
    local _table="$1" _type="$2" _out_var="$3"
    local _i
    for (( _i=0; _i<${#_SHQL_TABS_TYPE[@]}; _i++ )); do
        if [[ "${_SHQL_TABS_TYPE[$_i]}" == "$_type" && \
              "${_SHQL_TABS_TABLE[$_i]}" == "$_table" ]]; then
            printf -v "$_out_var" '%d' "$_i"
            return 0
        fi
    done
    printf -v "$_out_var" '%d' -1
}

# ── _shql_tab_open ────────────────────────────────────────────────────────────
# _shql_tab_open <table> <type>
# Opens a tab for (table, type). Deduplicates data/schema; query tabs always new.
# Sets _SHQL_TAB_ACTIVE to the index of the opened/found tab.
# Does NOT check capacity (capacity check happens in the key handler).
_shql_tab_open() {
    local _table="$1" _type="$2"

    # Query tabs always create new
    if [[ "$_type" != "query" ]]; then
        local _found=-1
        _shql_tab_find "$_table" "$_type" _found
        if (( _found >= 0 )); then
            _shql_tab_activate "$_found"
            return 0
        fi
    fi

    # Assign context id
    local _ctx="t${_SHQL_TAB_CTX_SEQ}"
    (( _SHQL_TAB_CTX_SEQ++ ))

    # Build label
    local _label
    if [[ "$_type" == "query" ]]; then
        (( _SHQL_TAB_QUERY_N++ ))
        _label="Query ${_SHQL_TAB_QUERY_N}"
    elif [[ "$_type" == "data" ]]; then
        _label="${_table}·Data"
    else
        _label="${_table}·Schema"
    fi

    _SHQL_TABS_TYPE+=("$_type")
    _SHQL_TABS_TABLE+=("$_table")
    _SHQL_TABS_LABEL+=("$_label")
    _SHQL_TABS_CTX+=("$_ctx")
    _shql_tab_activate $(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
}

# ── _shql_tab_activate ────────────────────────────────────────────────────────
# Set the active tab index and reset inspector state (Decision D1).
_shql_tab_activate() {
    _SHQL_TAB_ACTIVE="$1"
    _SHQL_INSPECTOR_ACTIVE=0
}

# ── _shql_tab_close ───────────────────────────────────────────────────────────
# _shql_tab_close [index]
# Removes the tab at index (default: _SHQL_TAB_ACTIVE) from all arrays.
# After removal, activates the tab to the left, or -1 if none remain.
_shql_tab_close() {
    local _idx="${1:-$_SHQL_TAB_ACTIVE}"
    local _n=${#_SHQL_TABS_TYPE[@]}
    (( _n == 0 || _idx < 0 || _idx >= _n )) && return 0

    # Rebuild arrays without the removed index
    local -a _new_type _new_table _new_label _new_ctx
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        (( _i == _idx )) && continue
        _new_type+=("${_SHQL_TABS_TYPE[$_i]}")
        _new_table+=("${_SHQL_TABS_TABLE[$_i]}")
        _new_label+=("${_SHQL_TABS_LABEL[$_i]}")
        _new_ctx+=("${_SHQL_TABS_CTX[$_i]}")
    done
    _SHQL_TABS_TYPE=("${_new_type[@]+"${_new_type[@]}"}")
    _SHQL_TABS_TABLE=("${_new_table[@]+"${_new_table[@]}"}")
    _SHQL_TABS_LABEL=("${_new_label[@]+"${_new_label[@]}"}")
    _SHQL_TABS_CTX=("${_new_ctx[@]+"${_new_ctx[@]}"}")

    local _new_n=${#_SHQL_TABS_TYPE[@]}
    if (( _new_n == 0 )); then
        _shql_tab_activate -1
    else
        # Activate tab to the left, or stay at 0
        local _new_active=$(( _idx - 1 ))
        (( _new_active < 0 )) && _new_active=0
        (( _new_active >= _new_n )) && _new_active=$(( _new_n - 1 ))
        _shql_tab_activate "$_new_active"
    fi
}

# ── _shql_tab_fits ────────────────────────────────────────────────────────────
# _shql_tab_fits <available_cols> <out_var>
# Sets out_var to 1 if all current tabs fit in available_cols, else 0.
# Accounts for: label + 2 padding chars per tab, 1 separator between tabs,
# plus 5 chars for the "+SQL" affordance at the right end.
_shql_tab_fits() {
    local _avail="$1" _out_var="$2"
    local _n=${#_SHQL_TABS_LABEL[@]}
    local _used=5   # "+SQL " = 5 chars minimum
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        local _llen=${#_SHQL_TABS_LABEL[$_i]}
        _used=$(( _used + _llen + 2 + 1 ))  # label + 2 padding + 1 separator
    done
    if (( _used <= _avail )); then
        printf -v "$_out_var" '%d' 1
    else
        printf -v "$_out_var" '%d' 0
    fi
}

# ── shql_browser_init ─────────────────────────────────────────────────────────
# Load tables list and reset browser state. Call before entering TABLE screen.
shql_browser_init() {
    shql_table_init_browser
    _SHQL_BROWSER_TABLES=()
    _SHQL_BROWSER_SIDEBAR_FOCUSED=0
    _SHQL_BROWSER_TABBAR_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUS="data"
    local _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _SHQL_BROWSER_TABLES+=("$_line")
    done < <(shql_db_list_tables "$SHQL_DB_PATH" 2>/dev/null)
    local _n=${#_SHQL_BROWSER_TABLES[@]}
    shellframe_sel_init "$_SHQL_BROWSER_SIDEBAR_CTX" "$_n"
}

# ── _shql_browser_sidebar_width ───────────────────────────────────────────────
_shql_browser_sidebar_width() {
    local _cols="$1" _out_var="$2"
    local _sbw=$(( _cols / 4 ))
    (( _sbw < 15 )) && _sbw=15
    (( _sbw > 30 )) && _sbw=30
    printf -v "$_out_var" '%d' "$_sbw"
}

# ── _shql_TABLE_render ────────────────────────────────────────────────────────

_shql_TABLE_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    local _sidebar_w
    _shql_browser_sidebar_width "$_cols" _sidebar_w
    local _right_w=$(( _cols - _sidebar_w ))
    local _right_left=$(( _sidebar_w + 1 ))

    local _body_top=2
    local _body_h=$(( _rows - 2 ))
    (( _body_h < 2 )) && _body_h=2
    local _content_top=3
    local _content_h=$(( _rows - 3 ))
    (( _content_h < 1 )) && _content_h=1

    shellframe_shell_region header   1              1              "$_cols"      1             nofocus
    shellframe_shell_region sidebar  "$_body_top"   1              "$_sidebar_w" "$_body_h"    focus
    shellframe_shell_region tabbar   "$_body_top"   "$_right_left" "$_right_w"  1             focus
    shellframe_shell_region content  "$_content_top" "$_right_left" "$_right_w" "$_content_h" focus
    shellframe_shell_region footer   "$_rows"       1              "$_cols"      1             nofocus
}

# ── _shql_TABLE_header_render ─────────────────────────────────────────────────

_shql_TABLE_header_render() {
    _shql_header_render "$1" "$2" "$3" "$(_shql_breadcrumb "")"
}

# ── _shql_TABLE_tabbar_render / on_key / on_focus ─────────────────────────────

_shql_TABLE_tabbar_render() {
    SHELLFRAME_TABBAR_LABELS=("Structure" "Data" "Query")
    SHELLFRAME_TABBAR_FOCUSED=$_SHQL_TABLE_TABBAR_FOCUSED
    SHELLFRAME_TABBAR_BG="${SHQL_THEME_TABBAR_BG:-}"
    shellframe_tabbar_render "$@"
}

_shql_TABLE_tabbar_on_key() {
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    if [[ "$1" == "$_k_down" ]]; then
        shellframe_shell_focus_set "body"
        return 0
    fi
    case "$1" in
        '[') (( SHELLFRAME_TABBAR_ACTIVE > 0 )) && (( SHELLFRAME_TABBAR_ACTIVE-- )) || true; return 0 ;;
        ']') (( SHELLFRAME_TABBAR_ACTIVE < _SHQL_TABLE_TAB_QUERY )) && (( SHELLFRAME_TABBAR_ACTIVE++ )) || true; return 0 ;;
    esac
    shellframe_tabbar_on_key "$1"
}

_shql_TABLE_tabbar_on_focus() {
    _SHQL_TABLE_TABBAR_FOCUSED="${1:-0}"
    SHELLFRAME_TABBAR_FOCUSED=$_SHQL_TABLE_TABBAR_FOCUSED
}

# ── _shql_table_structure_render / on_key ─────────────────────────────────────

_shql_table_structure_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    shellframe_scroll_resize "$_SHQL_TABLE_DDL_CTX" "$_height" 1
    local _scroll_top
    shellframe_scroll_top "$_SHQL_TABLE_DDL_CTX" _scroll_top
    local _n=${#_SHQL_TABLE_DDL_LINES[@]}
    local _rst="${SHELLFRAME_RESET:-}"
    local _dim_on="" _dim_off=""
    if (( ! _SHQL_TABLE_BODY_FOCUSED )); then
        _dim_on="${SHELLFRAME_DIM:-}"
        _dim_off="$_rst"
    fi
    printf '%s' "$_dim_on" >/dev/tty
    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _row=$(( _top + _r ))
        local _idx=$(( _scroll_top + _r ))
        printf '\033[%d;%dH%*s' "$_row" "$_left" "$_width" '' >/dev/tty
        [[ $_idx -ge $_n ]] && continue
        local _line="${_SHQL_TABLE_DDL_LINES[$_idx]}"
        local _clipped
        _clipped=$(shellframe_str_clip_ellipsis "$_line" "$_line" "$_width")
        printf '\033[%d;%dH%s' "$_row" "$_left" "$_clipped" >/dev/tty
    done
    printf '%s' "$_dim_off" >/dev/tty
}

_shql_table_structure_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"
    if   [[ "$_key" == "$_k_down"  ]]; then shellframe_scroll_move "$_SHQL_TABLE_DDL_CTX" down;      return 0
    elif [[ "$_key" == "$_k_up"    ]]; then shellframe_scroll_move "$_SHQL_TABLE_DDL_CTX" up;        return 0
    elif [[ "$_key" == "$_k_pgdn"  ]]; then shellframe_scroll_move "$_SHQL_TABLE_DDL_CTX" page_down; return 0
    elif [[ "$_key" == "$_k_pgup"  ]]; then shellframe_scroll_move "$_SHQL_TABLE_DDL_CTX" page_up;   return 0
    elif [[ "$_key" == "$_k_home"  ]]; then shellframe_scroll_move "$_SHQL_TABLE_DDL_CTX" home;      return 0
    elif [[ "$_key" == "$_k_end"   ]]; then shellframe_scroll_move "$_SHQL_TABLE_DDL_CTX" end;       return 0
    fi
    return 1
}

# ── _shql_grid_fill_width ─────────────────────────────────────────────────────
# Temporarily expand the last column so the grid fills the given width.
# Saves the original width in _SHQL_GRID_SAVED_LAST_W for restoration.
# No-op when SHELLFRAME_GRID_COLS == 0 or columns already fill the width.

_shql_grid_fill_width() {
    local _width="$1"
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_GRID_SAVED_LAST_W=""
    (( _ncols == 0 )) && return 0
    local _last=$(( _ncols - 1 ))
    local _total=0 _i
    for (( _i=0; _i<_ncols; _i++ )); do
        _total=$(( _total + ${SHELLFRAME_GRID_COL_WIDTHS[$_i]:-10} ))
        (( _i < _ncols - 1 )) && (( _total++ ))   # 1-px column separator
    done
    local _extra=$(( _width - _total ))
    if (( _extra > 0 )); then
        _SHQL_GRID_SAVED_LAST_W="${SHELLFRAME_GRID_COL_WIDTHS[$_last]:-10}"
        SHELLFRAME_GRID_COL_WIDTHS[$_last]=$(( _SHQL_GRID_SAVED_LAST_W + _extra ))
    fi
}

_shql_grid_restore_last() {
    [[ -n "${_SHQL_GRID_SAVED_LAST_W:-}" ]] || return 0
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    (( _ncols > 0 )) && SHELLFRAME_GRID_COL_WIDTHS[$(( _ncols - 1 ))]="$_SHQL_GRID_SAVED_LAST_W"
}

# ── _shql_detect_grid_align ───────────────────────────────────────────────────
# Scan SHELLFRAME_GRID_DATA and populate SHELLFRAME_GRID_COL_ALIGN.
# Integer/float columns → right; boolean (0/1/true/false/t/f) → center; text → left.
# Columns with no non-empty values default to left.

_shql_detect_grid_align() {
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    local _nrows="${SHELLFRAME_GRID_ROWS:-0}"
    SHELLFRAME_GRID_COL_ALIGN=()
    (( _ncols == 0 )) && return 0

    local -a _all_num _all_bool _any_val
    local _c
    for (( _c=0; _c<_ncols; _c++ )); do
        _all_num[$_c]=1
        _all_bool[$_c]=1
        _any_val[$_c]=0
    done

    local _r _cell
    for (( _r=0; _r<_nrows; _r++ )); do
        for (( _c=0; _c<_ncols; _c++ )); do
            _cell="${SHELLFRAME_GRID_DATA[$(( _r * _ncols + _c ))]:-}"
            [[ -z "$_cell" ]] && continue
            _any_val[$_c]=1
            if (( _all_num[_c] )); then
                [[ "$_cell" =~ ^-?[0-9]+$ ]] || [[ "$_cell" =~ ^-?[0-9]*\.[0-9]+$ ]] \
                    || _all_num[$_c]=0
            fi
            if (( _all_bool[_c] )); then
                case "$_cell" in
                    0|1|true|false|TRUE|FALSE|t|f|T|F) ;;
                    *) _all_bool[$_c]=0 ;;
                esac
            fi
        done
    done

    for (( _c=0; _c<_ncols; _c++ )); do
        if (( _any_val[_c] && _all_bool[_c] )); then
            SHELLFRAME_GRID_COL_ALIGN[$_c]="center"
        elif (( _any_val[_c] && _all_num[_c] )); then
            SHELLFRAME_GRID_COL_ALIGN[$_c]="right"
        else
            SHELLFRAME_GRID_COL_ALIGN[$_c]="left"
        fi
    done
}

# ── _shql_table_data_render ───────────────────────────────────────────────────

_shql_table_data_render() {
    SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
    SHELLFRAME_GRID_FOCUSED=$_SHQL_TABLE_BODY_FOCUSED
    _shql_grid_fill_width "$3"   # $3 = width
    shellframe_grid_render "$@"
    _shql_grid_restore_last
}

# ── Content region stubs (replaced in Task 7) ─────────────────────────────────
_shql_TABLE_content_render()   { :; }
_shql_TABLE_content_on_key()   { return 1; }
_shql_TABLE_content_on_focus() { _SHQL_BROWSER_CONTENT_FOCUSED="${1:-0}"; }
_shql_TABLE_content_action()   { :; }

# ── _shql_table_data_footer_hint ─────────────────────────────────────────────
# Build the data-tab footer hint with a live row-range prefix.
# Stores the result in the named output variable.

_shql_table_data_footer_hint() {
    local _out_var="$1"
    local _nrows="${SHELLFRAME_GRID_ROWS:-0}"

    if (( _nrows == 0 )); then
        printf -v "$_out_var" '%s' "$_SHQL_TABLE_FOOTER_HINTS_DATA"
        return
    fi

    local _scroll_top=0
    shellframe_scroll_top "$_SHQL_TABLE_GRID_CTX" _scroll_top

    local _term_rows _term_cols
    _shellframe_shell_terminal_size _term_rows _term_cols
    local _vrows=$(( _term_rows - 4 - 2 ))   # body_h=rows-4, minus 2 grid header rows
    (( _vrows < 1 )) && _vrows=1

    local _first=$(( _scroll_top + 1 ))
    local _last=$(( _scroll_top + _vrows ))
    (( _last > _nrows )) && _last=$_nrows

    printf -v "$_out_var" 'Rows %d–%d of %d  %s' \
        "$_first" "$_last" "$_nrows" "$_SHQL_TABLE_FOOTER_HINTS_DATA"
}

# ── _shql_TABLE_footer_render ─────────────────────────────────────────────────

_shql_TABLE_footer_render() {
    local _top="$1" _left="$2"
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    local _hint
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _hint="$_SHQL_TABLE_FOOTER_HINTS_INSPECTOR"
    elif (( _SHQL_TABLE_TABBAR_FOCUSED )); then
        _hint="$_SHQL_TABLE_FOOTER_HINTS_TABBAR"
    else
        local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
        case "$_tab" in
            "$_SHQL_TABLE_TAB_DATA")      _shql_table_data_footer_hint _hint ;;
            "$_SHQL_TABLE_TAB_STRUCTURE") _hint="$_SHQL_TABLE_FOOTER_HINTS_STRUCTURE" ;;
            "$_SHQL_TABLE_TAB_QUERY")     _shql_query_footer_hint _hint ;;
            *)                            _hint="" ;;
        esac
    fi
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" "$_gray" "$_hint" "$_rst" >/dev/tty
}

# ── _shql_TABLE_quit ──────────────────────────────────────────────────────────

_shql_TABLE_quit() {
    _SHELLFRAME_SHELL_NEXT="SCHEMA"
}

# ── shql_table_init ───────────────────────────────────────────────────────────

# Called once before the TABLE screen is first entered.
# SHQL_DB_PATH and _SHQL_TABLE_NAME must already be set.
shql_table_init() {
    _SHQL_TABLE_TABBAR_FOCUSED=0
    _SHQL_TABLE_BODY_FOCUSED=0
    SHELLFRAME_TABBAR_ACTIVE=0
    _SHQL_INSPECTOR_ACTIVE=0    # reset inspector state on table entry

    _shql_table_load_ddl
    _shql_table_load_data
    _shql_query_init
}
