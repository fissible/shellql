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
SHQL_DRIVER=""           # "sqlite" | "mysql" | "postgresql" | "" (default/unknown)
SHQL_DB_HOST=""          # hostname for network drivers (mysql, postgresql)
SHQL_DB_NAME=""          # database name for network drivers

# ── Data directory ────────────────────────────────────────────────────────────

SHQL_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/shellql"

# ── Recent files (mock mode) ──────────────────────────────────────────────────

SHQL_RECENT_FILES=()     # ordered list of recently-opened database paths (mock mode)
SHQL_RECENT_NAMES=()     # display names (e.g. "myapp/db.sqlite")
SHQL_RECENT_DETAILS=()   # path (sqlite) or host:port/db_name (network)
SHQL_RECENT_SOURCES=()   # 'local' | 'sigil'
SHQL_RECENT_REFS=()      # connections.id (local) | sigil entry name (sigil)
