#!/usr/bin/env bash
# shellql/src/screens/schema.sh — Schema browser screen
#
# REQUIRES: shellframe sourced, src/state.sh sourced, src/db.sh or db_mock.sh.
#
# ── Layout ────────────────────────────────────────────────────────────────────
#
#   row 1        : header (db path, nofocus)
#   rows 2..N-1  : sidebar (table list) | detail (DDL text)
#   row N        : footer (key hints, nofocus)
#
# ── Screens ───────────────────────────────────────────────────────────────────
#
#   SCHEMA  — two-pane schema browser
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#
#   source src/screens/schema.sh
#   # SHQL_DB_PATH must be set before calling shellframe_shell with SCHEMA

# ── Context names ─────────────────────────────────────────────────────────────

_SHQL_SCHEMA_LIST_CTX="schema_tables"
_SHQL_SCHEMA_DDL_CTX="schema_ddl"

# ── Mutable state ─────────────────────────────────────────────────────────────

_SHQL_SCHEMA_TABLES=()       # table names loaded from db adapter
_SHQL_SCHEMA_DDL_LINES=()    # DDL lines for currently shown table
_SHQL_SCHEMA_PREV_TABLE=""   # detect table change → reset DDL scroll

_SHQL_SCHEMA_SIDEBAR_FOCUSED=0
_SHQL_SCHEMA_DETAIL_FOCUSED=0

# ── Constants ─────────────────────────────────────────────────────────────────

_SHQL_SCHEMA_FOOTER_HINTS="[↑↓] Select  [Tab] Switch pane  [↑↓] Scroll DDL  [q] Back"
_SHQL_SCHEMA_SIDEBAR_WIDTH_MIN=20
_SHQL_SCHEMA_SIDEBAR_FRACTION=3  # sidebar gets 1/N of total width

# ── _shql_schema_sidebar_width ────────────────────────────────────────────────

_shql_schema_sidebar_width() {
    local _cols="$1" _out="$2"
    local _result=$(( _cols / _SHQL_SCHEMA_SIDEBAR_FRACTION ))
    (( _result < _SHQL_SCHEMA_SIDEBAR_WIDTH_MIN )) && _result=$_SHQL_SCHEMA_SIDEBAR_WIDTH_MIN
    (( _result > _cols - 10 )) && _result=$(( _cols - 10 ))
    printf -v "$_out" '%d' "$_result"
}

# ── _shql_schema_load_tables ──────────────────────────────────────────────────

# Populate _SHQL_SCHEMA_TABLES from the db adapter.
_shql_schema_load_tables() {
    _SHQL_SCHEMA_TABLES=()
    local _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _SHQL_SCHEMA_TABLES+=("$_line")
    done < <(shql_db_list_tables "$SHQL_DB_PATH" 2>/dev/null)
}

# ── _shql_schema_load_ddl ─────────────────────────────────────────────────────

