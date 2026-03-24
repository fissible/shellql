#!/usr/bin/env bash
# tests/unit/test-connections.sh — Unit tests for connections module

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$PTYUNIT_HOME/assert.sh"

# ── Setup: temp data dir ───────────────────────────────────────────────────
_data_dir=$(mktemp -d)
export XDG_DATA_HOME="$_data_dir"
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/connections.sh"

# ── shql_conn_init: creates schema ─────────────────────────────────────────
ptyunit_test_begin "shql_conn_init: creates schema"
shql_conn_init
_tables=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
assert_eq "connections
last_accessed" "$_tables"

# ── shql_conn_init: idempotent ─────────────────────────────────────────────
ptyunit_test_begin "shql_conn_init: is idempotent"
_rc=0
shql_conn_init || _rc=$?
assert_eq "0" "$_rc"

# ── shql_conn_push: inserts new connection ─────────────────────────────────
ptyunit_test_begin "shql_conn_push: inserts new connection"
shql_conn_push "sqlite" "/tmp/test.sqlite"
_count=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "1" "$_count"

# ── shql_conn_push: auto-derives name ─────────────────────────────────────
ptyunit_test_begin "shql_conn_push: auto-derives name from last two path segments"
_name=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT name FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "tmp/test.sqlite" "$_name"

# ── shql_conn_push: creates last_accessed ─────────────────────────────────
ptyunit_test_begin "shql_conn_push: creates last_accessed entry"
_la=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM last_accessed WHERE source='local'")
assert_eq "1" "$_la"

# ── shql_conn_push: preserves id on re-push ───────────────────────────────
ptyunit_test_begin "shql_conn_push: preserves id on re-push (no INSERT OR REPLACE)"
_id1=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT id FROM connections WHERE path='/tmp/test.sqlite'")
shql_conn_push "sqlite" "/tmp/test.sqlite"
_id2=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT id FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "$_id1" "$_id2"

# ── shql_conn_push: deduplicates ──────────────────────────────────────────
ptyunit_test_begin "shql_conn_push: same path yields one row"
_count=$(sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "SELECT COUNT(*) FROM connections WHERE path='/tmp/test.sqlite'")
assert_eq "1" "$_count"

# ── shql_conn_push: fails silently ────────────────────────────────────────
ptyunit_test_begin "shql_conn_push: fails silently on unwritable db"
chmod 444 "$SHQL_DATA_DIR/shellql.db"
_out=$(shql_conn_push "sqlite" "/tmp/other.sqlite" 2>&1)
_rc=$?
chmod 644 "$SHQL_DATA_DIR/shellql.db"
assert_eq "0" "$_rc"
assert_eq "" "$_out"

# ── shql_conn_migrate tests ────────────────────────────────────────────────
# Use a fresh data dir for isolation from push tests above.
_mig_dir=$(mktemp -d)
export XDG_DATA_HOME="$_mig_dir"
source "$SHQL_ROOT/src/state.sh"    # re-sources; SHQL_DATA_DIR now points at _mig_dir
shql_conn_init

ptyunit_test_begin "shql_conn_migrate: no-op when recent file absent"
shql_conn_migrate
assert_eq "0" "$?"
assert_eq "0" "$(sqlite3 "$SHQL_DATA_DIR/shellql.db" "SELECT COUNT(*) FROM connections")"

ptyunit_test_begin "shql_conn_migrate: imports each path as a connection"
printf '/tmp/a.sqlite\n/tmp/b.sqlite\n' > "$SHQL_DATA_DIR/recent"
shql_conn_migrate
assert_eq "2" "$(sqlite3 "$SHQL_DATA_DIR/shellql.db" "SELECT COUNT(*) FROM connections")"

ptyunit_test_begin "shql_conn_migrate: does not create last_accessed entries"
assert_eq "0" \
    "$(sqlite3 "$SHQL_DATA_DIR/shellql.db" "SELECT COUNT(*) FROM last_accessed")"

