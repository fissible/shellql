#!/usr/bin/env bash
# shellql/src/screens/welcome.sh — Welcome screen
#
# REQUIRES: shellframe sourced, src/state.sh sourced.
#
# ── Layout ────────────────────────────────────────────────────────────────────
#
#   row 1        : header (title + key hints)
#   rows 2..N-1  : recent-files list OR empty-state message
#   row N        : footer (status bar)
#
# ── Screens ───────────────────────────────────────────────────────────────────
#
#   WELCOME  — recent-files list with selectable rows
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#
#   source src/screens/welcome.sh
#   shql_welcome_run

# ── Constants ─────────────────────────────────────────────────────────────────

_SHQL_WELCOME_EMPTY_MSG="No recent databases.  Press [o] to open a file."
_SHQL_WELCOME_FOOTER_HINTS="[↑↓] Navigate  [Enter] Open  [o] Open new  [q] Quit"

# ── List context name ─────────────────────────────────────────────────────────

_SHQL_LIST_CTX="welcome_recent"

# ── _shql_WELCOME_render ──────────────────────────────────────────────────────

_shql_WELCOME_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    # Header: 1 row
    shellframe_shell_region header 1 1 "$_cols" 1 nofocus

    # Body: list or empty state
    local _body_top=2
    local _body_h=$(( _rows - 2 ))
    (( _body_h < 1 )) && _body_h=1

    if (( ${#SHQL_RECENT_FILES[@]} > 0 )); then
        shellframe_shell_region list "$_body_top" 1 "$_cols" "$_body_h" focus
    else
        shellframe_shell_region empty "$_body_top" 1 "$_cols" "$_body_h" nofocus
    fi

    # Footer: 1 row
    shellframe_shell_region footer "$_rows" 1 "$_cols" 1 nofocus
}

# ── _shql_WELCOME_header_render ───────────────────────────────────────────────

_shql_WELCOME_header_render() {
    _shql_header_render "$1" "$2" "$3" "ShellQL"
}

# ── _shql_WELCOME_list_render ─────────────────────────────────────────────────

_shql_WELCOME_list_render() {
    SHELLFRAME_LIST_CTX="$_SHQL_LIST_CTX"
    SHELLFRAME_LIST_ITEMS=("${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}")
    shellframe_list_render "$@"
}

_shql_WELCOME_list_on_key() {
    # Intercept keys the list widget doesn't own before delegating.
    case "$1" in
        o)
            # TODO Phase 6: open file-picker; for now, no-op (redraw)
            return 0
            ;;
    esac
    SHELLFRAME_LIST_CTX="$_SHQL_LIST_CTX"
    shellframe_list_on_key "$1"
}

_shql_WELCOME_list_on_focus() {
    SHELLFRAME_LIST_FOCUSED="${1:-0}"
}

_shql_WELCOME_list_action() {
    # Enter pressed on a recent file — open it and navigate to schema browser
    local _cursor
    shellframe_sel_cursor "$_SHQL_LIST_CTX" _cursor 2>/dev/null \
        || _cursor=$(shellframe_sel_cursor "$_SHQL_LIST_CTX")
    SHQL_DB_PATH="${SHQL_RECENT_FILES[$_cursor]:-}"
    shql_schema_init
    _SHELLFRAME_SHELL_NEXT="SCHEMA"
}

# ── _shql_WELCOME_empty_render ────────────────────────────────────────────────

_shql_WELCOME_empty_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _rst="${SHELLFRAME_RESET:-}"
    # Clear the region
    local _r
    for (( _r=0; _r<_height; _r++ )); do
        printf '\033[%d;%dH\033[2K' "$(( _top + _r ))" "$_left" >/dev/tty
    done
    # Print empty message vertically centered
    local _mid=$(( _top + _height / 2 ))
    printf '\033[%d;%dH%s%s%s' "$_mid" "$_left" \
        "$_gray" "$_SHQL_WELCOME_EMPTY_MSG" "$_rst" >/dev/tty
}

# ── _shql_WELCOME_footer_render ───────────────────────────────────────────────

_shql_WELCOME_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _rst="${SHELLFRAME_RESET:-}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" \
        "$_gray" "$_SHQL_WELCOME_FOOTER_HINTS" "$_rst" >/dev/tty
}

# ── _shql_WELCOME_quit ────────────────────────────────────────────────────────

_shql_WELCOME_quit() {
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

# ── shql_welcome_run ──────────────────────────────────────────────────────────

shql_welcome_run() {
    # Populate recent files (real or mock)
    if (( SHQL_MOCK )); then
        shql_mock_load_recent
    else
        shql_state_load_recent
    fi

    # Initialise list widget
    SHELLFRAME_LIST_CTX="$_SHQL_LIST_CTX"
    SHELLFRAME_LIST_ITEMS=("${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}")
    shellframe_list_init "$_SHQL_LIST_CTX"

    shellframe_shell "_shql" "WELCOME"

    # Caller can read SHQL_DB_PATH to know which file was selected (may be empty)
}
