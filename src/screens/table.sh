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
_SHQL_BROWSER_OBJECT_TYPES=()
_SHQL_BROWSER_SIDEBAR_ITEMS=()
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

# ── Browser footer hint strings ───────────────────────────────────────────────

_SHQL_BROWSER_FOOTER_HINTS_SIDEBAR="[↑↓] Navigate  [Enter] Data  s=Schema  [→/Tab] Focus  [q] Back"
_SHQL_BROWSER_FOOTER_HINTS_TABBAR="[←→] Switch tab  [↓/Enter] Content  [w] Close  [n] New query  [Tab] Sidebar"
_SHQL_BROWSER_FOOTER_HINTS_DATA="[↑↓] Navigate  [←→] Scroll  [Enter] Inspect  [[/]] Tabs  [Tab] Sidebar  [q] Back"
_SHQL_BROWSER_FOOTER_HINTS_SCHEMA="[↑↓] Scroll  [Tab] DDL/exit  [q] Back"
# Documentation constant only — runtime hint is built dynamically by _shql_query_footer_hint
_SHQL_BROWSER_FOOTER_HINTS_QUERY_BUTTON="[Enter] Edit  [Tab] Results  [Esc] Tab bar"
_SHQL_BROWSER_FOOTER_HINTS_INSPECTOR="[←→] Prev/Next  [↑↓] Scroll  [Esc] Grid  [Tab] Sidebar"
_SHQL_BROWSER_FOOTER_HINTS_EMPTY="[↑↓] select a table  [Enter] Data  [s] Schema  [n] New query  [q] Back"

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
    # Set content sub-focus based on tab type
    if (( _SHQL_TAB_ACTIVE >= 0 )); then
        case "${_SHQL_TABS_TYPE[$_SHQL_TAB_ACTIVE]}" in
            schema) _SHQL_BROWSER_CONTENT_FOCUS="schema_cols" ;;
            query)  _SHQL_BROWSER_CONTENT_FOCUS="query" ;;
            *)      _SHQL_BROWSER_CONTENT_FOCUS="data" ;;
        esac
    fi
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
    _SHQL_BROWSER_SIDEBAR_FOCUSED=1
    _SHQL_BROWSER_TABBAR_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUS="data"
    _SHQL_BROWSER_GRID_OWNER_CTX=""
    _SHQL_BROWSER_OBJECT_TYPES=()
    _SHQL_BROWSER_SIDEBAR_ITEMS=()
    local _obj_name _obj_type
    while IFS=$'\t' read -r _obj_name _obj_type; do
        [[ -z "$_obj_name" ]] && continue
        _SHQL_BROWSER_TABLES+=("$_obj_name")
        _SHQL_BROWSER_OBJECT_TYPES+=("${_obj_type:-table}")
        local _icon=""
        if [[ "$_obj_type" == "view" ]]; then
            _icon="${SHQL_THEME_VIEW_ICON:-}"
        else
            _icon="${SHQL_THEME_TABLE_ICON:-}"
        fi
        _SHQL_BROWSER_SIDEBAR_ITEMS+=("${_icon}${_obj_name}")
    done < <(shql_db_list_objects "$SHQL_DB_PATH" 2>/dev/null)
    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
    shellframe_list_init "$_SHQL_BROWSER_SIDEBAR_CTX"
    # Sidebar starts focused
    shellframe_shell_focus_set "sidebar"
}

# ── _shql_browser_sidebar_width ───────────────────────────────────────────────
_shql_browser_sidebar_width() {
    local _cols="$1" _out_var="$2"
    local _sbw=$(( _cols / 4 ))
    (( _sbw < 15 )) && _sbw=15
    (( _sbw > 30 )) && _sbw=30
    printf -v "$_out_var" '%d' "$_sbw"
}

# ── _shql_TABLE_sidebar_render ────────────────────────────────────────────────

