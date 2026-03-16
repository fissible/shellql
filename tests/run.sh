#!/usr/bin/env bash
# tests/run.sh — shellql test runner
#
# Usage: bash tests/run.sh [--unit | --integration | --all]
#
# Thin wrapper around ptyunit's runner that points it at shellql's own
# tests/unit/ and tests/integration/ directories rather than ptyunit's self-tests.

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTYUNIT_DIR="$TESTS_DIR/ptyunit"

_mode="${1:---all}"
_total_pass=0
_total_fail=0
_total_files=0
_failed_files=()

_run_file() {
    local f="$1" name
    name="$(basename "$f")"
    printf '  %s ... ' "$name"
    local out
    out=$(bash "$f" 2>&1)
    local rc=$?
    if (( rc == 0 )); then
        local passed total
        passed=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f1)
        total=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f2)
        (( _total_pass += ${passed:-0} ))
        (( _total_fail += $(( ${total:-0} - ${passed:-0} )) ))
        printf 'OK (%s/%s)\n' "${passed:-?}" "${total:-?}"
    else
        printf 'FAIL\n'
        printf '%s\n' "$out" | sed 's/^/    /'
        _failed_files+=("$name")
        local passed total
        passed=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f1)
        total=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f2)
        (( _total_pass += ${passed:-0} ))
        (( _total_fail += $(( ${total:-0} - ${passed:-0} )) ))
    fi
    (( _total_files++ ))
}

_run_suite() {
    local suite_dir="$1" label="$2"
    local files=()
    local f
    for f in "$suite_dir"/test-*.sh; do
        [ -f "$f" ] && files+=("$f")
    done
    (( ${#files[@]} == 0 )) && return
    printf '\n%s tests:\n' "$label"
    for f in "${files[@]}"; do _run_file "$f"; done
}

printf 'shellql test runner\n'

case "$_mode" in
    --unit)
        _run_suite "$TESTS_DIR/unit" "Unit"
        ;;
    --integration)
        if ! command -v python3 >/dev/null 2>&1; then
            printf '\nSkipping integration tests (python3 not found)\n'
        else
            _run_suite "$TESTS_DIR/integration" "Integration"
        fi
        ;;
    --all|*)
        _run_suite "$TESTS_DIR/unit" "Unit"
        if command -v python3 >/dev/null 2>&1; then
            _run_suite "$TESTS_DIR/integration" "Integration"
        else
            printf '\nSkipping integration tests (python3 not found)\n'
        fi
        ;;
esac

local_total=$(( _total_pass + _total_fail ))
printf '\n─────────────────────────────────\n'
printf '%d/%d assertions passed across %d file(s)\n' \
    "$_total_pass" "$local_total" "$_total_files"

if (( ${#_failed_files[@]} > 0 )); then
    printf 'Failed files:\n'
    local_f=""
    for local_f in "${_failed_files[@]}"; do
        printf '  %s\n' "$local_f"
    done
    exit 1
fi
exit 0
