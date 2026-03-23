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

_SHQL_CONN_DB=""      # set by shql_conn_init; used as default by other functions
_SHQL_SQLITE3=""      # absolute path to sqlite3 binary; set by shql_conn_init
_SHQL_SORT=""         # absolute path to sort; set by shql_conn_init
_SHQL_RM=""           # absolute path to rm; set by shql_conn_init

# ── shql_conn_init ─────────────────────────────────────────────────────────
# Ensure shellql.db exists with current schema. Creates SHQL_DATA_DIR if needed.
# No-op if already initialised. Returns 1 on error (sqlite3 absent or dir unwritable).

shql_conn_init() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        printf 'error: sqlite3 not found on PATH\n' >&2
        return 1
    fi
    _SHQL_SQLITE3=$(command -v sqlite3)
    _SHQL_SORT=$(command -v sort 2>/dev/null) || _SHQL_SORT="sort"
    _SHQL_RM=$(command -v rm 2>/dev/null) || _SHQL_RM="rm"
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
        _id=$("${_SHQL_SQLITE3:-sqlite3}" "$_db" "SELECT id FROM connections WHERE path='$_ep'")
    elif [ -n "$_host" ]; then
        _id=$("${_SHQL_SQLITE3:-sqlite3}" "$_db" \
            "SELECT id FROM connections WHERE host='$_eh' AND port='$_eport' AND db_name='$_ed'")
    fi

    if [ -z "$_id" ]; then
        _id=$(_shql_conn_uuid)
        "${_SHQL_SQLITE3:-sqlite3}" "$_db" \
            "INSERT INTO connections (id,driver,name,path,host,port,user,db_name,sigil_name)
             VALUES ('$_id','$_edrv','$_en','$_ep','$_eh','$_eport','$_eu','$_ed','$_es')"
    else
        "${_SHQL_SQLITE3:-sqlite3}" "$_db" \
            "UPDATE connections
             SET driver='$_edrv',name='$_en',path='$_ep',host='$_eh',
                 port='$_eport',user='$_eu',db_name='$_ed',sigil_name='$_es'
             WHERE id='$_id'"
    fi

    local _now
    _now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    "${_SHQL_SQLITE3:-sqlite3}" "$_db" \
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
    local _line _id _name _ep _en _sql _count
    _sql="BEGIN;"
    _count=0
    while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        _id=$(_shql_conn_uuid)
        _name=$(_shql_conn_derive_name "sqlite" "$_line" "")
        _ep="${_line//\'/\'\'}"
        _en="${_name//\'/\'\'}"
        _sql="${_sql}"$'\n'"INSERT OR IGNORE INTO connections (id,driver,name,path) VALUES ('${_id}','sqlite','${_en}','${_ep}');"
        _count=$(( _count + 1 ))
    done < "$_legacy"
    _sql="${_sql}"$'\n'"COMMIT;"

    [ "$_count" -eq 0 ] && return 0

    if printf '%s\n' "$_sql" | "${_SHQL_SQLITE3:-sqlite3}" "$_db" 2>/dev/null; then
        mv "$_legacy" "${_legacy}.bak"
    else
        printf 'error: migration failed; %s left intact\n' "$_legacy" >&2
        return 1
    fi
}

# ── shql_conn_list ─────────────────────────────────────────────────────────
# Print aggregate connection list to stdout. Format: 6 tab-delimited columns:
#   <source>\t<driver>\t<name>\t<detail>\t<last_used>\t<ref_id>
# source   = 'local' | 'sigil'
# detail   = path (sqlite) | host:port/db_name (network)
# last_used = ISO8601 string, or empty for never-accessed
# ref_id   = connections.id (local) | sigil entry name[@env] (sigil)
# Sorted by last_used DESC; empty last_used (never-accessed) sorts last.
# Silently skips sigil aggregation if sigil is absent or --porcelain unsupported.

