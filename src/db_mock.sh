#!/usr/bin/env bash
# shellql/src/db_mock.sh — Mock SQLite adapter for UI development
#
# Source this file (instead of src/db.sh) when SHQL_MOCK=1.
# All functions return static fixture data so screens can be built and tested
# without a real database.

# ── Mock recent files ─────────────────────────────────────────────────────────

# Populate SHQL_RECENT_FILES with fixture paths for the welcome screen.
shql_mock_load_recent() {
    SHQL_RECENT_FILES=(
        "$HOME/projects/app.db"
        "$HOME/Downloads/chinook.sqlite"
        "$HOME/Documents/budget.db"
        "$HOME/work/analytics.db"
        "$HOME/scratch/test.sqlite"
    )
}

# ── Mock adapter functions ────────────────────────────────────────────────────

# shql_db_list_tables <db_path>
shql_db_list_tables() {
    printf '%s\n' users orders products categories
}

# shql_db_describe <db_path> <table>
shql_db_describe() {
    local _table="${2:-users}"
    case "$_table" in
        users)
            printf '%s\n' \
                "CREATE TABLE users (" \
                "  id INTEGER PRIMARY KEY," \
                "  name TEXT NOT NULL," \
                "  email TEXT UNIQUE," \
                "  created_at TEXT DEFAULT CURRENT_TIMESTAMP" \
                ");"
            ;;
        orders)
            printf '%s\n' \
                "CREATE TABLE orders (" \
                "  id INTEGER PRIMARY KEY," \
                "  user_id INTEGER REFERENCES users(id)," \
                "  total REAL NOT NULL," \
                "  placed_at TEXT DEFAULT CURRENT_TIMESTAMP" \
                ");"
            ;;
        *)
            printf 'CREATE TABLE %s (id INTEGER PRIMARY KEY);\n' "$_table"
            ;;
    esac
}

# shql_db_fetch <db_path> <table> [limit] [offset]
shql_db_fetch() {
    local _table="${2:-users}"
    printf '%s\t%s\t%s\t%s\n' id name email created_at
    printf '%s\t%s\t%s\t%s\n' 1  "Alice"   "alice@example.com"   "2024-01-01"
    printf '%s\t%s\t%s\t%s\n' 2  "Bob"     "bob@example.com"     "2024-01-02"
    printf '%s\t%s\t%s\t%s\n' 3  "Charlie" "charlie@example.com" "2024-01-03"
}

# shql_db_query <db_path> <sql>
shql_db_query() {
    printf '%s\t%s\n' count result
    printf '%s\t%s\n' 42 "mock row"
}
