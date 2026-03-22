#!/usr/bin/env bash
# shellql/src/cli.sh — CLI argument parsing and non-TUI output formatting
#
# Provides:
#   shql_cli_parse "$@"         — parse args, set _SHQL_CLI_* globals
#   shql_cli_format_table <tsv> — print MySQL-style box table to stdout

[[ -n "${_SHQL_CLI_LOADED:-}" ]] && return 0
_SHQL_CLI_LOADED=1

# ── Globals (set by shql_cli_parse) ───────────────────────────────────────────

_SHQL_CLI_MODE=""
_SHQL_CLI_DB=""
_SHQL_CLI_TABLE=""
_SHQL_CLI_SQL=""
_SHQL_CLI_PORCELAIN=0

# ── shql_cli_parse ────────────────────────────────────────────────────────────
#
# Parse $@ and set _SHQL_CLI_* globals. All globals are reset at the top of
# each call, so successive calls produce a clean state.
#
# Mode resolution order (first match wins):
#   1. First positional = "databases" (no db yet) → databases
#   2. -q <sql> flag                              → query-out
#   3. Stdin is a pipe (FIFO) and no -q            → pipe (reads stdin)
#   4. --query flag + db path                     → query-tui
#   5. Two positionals (db + table)               → table
#   6. One positional (db)                        → open
#   7. No args                                    → welcome
#
# Returns 1 and prints to stderr on: unknown flag, -q without SQL,
#   --query without db path, pipe mode without db path.

shql_cli_parse() {
    # Reset all globals
    _SHQL_CLI_MODE="welcome"
    _SHQL_CLI_DB=""
    _SHQL_CLI_TABLE=""
    _SHQL_CLI_SQL=""
    _SHQL_CLI_PORCELAIN=0

    local _pos=()
    local _has_q=0
    local _q_sql=""
    local _has_query=0

    # Single-pass argument scan: collect flags and positionals
    while (( $# > 0 )); do
        case "$1" in
            --porcelain)
                _SHQL_CLI_PORCELAIN=1
                shift ;;
            -q)
                if (( $# < 2 )); then
                    printf 'error: -q requires a SQL argument\n' >&2
                    return 1
                fi
                _has_q=1
                _q_sql="$2"
                shift 2 ;;
            --query)
                _has_query=1
                shift ;;
            -*)
                printf 'error: unknown option: %s\n' "$1" >&2
                return 1 ;;
            *)
                _pos+=("$1")
                shift ;;
        esac
    done

    local _first_pos="${_pos[0]:-}"
    local _second_pos="${_pos[1]:-}"

    # Rule 1: "databases" as first positional (before db path)
    if [[ "$_first_pos" == "databases" ]]; then
        _SHQL_CLI_MODE="databases"
        return 0
    fi

    # Collect db and (optional) table from positionals
    local _db="${_first_pos}"
    local _table="${_second_pos}"

    # Rule 2: -q flag present
    if (( _has_q )); then
        _SHQL_CLI_MODE="query-out"
        _SHQL_CLI_DB="$_db"
        _SHQL_CLI_SQL="$_q_sql"
        return 0
    fi

    # Rule 3: stdin is a pipe (and no -q)
    # Use -p /dev/stdin to detect an actual pipe rather than [ ! -t 0 ],
    # which would incorrectly trigger in non-interactive shells and test runners.
    if [ -p /dev/stdin ]; then
        if [[ -z "$_db" ]]; then
            printf 'error: a database path is required when reading SQL from stdin\n' >&2
            return 1
        fi
        _SHQL_CLI_MODE="pipe"
        _SHQL_CLI_DB="$_db"
        _SHQL_CLI_SQL=$(cat)
        return 0
    fi

    # Rule 4: --query flag
    if (( _has_query )); then
        if [[ -z "$_db" ]]; then
            printf 'error: --query requires a database path\n' >&2
            return 1
        fi
        _SHQL_CLI_MODE="query-tui"
        _SHQL_CLI_DB="$_db"
        return 0
    fi

    # Rule 5: two positionals (db + table)
    if [[ -n "$_table" ]]; then
        _SHQL_CLI_MODE="table"
        _SHQL_CLI_DB="$_db"
        _SHQL_CLI_TABLE="$_table"
        return 0
    fi

    # Rule 6: one positional (db)
    if [[ -n "$_db" ]]; then
        _SHQL_CLI_MODE="open"
        _SHQL_CLI_DB="$_db"
        return 0
    fi

    # Rule 7: no args
    _SHQL_CLI_MODE="welcome"
    return 0
}

