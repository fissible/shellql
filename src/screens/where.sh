#!/usr/bin/env bash
# shellql/src/screens/where.sh — WHERE filter overlay
#
# REQUIRES: shellframe sourced (including input-field.sh), src/state.sh sourced.
#
# Applied filters are stored per-tab as newline-delimited entries:
#   _SHQL_WHERE_APPLIED_${tab_ctx}  — "col<TAB>op<TAB>val\ncol<TAB>op<TAB>val\n..."
#                                     empty string = no filters
#
# Pill scroll state is stored per-tab:
#   _SHQL_WHERE_PILL_SCROLL_${tab_ctx}  — index of first visible pill (default 0)
#
# ── State globals ──────────────────────────────────────────────────────────────
#   _SHQL_WHERE_ACTIVE      — 0|1: overlay visible
#   _SHQL_WHERE_TABLE       — table name currently being filtered
#   _SHQL_WHERE_TAB_CTX     — tab context for stored filters
#   _SHQL_WHERE_CTX         — field context prefix (for shellframe_cur_*)
#   _SHQL_WHERE_FOCUS       — 0=column, 1=operator, 2=value
#   _SHQL_WHERE_OP_IDX      — index into _SHQL_WHERE_OPERATORS
#   _SHQL_WHERE_EDIT_IDX    — index of filter being edited (-1 = new filter)
#
# ── Output globals (set by helpers, avoids printf -v scope issues) ─────────────
#   _SHQL_WHERE_RESULT_COUNT — set by _shql_where_filter_count
#   _SHQL_WHERE_RESULT_COL   — set by _shql_where_filter_get
#   _SHQL_WHERE_RESULT_OP    — set by _shql_where_filter_get
#   _SHQL_WHERE_RESULT_VAL   — set by _shql_where_filter_get
#   _SHQL_WHERE_PILL_TEXT    — set by _shql_where_pill_label
#
# ── Pill layout globals (set by _shql_where_pills_layout) ─────────────────────
#   _SHQL_PILL_LAYOUT_N          — number of visible pills
#   _SHQL_PILL_LAYOUT_TOTAL      — total filter count
#   _SHQL_PILL_LAYOUT_SCROLL     — current scroll offset
#   _SHQL_PILL_LAYOUT_HAS_PREV   — 1 if [<] shown
#   _SHQL_PILL_LAYOUT_PREV_COL   — column of [<] (-1 if not shown)
#   _SHQL_PILL_LAYOUT_HAS_NEXT   — 1 if [>] shown
#   _SHQL_PILL_LAYOUT_NEXT_COL   — column of [>] (-1 if not shown)
#   _SHQL_PILL_LAYOUT_IDX_<j>    — filter index of visible pill j
#   _SHQL_PILL_LAYOUT_COL_<j>    — start column of visible pill j
#   _SHQL_PILL_LAYOUT_W_<j>      — width of visible pill j
#   _SHQL_PILL_LAYOUT_EXPR_<j>   — full pill string "(expr x)" for pill j
#
# ── Public functions ───────────────────────────────────────────────────────────
#   _shql_where_filter_count tab_ctx          — count filters → _SHQL_WHERE_RESULT_COUNT
#   _shql_where_filter_get tab_ctx idx        — get filter → _SHQL_WHERE_RESULT_{COL,OP,VAL}
#   _shql_where_filter_set tab_ctx idx col op val — overwrite filter at idx
#   _shql_where_filter_add tab_ctx col op val — append new filter
#   _shql_where_filter_del tab_ctx idx        — delete filter at idx
#   _shql_where_open table tab_ctx edit_idx   — open overlay (edit_idx=-1 for new)
#   _shql_where_apply                         — read fields and store/update filter
#   _shql_where_render t l w h                — draw overlay (call from content_render)
#   _shql_where_on_key key                    — handle keys; returns 0 (handled) or 1
#   _shql_where_build_clause col op val out_var — build SQL WHERE fragment
#   _shql_where_pill_label tab_ctx idx max_len — set _SHQL_WHERE_PILL_TEXT
#   _shql_where_pills_layout tab_ctx area_left area_right — compute pill layout globals
#   _shql_where_pills_render tab_ctx row area_left area_right style focus_style
#   _shql_where_clear [tab_ctx]               — clear ALL filters, force reload
#   _shql_where_clear_one tab_ctx idx         — clear single filter, force reload

_SHQL_WHERE_ACTIVE=0
_SHQL_WHERE_TABLE=""
_SHQL_WHERE_TAB_CTX=""
_SHQL_WHERE_CTX="where_form"
_SHQL_WHERE_FOCUS=0
_SHQL_WHERE_OP_IDX=0
_SHQL_WHERE_EDIT_IDX=-1

