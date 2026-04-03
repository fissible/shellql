#!/usr/bin/env bash
# shellql/src/screens/dml.sh — DML overlay: Insert, Update, Delete row
#
# REQUIRES: shellframe sourced (including form.sh and toast.sh), src/state.sh
#           sourced, src/screens/util.sh sourced.
#
# ── State globals ──────────────────────────────────────────────────────────────
#   _SHQL_DML_ACTIVE          — 0|1: whether the DML form overlay is visible
#   _SHQL_DML_MODE            — "insert" | "update"
#   _SHQL_DML_TABLE           — table name being modified
#   _SHQL_DML_COL_DEFS        — array of "name<TAB>type<TAB>flags"
#   _SHQL_DML_CTX             — form context name
#   _SHQL_DML_ROW_VALS        — row values snapshot (for delete WHERE clause)
#
# ── Public functions ──────────────────────────────────────────────────────────
#   _shql_dml_insert_open table           — open insert form
#   _shql_dml_update_open table row_idx   — open update form pre-filled
#   _shql_dml_delete_open table row_idx   — confirm and run DELETE
#   _shql_dml_render top left w h         — render form overlay
#   _shql_dml_on_key key                  — handle keys; returns 0|1
#
# ── SQL builders (pure functions, independently testable) ─────────────────────
#   _shql_dml_build_insert table col_defs_arr vals_arr out_sql
#   _shql_dml_build_update table col_defs_arr vals_arr out_sql
#   _shql_dml_build_delete table col_defs_arr vals_arr out_sql
#   _shql_dml_validate col_defs_arr vals_arr out_err

_SHQL_DML_ACTIVE=0
_SHQL_DML_MODE=""
_SHQL_DML_TABLE=""
_SHQL_DML_COL_DEFS=()
_SHQL_DML_CTX="dml_form"
_SHQL_DML_ROW_VALS=()
_SHQL_DML_DELETE_PK_LABEL=""
_SHQL_DML_DELETE_PK_VAL=""
_SHQL_DML_ROW_IDX=-1
_SHQL_DML_GRID_CTX=""
_SHQL_DML_CALLER="grid"
_SHQL_DML_INSPECTOR_RESTORE=0

# ── _shql_dml_quote_val ───────────────────────────────────────────────────────
# Produce a SQLite-safe quoted value string.
# Empty value + nullable → SQL NULL. Otherwise single-quoted with ' escaped.

_shql_dml_quote_val() {
    local _v="$1" _nullable="$2" _out="$3"
    if [[ -z "$_v" ]] && (( _nullable )); then
        printf -v "$_out" '%s' "NULL"
    else
        local _escaped="${_v//\'/\'\'}"
        printf -v "$_out" '%s' "'${_escaped}'"
    fi
}

# ── _shql_dml_validate ────────────────────────────────────────────────────────
# Validate that all NOT NULL non-PK fields have values.
# col_defs_arr and vals_arr are variable names (passed by name).

_shql_dml_validate() {
    local _defs_name="$1" _vals_name="$2" _err_out="$3"
    local _n _i
    eval "_n=\${#${_defs_name}[@]}"
    for (( _i=0; _i<_n; _i++ )); do
        local _def _flags _colname _val
        eval "_def=\"\${${_defs_name}[$_i]}\""
        _colname="${_def%%$'\t'*}"
        _flags="${_def##*$'\t'}"
        eval "_val=\"\${${_vals_name}[$_i]:-}\""
        [[ "$_flags" == *PK* ]] && continue
        if [[ "$_flags" == *NN* && -z "$_val" ]]; then
            printf -v "$_err_out" '%s' "'${_colname}' is required (NOT NULL)"
            return 1
        fi
    done
    printf -v "$_err_out" '%s' ""
    return 0
}

# ── _shql_dml_build_insert ────────────────────────────────────────────────────

_shql_dml_build_insert() {
    local _table="$1" _defs_name="$2" _vals_name="$3" _out="$4"
    local _n _i
    eval "_n=\${#${_defs_name}[@]}"
    local _cols="" _vals_str=""
    for (( _i=0; _i<_n; _i++ )); do
        local _def _flags _colname _val _nullable _qval
        eval "_def=\"\${${_defs_name}[$_i]}\""
        _colname="${_def%%$'\t'*}"
        _flags="${_def##*$'\t'}"
        eval "_val=\"\${${_vals_name}[$_i]:-}\""
        [[ "$_flags" == *PK* ]] && continue
        _nullable=1; [[ "$_flags" == *NN* ]] && _nullable=0
        _shql_dml_quote_val "$_val" "$_nullable" _qval
        if [[ -n "$_cols" ]]; then _cols="${_cols}, "; _vals_str="${_vals_str}, "; fi
        _cols="${_cols}\"${_colname}\""
        _vals_str="${_vals_str}${_qval}"
    done
    printf -v "$_out" 'INSERT INTO "%s" (%s) VALUES (%s)' \
        "${_table//\"/\"\"}" "$_cols" "$_vals_str"
}

