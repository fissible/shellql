#!/usr/bin/env bash
# shellql/src/screens/export.sh — Export overlay (CSV / SQL dump)
#
# Overlay pattern: _SHQL_EXPORT_ACTIVE=1 routes all content key events here
# and adds this panel on top of the frozen grid in _shql_TABLE_content_render.
#
# CSV export for data tabs: re-queries with 2× fetch_limit using the cached
# WHERE/ORDER from _SHQL_QUERY_WHERE_<ctx> / _SHQL_QUERY_ORDER_<ctx>.
# CSV export for query tabs: dumps the already-loaded SHELLFRAME_GRID_DATA.
# SQL dump: delegates to `sqlite3 <db> .dump`.

# ── State globals ─────────────────────────────────────────────────────────────

_SHQL_EXPORT_ACTIVE=0       # 1 while the export overlay is showing
_SHQL_EXPORT_FORMAT="csv"   # "csv" | "sql"
_SHQL_EXPORT_CTX=""         # tab ctx active when export was opened
_SHQL_EXPORT_TABLE=""       # table name; empty for query tabs
_SHQL_EXPORT_STATUS=""      # "" | "ok:<path>" | "err:<message>"

# Field context name used by shellframe_field_* for the path input
_SHQL_EXPORT_FIELD_CTX="export_path"

# ── _shql_csv_quote_field <field> ─────────────────────────────────────────────
# Prints the RFC 4180-quoted representation of <field>.
# Fields that contain comma, double-quote, newline, or carriage-return are
# wrapped in double-quotes; embedded double-quotes are doubled.
# Fields that need no quoting are printed as-is.

_shql_csv_quote_field() {
    local _f="$1"
    case "$_f" in
        *,* | *'"'* | *$'\n'* | *$'\r'*)
            printf '"%s"' "${_f//\"/\"\"}" ;;
        *)
            printf '%s' "$_f" ;;
    esac
}

# ── _shql_export_default_path ─────────────────────────────────────────────────
# Sets _out_var to the default export path for the current format/table.

_shql_export_default_path() {
    local _out_var="$1"
    local _dir="${HOME}/Downloads"
    local _path
    if [[ "$_SHQL_EXPORT_FORMAT" == "sql" ]]; then
        local _base
        _base="$(basename "$SHQL_DB_PATH" .sqlite)"
        _base="$(basename "$_base" .db)"
        _path="${_dir}/${_base}_dump.sql"
    else
        if [[ -n "$_SHQL_EXPORT_TABLE" ]]; then
            _path="${_dir}/${_SHQL_EXPORT_TABLE}.csv"
        else
            _path="${_dir}/query.csv"
        fi
    fi
    printf -v "$_out_var" '%s' "$_path"
}

# ── _shql_export_open ─────────────────────────────────────────────────────────
# Open the export overlay for the active tab.

_shql_export_open() {
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0
    _SHQL_EXPORT_ACTIVE=1
    _SHQL_EXPORT_STATUS=""
    _SHQL_EXPORT_FORMAT="csv"
    _SHQL_EXPORT_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    _SHQL_EXPORT_TABLE="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]:-}"

    # Initialise path field with default path
    shellframe_field_init "$_SHQL_EXPORT_FIELD_CTX"
    local _default_path
    _shql_export_default_path _default_path
    shellframe_cur_set "$_SHQL_EXPORT_FIELD_CTX" "$_default_path"
}

# ── _shql_export_close ────────────────────────────────────────────────────────
# Dismiss the export overlay without exporting.

_shql_export_close() {
    _SHQL_EXPORT_ACTIVE=0
    _SHQL_EXPORT_STATUS=""
}

# ── _shql_export_on_key <key> ─────────────────────────────────────────────────
# Handle key events while the export overlay is active.
# Returns 0 to consume, 1 to pass through.

_shql_export_on_key() {
    local _key="$1"
    local _k_enter="${SHELLFRAME_KEY_ENTER:-$'\n'}"
    local _k_tab=$'\t'

    case "$_key" in
        $'\033')            # Esc — cancel
            _shql_export_close
            shellframe_shell_mark_dirty
            return 0 ;;
        "$_k_tab"|$'\t')   # Tab — toggle format + update default path in field
            if [[ "$_SHQL_EXPORT_FORMAT" == "csv" ]]; then
                _SHQL_EXPORT_FORMAT="sql"
            else
                _SHQL_EXPORT_FORMAT="csv"
            fi
            # Reset path field to default for the new format
            local _new_path
            _shql_export_default_path _new_path
            shellframe_cur_set "$_SHQL_EXPORT_FIELD_CTX" "$_new_path"
            shellframe_shell_mark_dirty
            return 0 ;;
        "$_k_enter"|$'\r') # Enter — execute export
            local _path
            shellframe_cur_text "$_SHQL_EXPORT_FIELD_CTX" _path
            _path="${_path:-}"
            if [[ -z "$_path" ]]; then
                _SHQL_EXPORT_STATUS="err:Path cannot be empty"
                shellframe_shell_mark_dirty
                return 0
            fi
            if [[ "$_SHQL_EXPORT_FORMAT" == "sql" ]]; then
                _shql_export_do_sql_dump "$_path"
            else
                _shql_export_do_csv "$_path"
            fi
            shellframe_shell_mark_dirty
            return 0 ;;
    esac

    # All other keys → field widget
    local _save_ctx="$SHELLFRAME_FIELD_CTX"
    SHELLFRAME_FIELD_CTX="$_SHQL_EXPORT_FIELD_CTX"
    shellframe_field_on_key "$_key"
    local _rc=$?
    SHELLFRAME_FIELD_CTX="$_save_ctx"
    shellframe_shell_mark_dirty
    return $_rc
}

