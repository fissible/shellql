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
_SHQL_TABS_LABEL=()   # display label: "users", "users·Schema", "Query 1"
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
_SHQL_BROWSER_QUERY_STATUS=""       # "Query returned N rows in Xms" (set by _shql_query_run)

# ── Quit-confirm overlay state ───────────────────────────────────────────────

_SHQL_QUIT_CONFIRM_ACTIVE=0    # 1 when "close database?" overlay is showing
_SHQL_DROP_CONFIRM_ACTIVE=0    # 1 when "drop table?" overlay is showing
_SHQL_DROP_CONFIRM_TABLE=""    # table/view name to drop
_SHQL_DROP_CONFIRM_TYPE="table" # "table" or "view"

# ── Context menu overlay state ──────────────────────────────────────────────

_SHQL_CMENU_ACTIVE=0           # 1 when a context menu is showing
_SHQL_CMENU_SOURCE=""          # "sidebar" | "tabbar" | "content"
_SHQL_CMENU_SOURCE_IDX=-1     # index of the clicked item (tab index, sidebar row, grid row)
_SHQL_CMENU_PREV_FOCUS=""     # region that had focus before the menu opened

# ── Sort overlay / header focus state ────────────────────────────────────────
# (sort state itself lives in _SHQL_SORT_<ctx> globals managed by sort.sh)

_SHQL_HEADER_FOCUSED=0      # 1 while keyboard is navigating column headers
_SHQL_HEADER_FOCUSED_COL=0  # absolute column index of the focused header

# ── Export overlay state ──────────────────────────────────────────────────────
# (export logic lives in src/screens/export.sh; flag declared here so table.sh
#  can reference it without a forward-declaration dependency.)
_SHQL_EXPORT_ACTIVE=0

# ── TTY for stderr passthrough ────────────────────────────────────────────────
# Use /dev/tty when available (interactive terminal); fall back to /dev/null in
# test environments where no controlling terminal exists.

if ( exec 9>/dev/tty ) 2>/dev/null; then
    _SHQL_STDERR_TTY=/dev/tty
else
    _SHQL_STDERR_TTY=/dev/null
fi

# ── Virtual scrolling ─────────────────────────────────────────────────────────
# Number of rows fetched per SQL query.  Small enough for fast initial load;
# large enough to cover many viewports before the next fetch is needed.
_SHQL_PAGE_SIZE=200

# ── Footer hint strings ────────────────────────────────────────────────────────