ptyunit_test_begin "shql_conn_migrate: renames recent to recent.bak on success"
assert_eq "1" "$( [ -f "$SHQL_DATA_DIR/recent.bak" ] && printf 1 || printf 0 )"
assert_eq "0" "$( [ -f "$SHQL_DATA_DIR/recent" ]     && printf 1 || printf 0 )"

ptyunit_test_begin "shql_conn_migrate: leaves recent intact on failure"
_fail_dir=$(mktemp -d)
export XDG_DATA_HOME="$_fail_dir"
source "$SHQL_ROOT/src/state.sh"
shql_conn_init
printf '/tmp/c.sqlite\n' > "$SHQL_DATA_DIR/recent"
chmod 444 "$SHQL_DATA_DIR/shellql.db"   # make DB unwritable → force failure
shql_conn_migrate 2>/dev/null           # suppress expected error message
_intact=$( [ -f "$SHQL_DATA_DIR/recent" ] && printf 1 || printf 0 )
chmod 644 "$SHQL_DATA_DIR/shellql.db"   # restore for cleanup
assert_eq "1" "$_intact"
rm -rf "$_mig_dir" "$_fail_dir"
export XDG_DATA_HOME="$_data_dir"   # restore so subsequent test sections start clean
source "$SHQL_ROOT/src/state.sh"

# ── shql_conn_list tests ───────────────────────────────────────────────────
_list_dir=$(mktemp -d)
export XDG_DATA_HOME="$_list_dir"
source "$SHQL_ROOT/src/state.sh"
shql_conn_init

ptyunit_test_begin "shql_conn_list: returns local connections"
shql_conn_push "sqlite" "/tmp/foo.sqlite"
_list=$(shql_conn_list)
assert_contains "$_list" "local"
assert_contains "$_list" "/tmp/foo.sqlite"

ptyunit_test_begin "shql_conn_list: never-accessed connections sort last"
# Insert a connection directly (no last_accessed row) to simulate never-accessed
sqlite3 "$SHQL_DATA_DIR/shellql.db" \
    "INSERT INTO connections (id,driver,name,path) VALUES ('t1','sqlite','tmp/bar.sqlite','/tmp/bar.sqlite')"
_list=$(shql_conn_list)
_first_line=$(printf '%s\n' "$_list" | head -1)
assert_contains "$_first_line" "foo.sqlite"   # foo has last_used; bar does not → foo first

ptyunit_test_begin "shql_conn_list: skips sigil aggregation when sigil not on PATH"
_saved_path="$PATH"
PATH="/no-such-dir"
_list=$(shql_conn_list 2>&1)
_rc=$?
PATH="$_saved_path"
assert_eq "0" "$_rc"
assert_contains "$_list" "local"   # local results still returned

rm -rf "$_list_dir"

# ── shql_conn_load_recent tests ────────────────────────────────────────────
_lr_dir=$(mktemp -d)
export XDG_DATA_HOME="$_lr_dir"
source "$SHQL_ROOT/src/state.sh"
shql_conn_init
shql_conn_push "sqlite" "/tmp/mydb.sqlite"

ptyunit_test_begin "shql_conn_load_recent: populates SHQL_RECENT_NAMES"
shql_conn_load_recent
assert_eq "1" "${#SHQL_RECENT_NAMES[@]}"
assert_eq "tmp/mydb.sqlite" "${SHQL_RECENT_NAMES[0]}"

ptyunit_test_begin "shql_conn_load_recent: populates SHQL_RECENT_DETAILS with path"
assert_eq "/tmp/mydb.sqlite" "${SHQL_RECENT_DETAILS[0]}"

ptyunit_test_begin "shql_conn_load_recent: populates SHQL_RECENT_SOURCES"
assert_eq "local" "${SHQL_RECENT_SOURCES[0]}"