_SHQL_WHERE_OPERATORS=("=" "<>" ">" "<" ">=" "<=" "LIKE" "NOT LIKE" "GLOB" "IN" "NOT IN" "BETWEEN" "NOT BETWEEN" "IS NULL" "IS NOT NULL")

# Output globals
_SHQL_WHERE_RESULT_COUNT=0
_SHQL_WHERE_RESULT_COL=""
_SHQL_WHERE_RESULT_OP=""
_SHQL_WHERE_RESULT_VAL=""
_SHQL_WHERE_PILL_TEXT=""

# Pill layout globals (populated by _shql_where_pills_layout)
_SHQL_PILL_LAYOUT_N=0
_SHQL_PILL_LAYOUT_TOTAL=0
_SHQL_PILL_LAYOUT_SCROLL=0
_SHQL_PILL_LAYOUT_HAS_PREV=0
_SHQL_PILL_LAYOUT_PREV_COL=-1
_SHQL_PILL_LAYOUT_HAS_NEXT=0
_SHQL_PILL_LAYOUT_NEXT_COL=-1

# ── _shql_where_filter_count ──────────────────────────────────────────────────
# Sets _SHQL_WHERE_RESULT_COUNT to number of filters for tab_ctx.

_shql_where_filter_count() {
    local _fc_var="_SHQL_WHERE_APPLIED_$1"
    local _fc_data="${!_fc_var:-}"
    if [[ -z "$_fc_data" ]]; then
        _SHQL_WHERE_RESULT_COUNT=0
        return
    fi
    local _fc_n=0 _fc_line
    while IFS= read -r _fc_line; do
        [[ -n "$_fc_line" ]] && (( _fc_n++ ))
    done <<< "$_fc_data"
    _SHQL_WHERE_RESULT_COUNT=$_fc_n
}

# ── _shql_where_filter_get ────────────────────────────────────────────────────
# Sets _SHQL_WHERE_RESULT_{COL,OP,VAL}. Returns 1 if idx out of range.

_shql_where_filter_get() {
    local _fg_var="_SHQL_WHERE_APPLIED_$1"
    local _fg_idx="$2"
    local _fg_data="${!_fg_var:-}"
    _SHQL_WHERE_RESULT_COL=""
    _SHQL_WHERE_RESULT_OP=""
    _SHQL_WHERE_RESULT_VAL=""
    local _fg_i=0 _fg_line
    while IFS= read -r _fg_line; do
        if [[ -n "$_fg_line" ]]; then
            if (( _fg_i == _fg_idx )); then
                IFS=$'\t' read -r _SHQL_WHERE_RESULT_COL _SHQL_WHERE_RESULT_OP _SHQL_WHERE_RESULT_VAL \
                    <<< "$_fg_line"
                return 0
            fi
            (( _fg_i++ ))
        fi
    done <<< "$_fg_data"
    return 1
}

# ── _shql_where_filter_set ────────────────────────────────────────────────────
# Overwrites filter at idx with new col/op/val.

_shql_where_filter_set() {
    local _fs_ctx="$1" _fs_idx="$2" _fs_col="$3" _fs_op="$4" _fs_val="$5"
    local _fs_var="_SHQL_WHERE_APPLIED_${_fs_ctx}"
    local _fs_data="${!_fs_var:-}"
    local _fs_i=0 _fs_new="" _fs_line
    while IFS= read -r _fs_line; do
        if [[ -n "$_fs_line" ]]; then
            if (( _fs_i == _fs_idx )); then
                _fs_new+="${_fs_col}"$'\t'"${_fs_op}"$'\t'"${_fs_val}"$'\n'
            else
                _fs_new+="${_fs_line}"$'\n'
            fi
            (( _fs_i++ ))
        fi
    done <<< "$_fs_data"
    _fs_new="${_fs_new%$'\n'}"
    printf -v "_SHQL_WHERE_APPLIED_${_fs_ctx}" '%s' "$_fs_new"
}

# ── _shql_where_filter_add ────────────────────────────────────────────────────
# Appends a new filter entry.

_shql_where_filter_add() {
    local _fa_ctx="$1" _fa_col="$2" _fa_op="$3" _fa_val="$4"
    local _fa_var="_SHQL_WHERE_APPLIED_${_fa_ctx}"
    local _fa_existing="${!_fa_var:-}"
    local _fa_entry="${_fa_col}"$'\t'"${_fa_op}"$'\t'"${_fa_val}"
    if [[ -z "$_fa_existing" ]]; then
        printf -v "_SHQL_WHERE_APPLIED_${_fa_ctx}" '%s' "$_fa_entry"
    else
        printf -v "_SHQL_WHERE_APPLIED_${_fa_ctx}" '%s' "${_fa_existing}"$'\n'"${_fa_entry}"
    fi
}

