#!/usr/bin/env bash
# shellql/src/screens/inspector.sh — Record inspector inline view
#
# REQUIRES: shellframe sourced, src/state.sh sourced.
#
# Renders a full-content-area key/value panel (inline, not centered overlay).
# Triggered by Enter on a data grid row (_shql_TABLE_body_action).
#
# ── State globals ──────────────────────────────────────────────────────────────
#   _SHQL_INSPECTOR_ACTIVE     — 0|1: whether the inspector is visible
#   _SHQL_INSPECTOR_PAIRS      — array of "key<TAB>value" strings (one per column)
#   _SHQL_INSPECTOR_CTX        — scroll context name
#   _SHQL_INSPECTOR_ROW_IDX    — which data-grid row is being inspected
#   _SHQL_INSPECTOR_TOTAL_ROWS — total rows in the grid (for nav bar)
#
# ── Public functions ───────────────────────────────────────────────────────────
#   _shql_inspector_open          — build pairs from current grid cursor row
#   _shql_inspector_render t l w h — draw inspector (call from body_render)
#   _shql_inspector_on_key key    — handle keys (call from body_on_key guard)
#   _shql_inspector_key_width out — compute key column width into out_var
#   _shql_inspector_nav_label out — compute nav bar label into out_var

_SHQL_INSPECTOR_ACTIVE=0
_SHQL_INSPECTOR_PAIRS=()
_SHQL_INSPECTOR_CTX="inspector_scroll"
_SHQL_INSPECTOR_ROW_IDX=0       # which data-grid row is being inspected
_SHQL_INSPECTOR_TOTAL_ROWS=0    # total rows in the grid (for nav bar)
_SHQL_INSPECTOR_GRID_CTX=""     # grid context for row stepping

# ── _shql_inspector_open ──────────────────────────────────────────────────────

_shql_inspector_open() {
    [[ "${SHELLFRAME_GRID_ROWS:-0}" -eq 0 ]] && return 0

    local _cursor=0
    shellframe_sel_cursor "${SHELLFRAME_GRID_CTX:-}" _cursor 2>/dev/null || true

    _SHQL_INSPECTOR_ROW_IDX=$_cursor
    _SHQL_INSPECTOR_TOTAL_ROWS="${SHELLFRAME_GRID_ROWS:-0}"
    _SHQL_INSPECTOR_GRID_CTX="${SHELLFRAME_GRID_CTX:-}"

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

# ── _shql_inspector_step ──────────────────────────────────────────────────────
# Move to the next (+1) or previous (-1) row in the grid.
_shql_inspector_step() {
    local _delta="$1"
    local _total="${_SHQL_INSPECTOR_TOTAL_ROWS:-0}"
    (( _total == 0 )) && return 0

    local _new=$(( _SHQL_INSPECTOR_ROW_IDX + _delta ))
    # Wrap
    (( _new < 0 )) && _new=$(( _total - 1 ))
    (( _new >= _total )) && _new=0

    _SHQL_INSPECTOR_ROW_IDX=$_new

    # Reload pairs from the grid data
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_INSPECTOR_PAIRS=()
    local _c _idx _key _val
    for (( _c=0; _c<_ncols; _c++ )); do
        _key="${SHELLFRAME_GRID_HEADERS[$_c]:-col$_c}"
        _idx=$(( _new * _ncols + _c ))
        _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        [[ -z "$_val" ]] && _val="(null)"
        _SHQL_INSPECTOR_PAIRS+=("${_key}"$'\t'"${_val}")
    done

    # Reset scroll to top for the new record
    local _n=${#_SHQL_INSPECTOR_PAIRS[@]}
    shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_n" 1 10 1
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

# ── _shql_inspector_nav_label ─────────────────────────────────────────────────

_shql_inspector_nav_label() {
    local _out_var="$1"
    local _first_val=""
    if [[ ${#_SHQL_INSPECTOR_PAIRS[@]} -gt 0 ]]; then
        _first_val="${_SHQL_INSPECTOR_PAIRS[0]#*	}"
    fi
    local _n=$(( _SHQL_INSPECTOR_ROW_IDX + 1 ))
    local _total="$_SHQL_INSPECTOR_TOTAL_ROWS"
    printf -v "$_out_var" '← %s  (%d/%d) →' "$_first_val" "$_n" "$_total"
}

# ── _shql_inspector_on_key ────────────────────────────────────────────────────

_shql_inspector_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

    case "$_key" in
        "$_k_right") _shql_inspector_step 1;  shellframe_shell_mark_dirty; return 0 ;;
        "$_k_left")  _shql_inspector_step -1; shellframe_shell_mark_dirty; return 0 ;;
        "$_k_up")
            # ↑ at scroll top dismisses inspector (back to grid)
            local _st=0; shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _st 2>/dev/null || true
            if (( _st == 0 )); then
                _SHQL_INSPECTOR_ACTIVE=0
                shellframe_shell_mark_dirty
            else
                shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" up
            fi
            return 0 ;;
        "$_k_down") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" down;      return 0 ;;
        "$_k_pgup") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" page_up;   return 0 ;;
        "$_k_pgdn") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" page_down; return 0 ;;
        $'\033'|$'\r'|$'\n'|q)
            # Return 0 (not 1) so the key does NOT fall through to the global
            # quit handler, which would navigate away from TABLE while the
            # inspector is still open.
            _SHQL_INSPECTOR_ACTIVE=0
            shellframe_shell_mark_dirty
            return 0
            ;;
    esac
    return 1
}

