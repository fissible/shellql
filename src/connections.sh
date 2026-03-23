#!/usr/bin/env bash
# shellql/src/connections.sh — Connection registry
#
# Provides:
#   shql_conn_init          — create/verify shellql.db schema
#   shql_conn_push          — upsert connection + update last_accessed
#   shql_conn_list          — print aggregate connection list (local + sigil)
#   shql_conn_load_recent   — populate SHQL_RECENT_* arrays
#   shql_conn_migrate       — one-time migration from legacy 'recent' flat file

[[ -n "${_SHQL_CONN_LOADED:-}" ]] && return 0
_SHQL_CONN_LOADED=1

_SHQL_CONN_DB=""   # set by shql_conn_init; used as default by other functions

# ── shql_conn_init ─────────────────────────────────────────────────────────
# Ensure shellql.db exists with current schema. Creates SHQL_DATA_DIR if needed.
# No-op if already initialised. Returns 1 on error (sqlite3 absent or dir unwritable).

shql_conn_init() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        printf 'error: sqlite3 not found on PATH\n' >&2
        return 1
    fi
    if ! mkdir -p "$SHQL_DATA_DIR"; then
        printf 'error: cannot create data directory: %s\n' "$SHQL_DATA_DIR" >&2
        return 1
    fi
    _SHQL_CONN_DB="$SHQL_DATA_DIR/shellql.db"
    local _rc=0
    sqlite3 "$_SHQL_CONN_DB" <<'SQL' || _rc=$?
CREATE TABLE IF NOT EXISTS connections (
    id         TEXT NOT NULL PRIMARY KEY,
    driver     TEXT NOT NULL,
    name       TEXT NOT NULL,
    path       TEXT NOT NULL DEFAULT '',
    host       TEXT NOT NULL DEFAULT '',
    port       TEXT NOT NULL DEFAULT '',
    user       TEXT NOT NULL DEFAULT '',
    db_name    TEXT NOT NULL DEFAULT '',
    sigil_name TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_connections_path
    ON connections (path) WHERE path != '';
CREATE UNIQUE INDEX IF NOT EXISTS uq_connections_network
    ON connections (host, port, db_name) WHERE host != '';
CREATE TABLE IF NOT EXISTS last_accessed (
    source    TEXT NOT NULL,
    ref_id    TEXT NOT NULL,
    last_used TEXT NOT NULL,
    PRIMARY KEY (source, ref_id)
);
CREATE INDEX IF NOT EXISTS idx_last_accessed_ref ON last_accessed (ref_id);
SQL
    if [ "$_rc" -ne 0 ]; then
        printf 'error: failed to initialise schema: %s\n' "$_SHQL_CONN_DB" >&2
        return "$_rc"
    fi
}

# ── _shql_conn_uuid ────────────────────────────────────────────────────────
# Generate a UUID. Tries uuidgen first, then /proc, then seconds+PID fallback.

_shql_conn_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        printf '%s-%s' "$(date +%s)" "$$"
    fi
}

# ── _shql_conn_derive_name ─────────────────────────────────────────────────
# Derive display name from driver + path/db_name.
# SQLite: last two path segments. Network: db_name only.

_shql_conn_derive_name() {
    local _driver="$1" _path="$2" _db_name="${3:-}"
    if [ "$_driver" = "sqlite" ]; then
        local _base _parent
        _base="${_path##*/}"
        _parent="${_path%/*}"
        _parent="${_parent##*/}"
        printf '%s/%s' "$_parent" "$_base"
    else
        printf '%s' "$_db_name"
    fi
}

# ── _shql_conn_push_inner ──────────────────────────────────────────────────
# Internal implementation of push. May exit non-zero; shql_conn_push silences it.