# Populate _SHQL_SCHEMA_DDL_LINES for $1 (table name).
# Resets the DDL scroll context.
_shql_schema_load_ddl() {
    local _table="$1"
    _SHQL_SCHEMA_DDL_LINES=()
    local _line
    while IFS= read -r _line; do
        _SHQL_SCHEMA_DDL_LINES+=("$_line")
    done < <(shql_db_describe "$SHQL_DB_PATH" "$_table" 2>/dev/null)
    local _n=${#_SHQL_SCHEMA_DDL_LINES[@]}
    shellframe_scroll_init "$_SHQL_SCHEMA_DDL_CTX" "$_n" 1 10 1
    _SHQL_SCHEMA_PREV_TABLE="$_table"
}

# ── _shql_schema_current_table ────────────────────────────────────────────────

# Print the name of the currently cursor-selected table, or "" if none.
_shql_schema_current_table() {
    local _out="${1:-}"
    local _cursor
    shellframe_sel_cursor "$_SHQL_SCHEMA_LIST_CTX" _cursor
    local _name="${_SHQL_SCHEMA_TABLES[$_cursor]:-}"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "$_name"
    else
        printf '%s' "$_name"
    fi
}

# ── _shql_SCHEMA_render ───────────────────────────────────────────────────────

_shql_SCHEMA_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    local _sidebar_w
    _shql_schema_sidebar_width "$_cols" _sidebar_w
    local _detail_w=$(( _cols - _sidebar_w ))

    local _body_top=2
    local _body_h=$(( _rows - 2 ))
    (( _body_h < 2 )) && _body_h=2

    shellframe_shell_region header   1            1             "$_cols"    1          nofocus
    shellframe_shell_region sidebar  "$_body_top" 1             "$_sidebar_w" "$_body_h" focus
    shellframe_shell_region detail   "$_body_top" "$(( _sidebar_w + 1 ))" "$_detail_w" "$_body_h" focus
    shellframe_shell_region footer   "$_rows"     1             "$_cols"    1          nofocus
}

# ── _shql_SCHEMA_header_render ────────────────────────────────────────────────

_shql_SCHEMA_header_render() {
    local _top="$1" _left="$2" _width="$3"
    local _bold="${SHELLFRAME_BOLD:-}" _rst="${SHELLFRAME_RESET:-}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _label="Schema — ${SHQL_DB_PATH:-<no database>}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" "$_bold" "$_label" "$_rst" >/dev/tty
}

# ── _shql_SCHEMA_sidebar_render ───────────────────────────────────────────────

_shql_SCHEMA_sidebar_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Draw panel border
    SHELLFRAME_PANEL_STYLE="single"
    SHELLFRAME_PANEL_TITLE="Tables"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_SHQL_SCHEMA_SIDEBAR_FOCUSED
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

    # Get inner bounds
    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    # Render list inside panel
    SHELLFRAME_LIST_CTX="$_SHQL_SCHEMA_LIST_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_SCHEMA_TABLES[@]+"${_SHQL_SCHEMA_TABLES[@]}"}")
    SHELLFRAME_LIST_FOCUSED=$_SHQL_SCHEMA_SIDEBAR_FOCUSED
    shellframe_list_render "$_it" "$_il" "$_iw" "$_ih"
}

_shql_SCHEMA_sidebar_on_key() {
    SHELLFRAME_LIST_CTX="$_SHQL_SCHEMA_LIST_CTX"
    shellframe_list_on_key "$1"
}

_shql_SCHEMA_sidebar_action() {
    local _table
    _shql_schema_current_table _table
    [[ -z "$_table" ]] && return 0
    _SHQL_TABLE_NAME="$_table"
    shql_table_init
    _SHELLFRAME_SHELL_NEXT="TABLE"
}

_shql_SCHEMA_sidebar_on_focus() {
    _SHQL_SCHEMA_SIDEBAR_FOCUSED="${1:-0}"
    SHELLFRAME_LIST_FOCUSED=$_SHQL_SCHEMA_SIDEBAR_FOCUSED
}

# ── _shql_SCHEMA_detail_render ────────────────────────────────────────────────