# ── shql_cli_format_table ─────────────────────────────────────────────────────
#
# Print a TSV result as a MySQL-style box table to stdout.
#
# Usage: shql_cli_format_table <tsv_string>
#
#   <tsv_string>  Full multi-line TSV. First line = tab-separated headers.
#                 Subsequent lines are data rows — including empty lines, which
#                 render as blank cells. Pass the TSV without a trailing newline
#                 (i.e. as returned by command substitution) to avoid a phantom
#                 blank row at the end. If empty: no output.
#                 If _SHQL_CLI_PORCELAIN=1: no output.
#
# Output format:
#   +----+-------+
#   | id | name  |
#   +----+-------+
#   | 1  | Alice |
#   +----+-------+
#
# Column width = max(header_length, max_data_cell_length).
# Each cell: | {space}{content padded to column_width}{space} |
# Separator dashes per column = column_width + 2.

shql_cli_format_table() {
    local _tsv="$1"
    [[ -z "$_tsv" ]] && return 0
    (( ${_SHQL_CLI_PORCELAIN:-0} )) && return 0

    # Split TSV into header line and data lines.
    # <<< appends exactly one \n; $(…) strips trailing newlines, so normal
    # multi-row inputs never produce a phantom blank row.  When the caller
    # explicitly passes a string ending in \n (e.g. $'name\n'), the extra
    # empty line IS a real data row (empty cell), so we keep all elements.
    local _header="" _rows=() _line _first=1
    while IFS= read -r _line; do
        if (( _first )); then
            _header="$_line"
            _first=0
        else
            _rows+=("$_line")
        fi
    done <<< "$_tsv"

    # Parse header into column array (tab-delimited)
    local _headers=() _IFS_SAVE="$IFS"
    IFS=$'\t' read -ra _headers <<< "$_header"
    IFS="$_IFS_SAVE"
    local _ncols=${#_headers[@]}

    # Initialise column widths from header lengths
    local _widths=() _i
    for (( _i = 0; _i < _ncols; _i++ )); do
        _widths+=( "${#_headers[$_i]}" )
    done

    # Expand widths from data cell lengths
    local _row _cells=() _cell _clen
    for _row in "${_rows[@]+"${_rows[@]}"}"; do
        _cells=()
        IFS=$'\t' read -ra _cells <<< "$_row"
        IFS="$_IFS_SAVE"
        for (( _i = 0; _i < _ncols; _i++ )); do
            _cell="${_cells[$_i]:-}"
            _clen=${#_cell}
            (( _clen > _widths[$_i] )) && _widths[$_i]=$_clen
        done
    done

    # Build separator line: +---+---+
    local _sep="+" _j _dashes _w
    for (( _i = 0; _i < _ncols; _i++ )); do
        _dashes=""
        _w=$(( _widths[$_i] + 2 ))
        for (( _j = 0; _j < _w; _j++ )); do _dashes="${_dashes}-"; done
        _sep="${_sep}${_dashes}+"
    done

    # Print top border
    printf '%s\n' "$_sep"

    # Print header row: | col1 | col2 |
    local _row_str="|" _v _pad _sp _m
    for (( _i = 0; _i < _ncols; _i++ )); do
        _v="${_headers[$_i]}"
        _pad=$(( _widths[$_i] - ${#_v} ))
        _sp=""
        for (( _m = 0; _m < _pad; _m++ )); do _sp="${_sp} "; done
        _row_str="${_row_str} ${_v}${_sp} |"
    done
    printf '%s\n' "$_row_str"

    # Print header separator
    printf '%s\n' "$_sep"

    # Print data rows
    for _row in "${_rows[@]+"${_rows[@]}"}"; do
        _cells=()
        IFS=$'\t' read -ra _cells <<< "$_row"
        IFS="$_IFS_SAVE"
        _row_str="|"
        for (( _i = 0; _i < _ncols; _i++ )); do
            _v="${_cells[$_i]:-}"
            _pad=$(( _widths[$_i] - ${#_v} ))
            _sp=""
            for (( _m = 0; _m < _pad; _m++ )); do _sp="${_sp} "; done
            _row_str="${_row_str} ${_v}${_sp} |"
        done
        printf '%s\n' "$_row_str"
    done

    # Print bottom border
    printf '%s\n' "$_sep"
}