_shql_conn_push_inner() {
    local _driver="$1"
    local _path="${2:-}"
    local _host="${3:-}"
    local _port="${4:-}"
    local _user="${5:-}"
    local _db_name="${6:-}"
    local _sigil_name="${7:-}"

    local _db="${_SHQL_CONN_DB:-$SHQL_DATA_DIR/shellql.db}"
    [ -w "$_db" ] || return 1

    local _name
    _name=$(_shql_conn_derive_name "$_driver" "$_path" "$_db_name")

    # Escape single quotes for inline SQL
    local _ep="${_path//\'/\'\'}"
    local _eh="${_host//\'/\'\'}"
    local _eu="${_user//\'/\'\'}"
    local _ed="${_db_name//\'/\'\'}"
    local _es="${_sigil_name//\'/\'\'}"
    local _en="${_name//\'/\'\'}"
    local _edrv="${_driver//\'/\'\'}"
    local _eport="${_port//\'/\'\'}"

    # Look up existing id (preserve on update — never INSERT OR REPLACE)
    local _id=""
    if [ "$_driver" = "sqlite" ] && [ -n "$_path" ]; then
        _id=$(sqlite3 "$_db" "SELECT id FROM connections WHERE path='$_ep'")
    elif [ -n "$_host" ]; then
        _id=$(sqlite3 "$_db" \
            "SELECT id FROM connections WHERE host='$_eh' AND port='$_eport' AND db_name='$_ed'")
    fi

    if [ -z "$_id" ]; then
        _id=$(_shql_conn_uuid)
        sqlite3 "$_db" \
            "INSERT INTO connections (id,driver,name,path,host,port,user,db_name,sigil_name)
             VALUES ('$_id','$_edrv','$_en','$_ep','$_eh','$_eport','$_eu','$_ed','$_es')"
    else
        sqlite3 "$_db" \
            "UPDATE connections
             SET driver='$_edrv',name='$_en',path='$_ep',host='$_eh',
                 port='$_eport',user='$_eu',db_name='$_ed',sigil_name='$_es'
             WHERE id='$_id'"
    fi

    local _now
    _now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sqlite3 "$_db" \
        "INSERT OR REPLACE INTO last_accessed (source,ref_id,last_used)
         VALUES ('local','$_id','$_now')"
}

# ── shql_conn_push ─────────────────────────────────────────────────────────
# Upsert connection and update last_accessed. Always exits 0 — fully silent on failure.
# Usage: shql_conn_push <driver> <path> [host] [port] [user] [db_name] [sigil_name]

shql_conn_push() {
    _shql_conn_push_inner "$@" 2>/dev/null
    return 0
}

# ── shql_conn_migrate ──────────────────────────────────────────────────────
# One-time migration: import $SHQL_DATA_DIR/recent (one path per line) into shellql.db.
# Inserts directly — no last_accessed rows (migrated entries appear as never-accessed).
# All-or-nothing: uses a transaction; leaves recent intact on failure.
# Renames recent → recent.bak only after full successful import.

shql_conn_migrate() {
    local _legacy="$SHQL_DATA_DIR/recent"
    [ -f "$_legacy" ] || return 0

    local _db="${_SHQL_CONN_DB:-$SHQL_DATA_DIR/shellql.db}"
    local _line _id _name _ep _en _sql

    # Build SQL in a variable first, then pipe to sqlite3
    _sql="BEGIN;"$'\n'
    while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        _id=$(_shql_conn_uuid)
        _name=$(_shql_conn_derive_name "sqlite" "$_line" "")
        _ep="${_line//\'/\'\'}"
        _en="${_name//\'/\'\'}"
        _sql="${_sql}"$'\n'"INSERT OR IGNORE INTO connections (id,driver,name,path) VALUES ('${_id}','sqlite','${_en}','${_ep}');"
    done < "$_legacy"
    _sql="${_sql}"$'\n'"COMMIT;"

    if printf '%s\n' "$_sql" | sqlite3 "$_db" 2>/dev/null; then
        mv "$_legacy" "${_legacy}.bak"
    fi
}