_shql_TABLE_sidebar_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Set sidebar cursor style (blue in cascade, or fallback to grid cursor)
    if [[ -n "${SHQL_THEME_SIDEBAR_CURSOR_BG:-}" ]]; then
        SHELLFRAME_LIST_CURSOR_STYLE="${SHQL_THEME_SIDEBAR_CURSOR_BG}"
    elif [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
        SHELLFRAME_LIST_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
    else
        SHELLFRAME_LIST_CURSOR_STYLE=""
    fi

    # Fill sidebar with sidebar bg
    if [[ -n "${SHQL_THEME_SIDEBAR_BG:-}" ]]; then
        local _sr
        for (( _sr=0; _sr<_height; _sr++ )); do
            printf '\033[%d;%dH%s%*s' "$(( _top + _sr ))" "$_left" "$SHQL_THEME_SIDEBAR_BG" "$_width" '' >/dev/tty
        done
        printf '%s' "${SHQL_THEME_RESET:-$'\033[0m'}" >/dev/tty
    fi

    SHELLFRAME_LIST_BG="${SHQL_THEME_SIDEBAR_BG:-}"

    if [[ "${SHQL_THEME_SIDEBAR_BORDER:-}" == "none" ]]; then
        # No panel border — render list directly in the full region
        SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
        SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
        SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_list_render "$_top" "$_left" "$_width" "$_height"
    else
        SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
        SHELLFRAME_PANEL_TITLE="Tables"
        SHELLFRAME_PANEL_TITLE_ALIGN="left"
        SHELLFRAME_PANEL_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

        local _it _il _iw _ih
        shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

        SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
        SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
        SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_list_render "$_it" "$_il" "$_iw" "$_ih"
    fi
}

# ── _shql_TABLE_sidebar_on_key ────────────────────────────────────────────────

_shql_TABLE_sidebar_on_key() {
    local _key="$1"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

    case "$_key" in
        "$_k_right") shellframe_shell_focus_set "tabbar";  return 0 ;;
        $'\r'|$'\n') _shql_TABLE_sidebar_action; return 0 ;;
        s)           _shql_TABLE_sidebar_action_schema; return 0 ;;
        n)
            local _fits=1
            local _rows _cols; _shellframe_shell_terminal_size _rows _cols
            local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
            _shql_tab_fits $(( _cols - _sidebar_w )) _fits
            if (( _fits )); then
                _shql_tab_open "" "query"
                shellframe_shell_focus_set "content"
            fi
            return 0 ;;
    esac
    # Delegate ↑/↓ and other list keys to the list widget
    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    shellframe_list_on_key "$_key"
}

_shql_TABLE_sidebar_on_focus() {
    _SHQL_BROWSER_SIDEBAR_FOCUSED="${1:-0}"
    SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
}

# ── _shql_TABLE_sidebar_action / sidebar_action_schema ────────────────────────

_shql_TABLE_sidebar_action() {
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
    local _table="${_SHQL_BROWSER_TABLES[$_cursor]:-}"
    [[ -z "$_table" ]] && return 0

    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    local _sidebar_w
    _shql_browser_sidebar_width "$_cols" _sidebar_w
    local _bar_w=$(( _cols - _sidebar_w ))
    local _fits=1
    _shql_tab_fits "$_bar_w" _fits
    if (( ! _fits )); then
        # Flash footer — capacity exceeded
        _SHQL_BROWSER_FLASH_MSG="Tab bar full — close a tab first (w)"
        return 0
    fi
    _shql_tab_open "$_table" "data"
    shellframe_shell_focus_set "content"
}

_shql_TABLE_sidebar_action_schema() {
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
    local _table="${_SHQL_BROWSER_TABLES[$_cursor]:-}"
    [[ -z "$_table" ]] && return 0
    _shql_tab_open "$_table" "schema"
    shellframe_shell_focus_set "content"
}

