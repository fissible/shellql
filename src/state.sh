#!/usr/bin/env bash
# shellql/src/state.sh — Application state globals
#
# All ShellQL globals use the SHQL_ prefix to avoid conflict
# with shellframe's SHELLFRAME_ namespace.

# ── Runtime flags ─────────────────────────────────────────────────────────────

# Set SHQL_MOCK=1 to use src/db_mock.sh instead of src/db.sh.
SHQL_MOCK="${SHQL_MOCK:-0}"

# ── Active database ───────────────────────────────────────────────────────────

SHQL_DB_PATH=""          # absolute path to the open database (empty if none)
SHQL_DB_TABLE=""         # currently selected table name

# ── Recent files ──────────────────────────────────────────────────────────────

SHQL_RECENT_FILES=()     # ordered list of recently-opened database paths
SHQL_RECENT_MAX=10       # maximum number of entries kept

# ── History file location ─────────────────────────────────────────────────────

SHQL_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/shellql"
SHQL_HISTORY_FILE="$SHQL_DATA_DIR/recent"

# ── shql_state_load_recent ────────────────────────────────────────────────────

# Populate SHQL_RECENT_FILES from SHQL_HISTORY_FILE (one path per line).
# Silent no-op if the file does not exist.
shql_state_load_recent() {
    SHQL_RECENT_FILES=()
    [[ -f "$SHQL_HISTORY_FILE" ]] || return 0
    local _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        SHQL_RECENT_FILES+=("$_line")
    done < "$SHQL_HISTORY_FILE"
}

# ── shql_state_push_recent ────────────────────────────────────────────────────

# Record $1 as the most-recently-opened database.
# Deduplicates (removes existing entry) and trims to SHQL_RECENT_MAX.
# Persists to SHQL_HISTORY_FILE.
shql_state_push_recent() {
    local _path="$1"
    [[ -z "$_path" ]] && return 0

    # Remove any existing entry for this path
    local _new=()
    local _e
    for _e in "${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}"; do
        [[ "$_e" == "$_path" ]] && continue
        _new+=("$_e")
    done

    # Prepend and trim
    SHQL_RECENT_FILES=("$_path" "${_new[@]+"${_new[@]}"}")
    if (( ${#SHQL_RECENT_FILES[@]} > SHQL_RECENT_MAX )); then
        SHQL_RECENT_FILES=("${SHQL_RECENT_FILES[@]:0:$SHQL_RECENT_MAX}")
    fi

    # Persist
    mkdir -p "$SHQL_DATA_DIR"
    local _f
    for _f in "${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}"; do
        printf '%s\n' "$_f"
    done > "$SHQL_HISTORY_FILE"
}