# ── _shql_dml_build_update ────────────────────────────────────────────────────

_shql_dml_build_update() {
    local _table="$1" _defs_name="$2" _vals_name="$3" _out="$4"
    local _n _i
    eval "_n=\${#${_defs_name}[@]}"
    local _set_clause="" _where_clause=""
    for (( _i=0; _i<_n; _i++ )); do
        local _def _flags _colname _val _nullable _qval
        eval "_def=\"\${${_defs_name}[$_i]}\""
        _colname="${_def%%$'\t'*}"
        _flags="${_def##*$'\t'}"
        eval "_val=\"\${${_vals_name}[$_i]:-}\""
        _nullable=1; [[ "$_flags" == *NN* ]] && _nullable=0
        if [[ "$_flags" == *PK* ]]; then
            _shql_dml_quote_val "$_val" 0 _qval
            if [[ -n "$_where_clause" ]]; then _where_clause="${_where_clause} AND "; fi
            _where_clause="${_where_clause}\"${_colname}\" = ${_qval}"
        else
            _shql_dml_quote_val "$_val" "$_nullable" _qval
            if [[ -n "$_set_clause" ]]; then _set_clause="${_set_clause}, "; fi
            _set_clause="${_set_clause}\"${_colname}\" = ${_qval}"
        fi
    done
    printf -v "$_out" 'UPDATE "%s" SET %s WHERE %s' \
        "${_table//\"/\"\"}" "$_set_clause" "$_where_clause"
}

# ── _shql_dml_build_delete ────────────────────────────────────────────────────

_shql_dml_build_delete() {
    local _table="$1" _defs_name="$2" _vals_name="$3" _out="$4"
    local _n _i
    eval "_n=\${#${_defs_name}[@]}"
    local _where_clause=""
    for (( _i=0; _i<_n; _i++ )); do
        local _def _flags _colname _val _qval
        eval "_def=\"\${${_defs_name}[$_i]}\""
        _colname="${_def%%$'\t'*}"
        _flags="${_def##*$'\t'}"
        eval "_val=\"\${${_vals_name}[$_i]:-}\""
        [[ "$_flags" != *PK* ]] && continue
        _shql_dml_quote_val "$_val" 0 _qval
        if [[ -n "$_where_clause" ]]; then _where_clause="${_where_clause} AND "; fi
        _where_clause="${_where_clause}\"${_colname}\" = ${_qval}"
    done
    printf -v "$_out" 'DELETE FROM "%s" WHERE %s' \
        "${_table//\"/\"\"}" "$_where_clause"
}

# ── _shql_dml_load_cols ───────────────────────────────────────────────────────

_shql_dml_load_cols() {
    local _table="$1"
    _SHQL_DML_COL_DEFS=()
    local _line
    while IFS= read -r _line; do
        [[ -n "$_line" ]] && _SHQL_DML_COL_DEFS+=("$_line")
    done < <(shql_db_columns "$SHQL_DB_PATH" "$_table" 2>/dev/null)
}

# ── _shql_dml_setup_form_fields ───────────────────────────────────────────────
# Build SHELLFRAME_FORM_FIELDS from _SHQL_DML_COL_DEFS and call form_init.

