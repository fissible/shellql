#!/usr/bin/env bash
# shellql/src/screens/where.sh — WHERE filter overlay
#
# REQUIRES: shellframe sourced (including input-field.sh), src/state.sh sourced.
#
# Renders a compact centered overlay with three fields:
#   Column   — free text (future: column-name dropdown)
#   Operator — cycling select with left/right arrows
#   Value    — free text (hidden for IS NULL / IS NOT NULL)
#
# Applied filter is stored per-tab:
#   _SHQL_WHERE_APPLIED_${tab_ctx}  — "col<TAB>op<TAB>val", or "" when cleared
#
# _shql_where_apply and _shql_where_clear reset _SHQL_BROWSER_GRID_OWNER_CTX
# to force a grid reload on the next render cycle.
#
# ── State globals ──────────────────────────────────────────────────────────────
#   _SHQL_WHERE_ACTIVE    — 0|1: overlay visible
#   _SHQL_WHERE_TABLE     — table name currently being filtered
#   _SHQL_WHERE_TAB_CTX   — tab context to store applied filter against
#   _SHQL_WHERE_CTX       — field context prefix
#   _SHQL_WHERE_FOCUS     — 0=column, 1=operator, 2=value
#   _SHQL_WHERE_OP_IDX    — index into _SHQL_WHERE_OPERATORS
#
# ── Public functions ───────────────────────────────────────────────────────────
#   _shql_where_open table tab_ctx     — open overlay (pre-fills from applied filter)
#   _shql_where_render t l w h         — draw overlay (call from content_render)
#   _shql_where_on_key key             — handle keys; returns 0 (handled) or 1
#   _shql_where_build_clause col op val out_var  — build SQL WHERE fragment
#   _shql_where_clear [tab_ctx]        — clear applied filter, force reload

_SHQL_WHERE_ACTIVE=0
_SHQL_WHERE_TABLE=""
_SHQL_WHERE_TAB_CTX=""
_SHQL_WHERE_CTX="where_form"
_SHQL_WHERE_FOCUS=0
_SHQL_WHERE_OP_IDX=0

_SHQL_WHERE_OPERATORS=("=" "<>" ">" "<" ">=" "<=" "LIKE" "NOT LIKE" "GLOB" "IS NULL" "IS NOT NULL")

# ── _shql_where_build_clause ──────────────────────────────────────────────────
# Builds a SQL WHERE fragment (without the "WHERE" keyword) into out_var.
# For IS NULL / IS NOT NULL the value argument is ignored.
# All other values are single-quoted; SQLite coerces via type affinity.

_shql_where_build_clause() {
    local _col="$1" _op="$2" _val="$3" _clause_out="$4"
    local _col_q="\"${_col//\"/\"\"}\""
    case "$_op" in
        "IS NULL"|"IS NOT NULL")
            printf -v "$_clause_out" '%s %s' "$_col_q" "$_op" ;;
        *)
            local _val_q="'${_val//\'/\'\'}'"
            printf -v "$_clause_out" '%s %s %s' "$_col_q" "$_op" "$_val_q" ;;
    esac
}

# ── _shql_where_pill_label ────────────────────────────────────────────────────
# Builds the display text for a filter pill from the stored filter string.
# Result is truncated to _max_len chars (minimum 6). Stored into _pout_var.