# ── _shql_tabbar_build_line ───────────────────────────────────────────────────
# Build the tab bar text content into out_var. No ANSI codes — used for tests.
_shql_tabbar_build_line() {
    local _width="$1" _out_var="$2"
    local _n=${#_SHQL_TABS_LABEL[@]}
    local _tbline=""
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        local _label=" ${_SHQL_TABS_LABEL[$_i]} "
        if (( _i > 0 )); then _tbline+="│"; fi
        _tbline+="$_label"
    done
    # Append +SQL affordance
    if [[ -n "$_tbline" ]]; then _tbline+="  +SQL"; else _tbline="+SQL"; fi
    printf -v "$_out_var" '%s' "$_tbline"
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
    local _content_top=4
    local _content_h=$(( _rows - 4 ))
    (( _content_h < 1 )) && _content_h=1

    # Content is only focusable when a tab is open
    local _content_focus="nofocus"
    (( _SHQL_TAB_ACTIVE >= 0 )) && _content_focus="focus"

    shellframe_shell_region header   1              1              "$_cols"      1             nofocus
    shellframe_shell_region sidebar  "$_body_top"   1              "$_sidebar_w" "$_body_h"    focus
    shellframe_shell_region tabbar   "$_body_top"   "$_right_left" "$_right_w"  1             focus
    shellframe_shell_region content  "$_content_top" "$_right_left" "$_right_w" "$_content_h" "$_content_focus"
    shellframe_shell_region footer   "$_rows"       1              "$_cols"      1             nofocus
}

# ── _shql_TABLE_header_render ─────────────────────────────────────────────────

_shql_TABLE_header_render() {
    _shql_header_render "$1" "$2" "$3" "$(_shql_breadcrumb "")"
}

# ── _shql_TABLE_tabbar_render / on_key / on_focus ─────────────────────────────

# ── _shql_TABLE_tabbar_render ─────────────────────────────────────────────────
# Replaces the old static shellframe_tabbar_render call.

_SHQL_BROWSER_TABBAR_ON_SQL=0  # 1 when cursor is on the +SQL button

_shql_TABLE_tabbar_render() {
    local _top="$1" _left="$2" _width="$3" _height="${4:-1}"
    local _inv="${SHELLFRAME_REVERSE:-}" _rst="${SHELLFRAME_RESET:-}"
    local _gray="${SHELLFRAME_GRAY:-}" _bold="${SHELLFRAME_BOLD:-}"

    # Clear only the tabbar's portion of the row (not the sidebar's border)
    if [[ -n "${SHQL_THEME_CONTENT_BG:-}" ]]; then
        printf '\033[%d;%dH%s%*s' "$_top" "$_left" "$SHQL_THEME_CONTENT_BG" "$_width" '' >/dev/tty
        printf '\033[%d;%dH' "$_top" "$_left" >/dev/tty
    else
        printf '\033[%d;%dH%*s' "$_top" "$_left" "$_width" '' >/dev/tty
    fi

    local _n=${#_SHQL_TABS_LABEL[@]}
    local _col=$_left
    # Track active tab pixel range for the content border gap
    _SHQL_TABBAR_ACTIVE_X0=-1
    _SHQL_TABBAR_ACTIVE_X1=-1
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        if (( _i > 0 )); then
            printf '\033[%d;%dH%s %s' "$_top" "$_col" "${SHQL_THEME_CONTENT_BG:-}" "${_rst}" >/dev/tty
            (( _col++ ))
        fi
        local _label=" ${_SHQL_TABS_LABEL[$_i]} "
        if (( _i == _SHQL_TAB_ACTIVE )); then
            _SHQL_TABBAR_ACTIVE_X0=$_col
            _SHQL_TABBAR_ACTIVE_X1=$(( _col + ${#_label} ))
            # Active tab: content bg, focus color only on THIS tab when focused
            local _tab_bg="${SHQL_THEME_CONTENT_BG:-}"
            if (( _SHQL_BROWSER_TABBAR_FOCUSED && ! _SHQL_BROWSER_TABBAR_ON_SQL )); then
                local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-$_bold}"
                printf '\033[%d;%dH%s%s%s%s' "$_top" "$_col" "$_tab_bg" "$_focus_color" "$_label" "$_rst" >/dev/tty
            elif [[ -n "$_tab_bg" ]]; then
                printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_tab_bg" "$_label" "$_rst" >/dev/tty
            else
                printf '\033[%d;%dH%s' "$_top" "$_col" "$_label" >/dev/tty
            fi
        else
            # Inactive tabs: always normal inactive styling (no focus color)
            local _itab_style="${SHQL_THEME_TAB_INACTIVE_BG:-${SHQL_THEME_TABBAR_BG:-$_inv}}"
            printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_itab_style" "$_label" "$_rst" >/dev/tty
        fi
        _col=$(( _col + ${#_label} ))
    done
    # +SQL button — styled like inactive tabs
    printf '\033[%d;%dH%s %s' "$_top" "$_col" "${SHQL_THEME_CONTENT_BG:-}" "${_rst}" >/dev/tty
    (( _col += 1 ))  # 1-char gap after last tab
    local _sql_label=" +SQL "
    local _itab_style="${SHQL_THEME_TAB_INACTIVE_BG:-${SHQL_THEME_TABBAR_BG:-$_inv}}"
    if (( _SHQL_BROWSER_TABBAR_ON_SQL )); then
        # Focused: purple text on inactive tab bg
        local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-$_bold}"
        printf '\033[%d;%dH%s%s%s%s' "$_top" "$_col" "$_itab_style" "$_focus_color" "$_sql_label" "$_rst" >/dev/tty
    else
        printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_itab_style" "$_sql_label" "$_rst" >/dev/tty
    fi
}

# ── _shql_TABLE_tabbar_on_key ────────────────────────────────────────────────

_shql_TABLE_tabbar_on_key() {
    local _key="$1"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"

    case "$_key" in
        "$_k_left")
            if (( _SHQL_BROWSER_TABBAR_ON_SQL )); then
                # From +SQL → back to last tab (or sidebar if no tabs)
                _SHQL_BROWSER_TABBAR_ON_SQL=0
                if (( ${#_SHQL_TABS_TYPE[@]} == 0 )); then
                    shellframe_shell_focus_set "sidebar"
                fi
            elif (( _SHQL_TAB_ACTIVE > 0 )); then
                _shql_tab_activate $(( _SHQL_TAB_ACTIVE - 1 ))
            else
                # At first tab → sidebar
                shellframe_shell_focus_set "sidebar"
            fi
            return 0 ;;
        "$_k_right")
            if (( _SHQL_BROWSER_TABBAR_ON_SQL )); then
                return 0  # already at rightmost position
            fi
            local _max=$(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
            if (( _SHQL_TAB_ACTIVE < _max )); then
                _shql_tab_activate $(( _SHQL_TAB_ACTIVE + 1 ))
            else
                # Past last tab → +SQL
                _SHQL_BROWSER_TABBAR_ON_SQL=1
            fi
            return 0 ;;
        "$_k_down")
            _SHQL_BROWSER_TABBAR_ON_SQL=0
            shellframe_shell_focus_set "content"
            return 0 ;;
        $'\r'|$'\n')
            if (( _SHQL_BROWSER_TABBAR_ON_SQL )); then
                # Enter on +SQL → new query
                _SHQL_BROWSER_TABBAR_ON_SQL=0
                local _fits=1
                local _rows _cols; _shellframe_shell_terminal_size _rows _cols
                local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
                _shql_tab_fits $(( _cols - _sidebar_w )) _fits
                if (( _fits )); then
                    _shql_tab_open "" "query"
                    shellframe_shell_focus_set "content"
                fi
            else
                shellframe_shell_focus_set "content"
            fi
            return 0 ;;
        w)
            _shql_tab_close
            return 0 ;;
        n)
            _SHQL_BROWSER_TABBAR_ON_SQL=0
            local _fits=1
            local _rows _cols; _shellframe_shell_terminal_size _rows _cols
            local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
            _shql_tab_fits $(( _cols - _sidebar_w )) _fits
            if (( _fits )); then
                _shql_tab_open "" "query"
                shellframe_shell_focus_set "content"
            fi
            return 0 ;;
    esac
    return 1
}

_shql_TABLE_tabbar_on_focus() {
    _SHQL_BROWSER_TABBAR_FOCUSED="${1:-0}"
    if (( ! _SHQL_BROWSER_TABBAR_FOCUSED )); then
        _SHQL_BROWSER_TABBAR_ON_SQL=0
    elif (( ${#_SHQL_TABS_TYPE[@]} == 0 )); then
        # No tabs open — auto-select +SQL when tabbar receives focus
        _SHQL_BROWSER_TABBAR_ON_SQL=1
    fi
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

# ── _shql_content_type ────────────────────────────────────────────────────────
# Sets out_var to the type string of the active tab: "data"|"schema"|"query"|"empty"
_shql_content_type() {
    local _out_var="$1"
    if (( _SHQL_TAB_ACTIVE < 0 )); then
        printf -v "$_out_var" '%s' "empty"
        return 0
    fi
    printf -v "$_out_var" '%s' "${_SHQL_TABS_TYPE[$_SHQL_TAB_ACTIVE]:-empty}"
}

# ── _shql_content_data_ensure ─────────────────────────────────────────────────
# Loads data grid for the active tab's table into the shared grid globals.
# Tracks which ctx currently owns the globals; reloads from sqlite on tab switch.
_SHQL_BROWSER_GRID_OWNER_CTX=""

_shql_content_data_ensure() {
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0
    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    local _table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]}"
    # Skip reload if this ctx already owns the globals
    [[ "$_SHQL_BROWSER_GRID_OWNER_CTX" == "$_ctx" ]] && return 0

    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_CTX="${_ctx}_grid"
    SHELLFRAME_GRID_PK_COLS=1

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
    done < <(shql_db_fetch "$SHQL_DB_PATH" "$_table" 2>"$_SHQL_STDERR_TTY")

    _shql_detect_grid_align
    shellframe_grid_init "${_ctx}_grid"
    _SHQL_BROWSER_GRID_OWNER_CTX="$_ctx"
}

# ── _shql_schema_tab_load ─────────────────────────────────────────────────────
# Load DDL and columns for the given table under the active tab's ctx.
_shql_schema_tab_load() {
    local _table="$1"
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0
    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    local _sentinel="_SHQL_SCHEMA_TAB_LOADED_${_ctx}"
    [[ "${!_sentinel:-0}" == "1" ]] && return 0

    # Load DDL into ctx-namespaced array
    local _arr_ddl="_SHQL_SCHEMA_TAB_DDL_${_ctx}"
    eval "${_arr_ddl}=()"
    local _line
    while IFS= read -r _line; do
        eval "${_arr_ddl}+=(\"${_line//\"/\\\"}\")"
    done < <(shql_db_describe "$SHQL_DB_PATH" "$_table" 2>/dev/null)
    local _n_ddl
    eval "_n_ddl=\${#${_arr_ddl}[@]}"
    shellframe_scroll_init "${_ctx}_ddl" "$_n_ddl" 1 10 1

    # Load columns into ctx-namespaced array
    local _arr_cols="_SHQL_SCHEMA_TAB_COLS_${_ctx}"
    eval "${_arr_cols}=()"
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        eval "${_arr_cols}+=(\"${_line//\"/\\\"}\")"
    done < <(shql_db_columns "$SHQL_DB_PATH" "$_table" 2>/dev/null)
    local _n_cols
    eval "_n_cols=\${#${_arr_cols}[@]}"
    shellframe_scroll_init "${_ctx}_cols" "$_n_cols" 1 10 1

    printf -v "$_sentinel" '%s' "1"
}

# ── _shql_schema_tab_render ───────────────────────────────────────────────────

_shql_schema_tab_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0

    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    local _table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]}"
    _shql_schema_tab_load "$_table"

    local _cols_w=$(( _width * 4 / 10 ))
    (( _cols_w < 15 )) && _cols_w=15
    local _ddl_w=$(( _width - _cols_w ))
    local _ddl_left=$(( _left + _cols_w ))

    local _cols_focused=0 _ddl_focused=0
    [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]] && _cols_focused=1
    [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_ddl"  ]] && _ddl_focused=1

    # Columns pane
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE="Columns"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_cols_focused
    shellframe_panel_render "$_top" "$_left" "$_cols_w" "$_height"
    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_cols_w" "$_height" _it _il _iw _ih
    local _arr_cols="_SHQL_SCHEMA_TAB_COLS_${_ctx}"
    local _n_cols; eval "_n_cols=\${#${_arr_cols}[@]}"
    shellframe_scroll_resize "${_ctx}_cols" "$_ih" 1
    local _scroll_top=0; shellframe_scroll_top "${_ctx}_cols" _scroll_top
    local _r
    for (( _r=0; _r<_ih; _r++ )); do
        local _idx=$(( _scroll_top + _r ))
        printf '\033[%d;%dH%*s' "$(( _it + _r ))" "$_il" "$_iw" '' >/dev/tty
        (( _idx >= _n_cols )) && continue
        local _entry; eval "_entry=\"\${${_arr_cols}[$_idx]}\""
        local _cname _ctype _cflags
        IFS=$'\t' read -r _cname _ctype _cflags <<< "$_entry"
        local _plain
        if [[ -n "$_cflags" ]]; then
            _plain=$(printf '%-12s %-7s %s' "$_cname" "$_ctype" "$_cflags")
        else
            _plain=$(printf '%-12s %s' "$_cname" "$_ctype")
        fi
        local _clipped; _clipped=$(shellframe_str_clip_ellipsis "$_plain" "$_plain" "$_iw")
        printf '\033[%d;%dH%s' "$(( _it + _r ))" "$_il" "$_clipped" >/dev/tty
    done

    # DDL pane
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE="DDL"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_ddl_focused
    shellframe_panel_render "$_top" "$_ddl_left" "$_ddl_w" "$_height"
    shellframe_panel_inner "$_top" "$_ddl_left" "$_ddl_w" "$_height" _it _il _iw _ih
    local _arr_ddl="_SHQL_SCHEMA_TAB_DDL_${_ctx}"
    local _n_ddl; eval "_n_ddl=\${#${_arr_ddl}[@]}"
    shellframe_scroll_resize "${_ctx}_ddl" "$_ih" 1
    _scroll_top=0; shellframe_scroll_top "${_ctx}_ddl" _scroll_top
    for (( _r=0; _r<_ih; _r++ )); do
        local _idx=$(( _scroll_top + _r ))
        printf '\033[%d;%dH%*s' "$(( _it + _r ))" "$_il" "$_iw" '' >/dev/tty
        (( _idx >= _n_ddl )) && continue
        local _line; eval "_line=\"\${${_arr_ddl}[$_idx]}\""
        local _clipped; _clipped=$(shellframe_str_clip_ellipsis "$_line" "$_line" "$_iw")
        printf '\033[%d;%dH%s' "$(( _it + _r ))" "$_il" "$_clipped" >/dev/tty
    done
}

# ── _shql_TABLE_content_render ────────────────────────────────────────────────

_shql_TABLE_content_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Fill content area + padding row above with theme background
    if [[ -n "${SHQL_THEME_CONTENT_BG:-}" ]]; then
        # Padding row (1 row above content top)
        printf '\033[%d;%dH%s%*s' "$(( _top - 1 ))" "$_left" "$SHQL_THEME_CONTENT_BG" "$_width" '' >/dev/tty
        local _r
        for (( _r=0; _r<_height; _r++ )); do
            printf '\033[%d;%dH%s%*s' "$(( _top + _r ))" "$_left" "$SHQL_THEME_CONTENT_BG" "$_width" '' >/dev/tty
        done
        printf '%s' "${SHQL_THEME_RESET:-$'\033[0m'}" >/dev/tty
    fi

    local _type
    _shql_content_type _type

    case "$_type" in
        data)
            # Load data for this tab's table if not already loaded
            _shql_content_data_ensure
            if (( _SHQL_INSPECTOR_ACTIVE )); then
                # Render grid header row visible above the inspector
                SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
                SHELLFRAME_GRID_FOCUSED=0
                SHELLFRAME_GRID_BG="${SHQL_THEME_CONTENT_BG:-}"
                SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
                SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
                SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
                SHELLFRAME_GRID_CURSOR_STYLE=""
                _shql_grid_fill_width "$_width"
                # Render 3 rows: header label + separator + 1 data row
                shellframe_grid_render "$_top" "$_left" "$_width" 3
                _shql_grid_restore_last
                # Inspector starts below the header
                local _insp_top=$(( _top + 3 ))
                local _insp_h=$(( _height - 3 ))
                (( _insp_h < 3 )) && _insp_h=3
                _shql_inspector_render "$_insp_top" "$_left" "$_width" "$_insp_h"
            else
                SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
                SHELLFRAME_GRID_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
                SHELLFRAME_GRID_BG="${SHQL_THEME_CONTENT_BG:-}"
                SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
                SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
                SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
                if [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
                    SHELLFRAME_GRID_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
                else
                    SHELLFRAME_GRID_CURSOR_STYLE=""
                fi
                _shql_grid_fill_width "$_width"
                shellframe_grid_render "$_top" "$_left" "$_width" "$_height"
                _shql_grid_restore_last
                # Dark surface below last data row
                local _data_end=$(( _top + 2 + SHELLFRAME_GRID_ROWS ))
                local _surface_bg="${SHQL_THEME_EDITOR_FOCUSED_BG:-${SHQL_THEME_CONTENT_BG:-}}"
                if [[ -n "$_surface_bg" ]] && (( _data_end < _top + _height )); then
                    local _sr
                    for (( _sr=_data_end; _sr < _top + _height; _sr++ )); do
                        printf '\033[%d;%dH%s%*s' "$_sr" "$_left" "$_surface_bg" "$_width" '' >/dev/tty
                    done
                    printf '%s' "${SHQL_THEME_RESET:-$'\033[0m'}" >/dev/tty
                fi
            fi
            ;;
        schema)
            _shql_schema_tab_render "$_top" "$_left" "$_width" "$_height"
            ;;
        query)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            _shql_query_render_ctx "$_ctx" "$_top" "$_left" "$_width" "$_height"
            ;;
        *)
            # Empty state
            local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
            local _r
            for (( _r=0; _r<_height; _r++ )); do
                printf '\033[%d;%dH%*s' "$(( _top + _r ))" "$_left" "$_width" '' >/dev/tty
            done
            local _mid=$(( _top + _height / 2 ))
            local _hint="↑↓ select a table · Enter = Data · s = Schema · n = New query"
            local _hlen=${#_hint}
            local _hcol=$(( _left + (_width - _hlen) / 2 ))
            (( _hcol < _left )) && _hcol=$_left
            printf '\033[%d;%dH%s%s%s' "$_mid" "$_hcol" "$_gray" "$_hint" "$_rst" >/dev/tty
            ;;
    esac
}