_shql_dml_setup_form_fields() {
    SHELLFRAME_FORM_FIELDS=()
    local _i _n=${#_SHQL_DML_COL_DEFS[@]}
    for (( _i=0; _i<_n; _i++ )); do
        local _def="${_SHQL_DML_COL_DEFS[$_i]}"
        local _colname="${_def%%$'\t'*}"
        local _flags="${_def##*$'\t'}"
        local _label="$_colname"
        [[ "$_flags" == *NN* && "$_flags" != *PK* ]] && _label="${_label} *"
        local _ftype="text"
        [[ "$_flags" == *PK* ]] && _ftype="readonly"
        SHELLFRAME_FORM_FIELDS+=("${_label}"$'\t'"dml_f_${_i}"$'\t'"${_ftype}")
    done
    shellframe_form_init "$_SHQL_DML_CTX"
}

# ── _shql_dml_insert_open ─────────────────────────────────────────────────────

_shql_dml_insert_open() {
    local _table="$1"
    _SHQL_DML_TABLE="$_table"
    _SHQL_DML_MODE="insert"
    _shql_dml_load_cols "$_table"
    _shql_dml_setup_form_fields
    # Pre-fill PK fields with "(auto)"
    local _i _n=${#_SHQL_DML_COL_DEFS[@]}
    for (( _i=0; _i<_n; _i++ )); do
        local _flags="${_SHQL_DML_COL_DEFS[$_i]##*$'\t'}"
        [[ "$_flags" == *PK* ]] && shellframe_form_set_value "$_SHQL_DML_CTX" "$_i" "(auto)"
    done
    shellframe_form_set_error "$_SHQL_DML_CTX" ""
    _SHQL_DML_ACTIVE=1
}

# ── _shql_dml_update_open ─────────────────────────────────────────────────────

_shql_dml_update_open() {
    local _table="$1" _row_idx="$2"
    _SHQL_DML_TABLE="$_table"
    _SHQL_DML_MODE="update"
    _SHQL_DML_ROW_IDX="$_row_idx"
    _SHQL_DML_GRID_CTX="${_SHQL_TABS_CTX[${_SHQL_TAB_ACTIVE:-0}]:-}_grid"
    _SHQL_DML_CALLER="grid"
    _shql_dml_load_cols "$_table"
    _shql_dml_setup_form_fields
    # Pre-fill all fields from current grid row
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    local _i
    for (( _i=0; _i<_ncols; _i++ )); do
        local _idx=$(( _row_idx * _ncols + _i ))
        local _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        shellframe_form_set_value "$_SHQL_DML_CTX" "$_i" "$_val"
    done
    shellframe_form_set_error "$_SHQL_DML_CTX" ""
    _SHQL_DML_ACTIVE=1
}

# ── _shql_dml_delete_open ─────────────────────────────────────────────────────

_shql_dml_delete_open() {
    local _table="$1" _row_idx="$2"
    _shql_dml_load_cols "$_table"

    # Snapshot current row values for WHERE clause
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_DML_ROW_VALS=()
    local _i
    for (( _i=0; _i<_ncols; _i++ )); do
        local _idx=$(( _row_idx * _ncols + _i ))
        _SHQL_DML_ROW_VALS+=("${SHELLFRAME_GRID_DATA[$_idx]:-}")
    done

    # Find PK column for the confirm message
    local _pk_label="" _pk_val=""
    for (( _i=0; _i<${#_SHQL_DML_COL_DEFS[@]}; _i++ )); do
        local _def="${_SHQL_DML_COL_DEFS[$_i]}"
        local _colname="${_def%%$'\t'*}"
        local _flags="${_def##*$'\t'}"
        if [[ "$_flags" == *PK* ]]; then
            _pk_label="$_colname"
            _pk_val="${_SHQL_DML_ROW_VALS[$_i]:-}"
            break
        fi
    done

    if [[ -z "$_pk_label" ]]; then
        shellframe_toast_show "Cannot delete: no primary key" error
        shellframe_shell_mark_dirty
        return 0
    fi

    _SHQL_DML_TABLE="$_table"
    _SHQL_DML_MODE="delete"
    _SHQL_DML_DELETE_PK_LABEL="$_pk_label"
    _SHQL_DML_DELETE_PK_VAL="$_pk_val"
    _SHQL_DML_ACTIVE=1
}

# ── _shql_dml_truncate_open ───────────────────────────────────────────────────

_shql_dml_truncate_open() {
    local _table="$1"
    _SHQL_DML_TABLE="$_table"
    _SHQL_DML_MODE="truncate"
    _SHQL_DML_ACTIVE=1
}

# ── _shql_dml_execute_truncate ────────────────────────────────────────────────

_shql_dml_execute_truncate() {
    local _sql
    printf -v _sql 'DELETE FROM "%s"' "${_SHQL_DML_TABLE//\"/\"\"}"
    local _err_file
    _err_file=$(mktemp)
    shql_db_query "$SHQL_DB_PATH" "$_sql" >"$_err_file" 2>&1
    local _qrc=$?
    if (( _qrc == 0 )); then
        shellframe_toast_show "Table truncated" success
        _shql_dml_refresh_grid "$_SHQL_DML_TABLE"
    else
        local _errmsg; _errmsg=$(cat "$_err_file")
        shellframe_toast_show "Truncate failed: ${_errmsg}" error
        _SHQL_DML_ACTIVE=0
    fi
    rm -f "$_err_file"
}

# ── _shql_dml_execute_delete ──────────────────────────────────────────────────

_shql_dml_execute_delete() {
    local _sql=""
    _shql_dml_build_delete "$_SHQL_DML_TABLE" _SHQL_DML_COL_DEFS _SHQL_DML_ROW_VALS _sql
    local _err_file
    _err_file=$(mktemp)
    shql_db_query "$SHQL_DB_PATH" "$_sql" >"$_err_file" 2>&1
    local _qrc=$?
    if (( _qrc == 0 )); then
        shellframe_toast_show "Row deleted" success
        _shql_dml_refresh_grid "$_SHQL_DML_TABLE"
    else
        local _errmsg; _errmsg=$(cat "$_err_file")
        shellframe_toast_show "Delete failed: ${_errmsg}" error
        _SHQL_DML_ACTIVE=0
    fi
    rm -f "$_err_file"
}

# ── _shql_dml_refresh_grid ────────────────────────────────────────────────────

_shql_dml_refresh_grid() {
    # Restore inspector if the form was opened from there
    if [[ "$_SHQL_DML_CALLER" == "inspector" ]]; then
        _SHQL_INSPECTOR_ACTIVE=1
        _SHQL_INSPECTOR_ROW_IDX="$_SHQL_DML_ROW_IDX"
        _SHQL_DML_INSPECTOR_RESTORE=1
    fi
    # Force reload on next render by clearing the grid owner context
    _SHQL_BROWSER_GRID_OWNER_CTX=""
    _SHQL_DML_ACTIVE=0
}

# ── _shql_dml_submit ──────────────────────────────────────────────────────────

_shql_dml_submit() {
    local _vals=()
    shellframe_form_values "$_SHQL_DML_CTX" _vals

    local _err=""
    _shql_dml_validate _SHQL_DML_COL_DEFS _vals _err
    if [[ -n "$_err" ]]; then
        shellframe_form_set_error "$_SHQL_DML_CTX" "$_err"
        shellframe_shell_mark_dirty
        return 0
    fi

    local _sql=""
    if [[ "$_SHQL_DML_MODE" == "insert" ]]; then
        _shql_dml_build_insert "$_SHQL_DML_TABLE" _SHQL_DML_COL_DEFS _vals _sql
    else
        _shql_dml_build_update "$_SHQL_DML_TABLE" _SHQL_DML_COL_DEFS _vals _sql
    fi

    local _err_file
    _err_file=$(mktemp)
    shql_db_query "$SHQL_DB_PATH" "$_sql" >"$_err_file" 2>&1
    local _qrc=$?
    if (( _qrc == 0 )); then
        local _verb="inserted"; [[ "$_SHQL_DML_MODE" == "update" ]] && _verb="updated"
        shellframe_toast_show "Row ${_verb}" success
        _shql_dml_refresh_grid "$_SHQL_DML_TABLE"
    else
        local _errmsg; _errmsg=$(cat "$_err_file")
        shellframe_form_set_error "$_SHQL_DML_CTX" "$_errmsg"
        shellframe_shell_mark_dirty
    fi
    rm -f "$_err_file"
}

# ── _shql_dml_on_key ──────────────────────────────────────────────────────────

_shql_dml_on_key() {
    local _key="$1"

    if [[ "$_key" == $'\033' ]]; then
        _SHQL_DML_ACTIVE=0
        shellframe_shell_mark_dirty
        return 0
    fi

    # Delete confirmation: d/y executes, n cancels; all other keys swallowed
    if [[ "$_SHQL_DML_MODE" == "delete" ]]; then
        if [[ "$_key" == 'd' || "$_key" == 'y' ]]; then
            _shql_dml_execute_delete
        else
            _SHQL_DML_ACTIVE=0
        fi
        shellframe_shell_mark_dirty
        return 0
    fi

    # Truncate confirmation: T/y executes, all other keys cancel
    if [[ "$_SHQL_DML_MODE" == "truncate" ]]; then
        if [[ "$_key" == 'T' || "$_key" == 'y' ]]; then
            _shql_dml_execute_truncate
        else
            _SHQL_DML_ACTIVE=0
        fi
        shellframe_shell_mark_dirty
        return 0
    fi

    shellframe_form_on_key "$_SHQL_DML_CTX" "$_key"
    local _frc=$?
    if (( _frc == 2 )); then
        _shql_dml_submit
        shellframe_shell_mark_dirty
        return 0
    elif (( _frc == 0 )); then
        shellframe_shell_mark_dirty
        return 0
    fi
    return 1
}

# ── _shql_dml_render ──────────────────────────────────────────────────────────

_shql_dml_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Draw panel border (same inline-popover style as the row inspector)
    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    local _title=""
    case "$_SHQL_DML_MODE" in
        insert)   _title="Insert Row — ${_SHQL_DML_TABLE}" ;;
        update)   _title="Edit Row — ${_SHQL_DML_TABLE}" ;;
        truncate) _title="Truncate Table — ${_SHQL_DML_TABLE}" ;;
    esac
    SHELLFRAME_PANEL_TITLE="$_title"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    # Clear inner area
    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    local _gray="${SHELLFRAME_GRAY:-}"

    if [[ "$_SHQL_DML_MODE" == "delete" ]]; then
        # Confirmation message centred vertically in the inner area
        local _mid=$(( _it + _ih / 2 ))
        local _pk_line="${_SHQL_DML_DELETE_PK_LABEL} = ${_SHQL_DML_DELETE_PK_VAL}"
        shellframe_fb_print "$(( _mid - 1 ))" "$(( _il + 2 ))" \
            "Are you sure you want to delete this row?" "${_ibg}"
        shellframe_fb_print "$_mid" "$(( _il + 2 ))" "$_pk_line" "${_ibg}${_gray}"
        shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
            " [d] Confirm  [Esc] Cancel" "${_ibg}${_gray}"
        return 0
    fi

    if [[ "$_SHQL_DML_MODE" == "truncate" ]]; then
        local _mid=$(( _it + _ih / 2 ))
        shellframe_fb_print "$(( _mid - 1 ))" "$(( _il + 2 ))" \
            "Delete ALL rows from '${_SHQL_DML_TABLE}'?" "${_ibg}"
        shellframe_fb_print "$_mid" "$(( _il + 2 ))" \
            "This cannot be undone." "${_ibg}${_gray}"
        shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
            " [T] Confirm  [Esc] Cancel" "${_ibg}${_gray}"
        return 0
    fi

    # Hint row at bottom of inner area
    shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" " Tab next  Enter submit  Esc cancel" "${_ibg}${_gray}"

    # Compute type hint column width from column definitions
    local _type_col_w=0 _ti
    local _n_cols=${#_SHQL_DML_COL_DEFS[@]}
    for (( _ti=0; _ti<_n_cols; _ti++ )); do
        local _cdef="${_SHQL_DML_COL_DEFS[$_ti]}"
        local _ctype="${_cdef#*$'\t'}"
        _ctype="${_ctype%%$'\t'*}"
        local _cflags="${_cdef##*$'\t'}"
        local _hint="$_ctype"
        [[ "$_cflags" == *PK* ]] && _hint="${_hint} PK"
        [[ "$_cflags" == *NN* && "$_cflags" != *PK* ]] && _hint="${_hint} NN"
        (( ${#_hint} > _type_col_w )) && _type_col_w=${#_hint}
    done
    # Reserve space: type hint + 2 padding
    local _type_reserve=0
    if (( _type_col_w > 0 && _iw > 30 )); then
        _type_reserve=$(( _type_col_w + 2 ))
    fi

    # Form fills inner area minus hint row, minus type column
    local _form_inner_h=$(( _ih - 1 ))
    (( _form_inner_h < 1 )) && _form_inner_h=1
    local _form_w=$(( _iw - _type_reserve ))
    SHELLFRAME_FORM_BG="$_ibg"
    shellframe_form_render "$_SHQL_DML_CTX" "$_it" "$_il" "$_form_w" "$_form_inner_h"
    SHELLFRAME_FORM_BG=""

    # Render type hints to the right of each visible field row
    if (( _type_reserve > 0 )); then
        local _type_left=$(( _il + _form_w + 1 ))
        local _scroll_var="_SHELLFRAME_FORM_${_SHQL_DML_CTX}_SCROLL"
        local _form_scroll="${!_scroll_var:-0}"
        for (( _ti=0; _ti<_form_inner_h && _ti + _form_scroll < _n_cols; _ti++ )); do
            local _fi=$(( _form_scroll + _ti ))
            local _cdef="${_SHQL_DML_COL_DEFS[$_fi]}"
            local _ctype="${_cdef#*$'\t'}"
            _ctype="${_ctype%%$'\t'*}"
            local _cflags="${_cdef##*$'\t'}"
            local _hint="$_ctype"
            [[ "$_cflags" == *PK* ]] && _hint="${_hint} PK"
            [[ "$_cflags" == *NN* && "$_cflags" != *PK* ]] && _hint="${_hint} NN"
            shellframe_fb_print "$(( _it + _ti ))" "$_type_left" "$_hint" "${_ibg}${_gray}"
        done
    fi
}