_SHQL_TABLE_FOOTER_HINTS_TABBAR="[←→] Switch tab  [Tab] Body  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_DATA="[↑↓] Navigate  [←→] Scroll  [Enter] Inspect  [Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_STRUCTURE="[↑↓] Scroll  [Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_INSPECTOR="[↑↓] Scroll  [PgUp/PgDn] Page  [Enter/Esc/q] Close"

# ── Browser footer hint strings ───────────────────────────────────────────────

_SHQL_BROWSER_FOOTER_HINTS_SIDEBAR="[↑↓] Navigate  [Enter] Data  [s] Schema  [c] New Table  [n] Query  [T] Truncate  [X] Drop  [→/Tab] Focus  [q] Back"
_SHQL_BROWSER_FOOTER_HINTS_TABBAR="[←→] Switch tab  [↓/Enter] Content  [w] Close  [n] New query  [Tab] Sidebar"
_SHQL_BROWSER_FOOTER_HINTS_DATA="[↑↓] Navigate  [←→] Scroll  [Enter] Inspect  [r] Refresh  [f] Filter  [x] Export  [[/]] Tabs  [Tab] Sidebar  [q] Back"
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
    while IFS=$'\x1f' read -r -a _row; do
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
        _label="${_table}"
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
    _SHQL_HEADER_FOCUSED=0
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

    # Query tabs use a deferred direct-draw for editor content that bypasses
    # _SF_FRAME_PREV. When the tab closes, the framebuffer diff sees no change
    # (content_bg+space == content_bg+space) and never re-emits those cells,
    # leaving the editor text as a ghost on the terminal. Reset PREV so the
    # next flush does a full re-emit and clears any deferred-draw residue.
    if [[ "${_SHQL_TABS_TYPE[$_idx]:-}" == "query" ]]; then
        shellframe_screen_clear
    fi

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

# ── _shql_tabs_close_by_table ─────────────────────────────────────────────────
# Close all open tabs whose table name matches. Iterates in reverse to keep
# indices stable as tabs are removed.
_shql_tabs_close_by_table() {
    local _table="$1"
    local _i
    for (( _i=${#_SHQL_TABS_TABLE[@]}-1; _i>=0; _i-- )); do
        [[ "${_SHQL_TABS_TABLE[$_i]}" == "$_table" ]] && _shql_tab_close "$_i"
    done
}

# ── _shql_browser_reload_sidebar ──────────────────────────────────────────────
# Reload the object list from the database and reinitialise the list widget.
_shql_browser_reload_sidebar() {
    _SHQL_BROWSER_TABLES=()
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
    _SHQL_BROWSER_SIDEBAR_ITEMS+=("+ New table")

    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
    shellframe_list_init "$_SHQL_BROWSER_SIDEBAR_CTX"
    _SHQL_BROWSER_GRID_OWNER_CTX=""  # force data grid reload for any open tabs
}

# ── _shql_tab_fits ────────────────────────────────────────────────────────────
# _shql_tab_fits <available_cols> <out_var>
# Sets out_var to 1 if all current tabs fit in available_cols, else 0.
# Accounts for: label + 2 padding chars per tab, 1 separator between tabs,
# plus 5 chars for the "+SQL" affordance at the right end.
_shql_tab_fits() {
    local _avail="$1" _out_var="$2"
    local _n=${#_SHQL_TABS_LABEL[@]}
    local _used=7   # 1 gap + " +SQL " = 7 chars
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        local _llen=${#_SHQL_TABS_LABEL[$_i]}
        _used=$(( _used + _llen + 4 ))  # " label " (llen+2) + "x " (2) = llen+4
        (( _i > 0 )) && (( _used++ ))   # 1-char separator between tabs
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
    _shql_ac_rebuild 2>/dev/null || true
    shql_table_init_browser
    _SHQL_BROWSER_TABLES=()
    _SHQL_BROWSER_SIDEBAR_FOCUSED=1
    _SHQL_BROWSER_TABBAR_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUS="data"
    _SHQL_CMENU_ACTIVE=0
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
    # Append "+ New table" action item at end of sidebar list
    _SHQL_BROWSER_SIDEBAR_ITEMS+=("+ New table")

    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
    shellframe_list_init "$_SHQL_BROWSER_SIDEBAR_CTX"

    # Empty database: auto-open a query tab so the user lands somewhere useful
    if (( ${#_SHQL_BROWSER_TABLES[@]} == 0 )); then
        _shql_tab_open "" "query"
        _SHQL_BROWSER_TABBAR_FOCUSED=0
        _SHQL_BROWSER_CONTENT_FOCUSED=1
        _SHQL_BROWSER_SIDEBAR_FOCUSED=0
        shellframe_shell_focus_set "content"
    else
        shellframe_shell_focus_set "sidebar"
    fi
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
            shellframe_fb_fill "$(( _top + _sr ))" "$_left" "$_width" " " "$SHQL_THEME_SIDEBAR_BG"
        done
    fi

    SHELLFRAME_LIST_BG="${SHQL_THEME_SIDEBAR_BG:-}"

    if [[ "${SHQL_THEME_SIDEBAR_BORDER:-}" == "none" ]]; then
        # No panel border — use list title slot for the "Relations" header
        SHELLFRAME_LIST_TITLE="Relations"
        SHELLFRAME_LIST_TITLE_STYLE="${SHQL_THEME_SIDEBAR_BG:-}${SHELLFRAME_GRAY:-}"
        SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
        SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
        SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        # Reserve rightmost column for scrollbar
        shellframe_list_render "$_top" "$_left" "$(( _width - 1 ))" "$_height"
        SHELLFRAME_LIST_TITLE=""
        # Scrollbar in rightmost column (skip title row)
        local _sb_col=$(( _left + _width - 1 ))
        local _sb_top=$(( _top + 1 ))
        local _sb_h=$(( _height - 1 ))
        SHELLFRAME_SCROLLBAR_STYLE="${SHQL_THEME_SIDEBAR_BG:-}${SHELLFRAME_GRAY:-$'\033[2m'}"
        SHELLFRAME_SCROLLBAR_THUMB_STYLE="${SHQL_THEME_SIDEBAR_BG:-}"
        if ! shellframe_scrollbar_render "$_SHQL_BROWSER_SIDEBAR_CTX" \
                "$_sb_col" "$_sb_top" "$_sb_h"; then
            # Content fits — fill the column with sidebar bg
            local _sb_r
            for (( _sb_r=0; _sb_r<_sb_h; _sb_r++ )); do
                shellframe_fb_put "$(( _sb_top + _sb_r ))" "$_sb_col" "${SHQL_THEME_SIDEBAR_BG:-} "
            done
        fi
    else
        SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
        SHELLFRAME_PANEL_TITLE="Relations"
        SHELLFRAME_PANEL_TITLE_ALIGN="left"
        SHELLFRAME_PANEL_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

        local _it _il _iw _ih
        shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

        SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
        SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
        SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        # Reserve rightmost inner column for scrollbar
        shellframe_list_render "$_it" "$_il" "$(( _iw - 1 ))" "$_ih"
        local _sb_col=$(( _il + _iw - 1 ))
        SHELLFRAME_SCROLLBAR_STYLE="${SHELLFRAME_GRAY:-$'\033[2m'}"
        SHELLFRAME_SCROLLBAR_THUMB_STYLE=""
        shellframe_scrollbar_render "$_SHQL_BROWSER_SIDEBAR_CTX" \
            "$_sb_col" "$_it" "$_ih" || true
    fi
}

# ── _shql_TABLE_sidebar_on_key ────────────────────────────────────────────────

_shql_TABLE_sidebar_on_key() {
    local _key="$1"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

    case "$_key" in
        "$_k_right") shellframe_shell_focus_set "tabbar"; shellframe_shell_mark_dirty; return 0 ;;
        $'\033'|q) _shql_quit_confirm "WELCOME"; return 0 ;;
        $'\r'|$'\n') _shql_TABLE_sidebar_action; shellframe_shell_mark_dirty; return 0 ;;
        s)           _shql_TABLE_sidebar_action_schema; shellframe_shell_mark_dirty; return 0 ;;
        c)           _shql_TABLE_sidebar_action_create_table; shellframe_shell_mark_dirty; return 0 ;;
        n)
            local _fits=1
            local _rows _cols; _shellframe_shell_terminal_size _rows _cols
            local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
            _shql_tab_fits $(( _cols - _sidebar_w )) _fits
            if (( _fits )); then
                _shql_tab_open "" "query"
                shellframe_shell_focus_set "content"
            fi
            shellframe_shell_mark_dirty
            return 0 ;;
        T)
            local _cursor=0
            shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
            if (( _cursor < ${#_SHQL_BROWSER_TABLES[@]} )); then
                local _ttype="${_SHQL_BROWSER_OBJECT_TYPES[$_cursor]:-table}"
                if [[ "$_ttype" == "table" ]]; then
                    local _tname="${_SHQL_BROWSER_TABLES[$_cursor]}"
                    _shql_dml_truncate_open "$_tname"
                    shellframe_shell_mark_dirty
                fi
            fi
            return 0 ;;
        X)
            local _cursor=0
            shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
            if (( _cursor < ${#_SHQL_BROWSER_TABLES[@]} )); then
                local _tname="${_SHQL_BROWSER_TABLES[$_cursor]}"
                local _ttype="${_SHQL_BROWSER_OBJECT_TYPES[$_cursor]:-table}"
                _shql_drop_confirm "$_tname" "$_ttype"
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

# ── _shql_TABLE_sidebar_on_mouse ─────────────────────────────────────────────

_shql_TABLE_sidebar_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5" _rleft="$6" _rwidth="$7" _rheight="$8"
    [[ "$_action" != "press" ]] && return 1

    # Right-click or Shift+click → context menu
    if (( _button == 2 || (_button == 0 && ${SHELLFRAME_MOUSE_SHIFT:-0}) )); then
        # Determine which sidebar item was right-clicked
        local _items_top=$(( _rtop + 1 ))  # +1 for "Relations" title row
        local _scroll_top=0
        shellframe_scroll_top "$_SHQL_BROWSER_SIDEBAR_CTX" _scroll_top 2>/dev/null || true
        local _item_idx=$(( _scroll_top + _mrow - _items_top ))
        local _n=${#_SHQL_BROWSER_SIDEBAR_ITEMS[@]}
        if (( _item_idx >= 0 && _item_idx < _n && _item_idx < ${#_SHQL_BROWSER_TABLES[@]} )); then
            shellframe_sel_set "$_SHQL_BROWSER_SIDEBAR_CTX" "$_item_idx"
            local _obj_type="${_SHQL_BROWSER_OBJECT_TYPES[$_item_idx]:-table}"
            local _items=("Open Data       (Enter)" "Open Schema         (s)" "New Query           (n)" "────────────────────" "New Table           (c)")
            if [[ "$_obj_type" == "table" ]]; then
                _items+=("Truncate Table      (T)" "Drop Table          (X)")
            else
                _items+=("Drop View           (X)")
            fi
            _shql_cmenu_open "sidebar" "$_item_idx" "$_mrow" "$_mcol" "${_items[@]}"
        fi
        return 0
    fi

    # Remember current cursor before delegating so we can detect re-click
    local _prev_cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _prev_cursor 2>/dev/null || true

    # Set title so list_on_mouse knows to offset for the header row
    SHELLFRAME_LIST_TITLE="Relations"
    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
    shellframe_list_on_mouse "$_button" "$_action" "$_mrow" "$_mcol" \
        "$_rtop" "$_rleft" "$_rwidth" "$_rheight"
    local _rc=$?
    SHELLFRAME_LIST_TITLE=""

    # If the click landed on the already-selected row, execute default action
    if (( _rc == 0 && _button <= 2 )); then
        local _new_cursor=0
        shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _new_cursor 2>/dev/null || true
        if (( _new_cursor == _prev_cursor )); then
            _shql_TABLE_sidebar_action
        fi
    fi
    return $_rc
}

# ── _shql_TABLE_sidebar_action / sidebar_action_schema ────────────────────────

_shql_TABLE_sidebar_action() {
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true

    # "+ New table" button (last sidebar item, beyond _SHQL_BROWSER_TABLES)
    local _ntables=${#_SHQL_BROWSER_TABLES[@]}
    if (( _cursor >= _ntables )); then
        _shql_TABLE_sidebar_action_create_table
        return 0
    fi

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
        _SHQL_BROWSER_FLASH_MSG="Tab bar full — close a tab first (w)"
        return 0
    fi
    _shql_tab_open "$_table" "data"
    shellframe_shell_focus_set "content"
}

_shql_TABLE_sidebar_action_schema() {
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
    # Skip for "+ New table" button
    (( _cursor >= ${#_SHQL_BROWSER_TABLES[@]} )) && return 0
    local _table="${_SHQL_BROWSER_TABLES[$_cursor]:-}"
    [[ -z "$_table" ]] && return 0
    _shql_tab_open "$_table" "schema"
    shellframe_shell_focus_set "content"
}

_shql_TABLE_sidebar_action_create_table() {
    local _rows _cols; _shellframe_shell_terminal_size _rows _cols
    local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
    local _fits=1; _shql_tab_fits $(( _cols - _sidebar_w )) _fits
    (( _fits )) || return 0

    _shql_tab_open "" "query"
    local _new_ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"

    # Override label to make tab purpose obvious
    _SHQL_TABS_LABEL[$_SHQL_TAB_ACTIVE]="New Table"

    # Store template for the lazy-init path in _shql_query_render to apply
    # after shellframe_editor_init (which overwrites any pre-set content).
    printf -v "_SHQL_QUERY_CTX_PREFILL_${_new_ctx}" '%s' \
        "$(printf '%s\n' \
            'CREATE TABLE table_name (' \
            '    id INTEGER PRIMARY KEY AUTOINCREMENT,' \
            '    name TEXT NOT NULL,' \
            '    -- add columns here' \
            ');')"

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
    local _right_left=$(( _sidebar_w + 1 ))
    local _right_w=$(( _cols - _sidebar_w ))

    local _header_top=1
    local _body_top=2
    local _footer_top=$(( _rows - 1 ))  # 2 rows for footer (status + hints)
    local _body_h=$(( _footer_top - _body_top ))
    (( _body_h < 2 )) && _body_h=2
    local _content_top=$(( _body_top + 2 ))
    local _content_h=$(( _footer_top - _content_top ))
    (( _content_h < 1 )) && _content_h=1

    # Content is only focusable when a tab is open
    local _content_focus="nofocus"
    (( _SHQL_TAB_ACTIVE >= 0 )) && _content_focus="focus"

    shellframe_shell_region header   1              1              "$_cols"      1             nofocus
    shellframe_shell_region sidebar  "$_body_top"   1              "$_sidebar_w" "$_body_h"    focus
    shellframe_shell_region tabbar   "$_body_top"   "$_right_left" "$_right_w"  2             focus
    shellframe_shell_region content  "$_content_top" "$_right_left" "$_right_w" "$_content_h" "$_content_focus"
    shellframe_shell_region footer   "$_footer_top" 1              "$_cols"      2             nofocus

    # Context menu overlay — registered last so it wins hit-testing
    if (( _SHQL_CMENU_ACTIVE )); then
        shellframe_shell_region cmenu 1 1 "$_cols" "$_rows" focus
    fi

    # Quit-confirm overlay — registered after cmenu so it wins over everything
    if (( _SHQL_QUIT_CONFIRM_ACTIVE )); then
        shellframe_shell_region quitconfirm 1 1 "$_cols" "$_rows" focus
    fi

    # Drop-confirm overlay — wins over everything else
    if (( _SHQL_DROP_CONFIRM_ACTIVE )); then
        shellframe_shell_region dropconfirm 1 1 "$_cols" "$_rows" focus
    fi
}

# ── _shql_TABLE_header_render ─────────────────────────────────────────────────

_shql_TABLE_header_render() {
    _shql_header_render "$1" "$2" "$3" "ShellQL"
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
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "${SHQL_THEME_CONTENT_BG:-}"

    local _n=${#_SHQL_TABS_LABEL[@]}
    local _col=$_left
    local _remaining=$_width
    # Track active tab pixel range for the content border gap
    _SHQL_TABBAR_ACTIVE_X0=-1
    _SHQL_TABBAR_ACTIVE_X1=-1

    # Reserve space for +SQL button (7 = 1 gap + " +SQL " 6 chars)
    local _sql_reserve=7
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        (( _remaining <= _sql_reserve )) && break
        if (( _i > 0 )); then
            shellframe_fb_fill "$_top" "$_col" 1 " " "${SHQL_THEME_CONTENT_BG:-}"
            (( _col++ ))
            (( _remaining-- ))
        fi
        local _label=" ${_SHQL_TABS_LABEL[$_i]} "
        local _tab_w=$(( ${#_label} + 2 ))   # +2 for "x "
        # Clip if tab doesn't fit (leave room for +SQL)
        if (( _tab_w > _remaining - _sql_reserve )); then
            local _avail=$(( _remaining - _sql_reserve ))
            if (( _avail >= 5 )); then
                # Truncate label with ellipsis, keep "x "
                local _lclip=$(( _avail - 4 ))  # " " + label + " " + "x " = 4 overhead
                local _clipped
                shellframe_str_clip_ellipsis "${_SHQL_TABS_LABEL[$_i]}" "${_SHQL_TABS_LABEL[$_i]}" "$_lclip" _clipped
                _label=" ${_clipped} "
                _tab_w=$(( ${#_label} + 2 ))
            else
                break   # Not enough room even for a clipped tab
            fi
        fi
        if (( _i == _SHQL_TAB_ACTIVE )); then
            _SHQL_TABBAR_ACTIVE_X0=$_col
            _SHQL_TABBAR_ACTIVE_X1=$(( _col + _tab_w ))
            local _tab_bg="${SHQL_THEME_CONTENT_BG:-}"
            local _tab_color="${SHQL_THEME_TAB_ACTIVE_COLOR:-$_bold}"
            if (( _SHQL_BROWSER_TABBAR_FOCUSED && ! _SHQL_BROWSER_TABBAR_ON_SQL )); then
                _tab_color="${SHQL_THEME_QUERY_PANEL_COLOR:-$_bold}"
            fi
            shellframe_fb_print "$_top" "$_col" "$_label" "${_tab_bg}${_tab_color}"
            shellframe_fb_print "$_top" "$(( _col + ${#_label} ))" "x " "${_tab_bg}${_gray}"
        else
            local _itab_style="${SHQL_THEME_TAB_INACTIVE_BG:-${SHQL_THEME_TABBAR_BG:-$_inv}}"
            shellframe_fb_print "$_top" "$_col" "$_label" "$_itab_style"
            shellframe_fb_print "$_top" "$(( _col + ${#_label} ))" "x " "${_itab_style}${_gray}"
        fi
        (( _col += _tab_w ))
        (( _remaining -= _tab_w ))
    done
    # +SQL button — styled like inactive tabs
    if (( _remaining >= _sql_reserve )); then
        shellframe_fb_fill "$_top" "$_col" 1 " " "${SHQL_THEME_CONTENT_BG:-}"
        (( _col += 1 ))
        (( _remaining -= 1 ))
        local _sql_label=" +SQL "
        local _itab_style="${SHQL_THEME_TAB_INACTIVE_BG:-${SHQL_THEME_TABBAR_BG:-$_inv}}"
        local _sql_focus_color=""
        if (( _SHQL_BROWSER_TABBAR_ON_SQL )); then
            _sql_focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-$_bold}"
        fi
        shellframe_fb_print "$_top" "$_col" "$_sql_label" "${_itab_style}${_sql_focus_color}"
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
            shellframe_shell_mark_dirty
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
            shellframe_shell_mark_dirty
            return 0 ;;
        "$_k_down")
            _SHQL_BROWSER_TABBAR_ON_SQL=0
            shellframe_shell_focus_set "content"
            shellframe_shell_mark_dirty
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
            shellframe_shell_mark_dirty
            return 0 ;;
        w)
            _shql_tab_close
            shellframe_shell_mark_dirty
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
            shellframe_shell_mark_dirty
            return 0 ;;
        $'\033')
            shellframe_shell_focus_set "sidebar"
            shellframe_shell_mark_dirty
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

# ── _shql_TABLE_tabbar_on_mouse ──────────────────────────────────────────────

_shql_TABLE_tabbar_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5" _rleft="$6" _rwidth="$7" _rheight="$8"
    [[ "$_action" != "press" ]] && return 1

    # Gap row (row below tab bar) — button clicks
    if (( _mrow == _rtop + 1 )); then
        local _gap_tab_active="${_SHQL_TAB_ACTIVE:-0}"
        local _gap_type="${_SHQL_TABS_TYPE[$_gap_tab_active]:-}"
        local _gap_table="${_SHQL_TABS_TABLE[$_gap_tab_active]:-}"
        if [[ "$_gap_type" == "data" && -n "$_gap_table" ]]; then
            # "New Row" button (left-aligned)
            local _nr_label=" New Row "
            if (( _mcol >= _rleft && _mcol < _rleft + ${#_nr_label} )); then
                _shql_dml_insert_open "$_gap_table"
                shellframe_shell_focus_set "content"
                shellframe_shell_mark_dirty
                return 0
            fi
            local _gap_ctx="${_SHQL_TABS_CTX[$_gap_tab_active]:-}"
            # "+ Filter" button (right-aligned) → always opens a new filter form
            local _filter_label=" + Filter "
            local _filter_right=$(( _rleft + _rwidth ))
            local _filter_left=$(( _filter_right - ${#_filter_label} ))
            if (( _mcol >= _filter_left && _mcol < _filter_right )); then
                if (( ! ${_SHQL_WHERE_ACTIVE:-0} )); then
                    _shql_where_open "$_gap_table" "$_gap_ctx" -1
                fi
                shellframe_shell_focus_set "content"
                shellframe_shell_mark_dirty
                return 0
            fi
            # Filter pills area (between New Row and + Filter)
            local _nr_label=" New Row "
            local _pills_area_left=$(( _rleft + ${#_nr_label} ))
            local _pills_area_right=$(( _filter_left ))
            if (( _mcol >= _pills_area_left && _mcol < _pills_area_right )); then
                _shql_where_pills_layout "$_gap_ctx" "$_pills_area_left" "$_pills_area_right"
                # [<] scroll-left — reveal older pills (increment scroll)
                if (( _SHQL_PILL_LAYOUT_HAS_PREV && \
                      _mcol >= _SHQL_PILL_LAYOUT_PREV_COL && \
                      _mcol < _SHQL_PILL_LAYOUT_PREV_COL + 3 )); then
                    local _sv="_SHQL_WHERE_PILL_SCROLL_${_gap_ctx}"
                    local _sv_val=$(( ${!_sv:-0} + 1 ))
                    printf -v "$_sv" '%d' "$_sv_val"
                    shellframe_shell_mark_dirty
                    return 0
                fi
                # [>] scroll-right — reveal newer pills (decrement scroll)
                if (( _SHQL_PILL_LAYOUT_HAS_NEXT && \
                      _mcol >= _SHQL_PILL_LAYOUT_NEXT_COL && \
                      _mcol < _SHQL_PILL_LAYOUT_NEXT_COL + 3 )); then
                    local _sv="_SHQL_WHERE_PILL_SCROLL_${_gap_ctx}"
                    local _sv_val=$(( ${!_sv:-0} - 1 ))
                    (( _sv_val < 0 )) && _sv_val=0
                    printf -v "$_sv" '%d' "$_sv_val"
                    shellframe_shell_mark_dirty
                    return 0
                fi
                # Pill body / close clicks
                local _pj
                for (( _pj=0; _pj<_SHQL_PILL_LAYOUT_N; _pj++ )); do
                    local _pjidx_v="_SHQL_PILL_LAYOUT_IDX_${_pj}"
                    local _pjcol_v="_SHQL_PILL_LAYOUT_COL_${_pj}"
                    local _pjw_v="_SHQL_PILL_LAYOUT_W_${_pj}"
                    local _pjidx="${!_pjidx_v}" _pjcol="${!_pjcol_v}" _pjw="${!_pjw_v}"
                    if (( _mcol >= _pjcol && _mcol < _pjcol + _pjw )); then
                        if (( _mcol >= _pjcol + _pjw - 3 )); then
                            # Click on " x)" → remove this filter
                            _shql_where_clear_one "$_gap_ctx" "$_pjidx"
                        else
                            # Click on body → edit this filter
                            _shql_where_open "$_gap_table" "$_gap_ctx" "$_pjidx"
                            shellframe_shell_focus_set "content"
                        fi
                        shellframe_shell_mark_dirty
                        return 0
                    fi
                done
            fi
        fi
        return 1
    fi

    # Walk the tab labels to find which tab was clicked (mirrors render logic)
    local _n=${#_SHQL_TABS_LABEL[@]}
    local _col=$_rleft
    local _i _hit_tab=-1 _hit_close=0
    for (( _i=0; _i<_n; _i++ )); do
        if (( _i > 0 )); then (( _col++ )); fi   # separator
        local _label=" ${_SHQL_TABS_LABEL[$_i]} "
        local _lw=${#_label}
        local _close_x=$(( _col + _lw ))    # "x" is at _close_x, " " at _close_x+1
        if (( _mcol >= _col && _mcol < _col + _lw )); then
            _hit_tab="$_i"
            break
        elif (( _mcol == _close_x )); then
            # Click on the "x" close button
            _hit_tab="$_i"
            _hit_close=1
            break
        fi
        _col=$(( _col + _lw + 2 ))   # +2 for "x "
    done

    # Right-click or Shift+click on a tab → context menu
    if (( (_button == 2 || (_button == 0 && ${SHELLFRAME_MOUSE_SHIFT:-0})) && _hit_tab >= 0 )); then
        _shql_tab_activate "$_hit_tab"
        _shql_cmenu_open "tabbar" "$_hit_tab" "$_mrow" "$_mcol" \
            "Close Tab" "New Query"
        return 0
    fi

    (( _button > 2 )) && return 1

    # Close button click → close tab
    if (( _hit_close && _hit_tab >= 0 )); then
        _shql_tab_activate "$_hit_tab"
        _shql_tab_close
        shellframe_shell_mark_dirty
        return 0
    fi

    if (( _hit_tab >= 0 )); then
        _SHQL_BROWSER_TABBAR_ON_SQL=0
        _shql_tab_activate "$_hit_tab"
        shellframe_shell_mark_dirty
        return 0
    fi

    # Check +SQL button (1-char gap after last tab, then " +SQL ")
    # Recompute _col to the end of all tabs (the for loop may have broken early)
    _col=$_rleft
    for (( _i=0; _i<_n; _i++ )); do
        if (( _i > 0 )); then (( _col++ )); fi
        _col=$(( _col + ${#_SHQL_TABS_LABEL[$_i]} + 4 ))   # " label " + "x "
    done
    (( _col++ ))  # gap
    local _sql_label=" +SQL "
    local _sw=${#_sql_label}
    if (( _mcol >= _col && _mcol < _col + _sw )); then
        _SHQL_BROWSER_TABBAR_ON_SQL=0
        local _fits=1
        local _rows _cols; _shellframe_shell_terminal_size _rows _cols
        local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
        _shql_tab_fits $(( _cols - _sidebar_w )) _fits
        if (( _fits )); then
            _shql_tab_open "" "query"
            shellframe_shell_focus_set "content"
        fi
        shellframe_shell_mark_dirty
        return 0
    fi

    return 1
}

# ── _shql_table_structure_render / on_key ─────────────────────────────────────

_shql_table_structure_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    shellframe_scroll_resize "$_SHQL_TABLE_DDL_CTX" "$_height" 1
    local _scroll_top
    shellframe_scroll_top "$_SHQL_TABLE_DDL_CTX" _scroll_top
    local _n=${#_SHQL_TABLE_DDL_LINES[@]}
    local _dim_on=""
    if (( ! _SHQL_TABLE_BODY_FOCUSED )); then
        _dim_on="${SHELLFRAME_DIM:-}"
    fi
    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _row=$(( _top + _r ))
        local _idx=$(( _scroll_top + _r ))
        shellframe_fb_fill "$_row" "$_left" "$_width" " " "$_dim_on"
        [[ $_idx -ge $_n ]] && continue
        local _line="${_SHQL_TABLE_DDL_LINES[$_idx]}"
        local _clipped
        shellframe_str_clip_ellipsis "$_line" "$_line" "$_width" _clipped
        shellframe_fb_print "$_row" "$_left" "$_clipped" "$_dim_on"
    done
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

    local _scan_rows=$(( _nrows < 200 ? _nrows : 200 ))

    local -a _all_num _all_bool _any_val
    local _c
    for (( _c=0; _c<_ncols; _c++ )); do
        _all_num[$_c]=1
        _all_bool[$_c]=1
        _any_val[$_c]=0
    done

    local _r _cell
    for (( _r=0; _r<_scan_rows; _r++ )); do
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

    # Build WHERE clause from all applied filters for this tab (joined with AND).
    # Uses _shql_where_filter_{count,get} which write to named globals to avoid
    # printf -v scope issues with local variables.
    local _where_arg=""
    _shql_where_filter_count "$_ctx"
    if (( _SHQL_WHERE_RESULT_COUNT > 0 )); then
        local _wclauses="" _wi
        for (( _wi=0; _wi<_SHQL_WHERE_RESULT_COUNT; _wi++ )); do
            _shql_where_filter_get "$_ctx" "$_wi"
            local _wc_q="\"${_SHQL_WHERE_RESULT_COL//\"/\"\"}\""
            local _wclause
            case "$_SHQL_WHERE_RESULT_OP" in
                "IS NULL"|"IS NOT NULL")
                    _wclause="${_wc_q} ${_SHQL_WHERE_RESULT_OP}" ;;
                "IN"|"NOT IN")
                    local _in_list="" _in_item _in_items
                    IFS=',' read -ra _in_items <<< "$_SHQL_WHERE_RESULT_VAL"
                    for _in_item in "${_in_items[@]}"; do
                        _in_item="${_in_item#"${_in_item%%[! ]*}"}"
                        _in_item="${_in_item%"${_in_item##*[! ]}"}"
                        _in_list+="'${_in_item//\'/\'\'}', "
                    done
                    _in_list="${_in_list%, }"
                    _wclause="${_wc_q} ${_SHQL_WHERE_RESULT_OP} (${_in_list})" ;;
                "BETWEEN"|"NOT BETWEEN")
                    local _bv1 _bv2
                    IFS=$'\t' read -r _bv1 _bv2 <<< "$_SHQL_WHERE_RESULT_VAL"
                    _wclause="${_wc_q} ${_SHQL_WHERE_RESULT_OP} '${_bv1//\'/\'\'}' AND '${_bv2//\'/\'\'}'" ;;
                *)
                    _wclause="${_wc_q} ${_SHQL_WHERE_RESULT_OP} '${_SHQL_WHERE_RESULT_VAL//\'/\'\'}'" ;;
            esac
            if [[ -z "$_wclauses" ]]; then
                _wclauses="$_wclause"
            else
                _wclauses+=" AND ${_wclause}"
            fi
        done
        _where_arg="$_wclauses"
    fi

    # Build ORDER BY clause from active sort entries for this tab.
    local _order_arg=""
    _shql_sort_build_clause "$_ctx"
    _order_arg="$_SHQL_SORT_RESULT_CLAUSE"

    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_CTX="${_ctx}_grid"
    SHELLFRAME_GRID_PK_COLS=1

    local _maxcw="${SHQL_MAX_COL_WIDTH:-30}"
    # Scan column widths only for the first N data rows; the rest are stored but
    # not measured.  The visible viewport is at most ~50 rows, so 200 rows gives
    # comfortable coverage for initial scroll positions without an O(N) scan.
    local _width_scan_limit=200
    local _idx=0 _c _cell _cw _hw _cv
    local _row=()
    local _t0=$SECONDS
    while IFS=$'\x1f' read -r -a _row; do
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
            if (( _idx <= _width_scan_limit )); then
                for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                    _cell="${_row[$_c]:-}"
                    SHELLFRAME_GRID_DATA+=("$_cell")
                    _cv=$(( ${#_cell} + 2 ))
                    (( _cv > _maxcw )) && _cv=$_maxcw
                    (( _cv > SHELLFRAME_GRID_COL_WIDTHS[$_c] )) && \
                        SHELLFRAME_GRID_COL_WIDTHS[$_c]=$_cv
                done
            else
                # Fast path: pad row to SHELLFRAME_GRID_COLS and bulk-append
                local _r_c
                for (( _r_c = ${#_row[@]}; _r_c < SHELLFRAME_GRID_COLS; _r_c++ )); do
                    _row[$_r_c]=""
                done
                SHELLFRAME_GRID_DATA+=("${_row[@]:0:$SHELLFRAME_GRID_COLS}")
            fi
            (( SHELLFRAME_GRID_ROWS++ ))
        fi
        (( _idx++ ))
    done < <(shql_db_fetch "$SHQL_DB_PATH" "$_table" "$_SHQL_PAGE_SIZE" "0" "$_where_arg" "$_order_arg" 2>"$_SHQL_STDERR_TTY")

    _shql_detect_grid_align
    # Widen sorted columns by 2 to accommodate the ↑/↓ sort indicator without
    # overlapping the column name.  This runs after all data-driven widths are
    # final, and the cache is invalidated on every sort change so the widths
    # always reflect current sort state.
    _shql_sort_count "$_ctx"
    if (( _SHQL_SORT_RESULT_COUNT > 0 )); then
        local _sc
        for (( _sc=0; _sc<SHELLFRAME_GRID_COLS; _sc++ )); do
            _shql_sort_find "$_ctx" "${SHELLFRAME_GRID_HEADERS[$_sc]:-}"
            [[ -n "$_SHQL_SORT_RESULT_DIR" ]] && \
                SHELLFRAME_GRID_COL_WIDTHS[$_sc]=$(( ${SHELLFRAME_GRID_COL_WIDTHS[$_sc]} + 2 ))
        done
    fi
    # Preserve horizontal scroll position across reloads (e.g. sort toggle)
    local _prev_scroll_left=0
    shellframe_scroll_left "${_ctx}_grid" _prev_scroll_left 2>/dev/null || true
    shellframe_grid_init "${_ctx}_grid"
    # Restore cursor to the row that was being edited (after DML save)
    if [[ -n "${_SHQL_DML_GRID_CTX:-}" && "${_SHQL_DML_GRID_CTX:-}" == "${_ctx}_grid" \
            && "${_SHQL_DML_ROW_IDX:--1}" -ge 0 ]]; then
        shellframe_sel_set "${_ctx}_grid" "$_SHQL_DML_ROW_IDX"
        _SHQL_DML_ROW_IDX=-1
        _SHQL_DML_GRID_CTX=""
        # Re-open inspector with fresh grid data if edit was launched from there
        if (( ${_SHQL_DML_INSPECTOR_RESTORE:-0} )); then
            _shql_inspector_open
            _SHQL_DML_INSPECTOR_RESTORE=0
        fi
    fi
    (( _prev_scroll_left > 0 )) && \
        shellframe_scroll_move "${_ctx}_grid" right "$_prev_scroll_left" 2>/dev/null || true
    # Cache the WHERE/ORDER used for this load so export.sh can re-query with
    # the same predicates without duplicating the clause-building logic.
    printf -v "_SHQL_QUERY_WHERE_${_ctx}" '%s' "$_where_arg"
    printf -v "_SHQL_QUERY_ORDER_${_ctx}" '%s' "$_order_arg"

    local _elapsed_ms=$(( (SECONDS - _t0) * 1000 ))
    (( _elapsed_ms == 0 )) && _elapsed_ms=1
    _SHQL_BROWSER_QUERY_STATUS="${SHELLFRAME_GRID_ROWS} rows in ${_elapsed_ms}ms"

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
        shellframe_fb_fill "$(( _it + _r ))" "$_il" "$_iw" " "
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
        local _clipped; shellframe_str_clip_ellipsis "$_plain" "$_plain" "$_iw" _clipped
        shellframe_fb_print "$(( _it + _r ))" "$_il" "$_clipped"
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
        shellframe_fb_fill "$(( _it + _r ))" "$_il" "$_iw" " "
        (( _idx >= _n_ddl )) && continue
        local _line; eval "_line=\"\${${_arr_ddl}[$_idx]}\""
        local _clipped; shellframe_str_clip_ellipsis "$_line" "$_line" "$_iw" _clipped
        shellframe_fb_print "$(( _it + _r ))" "$_il" "$_clipped"
    done
}

# ── _shql_TABLE_content_render ────────────────────────────────────────────────

_shql_TABLE_content_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Fill content area + padding row above with theme background
    if [[ -n "${SHQL_THEME_CONTENT_BG:-}" ]]; then
        # Padding row (1 row above content top)
        shellframe_fb_fill "$(( _top - 1 ))" "$_left" "$_width" " " "$SHQL_THEME_CONTENT_BG"
        local _r
        for (( _r=0; _r<_height; _r++ )); do
            shellframe_fb_fill "$(( _top + _r ))" "$_left" "$_width" " " "$SHQL_THEME_CONTENT_BG"
        done
    fi

    local _type
    _shql_content_type _type

    case "$_type" in
        data)
            # Load data for this tab's table if not already loaded
            _shql_content_data_ensure
            # Gap row: "New Row" (left) | active-filter pill (centre) | "+ Filter" (right)
            local _inv="${SHELLFRAME_REVERSE:-}"
            local _itab_style="${SHQL_THEME_TAB_INACTIVE_BG:-${SHQL_THEME_TABBAR_BG:-$_inv}}"
            local _ctx_active="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]:-}"
            local _nr_label=" New Row "
            shellframe_fb_print "$(( _top - 1 ))" "$_left" "$_nr_label" "$_itab_style"
            local _filter_label=" + Filter "
            shellframe_fb_print "$(( _top - 1 ))" \
                "$(( _left + _width - ${#_filter_label} ))" \
                "$_filter_label" "$_itab_style"
            # Filter pills between the two buttons
            local _pill_focus="${SHQL_THEME_QUERY_PANEL_COLOR:-}"
            local _pills_left=$(( _left + ${#_nr_label} ))
            local _pills_right=$(( _left + _width - ${#_filter_label} ))
            _shql_where_pills_render "$_ctx_active" "$(( _top - 1 ))" \
                "$_pills_left" "$_pills_right" "$_itab_style" "$_pill_focus"
            if (( ${_SHQL_WHERE_ACTIVE:-0} )); then
                # Render full grid (unfocused) so the table is visible behind the overlay
                SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
                SHELLFRAME_GRID_FOCUSED=0
                SHELLFRAME_GRID_BG="${SHQL_THEME_CONTENT_BG:-}"
                SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
                SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
                SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
                SHELLFRAME_GRID_CURSOR_STYLE=""
                local _wgrid_w="$_width"
                if (( _width > 10 && _height > 3 )); then
                    _wgrid_w=$(( _width - 1 ))
                fi
                _shql_grid_fill_width "$_wgrid_w"
                shellframe_grid_render "$_top" "$_left" "$_wgrid_w" "$_height"
                _shql_grid_restore_last
                # Overlay the WHERE panel on top of the grid
                _shql_where_render "$_top" "$_left" "$_width" "$_height"
            elif (( ${_SHQL_DML_ACTIVE:-0} )); then
                # Popover pattern: frozen 3-row grid header + DML form below
                SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
                SHELLFRAME_GRID_FOCUSED=0
                SHELLFRAME_GRID_BG="${SHQL_THEME_CONTENT_BG:-}"
                SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
                SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
                SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
                SHELLFRAME_GRID_CURSOR_STYLE=""
                _shql_grid_fill_width "$_width"
                shellframe_grid_render "$_top" "$_left" "$_width" 3
                _shql_grid_restore_last
                local _dml_top=$(( _top + 3 ))
                local _dml_h=$(( _height - 3 ))
                (( _dml_h < 3 )) && _dml_h=3
                _shql_dml_render "$_dml_top" "$_left" "$_width" "$_dml_h"
            elif (( _SHQL_INSPECTOR_ACTIVE )); then
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
                # Suppress grid row highlight while keyboard is in header focus mode
                SHELLFRAME_GRID_FOCUSED=$(( _SHQL_BROWSER_CONTENT_FOCUSED && ! _SHQL_HEADER_FOCUSED ))
                SHELLFRAME_GRID_BG="${SHQL_THEME_CONTENT_BG:-}"
                SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
                SHELLFRAME_GRID_HEADER_STYLE="${SHQL_THEME_GRID_HEADER_COLOR:-}"
                SHELLFRAME_GRID_HEADER_BG="${SHQL_THEME_GRID_HEADER_BG:-}"
                if [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
                    SHELLFRAME_GRID_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
                else
                    SHELLFRAME_GRID_CURSOR_STYLE=""
                fi
                # Reserve 1 column for scrollbar when there's enough space
                local _grid_w="$_width"
                local _sb_col=0
                if (( _width > 10 && _height > 3 )); then
                    _grid_w=$(( _width - 1 ))
                    _sb_col=$(( _left + _grid_w ))
                fi

                _shql_grid_fill_width "$_grid_w"
                shellframe_grid_render "$_top" "$_left" "$_grid_w" "$_height"
                _shql_grid_restore_last
                # Sort indicators + header focus highlight (overlaid on header row)
                _shql_sort_overlay_headers "$_top" "$_left" "$_grid_w" "$_ctx_active"
                # Scrollbar in rightmost column (data rows start 2 below _top: headers + hint)
                if (( _sb_col > 0 )); then
                    local _sb_top=$(( _top + 2 ))
                    local _sb_h=$(( _height - 2 ))
                    SHELLFRAME_SCROLLBAR_STYLE="${SHQL_THEME_CONTENT_BG:-}${SHELLFRAME_GRAY:-$'\033[2m'}"
                    SHELLFRAME_SCROLLBAR_THUMB_STYLE="${SHQL_THEME_CONTENT_BG:-}"
                    if ! shellframe_scrollbar_render "${SHELLFRAME_GRID_CTX:-grid}" \
                            "$_sb_col" "$_sb_top" "$_sb_h"; then
                        local _sb_r
                        for (( _sb_r=0; _sb_r<_sb_h; _sb_r++ )); do
                            shellframe_fb_put "$(( _sb_top + _sb_r ))" "$_sb_col" "${SHQL_THEME_CONTENT_BG:-} "
                        done
                    fi
                    # Header rows in scrollbar column
                    shellframe_fb_put "$_top"           "$_sb_col" "${SHQL_THEME_GRID_HEADER_BG:-} "
                    shellframe_fb_put "$(( _top + 1 ))" "$_sb_col" "${SHQL_THEME_CONTENT_BG:-} "
                fi
                # Dark surface below last data row
                local _data_end=$(( _top + 2 + SHELLFRAME_GRID_ROWS ))
                local _surface_bg="${SHQL_THEME_EDITOR_FOCUSED_BG:-${SHQL_THEME_CONTENT_BG:-}}"
                if [[ -n "$_surface_bg" ]] && (( _data_end < _top + _height )); then
                    local _gray="${SHELLFRAME_GRAY:-}"
                    local _sr
                    for (( _sr=_data_end; _sr < _top + _height; _sr++ )); do
                        shellframe_fb_fill "$_sr" "$_left" "$_width" " " "$_surface_bg"
                    done
                    # DML key hints on the first row below data (hidden when table fills screen)
                    shellframe_fb_print "$_data_end" "$(( _left + 1 ))" \
                        "[i] Insert  [e] Edit  [d] Delete  [T] Truncate" "${_surface_bg}${_gray}"
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
            # Empty state — fill with content bg only; footer hint provides guidance.
            # (A center hint using multi-byte chars like ↑↓ ghosts when a tab opens
            #  because shellframe_fb_print maps bytes not glyphs, leaving stale cells.)
            local _cbg="${SHQL_THEME_CONTENT_BG:-}"
            local _r
            for (( _r=0; _r<_height; _r++ )); do
                shellframe_fb_fill "$(( _top + _r ))" "$_left" "$_width" " " "$_cbg"
            done
            ;;
    esac

    # Export overlay (below toast)
    if (( ${_SHQL_EXPORT_ACTIVE:-0} )); then
        _shql_export_render "$_top" "$_left" "$_width" "$_height"
    fi

    # Toast overlay (always topmost)
    shellframe_toast_render "$_top" "$_left" "$_width" "$_height"
}

_shql_TABLE_content_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_enter="${SHELLFRAME_KEY_ENTER:-$'\n'}"
    local _k_tab=$'\t'


    # Route to export overlay when active
    if (( ${_SHQL_EXPORT_ACTIVE:-0} )); then
        _shql_export_on_key "$_key"
        return $?
    fi

    # Route to WHERE filter overlay when active
    if (( ${_SHQL_WHERE_ACTIVE:-0} )); then
        _shql_where_on_key "$_key"
        return $?
    fi

    # Route to DML form when active (takes priority over inspector)
    if (( ${_SHQL_DML_ACTIVE:-0} )); then
        _shql_dml_on_key "$_key"
        return $?
    fi

    # Route to inspector when active
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        # [e] from inspector → close inspector and open edit form for that row
        if [[ "$_key" == 'e' ]]; then
            local _e_table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]:-}"
            if [[ -n "$_e_table" ]]; then
                _SHQL_INSPECTOR_ACTIVE=0
                _shql_dml_update_open "$_e_table" "$_SHQL_INSPECTOR_ROW_IDX"
                _SHQL_DML_CALLER="inspector"
                shellframe_shell_mark_dirty
                return 0
            fi
        fi
        _shql_inspector_on_key "$_key"
        return $?
    fi

    local _type
    _shql_content_type _type

    # Esc from content → move focus to tabbar (prevent global quit)
    # Exception: query tabs handle Esc internally (typing → button, button → tabbar)
    if [[ "$_key" == $'\033' && "$_type" != "query" ]]; then
        shellframe_shell_focus_set "tabbar"
        shellframe_shell_mark_dirty
        return 0
    fi

    # [ / ] switch tabs from content (D1: _shql_tab_activate resets inspector)
    case "$_key" in
        '[')
            (( _SHQL_TAB_ACTIVE > 0 )) && _shql_tab_activate $(( _SHQL_TAB_ACTIVE - 1 ))
            shellframe_shell_mark_dirty
            return 0 ;;
        ']')
            local _max=$(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
            (( _SHQL_TAB_ACTIVE < _max )) && _shql_tab_activate $(( _SHQL_TAB_ACTIVE + 1 ))
            shellframe_shell_mark_dirty
            return 0 ;;
    esac

    case "$_type" in
        data)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"

            # ── Header focus mode ─────────────────────────────────────────────
            # Entered via ↑ at grid row 0 or a header click.
            # ← / → move between columns and scroll the grid.
            # Enter toggles sort; ↑ exits to tabbar; ↓/Esc/Tab returns to grid.
            if (( _SHQL_HEADER_FOCUSED )); then
                case "$_key" in
                    "$_k_left")
                        if (( _SHQL_HEADER_FOCUSED_COL > 0 )); then
                            (( _SHQL_HEADER_FOCUSED_COL-- ))
                            local _sl=0
                            shellframe_scroll_left "${_ctx}_grid" _sl 2>/dev/null || true
                            if (( _SHQL_HEADER_FOCUSED_COL < _sl )); then
                                shellframe_scroll_move "${_ctx}_grid" left 1 2>/dev/null || true
                            fi
                        fi
                        shellframe_shell_mark_dirty
                        return 0 ;;
                    "$_k_right")
                        local _ncols="${SHELLFRAME_GRID_COLS:-0}"
                        if (( _SHQL_HEADER_FOCUSED_COL < _ncols - 1 )); then
                            (( _SHQL_HEADER_FOCUSED_COL++ ))
                            local _vis_end="${_SHQL_SORT_VISIBLE_END_COL:--1}"
                            if (( _SHQL_HEADER_FOCUSED_COL > _vis_end )); then
                                shellframe_scroll_move "${_ctx}_grid" right 1 2>/dev/null || true
                            fi
                        fi
                        shellframe_shell_mark_dirty
                        return 0 ;;
                    "$_k_up")
                        # ↑ in header mode → exit header focus and move to tabbar
                        _SHQL_HEADER_FOCUSED=0
                        shellframe_shell_focus_set "tabbar"
                        shellframe_shell_mark_dirty
                        return 0 ;;
                    "$_k_down"|"$_k_tab"|$'\033')
                        # ↓ / Tab / Esc → exit header focus, return to data grid
                        _SHQL_HEADER_FOCUSED=0
                        shellframe_shell_mark_dirty
                        return 0 ;;
                    "$_k_enter"|$'\r')
                        # Enter → toggle sort on focused column
                        local _hcol="${SHELLFRAME_GRID_HEADERS[$_SHQL_HEADER_FOCUSED_COL]:-}"
                        if [[ -n "$_hcol" ]]; then
                            _shql_sort_toggle "$_ctx" "$_hcol"
                            _SHQL_BROWSER_GRID_OWNER_CTX=""
                        fi
                        shellframe_shell_mark_dirty
                        return 0 ;;
                esac
                # Any other key exits header focus mode and falls through to data grid
                _SHQL_HEADER_FOCUSED=0
                shellframe_shell_mark_dirty
            fi

            # ↑ at grid row 0 → enter header focus mode (headers are "above" data)
            if [[ "$_key" == "$_k_up" ]]; then
                local _cursor=0
                shellframe_sel_cursor "${_ctx}_grid" _cursor 2>/dev/null || true
                if (( _cursor == 0 )); then
                    _SHQL_HEADER_FOCUSED=1
                    local _sl=0
                    shellframe_scroll_left "${_ctx}_grid" _sl 2>/dev/null || true
                    _SHQL_HEADER_FOCUSED_COL="$_sl"
                    shellframe_shell_mark_dirty
                    return 0
                fi
            fi
            # ← at col 0 → sidebar
            if [[ "$_key" == "$_k_left" ]]; then
                local _scroll_left=0
                shellframe_scroll_left "${_ctx}_grid" _scroll_left 2>/dev/null || true
                if (( _scroll_left == 0 )); then
                    shellframe_shell_focus_set "sidebar"
                    shellframe_shell_mark_dirty
                    return 0
                fi
            fi
            # q from data grid → tabbar (prevent falling through to global quit)
            if [[ "$_key" == 'q' ]]; then
                shellframe_shell_focus_set "tabbar"
                shellframe_shell_mark_dirty
                return 0
            fi
            # DML triggers
            local _dml_table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]:-}"
            if [[ "$_key" == 'i' && -n "$_dml_table" ]]; then
                _shql_dml_insert_open "$_dml_table"
                shellframe_shell_mark_dirty
                return 0
            fi
            if [[ "$_key" == 'e' && -n "$_dml_table" ]]; then
                if (( SHELLFRAME_GRID_ROWS > 0 )); then
                    local _cursor=0
                    shellframe_sel_cursor "${_ctx}_grid" _cursor 2>/dev/null || true
                    _shql_dml_update_open "$_dml_table" "$_cursor"
                    shellframe_shell_mark_dirty
                fi
                return 0
            fi
            if [[ "$_key" == 'd' && -n "$_dml_table" ]]; then
                if (( SHELLFRAME_GRID_ROWS > 0 )); then
                    local _cursor=0
                    shellframe_sel_cursor "${_ctx}_grid" _cursor 2>/dev/null || true
                    _shql_dml_delete_open "$_dml_table" "$_cursor"
                    shellframe_shell_mark_dirty
                fi
                return 0
            fi
            if [[ "$_key" == 'T' && -n "$_dml_table" ]]; then
                _shql_dml_truncate_open "$_dml_table"
                shellframe_shell_mark_dirty
                return 0
            fi
            if [[ "$_key" == 'f' && -n "$_dml_table" ]]; then
                _shql_where_open "$_dml_table" "$_ctx" -1
                shellframe_shell_mark_dirty
                return 0
            fi
            if [[ "$_key" == 'r' ]]; then
                _SHQL_BROWSER_GRID_OWNER_CTX=""
                shellframe_shell_mark_dirty
                return 0
            fi
            if [[ "$_key" == 'x' ]]; then
                _shql_export_open
                shellframe_shell_mark_dirty
                return 0
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
            if [[ "$_key" == 'x' ]]; then
                _shql_export_open
                shellframe_shell_mark_dirty
                return 0
            fi
            _shql_query_on_key_ctx "$_ctx" "$_key"
            return $?
            ;;
    esac
    return 1
}

_shql_TABLE_content_on_focus() {
    _SHQL_BROWSER_CONTENT_FOCUSED="${1:-0}"
    _SHQL_TABLE_BODY_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
    SHELLFRAME_GRID_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
    # Losing focus clears header focus mode
    if (( ! _SHQL_BROWSER_CONTENT_FOCUSED )); then
        _SHQL_HEADER_FOCUSED=0
    fi
    # Losing focus deactivates editor mode for any active query tab
    if (( ! _SHQL_BROWSER_CONTENT_FOCUSED && _SHQL_TAB_ACTIVE >= 0 )); then
        local _type; _shql_content_type _type
        if [[ "$_type" == "query" ]]; then
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' 0
        fi
    fi
}

# ── _shql_TABLE_content_on_mouse ─────────────────────────────────────────────

_shql_TABLE_content_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5" _rleft="$6" _rwidth="$7" _rheight="$8"
    (( _SHQL_TAB_ACTIVE < 0 )) && return 1

    # Click (press only) while inspector is active → dismiss it.
    # Ignore release events — a single physical click generates both press and
    # release; without this guard the release from the click that OPENED the
    # inspector would immediately dismiss it.
    if (( _SHQL_INSPECTOR_ACTIVE )) && [[ "$_action" == "press" ]]; then
        _SHQL_INSPECTOR_ACTIVE=0
        shellframe_shell_mark_dirty
        return 0
    fi
    # Swallow release events while inspector is still active (from the opening click)
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        return 0
    fi

    local _type
    _shql_content_type _type

    case "$_type" in
        data)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            SHELLFRAME_GRID_CTX="${_ctx}_grid"

            # Right-click or Shift+click on data grid → context menu
            if (( _button == 2 || (_button == 0 && ${SHELLFRAME_MOUSE_SHIFT:-0}) )); then
                # Move cursor to the clicked row before opening the menu
                shellframe_grid_on_mouse 0 "press" "$_mrow" "$_mcol" \
                    "$_rtop" "$_rleft" "$_rwidth" "$_rheight" 2>/dev/null || true
                local _click_cursor=0
                shellframe_sel_cursor "${_ctx}_grid" _click_cursor 2>/dev/null || true
                local _data_items=("Inspect Row   (Enter)" "Edit Row          (e)" "Delete Row        (d)" "────────────────────" "Insert Row        (i)" "Refresh           (r)" "Filter            (f)" "Export            (x)")
                _shql_cmenu_open "content" "$_click_cursor" "$_mrow" "$_mcol" "${_data_items[@]}"
                return 0
            fi

            # Click on header row → toggle sort for that column + enter header focus
            if (( _mrow == _rtop && _button == 0 )) && [[ "$_action" == "press" ]]; then
                _shql_sort_col_at_x "$_ctx" "$_mcol" "$_rleft" "$_rwidth"
                local _hit_col="$_SHQL_SORT_RESULT_IDX"
                if (( _hit_col >= 0 )); then
                    local _hcol="${SHELLFRAME_GRID_HEADERS[$_hit_col]:-}"
                    if [[ -n "$_hcol" ]]; then
                        _shql_sort_toggle "$_ctx" "$_hcol"
                        _SHQL_BROWSER_GRID_OWNER_CTX=""
                    fi
                    _SHQL_HEADER_FOCUSED=1
                    _SHQL_HEADER_FOCUSED_COL="$_hit_col"
                    shellframe_shell_mark_dirty
                fi
                return 0
            fi
            # Swallow release on header row (paired with the press above)
            if (( _mrow == _rtop )); then
                return 0
            fi

            # Click outside header → clear header focus
            if (( _SHQL_HEADER_FOCUSED )); then
                _SHQL_HEADER_FOCUSED=0
            fi

            # Remember cursor before click
            local _prev_cursor=0
            shellframe_sel_cursor "${_ctx}_grid" _prev_cursor 2>/dev/null || true

            shellframe_grid_on_mouse "$_button" "$_action" "$_mrow" "$_mcol" \
                "$_rtop" "$_rleft" "$_rwidth" "$_rheight"
            local _rc=$?

            # Click on already-selected data row → open inspector
            if (( _rc == 0 && _button <= 2 )); then
                local _new_cursor=0
                shellframe_sel_cursor "${_ctx}_grid" _new_cursor 2>/dev/null || true
                if (( _new_cursor == _prev_cursor )); then
                    _shql_inspector_open
                    shellframe_shell_mark_dirty
                fi
            fi
            return $_rc
            ;;
        query)
            # Query sub-panes: editor (30% top) and results (70% bottom)
            local _editor_rows=$(( _rheight * 30 / 100 ))
            (( _editor_rows < 5 )) && _editor_rows=5
            local _results_top=$(( _rtop + _editor_rows ))

            # Click (press) while detail panel is active → dismiss it
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            local _da_var="_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}"
            if [[ "${!_da_var:-0}" == "1" ]] && [[ "$_action" == "press" ]]; then
                printf -v "_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}" '%d' 0
                _SHQL_QUERY_DETAIL_ACTIVE=0
                shellframe_shell_mark_dirty
                return 0
            fi
            # Swallow release while detail still active
            if [[ "${!_da_var:-0}" == "1" ]]; then
                return 0
            fi

            # Right-click or Shift+click in results pane → context menu
            if (( (_button == 2 || (_button == 0 && ${SHELLFRAME_MOUSE_SHIFT:-0})) && _mrow >= _results_top )); then
                # Move cursor to clicked row (use panel inner bounds, same as left-click)
                local _rh=$(( _rheight - _editor_rows ))
                SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
                local _rit=0 _ril=0 _riw=0 _rih=0
                shellframe_panel_inner "$_results_top" "$_rleft" "$_rwidth" "$_rh" \
                    _rit _ril _riw _rih
                SHELLFRAME_GRID_CTX="${_ctx}_results"
                shellframe_grid_on_mouse 0 "press" "$_mrow" "$_mcol" \
                    "$_rit" "$_ril" "$_riw" "$_rih" 2>/dev/null || true
                _shql_cmenu_open "content" 0 "$_mrow" "$_mcol" \
                    "View Details  (Enter)" "────────────────────" "Re-run        (r)" "Export        (x)"
                return 0
            fi

            if (( _mrow < _results_top )); then
                # Click in editor pane
                local _fp_var="_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"
                local _ea_var="_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}"
                if [[ "${!_fp_var:-}" == "editor" ]] && [[ "$_action" == "press" ]]; then
                    # Already focused on editor — activate edit mode + position cursor
                    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' 1
                    # Compute editor inner bounds (same split as render)
                    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
                    local _eit=0 _eil=0 _eiw=0 _eih=0
                    shellframe_panel_inner "$_rtop" "$_rleft" "$_rwidth" "$_editor_rows" \
                        _eit _eil _eiw _eih
                    SHELLFRAME_EDITOR_CTX="${_ctx}_editor"
                    shellframe_editor_on_mouse "$_button" "$_action" "$_mrow" "$_mcol" \
                        "$_eit" "$_eil" "$_eiw" "$_eih"
                else
                    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}" '%s' "editor"
                fi
                shellframe_shell_mark_dirty
                return 0
            else
                # Click in results pane — deactivate editor mode, set focus to results
                printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' 0
                printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}" '%s' "results"
                SHELLFRAME_GRID_CTX="${_ctx}_results"

                # Remember cursor before click for re-click detection
                local _prev_cursor=0
                shellframe_sel_cursor "${_ctx}_results" _prev_cursor 2>/dev/null || true

                # Compute panel inner bounds (grid is rendered inside a framed panel)
                local _rh=$(( _rheight - _editor_rows ))
                SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
                local _rit=0 _ril=0 _riw=0 _rih=0
                shellframe_panel_inner "$_results_top" "$_rleft" "$_rwidth" "$_rh" \
                    _rit _ril _riw _rih
                shellframe_grid_on_mouse "$_button" "$_action" "$_mrow" "$_mcol" \
                    "$_rit" "$_ril" "$_riw" "$_rih"
                local _grc=$?

                # Re-click on same row → open detail panel
                if (( _grc == 0 && _button <= 2 )); then
                    local _new_cursor=0
                    shellframe_sel_cursor "${_ctx}_results" _new_cursor 2>/dev/null || true
                    if (( _new_cursor == _prev_cursor )); then
                        _SHQL_QUERY_GRID_CTX="${_ctx}_results"
                        _shql_query_detail_open
                        # Persist to per-ctx so the next render sees it
                        printf -v "_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}" '%d' 1
                    fi
                fi
                shellframe_shell_mark_dirty
                return 0
            fi
            ;;
        schema)
            # Schema sub-panes: columns (40% left) and DDL (60% right)
            local _cols_w=$(( _rwidth * 4 / 10 ))
            (( _cols_w < 15 )) && _cols_w=15
            local _ddl_left=$(( _rleft + _cols_w ))

            if (( _mcol < _ddl_left )); then
                _SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
            else
                _SHQL_BROWSER_CONTENT_FOCUS="schema_ddl"
            fi
            shellframe_shell_mark_dirty
            return 0
            ;;
    esac
    return 1
}

_shql_TABLE_content_action() {
    local _type
    _shql_content_type _type
    if [[ "$_type" == "data" ]]; then
        local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
        SHELLFRAME_GRID_CTX="${_ctx}_grid"
        _shql_inspector_open
        shellframe_shell_mark_dirty
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
            shellframe_shell_mark_dirty
            return 0 ;;
        "$_k_shift_tab")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_ddl" ]]; then
                _SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
            else
                shellframe_shell_focus_set "tabbar"
            fi
            shellframe_shell_mark_dirty
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
    local _da="_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}"
    _SHQL_QUERY_FOCUSED_PANE="${!_fp:-editor}"
    _SHQL_QUERY_EDITOR_ACTIVE="${!_ea:-0}"
    _SHQL_QUERY_HAS_RESULTS="${!_hr:-0}"
    _SHQL_QUERY_STATUS="${!_st:-}"
    _SHQL_QUERY_ERROR="${!_er:-}"
    _SHQL_QUERY_LAST_SQL="${!_ls:-}"
    _SHQL_QUERY_DETAIL_ACTIVE="${!_da:-0}"
    _shql_query_on_key "$_key"
    local _rc=$?
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "$_SHQL_QUERY_FOCUSED_PANE"
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_EDITOR_ACTIVE"
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' "$_SHQL_QUERY_HAS_RESULTS"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' "$_SHQL_QUERY_STATUS"
    printf -v "_SHQL_QUERY_CTX_ERROR_${_ctx}"          '%s' "$_SHQL_QUERY_ERROR"
    printf -v "_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"       '%s' "$_SHQL_QUERY_LAST_SQL"
    printf -v "_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_DETAIL_ACTIVE"
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
            data)
                if (( _SHQL_HEADER_FOCUSED )); then
                    printf -v "$_out_var" '%s' "[←→] Move  [Enter] Sort  [↑] Tabbar  [↓/Esc] Grid"
                else
                    printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_DATA"
                fi ;;
            schema)  printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_SCHEMA" ;;
            query)   _shql_query_footer_hint "$_out_var" ;;
            *)       printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_EMPTY" ;;
        esac
    fi
}

# ── Context menu helpers ─────────────────────────────────────────────────────

# Open a context menu at (anchor_row, anchor_col) with the given items.
# Sets _SHQL_CMENU_ACTIVE=1, saves source and previous focus.
_shql_cmenu_open() {
    local _source="$1" _idx="$2" _arow="$3" _acol="$4"
    shift 4
    # Remaining args are menu item labels
    SHELLFRAME_CMENU_ITEMS=("$@")
    SHELLFRAME_CMENU_ANCHOR_ROW="$_arow"
    SHELLFRAME_CMENU_ANCHOR_COL="$_acol"
    SHELLFRAME_CMENU_CTX="shql_cmenu"
    SHELLFRAME_CMENU_FOCUSED=1
    SHELLFRAME_CMENU_STYLE="single"
    SHELLFRAME_CMENU_BG=""
    SHELLFRAME_CMENU_RESULT=-1
    shellframe_cmenu_init "shql_cmenu"
    _SHQL_CMENU_ACTIVE=1
    _SHQL_CMENU_SOURCE="$_source"
    _SHQL_CMENU_SOURCE_IDX="$_idx"
    _SHQL_CMENU_PREV_FOCUS="$_source"
    shellframe_shell_focus_set "cmenu"
    shellframe_shell_mark_dirty
}

# Dismiss the context menu and restore previous focus.
_shql_cmenu_dismiss() {
    _SHQL_CMENU_ACTIVE=0
    shellframe_shell_focus_set "$_SHQL_CMENU_PREV_FOCUS"
    shellframe_shell_mark_dirty
}

# Dispatch the selected context menu action based on source and result index.
_shql_cmenu_dispatch() {
    local _result="$SHELLFRAME_CMENU_RESULT"
    local _source="$_SHQL_CMENU_SOURCE"
    local _idx="$_SHQL_CMENU_SOURCE_IDX"

    _shql_cmenu_dismiss

    # Dismissed without selection
    (( _result < 0 )) && return 0

    case "$_source" in
        sidebar)
            # 0=Open Data, 1=Open Schema, 2=New Query, 3=separator,
            # 4=New Table, 5=Truncate Table (table) or Drop View (view), 6=Drop Table (table only)
            case "$_result" in
                0) shellframe_sel_set "$_SHQL_BROWSER_SIDEBAR_CTX" "$_idx"
                   _shql_TABLE_sidebar_action ;;
                1) shellframe_sel_set "$_SHQL_BROWSER_SIDEBAR_CTX" "$_idx"
                   _shql_TABLE_sidebar_action_schema ;;
                2) local _fits=1
                   local _rows _cols; _shellframe_shell_terminal_size _rows _cols
                   local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
                   _shql_tab_fits $(( _cols - _sidebar_w )) _fits
                   if (( _fits )); then
                       _shql_tab_open "" "query"
                       shellframe_shell_focus_set "content"
                   fi ;;
                3) ;; # separator — no-op
                4) _shql_TABLE_sidebar_action_create_table ;;
                5) # Truncate (table) or Drop (view)
                   local _ttype="${_SHQL_BROWSER_OBJECT_TYPES[$_idx]:-table}"
                   if [[ "$_ttype" == "table" ]]; then
                       local _tname="${_SHQL_BROWSER_TABLES[$_idx]:-}"
                       [[ -n "$_tname" ]] && _shql_dml_truncate_open "$_tname"
                   else
                       local _tname="${_SHQL_BROWSER_TABLES[$_idx]:-}"
                       [[ -n "$_tname" ]] && _shql_drop_confirm "$_tname" "$_ttype"
                   fi ;;
                6) # Drop Table
                   local _tname="${_SHQL_BROWSER_TABLES[$_idx]:-}"
                   local _ttype="${_SHQL_BROWSER_OBJECT_TYPES[$_idx]:-table}"
                   [[ -n "$_tname" ]] && _shql_drop_confirm "$_tname" "$_ttype" ;;
            esac ;;
        tabbar)
            # 0=Close Tab, 1=New Query
            case "$_result" in
                0) _shql_tab_close ;;
                1) local _fits=1
                   local _rows _cols; _shellframe_shell_terminal_size _rows _cols
                   local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
                   _shql_tab_fits $(( _cols - _sidebar_w )) _fits
                   if (( _fits )); then
                       _shql_tab_open "" "query"
                       shellframe_shell_focus_set "content"
                   fi ;;
            esac ;;
        content)
            local _type; _shql_content_type _type
            case "$_type" in
                data)
                    # 0=Inspect, 1=Edit, 2=Delete, 3=sep, 4=Insert, 5=Refresh, 6=Filter, 7=Export
                    # _idx = grid row that was right-clicked (cursor was set before menu opened)
                    local _dml_table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]:-}"
                    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]:-}"
                    case "$_result" in
                        0) _shql_inspector_open ;;
                        1) if [[ -n "$_dml_table" ]] && (( SHELLFRAME_GRID_ROWS > 0 )); then
                               _shql_dml_update_open "$_dml_table" "$_idx"
                           fi ;;
                        2) if [[ -n "$_dml_table" ]] && (( SHELLFRAME_GRID_ROWS > 0 )); then
                               _shql_dml_delete_open "$_dml_table" "$_idx"
                           fi ;;
                        3) ;; # separator
                        4) [[ -n "$_dml_table" ]] && _shql_dml_insert_open "$_dml_table" ;;
                        5) _SHQL_BROWSER_GRID_OWNER_CTX=""  ;; # refresh
                        6) [[ -n "$_dml_table" ]] && _shql_where_open "$_dml_table" "$_ctx" -1 ;;
                        7) _shql_export_open ;;
                    esac ;;
                query)
                    # 0=View Details, 1=sep, 2=Re-run, 3=Export
                    # Hydrate query ctx globals so functions see the right state
                    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]:-}"
                    _SHQL_QUERY_EDITOR_CTX="${_ctx}_editor"
                    _SHQL_QUERY_GRID_CTX="${_ctx}_results"
                    SHELLFRAME_GRID_CTX="${_ctx}_results"
                    local _hr_var="_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"
                    _SHQL_QUERY_HAS_RESULTS="${!_hr_var:-0}"
                    local _ls_var="_SHQL_QUERY_CTX_LAST_SQL_${_ctx}"
                    _SHQL_QUERY_LAST_SQL="${!_ls_var:-}"
                    case "$_result" in
                        0) _shql_query_detail_open
                           printf -v "_SHQL_QUERY_CTX_DETAIL_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_DETAIL_ACTIVE" ;;
                        1) ;; # separator
                        2) local _sql
                           shellframe_editor_get_text "${_ctx}_editor" _sql
                           _shql_query_run "$_sql"
                           printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}" '%s' "$_SHQL_QUERY_STATUS"
                           printf -v "_SHQL_QUERY_CTX_ERROR_${_ctx}" '%s' "$_SHQL_QUERY_ERROR"
                           printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}" '%d' "$_SHQL_QUERY_HAS_RESULTS"
                           printf -v "_SHQL_QUERY_CTX_LAST_SQL_${_ctx}" '%s' "$_SHQL_QUERY_LAST_SQL" ;;
                        3) _shql_export_open ;;
                    esac ;;
            esac ;;
    esac
    shellframe_shell_mark_dirty
}

