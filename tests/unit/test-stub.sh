#!/usr/bin/env bash
# tests/unit/test-stub.sh — placeholder; replace with real tests as src/ is built

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "stub: placeholder always passes"
assert_eq "ok" "ok"

ptyunit_test_summary
