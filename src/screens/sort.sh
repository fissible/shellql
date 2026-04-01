#!/usr/bin/env bash
# shellql/src/screens/sort.sh — Per-tab ORDER BY sort state
#
# Sort state is stored as a per-context global variable
# _SHQL_SORT_<ctx> containing newline-delimited entries of:
#   col<TAB>DIR   (where DIR is ASC or DESC)
#
# Entries appear in the order columns were first clicked (click order).
# Helper functions write to named globals (_SHQL_SORT_RESULT_*) to avoid
# printf -v scope issues.

# ── Named output globals ──────────────────────────────────────────────────────

_SHQL_SORT_RESULT_COUNT=0
_SHQL_SORT_RESULT_COL=""
_SHQL_SORT_RESULT_DIR=""
_SHQL_SORT_RESULT_IDX=-1
_SHQL_SORT_RESULT_CLAUSE=""

# ── Header keyboard focus state ───────────────────────────────────────────────
# _SHQL_HEADER_FOCUSED: 1 while the user is navigating column headers via keyboard
# _SHQL_HEADER_FOCUSED_COL: absolute column index that currently has focus

_SHQL_HEADER_FOCUSED=0
_SHQL_HEADER_FOCUSED_COL=0

# ── _shql_sort_count <ctx> ────────────────────────────────────────────────────
# Sets _SHQL_SORT_RESULT_COUNT to the number of active sort entries for <ctx>.

_shql_sort_count() {
    local _var="_SHQL_SORT_${1}"
    local _data="${!_var:-}"
    _SHQL_SORT_RESULT_COUNT=0
    [[ -z "$_data" ]] && return 0
    local _line
    while IFS= read -r _line; do
        [[ -n "$_line" ]] && (( _SHQL_SORT_RESULT_COUNT++ ))
    done <<< "$_data"
}

# ── _shql_sort_get <ctx> <idx> ────────────────────────────────────────────────
# Sets _SHQL_SORT_RESULT_COL and _SHQL_SORT_RESULT_DIR for the entry at <idx>.
# Returns 1 if <idx> is out of range.

_shql_sort_get() {
    local _ctx="$1" _idx="$2"
    local _var="_SHQL_SORT_${_ctx}"
    local _data="${!_var:-}"
    _SHQL_SORT_RESULT_COL=""
    _SHQL_SORT_RESULT_DIR=""
    local _i=0 _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if (( _i == _idx )); then
            IFS=$'\t' read -r _SHQL_SORT_RESULT_COL _SHQL_SORT_RESULT_DIR <<< "$_line"
            return 0
        fi
        (( _i++ ))
    done <<< "$_data"
    return 1
}

# ── _shql_sort_find <ctx> <col> ───────────────────────────────────────────────
# Sets _SHQL_SORT_RESULT_IDX to the index of <col>, or -1 if absent.
# Also sets _SHQL_SORT_RESULT_DIR when found.

_shql_sort_find() {
    local _ctx="$1" _col="$2"
    local _var="_SHQL_SORT_${_ctx}"
    local _data="${!_var:-}"
    _SHQL_SORT_RESULT_IDX=-1
    _SHQL_SORT_RESULT_DIR=""
    [[ -z "$_data" ]] && return 0
    local _i=0 _line _c _d
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        IFS=$'\t' read -r _c _d <<< "$_line"
        if [[ "$_c" == "$_col" ]]; then
            _SHQL_SORT_RESULT_IDX=$_i
            _SHQL_SORT_RESULT_DIR="$_d"
            return 0
        fi
        (( _i++ ))
    done <<< "$_data"
}

# ── _shql_sort_toggle <ctx> <col> ─────────────────────────────────────────────
# Cycles the sort direction for <col>: absent → ASC → DESC → absent.
# The relative order of other columns is preserved.

_shql_sort_toggle() {
    local _ctx="$1" _col="$2"
    local _var="_SHQL_SORT_${_ctx}"
    local _data="${!_var:-}"
    local _new_data="" _found=0 _line _c _d
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        IFS=$'\t' read -r _c _d <<< "$_line"
        if [[ "$_c" == "$_col" ]]; then
            _found=1
            if [[ "$_d" == "ASC" ]]; then
                # ASC → DESC
                [[ -n "$_new_data" ]] && _new_data+=$'\n'
                _new_data+="${_col}"$'\t'"DESC"
            fi
            # DESC → absent (entry is dropped)
        else
            [[ -n "$_new_data" ]] && _new_data+=$'\n'
            _new_data+="$_line"
        fi
    done <<< "$_data"
    if (( ! _found )); then
        # absent → ASC; append at end to preserve first-click order
        [[ -n "$_new_data" ]] && _new_data+=$'\n'
        _new_data+="${_col}"$'\t'"ASC"
    fi
    printf -v "$_var" '%s' "$_new_data"
}

# ── _shql_sort_build_clause <ctx> ─────────────────────────────────────────────
# Sets _SHQL_SORT_RESULT_CLAUSE to the ORDER BY expression
# (e.g. '"col" ASC, "col2" DESC') or "" when there are no active sorts.