# ── _shql_TABLE_cmenu_render ────────────────────────────────────────────────

_shql_TABLE_cmenu_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    SHELLFRAME_CMENU_CTX="shql_cmenu"
    SHELLFRAME_CMENU_FOCUSED=1
    shellframe_cmenu_render "$_top" "$_left" "$_width" "$_height"
}

# ── _shql_TABLE_cmenu_on_key ───────────────────────────────────────────────

_shql_TABLE_cmenu_on_key() {
    local _key="$1"
    SHELLFRAME_CMENU_CTX="shql_cmenu"
    shellframe_cmenu_on_key "$_key"
    local _rc=$?
    if (( _rc == 2 )); then
        _shql_cmenu_dispatch
        return 0
    fi
    return "$_rc"
}

# ── _shql_TABLE_cmenu_on_mouse ─────────────────────────────────────────────

_shql_TABLE_cmenu_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5" _rleft="$6" _rwidth="$7" _rheight="$8"
    SHELLFRAME_CMENU_CTX="shql_cmenu"
    shellframe_cmenu_on_mouse "$_button" "$_action" "$_mrow" "$_mcol" \
        "$_rtop" "$_rleft" "$_rwidth" "$_rheight"
    local _rc=$?
    if (( _rc == 2 )); then
        _shql_cmenu_dispatch
        return 0
    fi
    return "$_rc"
}