_shql_TABLE_content_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"

    # Route to inspector when active
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _shql_inspector_on_key "$_key"
        return $?
    fi

    local _type
    _shql_content_type _type

    # Esc from content → move focus to tabbar (prevent global quit)
    # Exception: query tabs handle Esc internally (typing → button, button → tabbar)
    if [[ "$_key" == $'\033' && "$_type" != "query" ]]; then
        shellframe_shell_focus_set "tabbar"
        return 0
    fi

    # [ / ] switch tabs from content (D1: _shql_tab_activate resets inspector)
    case "$_key" in
        '[')
            (( _SHQL_TAB_ACTIVE > 0 )) && _shql_tab_activate $(( _SHQL_TAB_ACTIVE - 1 ))
            return 0 ;;
        ']')
            local _max=$(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
            (( _SHQL_TAB_ACTIVE < _max )) && _shql_tab_activate $(( _SHQL_TAB_ACTIVE + 1 ))
            return 0 ;;
    esac

    case "$_type" in
        data)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            # ↑ at row 0 → tabbar
            if [[ "$_key" == "$_k_up" ]]; then
                local _cursor=0
                shellframe_sel_cursor "${_ctx}_grid" _cursor 2>/dev/null || true
                if (( _cursor == 0 )); then
                    shellframe_shell_focus_set "tabbar"
                    return 0
                fi
            fi
            # ← at col 0 → sidebar
            if [[ "$_key" == "$_k_left" ]]; then
                local _scroll_left=0
                shellframe_scroll_left "${_ctx}_grid" _scroll_left 2>/dev/null || true
                if (( _scroll_left == 0 )); then
                    shellframe_shell_focus_set "sidebar"
                    return 0
                fi
            fi
            SHELLFRAME_GRID_CTX="${_ctx}_grid"
            shellframe_grid_on_key "$_key"
            return $?
            ;;
        schema)
            _shql_schema_tab_on_key "$_key"
            return $?
            ;;
        query)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            _shql_query_on_key_ctx "$_ctx" "$_key"
            return $?
            ;;
    esac
    return 1
}