_shql_sort_build_clause() {
    local _ctx="$1"
    local _var="_SHQL_SORT_${_ctx}"
    local _data="${!_var:-}"
    _SHQL_SORT_RESULT_CLAUSE=""
    [[ -z "$_data" ]] && return 0
    local _clause="" _line _c _d
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        IFS=$'\t' read -r _c _d <<< "$_line"
        [[ -n "$_clause" ]] && _clause+=", "
        _clause+="\"${_c//\"/\"\"}\" ${_d}"
    done <<< "$_data"
    _SHQL_SORT_RESULT_CLAUSE="$_clause"
}

# ── _shql_sort_clear <ctx> ────────────────────────────────────────────────────
# Remove all sort entries for <ctx>.

_shql_sort_clear() {
    local _var="_SHQL_SORT_${1}"
    printf -v "$_var" '%s' ""
}

# ── _shql_sort_col_at_x <ctx> <screen_x> <region_left> <region_width> ────────
# Determine which absolute grid column index is at screen column <screen_x>,
# accounting for the grid's horizontal scroll and SHELLFRAME_GRID_COL_WIDTHS.
# Sets _SHQL_SORT_RESULT_IDX to the column index, or -1 if none found.

_shql_sort_col_at_x() {
    local _ctx="$1" _scr_x="$2" _rleft="$3" _rwidth="$4"
    _SHQL_SORT_RESULT_IDX=-1
    local _scroll_left=0
    shellframe_scroll_left "${_ctx}_grid" _scroll_left 2>/dev/null || true
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    local _x="$_rleft" _c
    for (( _c = _scroll_left; _c < _ncols; _c++ )); do
        local _cw="${SHELLFRAME_GRID_COL_WIDTHS[$_c]:-8}"
        if (( _x + _cw > _rleft + _rwidth )); then break; fi
        if (( _scr_x >= _x && _scr_x < _x + _cw )); then
            _SHQL_SORT_RESULT_IDX=$_c
            return 0
        fi
        _x=$(( _x + _cw ))
    done
}

# ── _SHQL_SORT_VISIBLE_END_COL ───────────────────────────────────────────────
# Set by _shql_sort_overlay_headers to the last column index that was rendered.
# Used by the key handler to decide when to scroll right.
_SHQL_SORT_VISIBLE_END_COL=-1

# ── _shql_sort_overlay_headers <top> <left> <width> <ctx> ────────────────────
# Overlay sort indicators (↑/↓) and the focused-header highlight on the header
# row that shellframe_grid_render has already drawn. Call after the grid render.
# Sets _SHQL_SORT_VISIBLE_END_COL to the last visible column index.

_shql_sort_overlay_headers() {
    local _top="$1" _left="$2" _width="$3" _ctx="$4"
    local _hdr_style="${SHQL_THEME_GRID_HEADER_COLOR:-}"
    local _hdr_bg="${SHQL_THEME_GRID_HEADER_BG:-}"
    local _cursor_bg="${SHQL_THEME_CURSOR_BG:-}"
    local _cursor_bold="${SHQL_THEME_CURSOR_BOLD:-}"

    _shql_sort_count "$_ctx"
    local _has_sort=0
    (( _SHQL_SORT_RESULT_COUNT > 0 )) && _has_sort=1

    _SHQL_SORT_VISIBLE_END_COL=-1

    if (( ! _has_sort && ! _SHQL_HEADER_FOCUSED )); then return 0; fi

    local _scroll_left=0
    shellframe_scroll_left "${_ctx}_grid" _scroll_left 2>/dev/null || true
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    local _x="$_left" _c

    for (( _c = _scroll_left; _c < _ncols; _c++ )); do
        local _cw="${SHELLFRAME_GRID_COL_WIDTHS[$_c]:-8}"
        if (( _x + _cw > _left + _width )); then break; fi
        _SHQL_SORT_VISIBLE_END_COL=$_c

        local _col="${SHELLFRAME_GRID_HEADERS[$_c]:-}"
        local _indicator=""
        if (( _has_sort )); then
            _shql_sort_find "$_ctx" "$_col"
            [[ "$_SHQL_SORT_RESULT_DIR" == "ASC"  ]] && _indicator="↑"
            [[ "$_SHQL_SORT_RESULT_DIR" == "DESC" ]] && _indicator="↓"
        fi

        if (( _SHQL_HEADER_FOCUSED && _c == _SHQL_HEADER_FOCUSED_COL )); then
            # Highlight the entire focused cell
            local _focus_bg="${_cursor_bg:-${_hdr_bg}}"
            shellframe_fb_fill "$_top" "$_x" "$_cw" " " "${_focus_bg}${_cursor_bold}"
            local _label=" ${_col}"
            [[ -n "$_indicator" ]] && _label+=" ${_indicator}"
            shellframe_fb_print "$_top" "$_x" "$_label" "${_focus_bg}${_cursor_bold}"
        elif [[ -n "$_indicator" ]]; then
            # Overlay indicator near the right edge of this cell
            local _ind_x=$(( _x + _cw - 2 ))
            (( _ind_x >= _left )) && \
                shellframe_fb_print "$_top" "$_ind_x" "$_indicator" "${_hdr_bg}${_hdr_style}"
        fi

        _x=$(( _x + _cw ))
    done
}