ptyunit_test_begin "shql_conn_load_recent: populates SHQL_RECENT_REFS with UUID"
assert_eq "1" "$( [ -n "${SHQL_RECENT_REFS[0]:-}" ] && printf 1 || printf 0 )"

ptyunit_test_begin "shql_conn_load_recent: parallel arrays stay in sync for multiple entries"
shql_conn_push "sqlite" "/tmp/second.sqlite"
shql_conn_load_recent
assert_eq "2" "${#SHQL_RECENT_NAMES[@]}"
assert_eq "${#SHQL_RECENT_NAMES[@]}" "${#SHQL_RECENT_DETAILS[@]}"
assert_eq "${#SHQL_RECENT_NAMES[@]}" "${#SHQL_RECENT_SOURCES[@]}"
assert_eq "${#SHQL_RECENT_NAMES[@]}" "${#SHQL_RECENT_REFS[@]}"

ptyunit_test_begin "shql_conn_load_recent: ref_id preserved when last_used is empty"
# Insert a connection with no last_accessed row (e.g. migrated entry).
# Empty last_used produces consecutive tabs (\t\t) in conn_list output.
# IFS=\t read collapses those, sliding ref_id into the wrong field without the fix.
"${_SHQL_SQLITE3:-sqlite3}" "$_SHQL_CONN_DB" \
    "INSERT INTO connections (id,driver,name,path) VALUES ('legacy-uuid','sqlite','tmp/legacy.sqlite','/tmp/legacy.sqlite')"
shql_conn_load_recent
_ref_ok=0
for _r in "${SHQL_RECENT_REFS[@]+"${SHQL_RECENT_REFS[@]}"}"; do
    [[ "$_r" == "legacy-uuid" ]] && _ref_ok=1 && break
done
assert_eq "1" "$_ref_ok"

rm -rf "$_lr_dir"

# ── shql_conn_resolve_name ────────────────────────────────────────────────

ptyunit_test_begin "conn_resolve_name: exact basename match"
SHQL_RECENT_DETAILS=("/db/chinook.sqlite")
SHQL_RECENT_SOURCES=("local")
_rc=0; _result=$(shql_conn_resolve_name "chinook.sqlite") || _rc=$?
assert_eq 0 "$_rc"
assert_eq "/db/chinook.sqlite" "$_result"

ptyunit_test_begin "conn_resolve_name: .sqlite strip match"
_rc=0; _result=$(shql_conn_resolve_name "chinook") || _rc=$?
assert_eq 0 "$_rc"
assert_eq "/db/chinook.sqlite" "$_result"

ptyunit_test_begin "conn_resolve_name: .db strip match"
SHQL_RECENT_DETAILS=("/db/budget.db")
SHQL_RECENT_SOURCES=("local")
_rc=0; _result=$(shql_conn_resolve_name "budget") || _rc=$?
assert_eq 0 "$_rc"
assert_eq "/db/budget.db" "$_result"

ptyunit_test_begin "conn_resolve_name: no match returns 1"
SHQL_RECENT_DETAILS=("/db/chinook.sqlite")
SHQL_RECENT_SOURCES=("local")
_rc=0; shql_conn_resolve_name "nonexistent" >/dev/null 2>&1 || _rc=$?
assert_eq 1 "$_rc"

ptyunit_test_begin "conn_resolve_name: empty array returns 1"
SHQL_RECENT_DETAILS=()
SHQL_RECENT_SOURCES=()
_rc=0; shql_conn_resolve_name "chinook" >/dev/null 2>&1 || _rc=$?
assert_eq 1 "$_rc"

ptyunit_test_begin "conn_resolve_name: sigil source not resolved"
SHQL_RECENT_DETAILS=("/db/chinook.sqlite")
SHQL_RECENT_SOURCES=("sigil")
_rc=0; shql_conn_resolve_name "chinook" >/dev/null 2>&1 || _rc=$?
assert_eq 1 "$_rc"

# ── cleanup ────────────────────────────────────────────────────────────────
rm -rf "$_data_dir"
ptyunit_test_summary
