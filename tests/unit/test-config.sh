#!/usr/bin/env bash
# tests/unit/test-config.sh — Unit tests for config utilities

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

# ── Temp config dir ───────────────────────────────────────────────────────────
# Override XDG_CONFIG_HOME so tests never touch ~/.config/shql/.toolrc

_cfg_dir=$(mktemp -d)
export XDG_CONFIG_HOME="$_cfg_dir"

source "$SHQL_ROOT/src/json.sh"
source "$SHQL_ROOT/src/config.sh"

# ── Helper: config file path (mirrors config.sh internal) ────────────────────
_cfg_file="${XDG_CONFIG_HOME}/shql/.toolrc"

# ── shql_config_get_fetch_limit — no file ────────────────────────────────────

ptyunit_test_begin "config_get_fetch_limit: returns 1000 when no config file"
rm -f "$_cfg_file"
_result=$(shql_config_get_fetch_limit)
assert_eq "1000" "$_result"

# ── shql_config_get_fetch_limit — file present, key absent ───────────────────

ptyunit_test_begin "config_get_fetch_limit: returns 500 when file present, key absent"
mkdir -p "$(dirname "$_cfg_file")"
printf '{}' > "$_cfg_file"
export STUB_EXTRACT_RESULT=""
_result=$(shql_config_get_fetch_limit)
assert_eq "500" "$_result"

# ── shql_config_get_fetch_limit — file present, key present ──────────────────

ptyunit_test_begin "config_get_fetch_limit: returns stored value when key present"
printf '{"fetch_limit":250}' > "$_cfg_file"
export STUB_EXTRACT_RESULT="250"
_result=$(shql_config_get_fetch_limit)
assert_eq "250" "$_result"

# ── shql_config_get_fetch_limit — sqlite3 absent ─────────────────────────────

ptyunit_test_begin "config_get_fetch_limit: returns 1000 when sqlite3 absent"
_SHQL_CONFIG_HAS_SQLITE=0
_result=$(shql_config_get_fetch_limit)
assert_eq "1000" "$_result"
_SHQL_CONFIG_HAS_SQLITE=1  # restore

# ── shql_config_get ───────────────────────────────────────────────────────────

ptyunit_test_begin "config_get: returns value for existing key"
printf '{"theme":"uranium"}' > "$_cfg_file"
export STUB_EXTRACT_RESULT="uranium"
_result=$(shql_config_get theme)
assert_eq "uranium" "$_result"

ptyunit_test_begin "config_get: returns empty string for missing key"
export STUB_EXTRACT_RESULT=""
_result=$(shql_config_get nonexistent_key)
assert_eq "" "$_result"

ptyunit_test_begin "config_get: returns empty string when sqlite3 absent"
_SHQL_CONFIG_HAS_SQLITE=0
_result=$(shql_config_get theme)
assert_eq "" "$_result"
_SHQL_CONFIG_HAS_SQLITE=1

# ── shql_config_set ───────────────────────────────────────────────────────────

ptyunit_test_begin "config_set: creates dir and file, writes key"
rm -rf "${XDG_CONFIG_HOME}/shql"
export STUB_SET_RESULT='{"fetch_limit":300}'
shql_config_set fetch_limit 300
assert_eq '{"fetch_limit":300}' "$(cat "$_cfg_file")"

ptyunit_test_begin "config_set: is no-op when sqlite3 absent"
_SHQL_CONFIG_HAS_SQLITE=0
rm -f "$_cfg_file"
shql_config_set fetch_limit 300
_rc=0; [[ -f "$_cfg_file" ]] && _rc=1
assert_eq 0 "$_rc"
_SHQL_CONFIG_HAS_SQLITE=1

# ── cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$_stub_dir" "$_cfg_dir"
ptyunit_test_summary
