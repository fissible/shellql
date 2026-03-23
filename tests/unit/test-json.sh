#!/usr/bin/env bash
# tests/unit/test-json.sh — Unit tests for JSON utilities

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# ── sqlite3 stub ──────────────────────────────────────────────────────────────
# json.sh pipes SQL to `sqlite3 :memory:` via stdin. The stub reads stdin
# and dispatches on SQL substrings to return canned output.

_stub_dir=$(mktemp -d)
cat > "$_stub_dir/sqlite3" << 'STUB'
#!/usr/bin/env bash
_sql=$(cat)
case "$_sql" in
    *json_extract*) printf '%s\n' "${STUB_EXTRACT_RESULT:-}" ;;
    *json_set*)     printf '%s\n' "${STUB_SET_RESULT:-}" ;;
    *json_each*)    printf '%s\n' "${STUB_KEYS_RESULT:-}" ;;
    *)              printf '' ;;
esac
STUB
chmod +x "$_stub_dir/sqlite3"
PATH="$_stub_dir:$PATH"

source "$SHQL_ROOT/src/json.sh"

# ── shql_json_get ─────────────────────────────────────────────────────────────

ptyunit_test_begin "json_get: returns value for existing key"
_tmpfile=$(mktemp)
printf '{"fetch_limit":500}' > "$_tmpfile"
export STUB_EXTRACT_RESULT="500"
_result=$(shql_json_get "$_tmpfile" fetch_limit)
assert_eq "500" "$_result"
rm -f "$_tmpfile"

ptyunit_test_begin "json_get: returns 1 for missing file"
_rc=0
shql_json_get "/tmp/_shql_nonexistent_$$" fetch_limit || _rc=$?
assert_eq 1 "$_rc"

ptyunit_test_begin "json_get: returns 1 when key absent (empty sqlite3 output)"
_tmpfile=$(mktemp)
printf '{}' > "$_tmpfile"
export STUB_EXTRACT_RESULT=""
_rc=0
shql_json_get "$_tmpfile" missing_key || _rc=$?
assert_eq 1 "$_rc"
rm -f "$_tmpfile"

# ── shql_json_get_str ─────────────────────────────────────────────────────────

ptyunit_test_begin "json_get_str: returns value from raw JSON string"
export STUB_EXTRACT_RESULT="500"
_result=$(shql_json_get_str '{"fetch_limit":500}' fetch_limit)
assert_eq "500" "$_result"

ptyunit_test_begin "json_get_str: returns 1 when key absent"
export STUB_EXTRACT_RESULT=""
_rc=0
shql_json_get_str '{}' missing_key || _rc=$?
assert_eq 1 "$_rc"

# ── shql_json_set ─────────────────────────────────────────────────────────────

ptyunit_test_begin "json_set: creates file with {} base if file missing"
_tmpfile=$(mktemp)
rm -f "$_tmpfile"
export STUB_SET_RESULT='{"fetch_limit":500}'
shql_json_set "$_tmpfile" fetch_limit 500
assert_eq '{"fetch_limit":500}' "$(cat "$_tmpfile")"
rm -f "$_tmpfile"

ptyunit_test_begin "json_set: updates existing file"
_tmpfile=$(mktemp)
printf '{"fetch_limit":500}' > "$_tmpfile"
export STUB_SET_RESULT='{"fetch_limit":1000}'
shql_json_set "$_tmpfile" fetch_limit 1000
assert_eq '{"fetch_limit":1000}' "$(cat "$_tmpfile")"
rm -f "$_tmpfile"

ptyunit_test_begin "json_set: stores string values (writes stub result without error)"
_tmpfile=$(mktemp)
export STUB_SET_RESULT='{"theme":"uranium"}'
shql_json_set "$_tmpfile" theme uranium
assert_eq '{"theme":"uranium"}' "$(cat "$_tmpfile")"
rm -f "$_tmpfile"

# ── shql_json_keys ────────────────────────────────────────────────────────────

ptyunit_test_begin "json_keys: prints top-level keys one per line"
_tmpfile=$(mktemp)
printf '{"fetch_limit":500,"theme":"basic"}' > "$_tmpfile"
export STUB_KEYS_RESULT="$(printf 'fetch_limit\ntheme')"
_result=$(shql_json_keys "$_tmpfile")
assert_contains "$_result" "fetch_limit"
assert_contains "$_result" "theme"
rm -f "$_tmpfile"

ptyunit_test_begin "json_keys: returns 1 for missing file"
_rc=0
shql_json_keys "/tmp/_shql_nonexistent_$$" || _rc=$?
assert_eq 1 "$_rc"

# ── cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$_stub_dir"
ptyunit_test_summary