_shql_TABLE_content_on_focus() {
    _SHQL_BROWSER_CONTENT_FOCUSED="${1:-0}"
    SHELLFRAME_GRID_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
}

_shql_TABLE_content_action() {
    local _type
    _shql_content_type _type
    if [[ "$_type" == "data" ]]; then
        local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
        SHELLFRAME_GRID_CTX="${_ctx}_grid"
        _shql_inspector_open
    fi
}

_shql_schema_tab_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_tab=$'\t'
    local _k_shift_tab=$'\033[Z'
    (( _SHQL_TAB_ACTIVE < 0 )) && return 1
    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"

    case "$_key" in
        "$_k_up")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]]; then
                shellframe_scroll_move "${_ctx}_cols" up
            else
                shellframe_scroll_move "${_ctx}_ddl" up
            fi
            return 0 ;;
        "$_k_down")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]]; then
                shellframe_scroll_move "${_ctx}_cols" down
            else
                shellframe_scroll_move "${_ctx}_ddl" down
            fi
            return 0 ;;
        "$_k_tab")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]]; then
                _SHQL_BROWSER_CONTENT_FOCUS="schema_ddl"
            else
                _SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
                shellframe_shell_focus_set "sidebar"   # Tab from DDL exits
            fi
            return 0 ;;
        "$_k_shift_tab")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_ddl" ]]; then
                _SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
            else
                shellframe_shell_focus_set "tabbar"
            fi
            return 0 ;;
    esac
    return 1
}