_shql_SCHEMA_detail_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Check if selected table changed → reload DDL
    local _cur_table
    _shql_schema_current_table _cur_table
    if [[ "$_cur_table" != "$_SHQL_SCHEMA_PREV_TABLE" ]]; then
        _shql_schema_load_ddl "$_cur_table"
    fi

    # Draw panel border
    SHELLFRAME_PANEL_STYLE="single"
    SHELLFRAME_PANEL_TITLE="DDL"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_SHQL_SCHEMA_DETAIL_FOCUSED
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

    # Get inner bounds
    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    # Sync scroll viewport height
    shellframe_scroll_resize "$_SHQL_SCHEMA_DDL_CTX" "$_ih" 1

    # Render DDL lines
    local _scroll_top
    shellframe_scroll_top "$_SHQL_SCHEMA_DDL_CTX" _scroll_top
    local _n=${#_SHQL_SCHEMA_DDL_LINES[@]}
    local _rst="${SHELLFRAME_RESET:-}"

    local _r
    for (( _r=0; _r<_ih; _r++ )); do
        local _row=$(( _it + _r ))
        local _idx=$(( _scroll_top + _r ))
        printf '\033[%d;%dH%*s' "$_row" "$_il" "$_iw" '' >/dev/tty
        [[ $_idx -ge $_n ]] && continue
        local _line="${_SHQL_SCHEMA_DDL_LINES[$_idx]}"
        local _clipped
        _clipped=$(shellframe_str_clip_ellipsis "$_line" "$_line" "$_iw")
        printf '\033[%d;%dH%s' "$_row" "$_il" "$_clipped" >/dev/tty
    done

    printf '\033[%d;%dH' "$(( _it + _ih - 1 ))" "$_il" >/dev/tty
}

_shql_SCHEMA_detail_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"

    if   [[ "$_key" == "$_k_down"  ]]; then shellframe_scroll_move "$_SHQL_SCHEMA_DDL_CTX" down;      return 0
    elif [[ "$_key" == "$_k_up"    ]]; then shellframe_scroll_move "$_SHQL_SCHEMA_DDL_CTX" up;        return 0
    elif [[ "$_key" == "$_k_pgdn"  ]]; then shellframe_scroll_move "$_SHQL_SCHEMA_DDL_CTX" page_down; return 0
    elif [[ "$_key" == "$_k_pgup"  ]]; then shellframe_scroll_move "$_SHQL_SCHEMA_DDL_CTX" page_up;   return 0
    elif [[ "$_key" == "$_k_home"  ]]; then shellframe_scroll_move "$_SHQL_SCHEMA_DDL_CTX" home;      return 0
    elif [[ "$_key" == "$_k_end"   ]]; then shellframe_scroll_move "$_SHQL_SCHEMA_DDL_CTX" end;       return 0
    fi
    return 1
}

_shql_SCHEMA_detail_on_focus() {
    _SHQL_SCHEMA_DETAIL_FOCUSED="${1:-0}"
}

# ── _shql_SCHEMA_footer_render ────────────────────────────────────────────────

_shql_SCHEMA_footer_render() {
    local _top="$1" _left="$2"
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" \
        "$_gray" "$_SHQL_SCHEMA_FOOTER_HINTS" "$_rst" >/dev/tty
}

# ── _shql_SCHEMA_quit ─────────────────────────────────────────────────────────

_shql_SCHEMA_quit() {
    _SHELLFRAME_SHELL_NEXT="WELCOME"
}

# ── shql_schema_init ──────────────────────────────────────────────────────────

# Called once before the SCHEMA screen is first entered.
shql_schema_init() {
    _SHQL_SCHEMA_TABLES=()
    _SHQL_SCHEMA_DDL_LINES=()
    _SHQL_SCHEMA_PREV_TABLE=""
    _SHQL_SCHEMA_SIDEBAR_FOCUSED=0
    _SHQL_SCHEMA_DETAIL_FOCUSED=0

    _shql_schema_load_tables

    SHELLFRAME_LIST_CTX="$_SHQL_SCHEMA_LIST_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_SCHEMA_TABLES[@]+"${_SHQL_SCHEMA_TABLES[@]}"}")
    shellframe_list_init "$_SHQL_SCHEMA_LIST_CTX"

    shellframe_scroll_init "$_SHQL_SCHEMA_DDL_CTX" 0 1 10 1

    # Load DDL for the first table immediately so detail pane isn't empty
    if (( ${#_SHQL_SCHEMA_TABLES[@]} > 0 )); then
        _shql_schema_load_ddl "${_SHQL_SCHEMA_TABLES[0]}"
    fi
}