_shql_where_pill_label() {
    local _tab_ctx="$1" _max_len="$2" _pout_var="$3"
    local _applied_var="_SHQL_WHERE_APPLIED_${_tab_ctx}"
    if [[ -z "${!_applied_var:-}" ]]; then
        printf -v "$_pout_var" '%s' ""
        return
    fi
    local _wpc _wpo _wpv
    IFS=$'\t' read -r _wpc _wpo _wpv <<< "${!_applied_var}"
    local _expr="${_wpc} ${_wpo}"
    [[ "$_wpo" != "IS NULL" && "$_wpo" != "IS NOT NULL" ]] && _expr+=" ${_wpv}"
    if (( ${#_expr} > _max_len )); then
        _expr="${_expr:0:$(( _max_len - 3 ))}..."
    fi
    printf -v "$_pout_var" '%s' "$_expr"
}

# ── _shql_where_open ──────────────────────────────────────────────────────────
# _fresh=1 → always start with empty fields (for "add new filter" action)
# _fresh=0 (default) → pre-fill from applied filter (for "edit" action)

_shql_where_open() {
    local _table="$1" _tab_ctx="$2" _fresh="${3:-0}"
    _SHQL_WHERE_TABLE="$_table"
    _SHQL_WHERE_TAB_CTX="$_tab_ctx"
    _SHQL_WHERE_FOCUS=0

    shellframe_field_init "${_SHQL_WHERE_CTX}_col"
    shellframe_field_init "${_SHQL_WHERE_CTX}_val"

    local _applied_var="_SHQL_WHERE_APPLIED_${_tab_ctx}"
    if (( ! _fresh )) && [[ -n "${!_applied_var:-}" ]]; then
        local _wcol _wop _wval
        IFS=$'\t' read -r _wcol _wop _wval <<< "${!_applied_var}"
        shellframe_cur_init "${_SHQL_WHERE_CTX}_col" "$_wcol"
        _SHQL_WHERE_OP_IDX=0
        local _i
        for (( _i=0; _i<${#_SHQL_WHERE_OPERATORS[@]}; _i++ )); do
            if [[ "${_SHQL_WHERE_OPERATORS[$_i]}" == "$_wop" ]]; then
                _SHQL_WHERE_OP_IDX=$_i
                break
            fi
        done
        shellframe_cur_init "${_SHQL_WHERE_CTX}_val" "$_wval"
    else
        shellframe_cur_init "${_SHQL_WHERE_CTX}_col" ""
        _SHQL_WHERE_OP_IDX=0
        shellframe_cur_init "${_SHQL_WHERE_CTX}_val" ""
    fi

    _SHQL_WHERE_ACTIVE=1
}

# ── _shql_where_apply ────────────────────────────────────────────────────────
# Reads current field values, stores the applied filter, forces grid reload.
# Empty column → clears the filter.

_shql_where_apply() {
    # Use unique names — shellframe_cur_text uses printf -v which can't reach
    # a local declared in this function if the names clash.
    local _wapply_col _wapply_val
    shellframe_cur_text "${_SHQL_WHERE_CTX}_col" _wapply_col
    shellframe_cur_text "${_SHQL_WHERE_CTX}_val" _wapply_val
    local _op="${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}"

    # Trim column name
    _wapply_col="${_wapply_col#"${_wapply_col%%[! ]*}"}"
    _wapply_col="${_wapply_col%"${_wapply_col##*[! ]}"}"

    if [[ -z "$_wapply_col" ]]; then
        printf -v "_SHQL_WHERE_APPLIED_${_SHQL_WHERE_TAB_CTX}" '%s' ""
    else
        printf -v "_SHQL_WHERE_APPLIED_${_SHQL_WHERE_TAB_CTX}" '%s' \
            "${_wapply_col}"$'\t'"${_op}"$'\t'"${_wapply_val}"
    fi
    _SHQL_BROWSER_GRID_OWNER_CTX=""
    _SHQL_WHERE_ACTIVE=0
}

# ── _shql_where_clear ────────────────────────────────────────────────────────

_shql_where_clear() {
    local _tab_ctx="${1:-$_SHQL_WHERE_TAB_CTX}"
    printf -v "_SHQL_WHERE_APPLIED_${_tab_ctx}" '%s' ""
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
    local _nfields=$(( _has_value ? 3 : 2 ))

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

    # Value field is hidden when op has no value — consume keystroke
    if (( _SHQL_WHERE_FOCUS == 2 && ! _has_value )); then
        return 0
    fi

    # Column (0) or Value (2): delegate to text field
    local _fctx
    (( _SHQL_WHERE_FOCUS == 0 )) && _fctx="${_SHQL_WHERE_CTX}_col" \
                                  || _fctx="${_SHQL_WHERE_CTX}_val"
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

    # Panel: 7 rows tall, up to 56 cols wide, centered in bounding box
    local _ph=7 _pw
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
    local _applied_var="_SHQL_WHERE_APPLIED_${_SHQL_WHERE_TAB_CTX}"
    local _active_marker=""
    [[ -n "${!_applied_var:-}" ]] && _active_marker=" *"
    SHELLFRAME_PANEL_TITLE="Filter — ${_SHQL_WHERE_TABLE}${_active_marker}"
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

    local _op="${_SHQL_WHERE_OPERATORS[$_SHQL_WHERE_OP_IDX]}"
    local _has_value=1
    [[ "$_op" == "IS NULL" || "$_op" == "IS NOT NULL" ]] && _has_value=0

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

    # ── Row 2: Value field ────────────────────────────────────────────────────
    if (( _ih >= 3 )); then
        local _lbl_val
        printf -v _lbl_val '%-*s' "$_lw" "Value"
        local _val_row=$(( _it + 2 ))
        if (( _has_value )); then
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
        else
            shellframe_fb_print "$_val_row" "$_pad_left" "${_lbl_val}:" "${_ibg}${_gray}"
            shellframe_fb_fill  "$_val_row" "$(( _pad_left + _lw + 1 ))" 1 " " "$_ibg"
            shellframe_fb_print "$_val_row" "$_field_left" "(not applicable)" "${_ibg}${_gray}"
        fi
    fi

    # ── Hint row ──────────────────────────────────────────────────────────────
    if (( _ih >= 5 )); then
        shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
            " [<][>] Operator  Tab Next  Enter Apply  Esc Cancel" "${_ibg}${_gray}"
    fi
}