_shql_query_on_key_ctx() {
    local _ctx="$1" _key="$2"
    _SHQL_QUERY_EDITOR_CTX="${_ctx}_editor"
    _SHQL_QUERY_GRID_CTX="${_ctx}_results"
    local _fp="_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"
    local _ea="_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}"
    local _hr="_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"
    local _st="_SHQL_QUERY_CTX_STATUS_${_ctx}"
    local _er="_SHQL_QUERY_CTX_ERROR_${_ctx}"
    local _ls="_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"
    _SHQL_QUERY_FOCUSED_PANE="${!_fp:-editor}"
    _SHQL_QUERY_EDITOR_ACTIVE="${!_ea:-0}"
    _SHQL_QUERY_HAS_RESULTS="${!_hr:-0}"
    _SHQL_QUERY_STATUS="${!_st:-}"
    _SHQL_QUERY_ERROR="${!_er:-}"
    _SHQL_QUERY_LAST_SQL="${!_ls:-}"
    _shql_query_on_key "$_key"
    local _rc=$?
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "$_SHQL_QUERY_FOCUSED_PANE"
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_EDITOR_ACTIVE"
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' "$_SHQL_QUERY_HAS_RESULTS"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' "$_SHQL_QUERY_STATUS"
    printf -v "_SHQL_QUERY_CTX_ERROR_${_ctx}"          '%s' "$_SHQL_QUERY_ERROR"
    printf -v "_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"       '%s' "$_SHQL_QUERY_LAST_SQL"
    return $_rc
}

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

# ── _shql_browser_footer_hint ─────────────────────────────────────────────────
#
# Compute the correct footer hint string for the current browser focus state
# and write it into the named out-var.

_shql_browser_footer_hint() {
    local _out_var="$1"
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_INSPECTOR"
    elif (( _SHQL_BROWSER_SIDEBAR_FOCUSED )); then
        printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_SIDEBAR"
    elif (( _SHQL_BROWSER_TABBAR_FOCUSED )); then
        printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_TABBAR"
    else
        local _type; _shql_content_type _type
        case "$_type" in
            data)    printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_DATA" ;;
            schema)  printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_SCHEMA" ;;
            query)   _shql_query_footer_hint "$_out_var" ;;
            *)       printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_EMPTY" ;;
        esac
    fi
}

# ── _shql_TABLE_footer_render ─────────────────────────────────────────────────

_shql_TABLE_footer_render() {
    local _top="$1" _left="$2"
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    local _hint; _shql_browser_footer_hint _hint
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" "$_gray" "$_hint" "$_rst" >/dev/tty
}

# ── _shql_TABLE_quit ──────────────────────────────────────────────────────────

_shql_TABLE_quit() {
    _SHELLFRAME_SHELL_NEXT="WELCOME"
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