# ── _shql_inspector_render ────────────────────────────────────────────────────

_shql_inspector_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Draw panel border with content bg + accent color for border cells
    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    local _table_name="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]:-}"
    SHELLFRAME_PANEL_TITLE="Record — ${_table_name}"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    # 1-char inner padding (all sides)
    local _pt=$(( _it + 1 ))         # pad top
    local _pl=$(( _il + 1 ))         # pad left
    local _pw=$(( _iw - 2 ))         # content width (1 pad each side)
    local _ph=$(( _ih - 2 ))         # content height (1 pad top + 1 pad bottom)
    (( _pw < 1 )) && _pw=1
    (( _ph < 1 )) && _ph=1

    # Clear inner area with editor bg (darker than content, lighter than black)
    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    # Nav bar — distinct bg for gradation (stripe color or cursor color)
    local _gray="${SHELLFRAME_GRAY:-}"
    local _nav_bg="${SHQL_THEME_ROW_STRIPE_BG:-$_cbg}"
    local _nav
    _shql_inspector_nav_label _nav
    local _nav_clipped
    shellframe_str_clip_ellipsis "$_nav" "$_nav" "$_pw" _nav_clipped
    shellframe_fb_fill  "$_pt" "$_il" "$_iw" " " "$_nav_bg"
    shellframe_fb_print "$_pt" "$_pl" "$_nav_clipped" "$_nav_bg"

    # Separator line — ─ is 3-byte UTF-8; use shellframe_fb_put per cell
    local _sep_row=$(( _pt + 1 ))
    local _si=0
    while (( _si < _iw )); do
        shellframe_fb_put "$_sep_row" "$(( _il + _si ))" "${_ibg}${_gray}─"
        (( _si++ ))
    done

    # Single-column key/value area starts 2 rows after padded top (nav + sep)
    local _kv_top=$(( _pt + 2 ))
    local _kv_h=$(( _ph - 2 ))
    (( _kv_h < 1 )) && _kv_h=1

    local _kw; _shql_inspector_key_width _kw
    local _val_avail=$(( _pw - _kw - 2 ))
    (( _val_avail < 1 )) && _val_avail=1
    local _val_left=$(( _pl + _kw + 2 ))

    local _kc="${SHQL_THEME_KEY_COLOR:-}"
    local _n_pairs=${#_SHQL_INSPECTOR_PAIRS[@]}

    # Build display-row map: long values wrap across multiple rows.
    local _dr_pair=() _dr_line=() _total_drows=0
    local _i _j _drows _vlen _pair_i _val_i
    for (( _i=0; _i<_n_pairs; _i++ )); do
        _pair_i="${_SHQL_INSPECTOR_PAIRS[$_i]}"
        _val_i="${_pair_i#*	}"
        _vlen=${#_val_i}
        _drows=$(( (_vlen + _val_avail - 1) / _val_avail ))
        (( _drows < 1 )) && _drows=1
        for (( _j=0; _j<_drows; _j++ )); do
            _dr_pair[$_total_drows]=$_i
            _dr_line[$_total_drows]=$_j
            (( _total_drows++ ))
        done
    done

    # Update scroll total without resetting position, then re-clamp
    printf -v "_SHELLFRAME_SCROLL_${_SHQL_INSPECTOR_CTX}_ROWS" '%d' "$_total_drows"
    shellframe_scroll_resize "$_SHQL_INSPECTOR_CTX" "$_kv_h" 1
    local _scroll_top=0
    shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _scroll_top

    local _r _dr _pi _ldr _row _pair _key _val _val_chunk _key_padded
    for (( _r=0; _r<_kv_h; _r++ )); do
        _dr=$(( _scroll_top + _r ))
        (( _dr >= _total_drows )) && continue
        _row=$(( _kv_top + _r ))
        _pi=${_dr_pair[$_dr]}
        _ldr=${_dr_line[$_dr]}
        _pair="${_SHQL_INSPECTOR_PAIRS[$_pi]}"
        _key="${_pair%%	*}"
        _val="${_pair#*	}"
        _val_chunk="${_val:$(( _ldr * _val_avail )):$_val_avail}"
        if (( _ldr == 0 )); then
            printf -v _key_padded '%-*s' "$_kw" "$_key"
        else
            printf -v _key_padded '%-*s' "$_kw" ""
        fi
        shellframe_fb_print "$_row" "$_pl"       "$_key_padded" "${_ibg}${_kc}"
        shellframe_fb_fill  "$_row" "$(( _pl + _kw ))" 2 " " "$_ibg"
        shellframe_fb_print "$_row" "$_val_left" "$_val_chunk" "$_ibg"
    done
}