# ── _shql_where_filter_del ────────────────────────────────────────────────────
# Removes the filter at idx; remaining entries shift down.

_shql_where_filter_del() {
    local _fd_ctx="$1" _fd_idx="$2"
    local _fd_var="_SHQL_WHERE_APPLIED_${_fd_ctx}"
    local _fd_data="${!_fd_var:-}"
    local _fd_i=0 _fd_new="" _fd_line
    while IFS= read -r _fd_line; do
        if [[ -n "$_fd_line" ]]; then
            if (( _fd_i != _fd_idx )); then
                _fd_new+="${_fd_line}"$'\n'
            fi
            (( _fd_i++ ))
        fi
    done <<< "$_fd_data"
    _fd_new="${_fd_new%$'\n'}"
    printf -v "_SHQL_WHERE_APPLIED_${_fd_ctx}" '%s' "$_fd_new"
}

# ── _shql_where_build_clause ──────────────────────────────────────────────────
# Builds a SQL WHERE fragment (without "WHERE") into out_var.
# IS NULL / IS NOT NULL ignore the value argument.

_shql_where_build_clause() {
    local _col="$1" _op="$2" _val="$3" _clause_out="$4"
    local _col_q="\"${_col//\"/\"\"}\""
    case "$_op" in
        "IS NULL"|"IS NOT NULL")
            printf -v "$_clause_out" '%s %s' "$_col_q" "$_op" ;;
        "IN"|"NOT IN")
            # _val is comma-separated; quote each trimmed item
            local _in_list="" _in_item _in_items
            IFS=',' read -ra _in_items <<< "$_val"
            for _in_item in "${_in_items[@]}"; do
                _in_item="${_in_item#"${_in_item%%[! ]*}"}"
                _in_item="${_in_item%"${_in_item##*[! ]}"}"
                _in_list+="'${_in_item//\'/\'\'}', "
            done
            _in_list="${_in_list%, }"
            printf -v "$_clause_out" '%s %s (%s)' "$_col_q" "$_op" "$_in_list" ;;
        "BETWEEN"|"NOT BETWEEN")
            # _val is "low<TAB>high"
            local _bv1 _bv2
            IFS=$'\t' read -r _bv1 _bv2 <<< "$_val"
            printf -v "$_clause_out" "%s %s '%s' AND '%s'" \
                "$_col_q" "$_op" "${_bv1//\'/\'\'}" "${_bv2//\'/\'\'}" ;;
        *)
            local _val_q="'${_val//\'/\'\'}'"
            printf -v "$_clause_out" '%s %s %s' "$_col_q" "$_op" "$_val_q" ;;
    esac
}

# ── _shql_where_pill_label ────────────────────────────────────────────────────
# Sets _SHQL_WHERE_PILL_TEXT to the display label for filter at idx.
# Truncates to _max_len chars. Empty if filter not found.

