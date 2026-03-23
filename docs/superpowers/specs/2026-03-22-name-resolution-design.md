# Name Resolution Design

**Date:** 2026-03-22
**Issue:** [shellql#10](https://github.com/fissible/shellql/issues/10)
**Effort:** S (1–2h)

---

## Goal

Allow `shql <name> -q "..."` to resolve a short database name (e.g. `chinook`, `budget`) to a full path from the connection registry, so users don't have to type full paths for recently-used databases.

---

## Scope

**In scope:**
- `shql_conn_resolve_name` function in `src/connections.sh`
- Pre-dispatch resolution block in `bin/shql`
- Unit tests appended to `tests/unit/test-connections.sh`

**Out of scope:**
- Fuzzy or case-insensitive matching
- Alias registry
- File-picker TUI
- Changes to `databases` mode output
- Resolution in mock mode (`SHQL_MOCK=1`)

---

## Function: `shql_conn_resolve_name`

**Location:** `src/connections.sh`

**Signature:**
```bash
# shql_conn_resolve_name <name>
# Searches SHQL_RECENT_DETAILS for a local path whose basename matches <name>.
# Caller must populate SHQL_RECENT_DETAILS/SHQL_RECENT_SOURCES first
# (call shql_conn_load_recent).
#
# Only entries where SHQL_RECENT_SOURCES[i] == 'local' are candidates.
# (There is no in-memory driver array; 'local' source is the available
# discriminator. Network entries have detail = 'host:port/db_name' which
# will not match any basename rule, so they are harmlessly skipped even
# without an explicit source check — but the source check is retained for
# clarity and correctness.)
#
# Matching rules (case-sensitive, first match wins):
#   1. basename "$detail" == "$name"          (chinook.sqlite → "chinook.sqlite")
#   2. basename "$detail" .sqlite == "$name"  (chinook.sqlite → "chinook")
#   3. basename "$detail" .db == "$name"      (budget.db → "budget")
#
# Rule 1 handles the edge case where a user passes a full filename (e.g.
# "chinook.sqlite") that is not a path on disk — intentional, not dead code.
#
# Echoes full path on match; returns 0.
# Echoes nothing; returns 1 on miss or empty array.
```

**Loop structure** — index-based to traverse parallel arrays:

```bash
shql_conn_resolve_name() {
    local _name="$1"
    local _i _detail _base
    for _i in "${!SHQL_RECENT_DETAILS[@]}"; do
        [[ "${SHQL_RECENT_SOURCES[$_i]:-}" == "local" ]] || continue
        _detail="${SHQL_RECENT_DETAILS[$_i]}"
        _base="${_detail##*/}"   # basename without subshell
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

Using `${_detail##*/}` avoids a `basename` subshell. `.sqlite`/`.db` stripping via `${_base%.sqlite}` / `${_base%.db}` is bash 3.2-safe.

---

## Wire-up in `bin/shql`

Single block after `shql_cli_parse "$@"`, before the `case` dispatch:

```bash
if [[ -n "$_SHQL_CLI_DB" && ! -e "$_SHQL_CLI_DB" ]] && ! (( ${SHQL_MOCK:-0} )); then
    shql_conn_load_recent
    _resolved=$(shql_conn_resolve_name "$_SHQL_CLI_DB")
    [[ -n "$_resolved" ]] && _SHQL_CLI_DB="$_resolved"
fi
```

`${SHQL_MOCK:-0}` is used defensively, though `SHQL_MOCK` is initialized in `src/state.sh` as `SHQL_MOCK="${SHQL_MOCK:-0}"` and is always set before this block executes.

**Gate logic:**
- `[[ -n "$_SHQL_CLI_DB" ]]` — skip if no DB arg (e.g. `welcome` or `databases` mode)
- `[[ ! -e "$_SHQL_CLI_DB" ]]` — skip if arg is already a valid path on disk
- `! (( ${SHQL_MOCK:-0} ))` — skip in mock mode (no registry in mock mode)

If resolution finds nothing, `_SHQL_CLI_DB` is left unchanged and the dispatch's existing path-validation error fires normally.

---

## Tests

Appended to `tests/unit/test-connections.sh`. Populate `SHQL_RECENT_DETAILS` and `SHQL_RECENT_SOURCES` directly — no sqlite3 call needed.

**Six cases:**

1. **Exact basename match** — `SHQL_RECENT_DETAILS=("/db/chinook.sqlite")`, `SHQL_RECENT_SOURCES=("local")`; `shql_conn_resolve_name "chinook.sqlite"` → echoes `/db/chinook.sqlite`, returns 0

2. **`.sqlite` strip match** — same arrays; `shql_conn_resolve_name "chinook"` → echoes `/db/chinook.sqlite`, returns 0

3. **`.db` strip match** — `SHQL_RECENT_DETAILS=("/db/budget.db")`, `SHQL_RECENT_SOURCES=("local")`; `shql_conn_resolve_name "budget"` → echoes `/db/budget.db`, returns 0

4. **No match** — `shql_conn_resolve_name "nonexistent"` → echoes nothing, returns 1

5. **Empty array** — `SHQL_RECENT_DETAILS=()`, `SHQL_RECENT_SOURCES=()`; `shql_conn_resolve_name "chinook"` → returns 1

6. **Sigil source skipped** — `SHQL_RECENT_DETAILS=("/db/chinook.sqlite")`, `SHQL_RECENT_SOURCES=("sigil")`; `shql_conn_resolve_name "chinook"` → returns 1 (source is not `local`)

---

## Data Flow

```
bin/shql
  └── shql_cli_parse "$@"         → _SHQL_CLI_DB = "chinook"
  └── [guard: set, not a file, not mock]
      └── shql_conn_load_recent   → SHQL_RECENT_DETAILS=("/path/to/chinook.sqlite" ...)
                                    SHQL_RECENT_SOURCES=("local" ...)
      └── shql_conn_resolve_name "chinook"
              i=0: source=local, detail="/path/to/chinook.sqlite"
                   base="chinook.sqlite", base%.sqlite="chinook" == "chinook" ✓
              printf "/path/to/chinook.sqlite"; return 0
      └── _SHQL_CLI_DB = "/path/to/chinook.sqlite"
  └── case dispatch (open/query-out/pipe/etc.)
```
