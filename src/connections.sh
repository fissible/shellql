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
    sqlite3 "$_SHQL_CONN_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS connections (
    id         TEXT PRIMARY KEY,
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
}
