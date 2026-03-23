# Name Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `shql_conn_resolve_name` to `src/connections.sh` and wire a pre-dispatch resolution block into `bin/shql` so short names like `chinook` resolve to full registry paths.

**Architecture:** One new function in `connections.sh` loops `SHQL_RECENT_DETAILS`/`SHQL_RECENT_SOURCES` (already populated by `shql_conn_load_recent`) and applies three basename-matching rules. A single guard block in `bin/shql` — after `shql_cli_parse`, before the `case` dispatch — calls it whenever `_SHQL_CLI_DB` is set but is not an existing file.

**Tech Stack:** bash 3.2, ptyunit assert framework (`tests/ptyunit/assert.sh`)

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| **Modify** | `src/connections.sh` | Add `shql_conn_resolve_name` function |
| **Modify** | `bin/shql` | Add pre-dispatch resolution block |
| **Modify** | `tests/unit/test-connections.sh` | Append 6 unit tests for the new function |

---

## Task 1: Write failing tests for `shql_conn_resolve_name`

**Files:**
- Modify: `tests/unit/test-connections.sh`

The function doesn't exist yet — tests will fail with "command not found". That's the correct TDD starting state.

- [ ] **Step 1: Append the 6 test cases**

Insert the following block directly before the `# ── cleanup` section at the bottom of `tests/unit/test-connections.sh`:

```bash
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
```

Note: each test sets `SHQL_RECENT_DETAILS` and `SHQL_RECENT_SOURCES` directly — no sqlite3 call needed. Tests 1 and 2 share the same array state (`.sqlite` strip re-uses the arrays set for exact match).

- [ ] **Step 2: Run the tests — verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit
```

Expected: `test-connections.sh` fails with something like:
```
FAIL [conn_resolve_name: exact basename match]
  expected: 0
  actual:   127
```
(exit code 127 = command not found). All other test files should still pass.

---

## Task 2: Implement `shql_conn_resolve_name`

**Files:**
- Modify: `src/connections.sh`

- [ ] **Step 1: Add the function**

Append the following block at the end of `src/connections.sh`, after `shql_conn_load_recent`:

```bash
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
```

- [ ] **Step 2: Run the tests — verify they pass**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit
```

Expected: all unit tests pass, including the 9 new assertions in `test-connections.sh`:
- Tests 1–3 (match cases): 2 assertions each (exit code + output value) = 6
- Tests 4–6 (miss/empty/sigil cases): 1 assertion each (exit code only) = 3

If a test fails:
- `actual: 127` → function not found; check that `shql_conn_resolve_name` is outside any `if` block and at the top level of `connections.sh`
- `.sqlite` strip failing → check `${_base%.sqlite}` expansion; must be double-bracket `[[ ]]` not single `[ ]`
- sigil test passing when it shouldn't → check `SHQL_RECENT_SOURCES[$_i]` access; confirm index `$_i` is used, not `$i`

- [ ] **Step 3: Commit**

```bash
git add src/connections.sh tests/unit/test-connections.sh
git commit -m "feat(connections): add shql_conn_resolve_name (shellql#10)"
```

---

## Task 3: Wire resolution into `bin/shql`

**Files:**
- Modify: `bin/shql`

- [ ] **Step 1: Add the pre-dispatch resolution block**

In `bin/shql`, locate this line:

```bash
shql_cli_parse "$@" || exit $?
```

Add the following block immediately after it, before the `# ── Dispatch` comment:

```bash
# ── Name resolution ───────────────────────────────────────────────────────────
# If _SHQL_CLI_DB is set but is not an existing path, attempt to resolve it as
# a short name (e.g. "chinook") from the connection registry.
# Skip in mock mode — there is no registry in SHQL_MOCK=1.

if [[ -n "$_SHQL_CLI_DB" && ! -e "$_SHQL_CLI_DB" ]] && ! (( ${SHQL_MOCK:-0} )); then
    shql_conn_load_recent
    _resolved=$(shql_conn_resolve_name "$_SHQL_CLI_DB")
    [[ -n "$_resolved" ]] && _SHQL_CLI_DB="$_resolved"
fi
```

- [ ] **Step 2: Run the full test suite**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh
```

Expected: all tests pass. The wire-up touches only `bin/shql` (not any sourced module), so no existing tests should regress.

If you see failures in `test-integration.sh`:
- Check that `shql_conn_load_recent` is idempotent (it is — it just re-populates the arrays)
- Check that the guard correctly skips when `_SHQL_CLI_DB` is already a valid file path (the `! -e` condition)

- [ ] **Step 3: Smoke-test end-to-end manually**

```bash
# Push the fixture DB to the registry via query-out (-q mode calls shql_conn_push on success)
SHELLFRAME_DIR=../shellframe bash bin/shql tests/fixtures/demo.sqlite -q "SELECT 1" --porcelain

# Then resolve by short name
SHELLFRAME_DIR=../shellframe bash bin/shql demo -q "SELECT name FROM users LIMIT 1" --porcelain
```

Expected second command: prints `Alice` (or similar) to stdout, exits 0. If it prints a "database not found" error, the wire-up block isn't firing — double-check placement in `bin/shql`.

- [ ] **Step 4: Commit**

```bash
git add bin/shql
git commit -m "feat(cli): wire name resolution into bin/shql dispatch (shellql#10)"
```

---

## Task 4: Close issue and update PLAN.md

- [ ] **Step 1: Close shellql#10**

```bash
gh issue close 10 --repo fissible/shellql \
  --comment "Done — shql_conn_resolve_name in src/connections.sh; pre-dispatch resolution block in bin/shql. 12 unit tests passing. Short names (chinook, budget) now resolve to full paths from the registry."
```

- [ ] **Step 2: Update PLAN.md**

In `PLAN.md`, update Phase 6.5 status and session handoff notes. Add a new entry under Phase 6:

```markdown
### 6.6 Name resolution — [shellql#10](https://github.com/fissible/shellql/issues/10) ✓ done
- `shql_conn_resolve_name` in `src/connections.sh`
- Pre-dispatch guard in `bin/shql`
- **Effort:** S (1–2h)
- **Status:** Done — 12 unit assertions added to `tests/unit/test-connections.sh`
```

Update session handoff notes to reflect Phase 6 fully complete and the project at M3 milestone (all phases done).

- [ ] **Step 3: Commit**

```bash
git add PLAN.md
git commit -m "docs: mark shellql#10 complete, update session handoff"
```