_shql_where_pill_label() {
    local _pl_ctx="$1" _pl_idx="$2" _pl_max="$3"
    _shql_where_filter_get "$_pl_ctx" "$_pl_idx"
    if [[ -z "$_SHQL_WHERE_RESULT_COL" ]]; then
        _SHQL_WHERE_PILL_TEXT=""
        return
    fi
    local _expr="${_SHQL_WHERE_RESULT_COL} ${_SHQL_WHERE_RESULT_OP}"
    case "$_SHQL_WHERE_RESULT_OP" in
        "IS NULL"|"IS NOT NULL") ;;
        "BETWEEN"|"NOT BETWEEN")
            local _bv1 _bv2
            IFS=$'\t' read -r _bv1 _bv2 <<< "$_SHQL_WHERE_RESULT_VAL"
            _expr+=" ${_bv1} AND ${_bv2}" ;;
        *) _expr+=" ${_SHQL_WHERE_RESULT_VAL}" ;;
    esac
    if (( ${#_expr} > _pl_max )); then
        _expr="${_expr:0:$(( _pl_max - 3 ))}..."
    fi
    _SHQL_WHERE_PILL_TEXT="$_expr"
}

# ── _shql_where_pills_layout ──────────────────────────────────────────────────
# Computes which pills are visible in [area_left, area_right) and where.
# Populates _SHQL_PILL_LAYOUT_* globals (see file header for full list).

_shql_where_pills_layout() {
    local _pl_ctx="$1" _pl_left="$2" _pl_right="$3"

    _shql_where_filter_count "$_pl_ctx"
    local _total="$_SHQL_WHERE_RESULT_COUNT"

    local _scroll_var="_SHQL_WHERE_PILL_SCROLL_${_pl_ctx}"
    local _scroll="${!_scroll_var:-0}"
    # Clamp scroll
    (( _scroll >= _total )) && _scroll=$(( _total > 0 ? _total - 1 : 0 ))
    (( _scroll < 0 )) && _scroll=0

    _SHQL_PILL_LAYOUT_TOTAL="$_total"
    _SHQL_PILL_LAYOUT_SCROLL="$_scroll"
    _SHQL_PILL_LAYOUT_N=0
    _SHQL_PILL_LAYOUT_HAS_PREV=0
    _SHQL_PILL_LAYOUT_PREV_COL=-1
    _SHQL_PILL_LAYOUT_HAS_NEXT=0
    _SHQL_PILL_LAYOUT_NEXT_COL=-1

    if (( _total == 0 )); then
        return
    fi

    local _cursor="$_pl_left"

    # [<] scroll-left indicator
    if (( _scroll > 0 )); then
        _SHQL_PILL_LAYOUT_HAS_PREV=1
        _SHQL_PILL_LAYOUT_PREV_COL="$_cursor"
        _cursor=$(( _cursor + 4 ))  # "[<] "
    fi

    local _i _j=0
    for (( _i=_scroll; _i<_total; _i++ )); do
        _shql_where_filter_get "$_pl_ctx" "$_i"
        local _expr="${_SHQL_WHERE_RESULT_COL} ${_SHQL_WHERE_RESULT_OP}"
        [[ "$_SHQL_WHERE_RESULT_OP" != "IS NULL" && \
           "$_SHQL_WHERE_RESULT_OP" != "IS NOT NULL" ]] && \
            _expr+=" ${_SHQL_WHERE_RESULT_VAL}"

        # Space before this pill if not the first visible
        local _sep=$(( _j > 0 ? 1 : 0 ))
        # Available: right boundary minus cursor, minus separator, minus 4 for potential [>]
        local _more_after=$(( _total - _i - 1 ))
        local _avail=$(( _pl_right - _cursor - _sep - (_more_after > 0 ? 4 : 0) ))
        # Pill is "(expr x)" = expr + 4 chars; need at least 5 (1-char expr)
        local _max_expr=$(( _avail - 4 ))
        if (( _max_expr < 1 )); then
            # Can't fit even a minimal pill — show [>] and stop
            _SHQL_PILL_LAYOUT_HAS_NEXT=1
            _SHQL_PILL_LAYOUT_NEXT_COL=$(( _pl_right - 3 ))
            break
        fi

        # Truncate expr if needed
        if (( ${#_expr} > _max_expr )); then
            if (( _max_expr >= 3 )); then
                _expr="${_expr:0:$(( _max_expr - 3 ))}..."
            else
                _expr="${_expr:0:$_max_expr}"
            fi
        fi

        local _pill="(${_expr} x)"
        local _pill_col=$(( _cursor + _sep ))
        printf -v "_SHQL_PILL_LAYOUT_IDX_${_j}" '%d' "$_i"
        printf -v "_SHQL_PILL_LAYOUT_COL_${_j}" '%d' "$_pill_col"
        printf -v "_SHQL_PILL_LAYOUT_W_${_j}"   '%d' "${#_pill}"
        printf -v "_SHQL_PILL_LAYOUT_EXPR_${_j}" '%s' "$_pill"
        (( _j++ ))
        _cursor=$(( _pill_col + ${#_pill} ))

        # If more pills remain and they won't fit, mark [>] now
        if (( _more_after > 0 )); then
            local _avail_after=$(( _pl_right - _cursor - 1 - 4 ))
            if (( _avail_after < 5 )); then
                _SHQL_PILL_LAYOUT_HAS_NEXT=1
                _SHQL_PILL_LAYOUT_NEXT_COL=$(( _pl_right - 3 ))
                break
            fi
        fi
    done

    _SHQL_PILL_LAYOUT_N="$_j"

    # If all pills shown but there were more, ensure [>] is set
    if (( _j < _total - _scroll && ! _SHQL_PILL_LAYOUT_HAS_NEXT )); then
        _SHQL_PILL_LAYOUT_HAS_NEXT=1
        _SHQL_PILL_LAYOUT_NEXT_COL=$(( _pl_right - 3 ))
    fi
}

# ── _shql_where_pills_render ──────────────────────────────────────────────────
# Renders all visible filter pills into the framebuffer at the given row.
# Also calls _shql_where_pills_layout to populate layout globals.

_shql_where_pills_render() {
    local _pr_ctx="$1" _pr_row="$2" _pr_left="$3" _pr_right="$4"
    local _pr_style="$5" _pr_focus_style="${6:-}"
    local _gray="${SHELLFRAME_GRAY:-}"

    _shql_where_pills_layout "$_pr_ctx" "$_pr_left" "$_pr_right"

    if (( _SHQL_PILL_LAYOUT_TOTAL == 0 )); then
        return
    fi

    if (( _SHQL_PILL_LAYOUT_HAS_PREV )); then
        shellframe_fb_print "$_pr_row" "$_SHQL_PILL_LAYOUT_PREV_COL" \
            "[<]" "${_pr_style}${_gray}"
    fi

    local _j
    for (( _j=0; _j<_SHQL_PILL_LAYOUT_N; _j++ )); do
        local _jcol_v="_SHQL_PILL_LAYOUT_COL_${_j}"
        local _jw_v="_SHQL_PILL_LAYOUT_W_${_j}"
        local _jexpr_v="_SHQL_PILL_LAYOUT_EXPR_${_j}"
        local _jcol="${!_jcol_v}" _jw="${!_jw_v}" _jexpr="${!_jexpr_v}"
        # Body (everything except trailing " x)") is the edit target
        shellframe_fb_print "$_pr_row" "$_jcol" \
            "${_jexpr:0:$(( _jw - 3 ))}" "${_pr_style}${_pr_focus_style}"
        shellframe_fb_print "$_pr_row" "$(( _jcol + _jw - 3 ))" \
            " x)" "${_pr_style}${_gray}"
    done

    if (( _SHQL_PILL_LAYOUT_HAS_NEXT )); then
        shellframe_fb_print "$_pr_row" "$_SHQL_PILL_LAYOUT_NEXT_COL" \
            "[>]" "${_pr_style}${_gray}"
    fi
}

# ── _shql_where_open ──────────────────────────────────────────────────────────
# edit_idx=-1  → open blank form for a new filter
# edit_idx>=0  → pre-fill from stored filter at that index

_shql_where_open() {
    local _table="$1" _tab_ctx="$2" _edit_idx="${3:--1}"
    _SHQL_WHERE_TABLE="$_table"
    _SHQL_WHERE_TAB_CTX="$_tab_ctx"
    _SHQL_WHERE_EDIT_IDX="$_edit_idx"
    _SHQL_WHERE_FOCUS=0

    shellframe_field_init "${_SHQL_WHERE_CTX}_col"
    shellframe_field_init "${_SHQL_WHERE_CTX}_val"
    shellframe_field_init "${_SHQL_WHERE_CTX}_val2"

    if (( _edit_idx >= 0 )); then
        _shql_where_filter_get "$_tab_ctx" "$_edit_idx"
        shellframe_cur_init "${_SHQL_WHERE_CTX}_col" "$_SHQL_WHERE_RESULT_COL"
        _SHQL_WHERE_OP_IDX=0
        local _oi
        for (( _oi=0; _oi<${#_SHQL_WHERE_OPERATORS[@]}; _oi++ )); do
            if [[ "${_SHQL_WHERE_OPERATORS[$_oi]}" == "$_SHQL_WHERE_RESULT_OP" ]]; then
                _SHQL_WHERE_OP_IDX=$_oi
                break
            fi
        done
        case "$_SHQL_WHERE_RESULT_OP" in
            "BETWEEN"|"NOT BETWEEN")
                local _bv1 _bv2
                IFS=$'\t' read -r _bv1 _bv2 <<< "$_SHQL_WHERE_RESULT_VAL"
                shellframe_cur_init "${_SHQL_WHERE_CTX}_val"  "$_bv1"
                shellframe_cur_init "${_SHQL_WHERE_CTX}_val2" "$_bv2" ;;
            *)
                shellframe_cur_init "${_SHQL_WHERE_CTX}_val"  "$_SHQL_WHERE_RESULT_VAL"
                shellframe_cur_init "${_SHQL_WHERE_CTX}_val2" "" ;;
        esac
    else
        shellframe_cur_init "${_SHQL_WHERE_CTX}_col"  ""
        shellframe_cur_init "${_SHQL_WHERE_CTX}_val"  ""
        shellframe_cur_init "${_SHQL_WHERE_CTX}_val2" ""
        _SHQL_WHERE_OP_IDX=0
    fi

    _SHQL_WHERE_ACTIVE=1
}

# ── _shql_where_apply ────────────────────────────────────────────────────────
# Reads current field values and stores/updates/deletes the filter.
# IMPORTANT: _wapply_col and _wapply_val must NOT be declared local —
# shellframe_cur_text uses printf -v which sets globals; a local declaration
# here would shadow the global, making the variable always appear empty.

_shql_where_apply() {
    _wapply_col=""
    _wapply_val=""
    _wapply_val2=""
    shellframe_cur_text "${_SHQL_WHERE_CTX}_col"  _wapply_col
    shellframe_cur_text "${_SHQL_WHERE_CTX}_val"  _wapply_val
    local _op="${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}"

    # For BETWEEN/NOT BETWEEN, combine val and val2 with a tab separator
    if [[ "$_op" == "BETWEEN" || "$_op" == "NOT BETWEEN" ]]; then
        shellframe_cur_text "${_SHQL_WHERE_CTX}_val2" _wapply_val2
        _wapply_val="${_wapply_val}"$'\t'"${_wapply_val2}"
    fi

    # Trim leading/trailing whitespace from column name
    _wapply_col="${_wapply_col#"${_wapply_col%%[! ]*}"}"
    _wapply_col="${_wapply_col%"${_wapply_col##*[! ]}"}"

    if [[ -z "$_wapply_col" ]]; then
        # Empty column: delete the filter we were editing (if any); new = noop
        if (( _SHQL_WHERE_EDIT_IDX >= 0 )); then
            _shql_where_filter_del "$_SHQL_WHERE_TAB_CTX" "$_SHQL_WHERE_EDIT_IDX"
        fi
    elif (( _SHQL_WHERE_EDIT_IDX >= 0 )); then
        _shql_where_filter_set "$_SHQL_WHERE_TAB_CTX" "$_SHQL_WHERE_EDIT_IDX" \
            "$_wapply_col" "$_op" "$_wapply_val"
    else
        _shql_where_filter_add "$_SHQL_WHERE_TAB_CTX" \
            "$_wapply_col" "$_op" "$_wapply_val"
    fi
    _SHQL_BROWSER_GRID_OWNER_CTX=""
    _SHQL_WHERE_ACTIVE=0
}

# ── _shql_where_clear ────────────────────────────────────────────────────────
# Clears ALL filters for the given tab (or current tab if omitted).

_shql_where_clear() {
    local _tab_ctx="${1:-$_SHQL_WHERE_TAB_CTX}"
    printf -v "_SHQL_WHERE_APPLIED_${_tab_ctx}" '%s' ""
    _SHQL_BROWSER_GRID_OWNER_CTX=""
    _SHQL_WHERE_ACTIVE=0
}

# ── _shql_where_clear_one ────────────────────────────────────────────────────
# Removes the single filter at idx for the given tab.

_shql_where_clear_one() {
    local _tab_ctx="$1" _idx="$2"
    _shql_where_filter_del "$_tab_ctx" "$_idx"
    _SHQL_BROWSER_GRID_OWNER_CTX=""
    _SHQL_WHERE_ACTIVE=0
}

# ── _shql_where_on_key ────────────────────────────────────────────────────────

_shql_where_on_key() {
    local _key="$1"
    local _k_tab="${SHELLFRAME_KEY_TAB:-$'\t'}"
    local _k_stab="${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

    local _op="${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}"
    local _has_value=1
    [[ "$_op" == "IS NULL" || "$_op" == "IS NOT NULL" ]] && _has_value=0
    local _nfields=3
    if (( ! _has_value )); then
        _nfields=2
    elif [[ "$_op" == "BETWEEN" || "$_op" == "NOT BETWEEN" ]]; then
        _nfields=4
    fi

    case "$_key" in
        "$_k_tab"|"$_k_down")
            _SHQL_WHERE_FOCUS=$(( (_SHQL_WHERE_FOCUS + 1) % _nfields ))
            return 0 ;;
        "$_k_stab"|"$_k_up")
            _SHQL_WHERE_FOCUS=$(( (_SHQL_WHERE_FOCUS - 1 + _nfields) % _nfields ))
            return 0 ;;
        $'\r'|$'\n')
            _shql_where_apply
            shellframe_shell_mark_dirty
            return 0 ;;
        $'\033')
            _SHQL_WHERE_ACTIVE=0
            shellframe_shell_mark_dirty
            return 0 ;;
    esac

    # Operator field (focus 1): left/right cycle; all other keys consumed
    if (( _SHQL_WHERE_FOCUS == 1 )); then
        local _n=${#_SHQL_WHERE_OPERATORS[@]}
        if [[ "$_key" == "$_k_left" ]]; then
            _SHQL_WHERE_OP_IDX=$(( (_SHQL_WHERE_OP_IDX - 1 + _n) % _n ))
            shellframe_shell_mark_dirty
        elif [[ "$_key" == "$_k_right" ]]; then
            _SHQL_WHERE_OP_IDX=$(( (_SHQL_WHERE_OP_IDX + 1) % _n ))
            shellframe_shell_mark_dirty
        fi
        return 0
    fi

    # Value field hidden when op has no value — consume keystroke
    if (( _SHQL_WHERE_FOCUS == 2 && ! _has_value )); then
        return 0
    fi

    # Column (0), Value (2), or To-value (3): delegate to text field
    local _fctx
    case "$_SHQL_WHERE_FOCUS" in
        0) _fctx="${_SHQL_WHERE_CTX}_col" ;;
        3) _fctx="${_SHQL_WHERE_CTX}_val2" ;;
        *) _fctx="${_SHQL_WHERE_CTX}_val" ;;
    esac
    local _save_ctx="$SHELLFRAME_FIELD_CTX"
    SHELLFRAME_FIELD_CTX="$_fctx"
    shellframe_field_on_key "$_key"
    local _frc=$?
    SHELLFRAME_FIELD_CTX="$_save_ctx"
    if (( _frc == 2 )); then
        _shql_where_apply
        shellframe_shell_mark_dirty
        return 0
    fi
    return "$_frc"
}

# ── _shql_where_render ────────────────────────────────────────────────────────
# Renders a compact centered panel within the given content bounding box.

_shql_where_render() {
    local _bound_top="$1" _bound_left="$2" _bound_w="$3" _bound_h="$4"

    local _op="${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}"

    # BETWEEN needs an extra row for the "To" field; otherwise 7 rows suffice
    local _ph=7 _pw
    [[ "$_op" == "BETWEEN" || "$_op" == "NOT BETWEEN" ]] && _ph=8
    _pw=$(( _bound_w < 56 ? _bound_w : 56 ))
    (( _ph > _bound_h )) && _ph=$_bound_h
    local _pt=$(( _bound_top  + (_bound_h - _ph) / 2 ))
    local _pl=$(( _bound_left + (_bound_w - _pw) / 2 ))
    (( _pt < _bound_top  )) && _pt=$_bound_top
    (( _pl < _bound_left )) && _pl=$_bound_left

    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    _shql_where_filter_count "$_SHQL_WHERE_TAB_CTX"
    local _filter_count="$_SHQL_WHERE_RESULT_COUNT"
    local _edit_marker=""
    (( _SHQL_WHERE_EDIT_IDX >= 0 )) && \
        _edit_marker=" [$(( _SHQL_WHERE_EDIT_IDX + 1 ))/${_filter_count}]"
    SHELLFRAME_PANEL_TITLE="Filter — ${_SHQL_WHERE_TABLE}${_edit_marker}"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_pt" "$_pl" "$_pw" "$_ph"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_pt" "$_pl" "$_pw" "$_ph" _it _il _iw _ih

    local _pad_left=$(( _il + 1 ))
    local _inner_w=$(( _iw - 2 ))
    (( _inner_w < 4 )) && _inner_w=4

    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _bold="${SHELLFRAME_BOLD:-}"

    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    # Label column = "Operator" = 8 chars (longest label)
    local _lw=8
    local _field_left=$(( _pad_left + _lw + 2 ))
    local _field_w=$(( _inner_w - _lw - 2 ))
    (( _field_w < 4 )) && _field_w=4

    local _has_value=1
    [[ "$_op" == "IS NULL" || "$_op" == "IS NOT NULL" ]] && _has_value=0
    local _is_between=0
    [[ "$_op" == "BETWEEN" || "$_op" == "NOT BETWEEN" ]] && _is_between=1
    local _is_in=0
    [[ "$_op" == "IN" || "$_op" == "NOT IN" ]] && _is_in=1

    local _sty_norm="${_ibg}"
    local _sty_focus="${_ibg}${_bold}"

    local _save_ctx="$SHELLFRAME_FIELD_CTX"
    local _save_foc="${SHELLFRAME_FIELD_FOCUSED:-0}"
    local _save_fbg="${SHELLFRAME_FIELD_BG:-}"

    # ── Row 0: Column field ────────────────────────────────────────────────────
    local _lbl_col
    printf -v _lbl_col '%-*s' "$_lw" "Column"
    local _col_sty; (( _SHQL_WHERE_FOCUS == 0 )) && _col_sty="$_sty_focus" || _col_sty="$_sty_norm"
    shellframe_fb_print "$_it" "$_pad_left" "${_lbl_col}:" "$_col_sty"
    shellframe_fb_fill  "$_it" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
    SHELLFRAME_FIELD_CTX="${_SHQL_WHERE_CTX}_col"
    SHELLFRAME_FIELD_FOCUSED=$(( _SHQL_WHERE_FOCUS == 0 ? 1 : 0 ))
    SHELLFRAME_FIELD_BG="$_ibg"
    shellframe_field_render "$_it" "$_field_left" "$_field_w" 1
    SHELLFRAME_FIELD_CTX="$_save_ctx"
    SHELLFRAME_FIELD_FOCUSED="$_save_foc"
    SHELLFRAME_FIELD_BG="$_save_fbg"

    # ── Row 1: Operator cycling select ────────────────────────────────────────
    if (( _ih >= 2 )); then
        local _lbl_op
        printf -v _lbl_op '%-*s' "$_lw" "Operator"
        local _op_row=$(( _it + 1 ))
        if (( _SHQL_WHERE_FOCUS == 1 )); then
            shellframe_fb_print "$_op_row" "$_pad_left" "${_lbl_op}:" "$_sty_focus"
            shellframe_fb_fill  "$_op_row" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
            local _op_txt
            printf -v _op_txt '< %-*s>' "$(( _field_w - 3 ))" "$_op"
            shellframe_fb_print "$_op_row" "$_field_left" "$_op_txt" "${_ibg}${_focus_color}"
        else
            shellframe_fb_print "$_op_row" "$_pad_left" "${_lbl_op}:" "$_sty_norm"
            shellframe_fb_fill  "$_op_row" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
            shellframe_fb_print "$_op_row" "$_field_left" "$_op" "${_ibg}${_gray}"
        fi
    fi

    # ── Row 2: Value / From field ─────────────────────────────────────────────
    if (( _ih >= 3 )); then
        local _val_row=$(( _it + 2 ))
        if (( _has_value )); then
            # Label: "Values" for IN/NOT IN, "From" for BETWEEN/NOT BETWEEN, else "Value"
            local _val_lbl="Value"
            (( _is_in ))      && _val_lbl="Values"
            (( _is_between )) && _val_lbl="From"
            local _lbl_val
            printf -v _lbl_val '%-*s' "$_lw" "$_val_lbl"
            local _val_sty; (( _SHQL_WHERE_FOCUS == 2 )) && _val_sty="$_sty_focus" || _val_sty="$_sty_norm"
            shellframe_fb_print "$_val_row" "$_pad_left" "${_lbl_val}:" "$_val_sty"
            shellframe_fb_fill  "$_val_row" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
            SHELLFRAME_FIELD_CTX="${_SHQL_WHERE_CTX}_val"
            SHELLFRAME_FIELD_FOCUSED=$(( _SHQL_WHERE_FOCUS == 2 ? 1 : 0 ))
            SHELLFRAME_FIELD_BG="$_ibg"
            shellframe_field_render "$_val_row" "$_field_left" "$_field_w" 1
            SHELLFRAME_FIELD_CTX="$_save_ctx"
            SHELLFRAME_FIELD_FOCUSED="$_save_foc"
            SHELLFRAME_FIELD_BG="$_save_fbg"
            # Dim hint for IN: show "(comma separated)" after the field
            if (( _is_in && _SHQL_WHERE_FOCUS != 2 )); then
                local _hint_col=$(( _field_left + _field_w + 1 ))
                local _hint_avail=$(( _il + _iw - _hint_col - 1 ))
                if (( _hint_avail >= 10 )); then
                    shellframe_fb_print "$_val_row" "$_hint_col" \
                        "(comma sep)" "${_ibg}${_gray}"
                fi
            fi
        else
            local _lbl_val
            printf -v _lbl_val '%-*s' "$_lw" "Value"
            shellframe_fb_print "$_val_row" "$_pad_left" "${_lbl_val}:" "${_ibg}${_gray}"
            shellframe_fb_fill  "$_val_row" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
            shellframe_fb_print "$_val_row" "$_field_left" "(not applicable)" "${_ibg}${_gray}"
        fi
    fi

    # ── Row 3: "To" field for BETWEEN / NOT BETWEEN ───────────────────────────
    if (( _ih >= 4 && _is_between )); then
        local _lbl_to
        printf -v _lbl_to '%-*s' "$_lw" "To"
        local _to_row=$(( _it + 3 ))
        local _to_sty; (( _SHQL_WHERE_FOCUS == 3 )) && _to_sty="$_sty_focus" || _to_sty="$_sty_norm"
        shellframe_fb_print "$_to_row" "$_pad_left" "${_lbl_to}:" "$_to_sty"
        shellframe_fb_fill  "$_to_row" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
        SHELLFRAME_FIELD_CTX="${_SHQL_WHERE_CTX}_val2"
        SHELLFRAME_FIELD_FOCUSED=$(( _SHQL_WHERE_FOCUS == 3 ? 1 : 0 ))
        SHELLFRAME_FIELD_BG="$_ibg"
        shellframe_field_render "$_to_row" "$_field_left" "$_field_w" 1
        SHELLFRAME_FIELD_CTX="$_save_ctx"
        SHELLFRAME_FIELD_FOCUSED="$_save_foc"
        SHELLFRAME_FIELD_BG="$_save_fbg"
    fi

    # ── Hint row ──────────────────────────────────────────────────────────────
    if (( _ih >= 5 )); then
        shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
            " [<][>] Operator  Tab Next  Enter Apply  Esc Cancel" "${_ibg}${_gray}"
    fi
}
