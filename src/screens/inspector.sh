#!/usr/bin/env bash
# shellql/src/screens/inspector.sh — Record inspector overlay
#
# REQUIRES: shellframe sourced, src/state.sh sourced.
#
# Renders a centered key/value overlay panel over the TABLE body region.
# Triggered by Enter on a data grid row (_shql_TABLE_body_action).
#
# ── State globals ──────────────────────────────────────────────────────────────
#   _SHQL_INSPECTOR_ACTIVE   — 0|1: whether the overlay is visible
#   _SHQL_INSPECTOR_PAIRS    — array of "key<TAB>value" strings (one per column)
#   _SHQL_INSPECTOR_CTX      — scroll context name
#
# ── Public functions ───────────────────────────────────────────────────────────
#   _shql_inspector_open          — build pairs from current grid cursor row
#   _shql_inspector_render t l w h — draw overlay (call from body_render)
#   _shql_inspector_on_key key    — handle keys (call from body_on_key guard)
#   _shql_inspector_key_width out — compute key column width into out_var

_SHQL_INSPECTOR_ACTIVE=0
_SHQL_INSPECTOR_PAIRS=()
_SHQL_INSPECTOR_CTX="inspector_scroll"

# ── _shql_inspector_open ──────────────────────────────────────────────────────

_shql_inspector_open() {
    # Guard: nothing to inspect in an empty table
    [[ "${SHELLFRAME_GRID_ROWS:-0}" -eq 0 ]] && return 0

    # PRECONDITION: SHELLFRAME_GRID_CTX must be set to the active grid context
    # before calling this function (done by _shql_TABLE_body_action).
    # shellframe_sel_cursor uses SHELLFRAME_GRID_CTX to locate the selection state.

    # Read current cursor row (out-var form — no subshell)
    local _cursor=0
    shellframe_sel_cursor "${SHELLFRAME_GRID_CTX:-}" _cursor 2>/dev/null || true

    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_INSPECTOR_PAIRS=()
    local _c _idx _key _val
    for (( _c=0; _c<_ncols; _c++ )); do
        _key="${SHELLFRAME_GRID_HEADERS[$_c]:-col$_c}"
        _idx=$(( _cursor * _ncols + _c ))
        _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        [[ -z "$_val" ]] && _val="(null)"
        _SHQL_INSPECTOR_PAIRS+=("${_key}"$'\t'"${_val}")
    done

    local _n=${#_SHQL_INSPECTOR_PAIRS[@]}
    shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_n" 1 10 1
    _SHQL_INSPECTOR_ACTIVE=1
}

# ── _shql_inspector_key_width ─────────────────────────────────────────────────

# Compute key column width: max key length across all pairs, bounded [8, 20].
# Stores result via printf -v into the named output variable.
_shql_inspector_key_width() {
    local _out_var="$1"
    local _max=0 _pair _key _klen
    for _pair in "${_SHQL_INSPECTOR_PAIRS[@]+"${_SHQL_INSPECTOR_PAIRS[@]}"}"; do
        _key="${_pair%%	*}"
        _klen=${#_key}
        (( _klen > _max )) && _max=$_klen
    done
    (( _max < 8  )) && _max=8
    (( _max > 20 )) && _max=20
    printf -v "$_out_var" '%d' "$_max"
}

# ── _shql_inspector_on_key ────────────────────────────────────────────────────

_shql_inspector_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"

    case "$_key" in
        "$_k_up")   shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" up;        return 0 ;;
        "$_k_down") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" down;      return 0 ;;
        "$_k_pgup") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" page_up;   return 0 ;;
        "$_k_pgdn") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" page_down; return 0 ;;
        $'\033'|$'\r'|$'\n'|q)
            # Return 0 (not 1) so the key does NOT fall through to the global
            # quit handler, which would navigate away from TABLE while the
            # inspector is still open.
            _SHQL_INSPECTOR_ACTIVE=0
            return 0
            ;;
    esac
    return 1
}

# ── _shql_inspector_render ────────────────────────────────────────────────────

_shql_inspector_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _bold="${SHELLFRAME_BOLD:-$'\033[1m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"

    # ── Panel dimensions (centered) ──
    local _panel_w=$(( _width * 2 / 3 ))
    (( _panel_w < 40           )) && _panel_w=40
    (( _panel_w > _width - 4   )) && _panel_w=$(( _width - 4 ))
    (( _panel_w < 1            )) && _panel_w=1

    local _panel_h=$(( _height * 3 / 4 ))
    (( _panel_h < 10           )) && _panel_h=10
    (( _panel_h > _height - 2  )) && _panel_h=$(( _height - 2 ))
    (( _panel_h < 1            )) && _panel_h=1

    local _panel_top=$(( _top  + (_height - _panel_h) / 2 ))
    local _panel_left=$(( _left + (_width  - _panel_w) / 2 ))

    # ── Draw panel border ──
    local _save_pstyle="$SHELLFRAME_PANEL_STYLE"
    local _save_ptitle="$SHELLFRAME_PANEL_TITLE"
    local _save_ptalign="$SHELLFRAME_PANEL_TITLE_ALIGN"
    local _save_pfocused="$SHELLFRAME_PANEL_FOCUSED"

    SHELLFRAME_PANEL_STYLE="single"
    SHELLFRAME_PANEL_TITLE="Row Inspector"
    SHELLFRAME_PANEL_TITLE_ALIGN="center"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h"

    # Get inner content bounds via panel API
    local _inner_top _inner_left _inner_w _inner_h
    shellframe_panel_inner "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h" \
        _inner_top _inner_left _inner_w _inner_h

    SHELLFRAME_PANEL_STYLE="$_save_pstyle"
    SHELLFRAME_PANEL_TITLE="$_save_ptitle"
    SHELLFRAME_PANEL_TITLE_ALIGN="$_save_ptalign"
    SHELLFRAME_PANEL_FOCUSED="$_save_pfocused"

    # ── Clear inner area ──
    local _ir
    for (( _ir=0; _ir<_inner_h; _ir++ )); do
        printf '\033[%d;%dH\033[2K' "$(( _inner_top + _ir ))" "$_inner_left" >/dev/tty
    done

    # ── Compute key column width ──
    local _kw
    _shql_inspector_key_width _kw
    local _val_avail=$(( _inner_w - _kw - 2 ))
    (( _val_avail < 1 )) && _val_avail=1

    # ── Update scroll viewport to actual height ──
    shellframe_scroll_resize "$_SHQL_INSPECTOR_CTX" "$_inner_h" 1
    local _scroll_top=0
    shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _scroll_top

    # ── Render key/value rows ──
    local _n=${#_SHQL_INSPECTOR_PAIRS[@]}
    local _r _idx _pair _key _val _val_clipped
    for (( _r=0; _r<_inner_h; _r++ )); do
        _idx=$(( _scroll_top + _r ))
        [[ $_idx -ge $_n ]] && continue
        _pair="${_SHQL_INSPECTOR_PAIRS[$_idx]}"
        _key="${_pair%%	*}"
        _val="${_pair#*	}"
        # shellframe_str_clip_ellipsis raw rendered width
        # raw and rendered are the same for plain text (no ANSI escapes in cell values)
        _val_clipped=$(shellframe_str_clip_ellipsis "$_val" "$_val" "$_val_avail")
        printf '\033[%d;%dH%s%-*s%s  %s' \
            "$(( _inner_top + _r ))" "$_inner_left" \
            "$_bold" "$_kw" "$_key" "$_rst" \
            "$_val_clipped" >/dev/tty
    done
}