# ── _shql_TABLE_cmenu_on_focus ─────────────────────────────────────────────

_shql_TABLE_cmenu_on_focus() {
    SHELLFRAME_CMENU_FOCUSED="${1:-0}"
}

# ── _shql_TABLE_footer_render ─────────────────────────────────────────────────

_shql_TABLE_footer_render() {
    local _top="$1" _left="$2" _width="$3" _height="${4:-2}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _fbg="${SHQL_THEME_FOOTER_BG:-}"

    # Row 1: Status bar — connection info (left) + query timing (right)
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "$_fbg"
    local _host="${SHQL_DB_HOST:-localhost}"
    local _db_file="${SHQL_DB_PATH##*/}"
    local _conn_info="${_host} // ${_db_file:-<none>}"
    shellframe_fb_print "$_top" "$_left" "$_conn_info" "${_fbg}${_gray}"
    # Right side: time + query status (cached — refresh at most once per second)
    local _now="${EPOCHSECONDS:-}"
    if [[ -z "$_now" || "$_now" != "${_SHQL_FOOTER_TIME_EPOCH:-}" ]]; then
        _SHQL_FOOTER_TIME_EPOCH="$_now"
        if printf -v _SHQL_FOOTER_TIME_CACHE '%(%l:%M %p)T' -1 2>/dev/null; then
            _SHQL_FOOTER_TIME_CACHE="${_SHQL_FOOTER_TIME_CACHE# }"
        else
            _SHQL_FOOTER_TIME_CACHE=$(date '+%l:%M %p' 2>/dev/null || date '+%H:%M')
            _SHQL_FOOTER_TIME_CACHE="${_SHQL_FOOTER_TIME_CACHE# }"
        fi
    fi
    local _time_str="$_SHQL_FOOTER_TIME_CACHE"
    local _right_info="$_time_str"
    if [[ -n "${_SHQL_BROWSER_QUERY_STATUS:-}" ]]; then
        _right_info="${_SHQL_BROWSER_QUERY_STATUS} @ ${_time_str}"
    fi
    local _rlen=${#_right_info}
    local _rcol=$(( _left + _width - _rlen ))
    (( _rcol < _left )) && _rcol=$_left
    shellframe_fb_print "$_top" "$_rcol" "$_right_info" "${_fbg}${_gray}"

    # Center: row count (for data/query content), centered over the content area
    if (( _SHQL_TAB_ACTIVE >= 0 )) && ! (( _SHQL_BROWSER_SIDEBAR_FOCUSED || _SHQL_BROWSER_TABBAR_FOCUSED )); then
        local _type; _shql_content_type _type
        if [[ "$_type" == "data" || "$_type" == "query" ]]; then
            local _nrows="${SHELLFRAME_GRID_ROWS:-0}"
            if (( _nrows > 0 )); then
                local _scroll_top=0
                shellframe_scroll_top "${SHELLFRAME_GRID_CTX:-grid}" _scroll_top
                local _sidebar_w; _shql_browser_sidebar_width "$_width" _sidebar_w
                local _content_left=$(( _left + _sidebar_w ))
                local _content_w=$(( _width - _sidebar_w ))
                local _term_rows _term_cols
                _shellframe_shell_terminal_size _term_rows _term_cols
                local _vrows=$(( _term_rows - 4 - 2 ))
                (( _vrows < 1 )) && _vrows=1
                local _first=$(( _scroll_top + 1 ))
                local _last=$(( _scroll_top + _vrows ))
                (( _last > _nrows )) && _last=$_nrows
                local _row_info
                printf -v _row_info 'Rows %d–%d of %d' "$_first" "$_last" "$_nrows"
                local _ri_len=${#_row_info}
                local _ri_col=$(( _content_left + (_content_w - _ri_len) / 2 ))
                (( _ri_col < _content_left )) && _ri_col=$_content_left
                shellframe_fb_print "$_top" "$_ri_col" "$_row_info" "${_fbg}${_gray}"
            fi
        fi
    fi

    # Row 2: Key hints (left) + version (right)
    local _hints_row=$(( _top + 1 ))
    shellframe_fb_fill "$_hints_row" "$_left" "$_width" " " "$_fbg"
    local _hint; _shql_browser_footer_hint _hint
    shellframe_fb_print "$_hints_row" "$_left" "$_hint" "${_fbg}${_gray}"
    local _ver="v${SHQL_VERSION:-dev}"
    local _ver_col=$(( _left + _width - ${#_ver} ))
    local _hint_end=$(( _left + ${#_hint} + 2 ))
    (( _ver_col > _hint_end )) && \
        shellframe_fb_print "$_hints_row" "$_ver_col" "$_ver" "${_fbg}${_gray}"
}

# ── _shql_TABLE_quit ──────────────────────────────────────────────────────────

_shql_TABLE_quit() {
    _shql_quit_confirm "WELCOME"
}

# ── _shql_quit_confirm ────────────────────────────────────────────────────────
# Activate the inline quit-confirm overlay (replaces shellframe_confirm which
# is incompatible with the shellframe event loop — it rewires fd 3).

_shql_quit_confirm() {
    _SHQL_QUIT_CONFIRM_ACTIVE=1
    shellframe_shell_focus_set "quitconfirm"
    shellframe_shell_mark_dirty
}

# ── _shql_TABLE_quitconfirm_render ───────────────────────────────────────────

_shql_TABLE_quitconfirm_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"

    # Small centered dialog: 5 rows × 38 cols
    local _dw=38 _dh=5
    (( _dw > _width  )) && _dw=$_width
    (( _dh > _height )) && _dh=$_height
    local _dt=$(( _top  + (_height - _dh) / 2 ))
    local _dl=$(( _left + (_width  - _dw) / 2 ))

    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    SHELLFRAME_PANEL_TITLE="Close database?"
    SHELLFRAME_PANEL_TITLE_ALIGN="center"
    SHELLFRAME_PANEL_FOCUSED=1
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    shellframe_panel_render "$_dt" "$_dl" "$_dw" "$_dh"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_dt" "$_dl" "$_dw" "$_dh" _it _il _iw _ih

    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    local _mid=$(( _it + _ih / 2 ))
    shellframe_fb_print "$(( _mid - 1 ))" "$(( _il + 2 ))" \
        "Close and go back to database list?" "${_ibg}"
    shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
        " [y] Close  [n/Esc] Stay" "${_ibg}${_gray}"
}

# ── _shql_TABLE_quitconfirm_on_key ───────────────────────────────────────────

_shql_TABLE_quitconfirm_on_key() {
    local _key="$1"
    case "$_key" in
        y|Y|$'\r'|$'\n')
            _SHQL_QUIT_CONFIRM_ACTIVE=0
            return 2   # triggers _shql_TABLE_quitconfirm_action
            ;;
        *)
            _SHQL_QUIT_CONFIRM_ACTIVE=0
            shellframe_shell_mark_dirty
            return 0
            ;;
    esac
}

_shql_TABLE_quitconfirm_action() {
    _SHELLFRAME_SHELL_NEXT="WELCOME"
}

# ── _shql_drop_confirm ────────────────────────────────────────────────────────

_shql_drop_confirm() {
    local _table="$1" _type="${2:-table}"
    _SHQL_DROP_CONFIRM_TABLE="$_table"
    _SHQL_DROP_CONFIRM_TYPE="$_type"
    _SHQL_DROP_CONFIRM_ACTIVE=1
    shellframe_shell_focus_set "dropconfirm"
    shellframe_shell_mark_dirty
}

# ── _shql_TABLE_dropconfirm_render ────────────────────────────────────────────

_shql_TABLE_dropconfirm_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"

    local _dw=46 _dh=5
    (( _dw > _width  )) && _dw=$_width
    (( _dh > _height )) && _dh=$_height
    local _dt=$(( _top  + (_height - _dh) / 2 ))
    local _dl=$(( _left + (_width  - _dw) / 2 ))

    local _dlabel="Table"; [[ "$_SHQL_DROP_CONFIRM_TYPE" == "view" ]] && _dlabel="View"
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    SHELLFRAME_PANEL_TITLE="Drop ${_dlabel}?"
    SHELLFRAME_PANEL_TITLE_ALIGN="center"
    SHELLFRAME_PANEL_FOCUSED=1
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    shellframe_panel_render "$_dt" "$_dl" "$_dw" "$_dh"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_dt" "$_dl" "$_dw" "$_dh" _it _il _iw _ih

    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    local _mid=$(( _it + _ih / 2 ))
    local _dlabel_lc="table"; [[ "$_SHQL_DROP_CONFIRM_TYPE" == "view" ]] && _dlabel_lc="view"
    shellframe_fb_print "$(( _mid - 1 ))" "$(( _il + 2 ))" \
        "Drop ${_dlabel_lc} '${_SHQL_DROP_CONFIRM_TABLE}'?" "${_ibg}"
    shellframe_fb_print "$_mid" "$(( _il + 2 ))" \
        "This cannot be undone." "${_ibg}${_gray}"
    shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
        " [X] Confirm  [Esc] Cancel" "${_ibg}${_gray}"
}

# ── _shql_TABLE_dropconfirm_on_key ───────────────────────────────────────────

_shql_TABLE_dropconfirm_on_key() {
    local _key="$1"
    case "$_key" in
        X|y|Y)
            _SHQL_DROP_CONFIRM_ACTIVE=0
            return 2   # triggers _shql_TABLE_dropconfirm_action
            ;;
        *)
            _SHQL_DROP_CONFIRM_ACTIVE=0
            shellframe_shell_focus_set "sidebar"
            shellframe_shell_mark_dirty
            return 0
            ;;
    esac
}

_shql_TABLE_dropconfirm_action() {
    local _table="$_SHQL_DROP_CONFIRM_TABLE"
    local _type="$_SHQL_DROP_CONFIRM_TYPE"
    local _keyword="TABLE"; [[ "$_type" == "view" ]] && _keyword="VIEW"
    local _sql
    printf -v _sql 'DROP %s "%s"' "$_keyword" "${_table//\"/\"\"}"
    local _err_file; _err_file=$(mktemp)
    shql_db_query "$SHQL_DB_PATH" "$_sql" >"$_err_file" 2>&1
    local _qrc=$?
    if (( _qrc == 0 )); then
        local _label="Table"; [[ "$_type" == "view" ]] && _label="View"
        shellframe_toast_show "${_label} dropped" success
        _shql_ac_rebuild 2>/dev/null || true
        _shql_tabs_close_by_table "$_table"
        _shql_browser_reload_sidebar
        if (( _SHQL_TAB_ACTIVE < 0 )); then
            shellframe_shell_focus_set "sidebar"
        fi
    else
        local _errmsg; _errmsg=$(cat "$_err_file")
        shellframe_toast_show "Drop failed: ${_errmsg}" error
        shellframe_shell_focus_set "sidebar"
    fi
    rm -f "$_err_file"
    shellframe_shell_mark_dirty
}

# ── shql_table_init ───────────────────────────────────────────────────────────

# Called once before the TABLE screen is first entered.
# SHQL_DB_PATH and _SHQL_TABLE_NAME must already be set.
shql_table_init() {
    _SHQL_TABLE_TABBAR_FOCUSED=0
    _SHQL_TABLE_BODY_FOCUSED=0
    _SHQL_QUIT_CONFIRM_ACTIVE=0
    _SHQL_DROP_CONFIRM_ACTIVE=0
    SHELLFRAME_TABBAR_ACTIVE=0
    _SHQL_INSPECTOR_ACTIVE=0    # reset inspector state on table entry

    _shql_table_load_ddl
    _shql_table_load_data
    _shql_query_init
}