# ── _shql_export_do_csv <path> ────────────────────────────────────────────────
# Write RFC 4180 CSV to <path>.
# Data tabs: re-query with 2 × fetch_limit using cached WHERE/ORDER.
# Query tabs: dump already-loaded SHELLFRAME_GRID_DATA.

_shql_export_do_csv() {
    local _path="$1"

    # Ensure parent directory exists
    local _dir
    _dir="$(dirname "$_path")"
    if [[ ! -d "$_dir" ]]; then
        _SHQL_EXPORT_STATUS="err:Directory does not exist: ${_dir}"
        return 1
    fi

    local _tmpfile
    _tmpfile=$(mktemp) || {
        _SHQL_EXPORT_STATUS="err:Could not create temp file"
        return 1
    }

    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    local _nrows="${SHELLFRAME_GRID_ROWS:-0}"

    # ── Header row ────────────────────────────────────────────────────────────
    local _hdr_line="" _c _cell_q
    for (( _c=0; _c<_ncols; _c++ )); do
        _cell_q="$(_shql_csv_quote_field "${SHELLFRAME_GRID_HEADERS[$_c]:-}")"
        if (( _c == 0 )); then
            _hdr_line="${_cell_q}"
        else
            _hdr_line+=",${_cell_q}"
        fi
    done
    printf '%s\r\n' "$_hdr_line" >> "$_tmpfile"

    # ── Data rows ─────────────────────────────────────────────────────────────
    local _type="${_SHQL_TABS_TYPE[$_SHQL_TAB_ACTIVE]:-}"

    if [[ "$_type" == "data" && -n "$_SHQL_EXPORT_TABLE" ]]; then
        # Data tab: re-query with 2 × fetch_limit
        local _fetch_limit
        _fetch_limit=$(shql_config_get_fetch_limit)
        local _export_limit=$(( _fetch_limit * 2 ))

        # Retrieve cached WHERE/ORDER for this ctx
        local _where_var="_SHQL_QUERY_WHERE_${_SHQL_EXPORT_CTX}"
        local _order_var="_SHQL_QUERY_ORDER_${_SHQL_EXPORT_CTX}"
        local _where="${!_where_var:-}"
        local _order="${!_order_var:-}"

        local _row=() _ri=0 _line
        while IFS=$'\x1f' read -r -a _row; do
            [[ ${#_row[@]} -eq 0 ]] && continue
            (( _ri == 0 )) && { (( _ri++ )); continue; }  # skip header row from db
            local _data_line="" _rc
            for (( _c=0; _c<_ncols; _c++ )); do
                _cell_q="$(_shql_csv_quote_field "${_row[$_c]:-}")"
                if (( _c == 0 )); then
                    _data_line="${_cell_q}"
                else
                    _data_line+=",${_cell_q}"
                fi
            done
            printf '%s\r\n' "$_data_line" >> "$_tmpfile"
            (( _ri++ ))
        done < <(shql_db_fetch "$SHQL_DB_PATH" "$_SHQL_EXPORT_TABLE" \
                    "$_export_limit" "0" "$_where" "$_order" 2>/dev/null)
    else
        # Query tab or schema tab: dump loaded SHELLFRAME_GRID_DATA
        local _r
        for (( _r=0; _r<_nrows; _r++ )); do
            local _data_line=""
            for (( _c=0; _c<_ncols; _c++ )); do
                local _idx=$(( _r * _ncols + _c ))
                _cell_q="$(_shql_csv_quote_field "${SHELLFRAME_GRID_DATA[$_idx]:-}")"
                if (( _c == 0 )); then
                    _data_line="${_cell_q}"
                else
                    _data_line+=",${_cell_q}"
                fi
            done
            printf '%s\r\n' "$_data_line" >> "$_tmpfile"
        done
    fi

    # Atomically move to final destination
    if mv "$_tmpfile" "$_path" 2>/dev/null; then
        _SHQL_EXPORT_STATUS="ok:${_path}"
        shellframe_toast_show "Exported to ${_path}" 3000
        _shql_export_close
    else
        rm -f "$_tmpfile"
        _SHQL_EXPORT_STATUS="err:Could not write to: ${_path}"
    fi
}

# ── _shql_export_do_sql_dump <path> ──────────────────────────────────────────
# Write a full sqlite3 .dump to <path>.

_shql_export_do_sql_dump() {
    local _path="$1"

    local _dir
    _dir="$(dirname "$_path")"
    if [[ ! -d "$_dir" ]]; then
        _SHQL_EXPORT_STATUS="err:Directory does not exist: ${_dir}"
        return 1
    fi

    if sqlite3 "$SHQL_DB_PATH" .dump > "$_path" 2>/dev/null; then
        _SHQL_EXPORT_STATUS="ok:${_path}"
        shellframe_toast_show "Exported to ${_path}" 3000
        _shql_export_close
    else
        rm -f "$_path"
        _SHQL_EXPORT_STATUS="err:sqlite3 dump failed"
    fi
}

# ── _shql_export_render <top> <left> <width> <height> ────────────────────────
# Draw the export overlay panel centered in the content region.

_shql_export_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Panel dimensions: 7 inner rows, up to 60 cols wide (but ≤ content width)
    local _panel_w=$(( _width < 62 ? _width : 62 ))
    local _panel_h=9   # 2 border + 7 inner rows
    local _panel_left=$(( _left + (_width - _panel_w) / 2 ))
    local _panel_top=$(( _top + (_height - _panel_h) / 2 ))

    # Draw panel border
    local _cbg="${SHQL_THEME_CONTENT_BG:-}"
    local _focus_color="${SHQL_THEME_QUERY_PANEL_COLOR:-}"
    SHELLFRAME_PANEL_CELL_ATTRS="${_cbg}${_focus_color}"
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    SHELLFRAME_PANEL_TITLE=" Export "
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h"
    SHELLFRAME_PANEL_CELL_ATTRS=""

    local _it _il _iw _ih
    shellframe_panel_inner "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h" \
        _it _il _iw _ih

    # Clear inner area
    local _ibg="${SHQL_THEME_EDITOR_FOCUSED_BG:-$_cbg}"
    local _ir
    for (( _ir=0; _ir<_ih; _ir++ )); do
        shellframe_fb_fill "$(( _it + _ir ))" "$_il" "$_iw" " " "$_ibg"
    done

    local _gray="${SHELLFRAME_GRAY:-}"
    local _inv="${SHELLFRAME_REVERSE:-}"

    # Row 0: Format selector  [ CSV ]  [ SQL Dump ]
    local _fmt_row="$_it"
    local _csv_label=" CSV "
    local _sql_label=" SQL Dump "
    local _csv_style="${_ibg}"
    local _sql_style="${_ibg}"
    if [[ "$_SHQL_EXPORT_FORMAT" == "csv" ]]; then
        _csv_style="${_ibg}${_inv}"
    else
        _sql_style="${_ibg}${_inv}"
    fi
    shellframe_fb_print "$_fmt_row" "$(( _il + 1 ))" "Format:" "${_ibg}${_gray}"
    shellframe_fb_print "$_fmt_row" "$(( _il + 9 ))" "$_csv_label" "$_csv_style"
    shellframe_fb_print "$_fmt_row" "$(( _il + 9 + ${#_csv_label} + 1 ))" "$_sql_label" "$_sql_style"

    # Row 1: blank separator
    # Row 2: path label
    shellframe_fb_print "$(( _it + 2 ))" "$(( _il + 1 ))" "Path:" "${_ibg}${_gray}"

    # Row 3: path field
    local _field_top=$(( _it + 3 ))
    local _field_left=$(( _il + 1 ))
    local _field_w=$(( _iw - 2 ))
    (( _field_w < 1 )) && _field_w=1
    local _save_ctx="$SHELLFRAME_FIELD_CTX"
    SHELLFRAME_FIELD_CTX="$_SHQL_EXPORT_FIELD_CTX"
    SHELLFRAME_FIELD_FOCUSED=1
    SHELLFRAME_FIELD_BG="$_ibg"
    shellframe_field_render "$_field_top" "$_field_left" "$_field_w" 1
    SHELLFRAME_FIELD_CTX="$_save_ctx"
    SHELLFRAME_FIELD_FOCUSED=0
    SHELLFRAME_FIELD_BG=""

    # Row 4: blank

    # Row 5: status / hint
    local _status_row=$(( _it + 5 ))
    if [[ "$_SHQL_EXPORT_STATUS" == err:* ]]; then
        local _err_msg="${_SHQL_EXPORT_STATUS#err:}"
        shellframe_fb_print "$_status_row" "$(( _il + 1 ))" "$_err_msg" \
            "${_ibg}${SHQL_THEME_ERROR_COLOR:-}"
    fi

    # Row 6 (last inner row): key hints
    shellframe_fb_print "$(( _it + _ih - 1 ))" "$_il" \
        " Tab format  Enter export  Esc cancel" "${_ibg}${_gray}"
}
