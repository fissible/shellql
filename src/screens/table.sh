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

# ── Tab index constants ────────────────────────────────────────────────────────

_SHQL_TABLE_TAB_STRUCTURE=0
_SHQL_TABLE_TAB_DATA=1
_SHQL_TABLE_TAB_QUERY=2

# ── Footer hint strings ────────────────────────────────────────────────────────

_SHQL_TABLE_FOOTER_HINTS_TABBAR="[←→] Switch tab  [Tab] Body  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_DATA="[↑↓] Navigate  [Enter] Inspect  [Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_STRUCTURE="[↑↓] Scroll  [Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_QUERY="[Tab] Tabs  [q] Back"
_SHQL_TABLE_FOOTER_HINTS_INSPECTOR="[↑↓] Scroll  [PgUp/PgDn] Page  [Enter/Esc/q] Close"

# ── _shql_table_load_ddl ──────────────────────────────────────────────────────

_shql_table_load_ddl() {
    _SHQL_TABLE_DDL_LINES=()
    local _line
    while IFS= read -r _line; do
        _SHQL_TABLE_DDL_LINES+=("$_line")
    done < <(shql_db_describe "$SHQL_DB_PATH" "$_SHQL_TABLE_NAME" 2>/dev/null)
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
                (( _cw < 8  )) && _cw=8
                (( _cw > 30 )) && _cw=30
                SHELLFRAME_GRID_COL_WIDTHS+=("$_cw")
            done
        else
            # Data row: append cells and grow column widths as needed
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
    done < <(shql_db_fetch "$SHQL_DB_PATH" "$_SHQL_TABLE_NAME" 2>/dev/null)

    shellframe_grid_init "$_SHQL_TABLE_GRID_CTX"
}

# ── _shql_TABLE_render ────────────────────────────────────────────────────────

_shql_TABLE_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    local _body_top=4
    local _body_h=$(( _rows - 4 ))
    (( _body_h < 1 )) && _body_h=1

    shellframe_shell_region header  1            1 "$_cols" 1          nofocus
    shellframe_shell_region tabbar  2            1 "$_cols" 1          focus
    shellframe_shell_region gap     3            1 "$_cols" 1          nofocus
    shellframe_shell_region body    "$_body_top" 1 "$_cols" "$_body_h" focus
    shellframe_shell_region footer  "$_rows"     1 "$_cols" 1          nofocus
}

_shql_TABLE_gap_render() {
    printf '\033[%d;%dH\033[2K' "$1" "$2" >/dev/tty
}

# ── _shql_TABLE_header_render ─────────────────────────────────────────────────

_shql_TABLE_header_render() {
    _shql_header_render "$1" "$2" "$3" "$(_shql_breadcrumb "${_SHQL_TABLE_NAME:-}")"
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

# ── _shql_table_data_render ───────────────────────────────────────────────────

_shql_table_data_render() {
    SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
    SHELLFRAME_GRID_FOCUSED=$_SHQL_TABLE_BODY_FOCUSED
    shellframe_grid_render "$@"
}

# ── _shql_table_query_render ──────────────────────────────────────────────────

_shql_table_query_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    local _mid=$(( _top + _height / 2 ))
    local _msg="Query editor — coming in Phase 5.4"
    local _r
    for (( _r=0; _r<_height; _r++ )); do
        printf '\033[%d;%dH\033[2K' "$(( _top + _r ))" "$_left" >/dev/tty
    done
    printf '\033[%d;%dH%s%s%s' "$_mid" "$_left" "$_gray" "$_msg" "$_rst" >/dev/tty
}

# ── _shql_TABLE_body_render / on_key / on_focus ───────────────────────────────

_shql_TABLE_body_render() {
    local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    case "$_tab" in
        "$_SHQL_TABLE_TAB_DATA")      _shql_table_data_render "$@" ;;
        "$_SHQL_TABLE_TAB_QUERY")     _shql_table_query_render "$@" ;;
        *)                            _shql_table_structure_render "$@" ;;
    esac
    # Overlay the record inspector if active
    (( _SHQL_INSPECTOR_ACTIVE )) && _shql_inspector_render "$@"
}

_shql_TABLE_body_on_key() {
    # Route all keys to the inspector when it is open
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _shql_inspector_on_key "$1"
        return $?
    fi

    # [ / ] switch tabs from the body regardless of which tab is active.
    # A future editor (query tab) will consume these keys itself when in insert
    # mode, so they will never reach here in that context.
    case "$1" in
        '[') (( SHELLFRAME_TABBAR_ACTIVE > 0 )) && (( SHELLFRAME_TABBAR_ACTIVE-- )) || true; return 0 ;;
        ']') (( SHELLFRAME_TABBAR_ACTIVE < _SHQL_TABLE_TAB_QUERY )) && (( SHELLFRAME_TABBAR_ACTIVE++ )) || true; return 0 ;;
    esac

    local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"

    # Up at the top of content → return focus to the tab bar.
    # Grid/scroll on_key always return 0 even at boundaries, so we must check
    # position before delegating rather than relying on a boundary signal.
    if [[ "$1" == "$_k_up" ]]; then
        local _at_top=0
        case "$_tab" in
            "$_SHQL_TABLE_TAB_DATA")
                local _cursor=0
                shellframe_sel_cursor "$_SHQL_TABLE_GRID_CTX" _cursor 2>/dev/null || true
                (( _cursor == 0 )) && _at_top=1
                ;;
            "$_SHQL_TABLE_TAB_STRUCTURE")
                local _scroll_top=0
                shellframe_scroll_top "$_SHQL_TABLE_DDL_CTX" _scroll_top
                (( _scroll_top == 0 )) && _at_top=1
                ;;
            *) _at_top=1 ;;
        esac
        if (( _at_top )); then
            shellframe_shell_focus_set "tabbar"
            return 0
        fi
    fi

    case "$_tab" in
        "$_SHQL_TABLE_TAB_DATA")
            SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
            shellframe_grid_on_key "$1"
            return $?
            ;;
        "$_SHQL_TABLE_TAB_STRUCTURE")
            _shql_table_structure_on_key "$1"
            return $?
            ;;
    esac
    return 1
}

_shql_TABLE_body_on_focus() {
    _SHQL_TABLE_BODY_FOCUSED="${1:-0}"
    SHELLFRAME_GRID_FOCUSED=$_SHQL_TABLE_BODY_FOCUSED
}

# ── _shql_TABLE_body_action ───────────────────────────────────────────────────
# Called by shellframe shell when body on_key returns 2 (Enter on grid row).

_shql_TABLE_body_action() {
    local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    [[ "$_tab" != "$_SHQL_TABLE_TAB_DATA" ]] && return 0
    SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
    _shql_inspector_open
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
            "$_SHQL_TABLE_TAB_DATA")      _hint="$_SHQL_TABLE_FOOTER_HINTS_DATA" ;;
            "$_SHQL_TABLE_TAB_STRUCTURE") _hint="$_SHQL_TABLE_FOOTER_HINTS_STRUCTURE" ;;
            *)                            _hint="$_SHQL_TABLE_FOOTER_HINTS_QUERY" ;;
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
}