shql_conn_list() {
    local _db="${_SHQL_CONN_DB:-$SHQL_DATA_DIR/shellql.db}"
    local _sq="${_SHQL_SQLITE3:-sqlite3}"
    local _sort="${_SHQL_SORT:-sort}"
    local _rm="${_SHQL_RM:-rm}"
    local _tmpfile
    _tmpfile=$(mktemp 2>/dev/null) || _tmpfile="/tmp/_shql_conn_list_$$"
    : > "$_tmpfile" || return 0

    # Local connections from shellql.db
    if [ -r "$_db" ]; then
        "$_sq" -separator $'\t' "$_db" "
            SELECT 'local', c.driver, c.name,
                CASE WHEN c.driver = 'sqlite' THEN c.path
                     ELSE c.host || ':' || c.port || '/' || c.db_name
                END,
                COALESCE(la.last_used, ''),
                c.id
            FROM connections c
            LEFT JOIN last_accessed la
                ON la.source = 'local' AND la.ref_id = c.id
        " 2>/dev/null >> "$_tmpfile"
    fi

    # Sigil-sourced connections (requires sigil --porcelain support)
    if command -v sigil >/dev/null 2>&1; then
        local _sigil_out
        _sigil_out=$(sigil list --type database --porcelain 2>/dev/null) || true
        if [ -n "$_sigil_out" ]; then
            local _sname _senv _sdriver _shost _sport _suser _sdb _spath
            local _sref _sdetail _slast _dup
            printf '%s\n' "$_sigil_out" | while IFS=$'\t' read -r _sname _senv _sdriver _shost _sport _suser _sdb _spath; do
                [ -z "$_sname" ] && continue
                _sref="$_sname"
                [ -n "$_senv" ] && _sref="${_sname}@${_senv}"
                # Skip if a local record already links to this sigil entry
                if [ -r "$_db" ]; then
                    _dup=$("$_sq" "$_db" \
                        "SELECT id FROM connections WHERE sigil_name='${_sref//\'/\'\'}'" \
                        2>/dev/null)
                    [ -n "$_dup" ] && continue
                fi
                if [ "$_sdriver" = "sqlite" ]; then
                    _sdetail="$_spath"
                else
                    _sdetail="${_shost}:${_sport}/${_sdb}"
                fi
                _slast=""
                if [ -r "$_db" ]; then
                    _slast=$("$_sq" "$_db" \
                        "SELECT last_used FROM last_accessed
                         WHERE source='sigil' AND ref_id='${_sref//\'/\'\'}'"\
                        2>/dev/null)
                fi
                printf 'sigil\t%s\t%s\t%s\t%s\t%s\n' \
                    "$_sdriver" "$_sname" "$_sdetail" "${_slast:-}" "$_sref" \
                    >> "$_tmpfile"
            done
        fi
    fi

    # Sort by column 5 (last_used) descending; empty strings sort last under reverse
    "$_sort" -t$'\t' -k5,5r "$_tmpfile"
    "$_rm" -f "$_tmpfile"
}

# ── shql_conn_load_recent ──────────────────────────────────────────────────
# Populate four parallel arrays from shql_conn_list output.
# Note: uses a captured variable (not a subshell pipeline) for bash 3.2 compat —
# array assignments inside `while ... | while` do not persist in bash 3.2.
#
# Populates (global):
#   SHQL_RECENT_NAMES=()   — display names (e.g. "myapp/db.sqlite")
#   SHQL_RECENT_DETAILS=() — path (sqlite) or host:port/db_name (network)
#   SHQL_RECENT_SOURCES=() — 'local' | 'sigil'
#   SHQL_RECENT_REFS=()    — connections.id (local) | sigil entry name (sigil)

shql_conn_load_recent() {
    SHQL_RECENT_NAMES=()
    SHQL_RECENT_DETAILS=()
    SHQL_RECENT_SOURCES=()
    SHQL_RECENT_REFS=()

    local _list _source _driver _name _detail _last _ref
    _list=$(shql_conn_list)
    [ -z "$_list" ] && return 0

    while IFS=$'\t' read -r _source _driver _name _detail _last _ref; do
        [ -z "$_source" ] && continue
        SHQL_RECENT_NAMES+=("$_name")
        SHQL_RECENT_DETAILS+=("$_detail")
        SHQL_RECENT_SOURCES+=("$_source")
        SHQL_RECENT_REFS+=("$_ref")
    done <<< "$_list"
}

# ── shql_conn_resolve_name ────────────────────────────────────────────────
# Resolve a short name to a full path from the in-memory recent-connections
# arrays. Caller must call shql_conn_load_recent first.
#
# Usage: shql_conn_resolve_name <name>
#
# Only entries where SHQL_RECENT_SOURCES[i] == 'local' are candidates.
# Matching rules (case-sensitive, first match wins):
#   1. basename == name           (chinook.sqlite → "chinook.sqlite")
#   2. basename strip .sqlite     (chinook.sqlite → "chinook")
#   3. basename strip .db         (budget.db → "budget")
#
# Echoes the full path on match; returns 0.
# Echoes nothing; returns 1 on miss or empty array.

shql_conn_resolve_name() {
    local _name="$1"
    local _i _detail _base
    for _i in "${!SHQL_RECENT_DETAILS[@]}"; do
        [[ "${SHQL_RECENT_SOURCES[$_i]:-}" == "local" ]] || continue
        _detail="${SHQL_RECENT_DETAILS[$_i]}"
        _base="${_detail##*/}"
        if [[ "$_base" == "$_name" ]] ||
           [[ "${_base%.sqlite}" == "$_name" ]] ||
           [[ "${_base%.db}" == "$_name" ]]; then
            printf '%s\n' "$_detail"
            return 0
        fi
    done
    return 1
}
