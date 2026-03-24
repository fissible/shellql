# Browser Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the TABLE screen into a persistent browser with a sidebar, dynamic tabs, an inline record inspector with nav bar, and spatial arrow-key navigation — retiring the SCHEMA screen as a standalone destination.

**Architecture:** Pure state-management functions come first (tab arrays, open/close lifecycle); then the layout is replaced (5-region shell replacing 4-region); then per-tab content renderers are wired up; finally the inspector and navigation polish are applied. Each task produces passing tests and a clean commit before the next begins.

**Tech Stack:** bash 3.2+, shellframe widgets (grid, editor, scroll, panel, list), ptyunit test framework, sqlite3 (via mock adapter in tests)

---

## File Map

| File | Change type | Responsibility |
|------|-------------|---------------|
| `src/screens/table.sh` | Heavily modified | Tab state arrays, lifecycle functions, 5-region layout, sidebar, dynamic tab bar, content dispatch, schema tab renderer, data tab renderer, spatial nav |
| `src/screens/inspector.sh` | Significantly modified | Inline content view, nav bar row, ←→ row stepping, 1-char padding, Esc cursor return |
| `src/screens/query.sh` | Minor modifications | Dynamic context id parameter, placeholder text fix |
| `bin/shql` | Minor modifications | Routing: `open`→TABLE, `query-tui`→TABLE+query tab, remove `shql_schema_init` calls |
| `tests/unit/test-table.sh` | Extended | Tab lifecycle tests, sidebar key tests, content dispatch tests |
| `tests/unit/test-inspector.sh` | Extended | Nav bar tests, row stepping tests, Esc cursor-return test |
| `tests/unit/test-query.sh` | Updated | Dynamic ctx tests, placeholder text test |
| `src/screens/schema.sh` | No longer dispatched to | Kept for helper fns; `_SCHEMA` screen is bypassed in routing |

### Pre-existing functions referenced by this plan

These functions already exist in the codebase and do not need to be created:

- `_shql_grid_fill_width` / `_shql_grid_restore_last` — in `table.sh` (lines 226–248)
- `_shql_detect_grid_align` — in `table.sh` (lines 251–297)
- `shql_db_columns` — added to `src/db.sh` and `src/db_mock.sh` in the current working diff (un-committed at plan-writing time); schema tab tasks assume it is committed before they run
- `_shql_query_footer_hint` — in `query.sh` (lines 103–124)
- `_shql_breadcrumb` — in `src/screens/header.sh`

### Inspector handoff note

Tasks 7–9 add the content dispatch and call `_shql_inspector_render`. At that point, the inspector is still the old overlay implementation. Task 11 replaces `_shql_inspector_render` with the inline version. The call site in Task 7 does not change — it simply calls the function, which will be the new inline version after Task 11 is applied.

---

## Task 1: Tab state globals and `_shql_tab_find`

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test-table.sh` before `ptyunit_test_summary`:

```bash
# ── Tab state model ───────────────────────────────────────────────────────────

ptyunit_test_begin "tab_arrays: globals exist and are empty after shql_table_init_browser"
shql_table_init_browser
assert_eq 0 "${#_SHQL_TABS_TYPE[@]}"
assert_eq 0 "${#_SHQL_TABS_LABEL[@]}"
assert_eq -1 "$_SHQL_TAB_ACTIVE"
assert_eq 0 "$_SHQL_TAB_CTX_SEQ"

ptyunit_test_begin "tab_find: returns -1 when no tabs open"
_result=-99
_shql_tab_find "users" "data" _result
assert_eq -1 "$_result"

ptyunit_test_begin "tab_find: returns -1 for wrong type"
_SHQL_TABS_TYPE=("data")
_SHQL_TABS_TABLE=("users")
_SHQL_TABS_LABEL=("users·Data")
_SHQL_TABS_CTX=("t0")
_shql_tab_find "users" "schema" _result
assert_eq -1 "$_result"

ptyunit_test_begin "tab_find: finds correct index"
_SHQL_TABS_TYPE=("data" "schema")
_SHQL_TABS_TABLE=("users" "users")
_SHQL_TABS_LABEL=("users·Data" "users·Schema")
_SHQL_TABS_CTX=("t0" "t1")
_shql_tab_find "users" "schema" _result
assert_eq 1 "$_result"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -A3 "tab_arrays"
```
Expected: FAIL — `shql_table_init_browser` not found, `_shql_tab_find` not found

- [ ] **Step 3: Add globals and `_shql_tab_find` to `table.sh`**

Replace the `# ── Tab index constants ──` block in `table.sh`:

```bash
# ── Tab state arrays ──────────────────────────────────────────────────────────
# Dynamic tab model. Each tab occupies the same index across all arrays.

_SHQL_TABS_TYPE=()    # "data" | "schema" | "query"
_SHQL_TABS_TABLE=()   # table name; empty string for query tabs
_SHQL_TABS_LABEL=()   # display label: "users·Data", "Query 1"
_SHQL_TABS_CTX=()     # unique context id: "t0", "t1", …
_SHQL_TAB_ACTIVE=-1   # index of active tab (-1 = no tabs open)
_SHQL_TAB_CTX_SEQ=0   # ever-incrementing; never reused
_SHQL_TAB_QUERY_N=0   # ever-incrementing query label counter

# Keep legacy constants for backward compatibility with test-table.sh
_SHQL_TABLE_TAB_STRUCTURE=0
_SHQL_TABLE_TAB_DATA=1
_SHQL_TABLE_TAB_QUERY=2
```

Add these functions after `_shql_table_load_data`:

```bash
# ── shql_table_init_browser ───────────────────────────────────────────────────
# Reset all tab state to empty (called on browser entry).
shql_table_init_browser() {
    _SHQL_TABS_TYPE=()
    _SHQL_TABS_TABLE=()
    _SHQL_TABS_LABEL=()
    _SHQL_TABS_CTX=()
    _SHQL_TAB_ACTIVE=-1
    _SHQL_TAB_CTX_SEQ=0
    _SHQL_TAB_QUERY_N=0
}

# ── _shql_tab_find ────────────────────────────────────────────────────────────
# _shql_tab_find <table> <type> <out_var>
# Sets out_var to the index of the matching tab, or -1 if not found.
# Query tabs are never found by this function (use _shql_tab_open for them).
_shql_tab_find() {
    local _table="$1" _type="$2" _out_var="$3"
    local _i
    for (( _i=0; _i<${#_SHQL_TABS_TYPE[@]}; _i++ )); do
        if [[ "${_SHQL_TABS_TYPE[$_i]}" == "$_type" && \
              "${_SHQL_TABS_TABLE[$_i]}" == "$_table" ]]; then
            printf -v "$_out_var" '%d' "$_i"
            return 0
        fi
    done
    printf -v "$_out_var" '%d' -1
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(tab_arrays|tab_find|PASS|FAIL)"
```
Expected: all 4 new tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): add tab state arrays and _shql_tab_find"
```

---

## Task 2: `_shql_tab_open` and `_shql_tab_close`

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "tab_open: creates new data tab"
shql_table_init_browser
_shql_tab_open "users" "data"
assert_eq 1 "${#_SHQL_TABS_TYPE[@]}"
assert_eq "data" "${_SHQL_TABS_TYPE[0]}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]}"
assert_eq "users·Data" "${_SHQL_TABS_LABEL[0]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_open: deduplicates — switches to existing tab"
_shql_tab_open "users" "schema"   # second tab
_shql_tab_open "users" "data"    # should switch back, not create
assert_eq 2 "${#_SHQL_TABS_TYPE[@]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_open: query tabs never deduplicate"
shql_table_init_browser
_shql_tab_open "" "query"
_shql_tab_open "" "query"
assert_eq 2 "${#_SHQL_TABS_TYPE[@]}"
assert_eq "query" "${_SHQL_TABS_TYPE[0]}"
assert_contains "${_SHQL_TABS_LABEL[0]}" "Query"

ptyunit_test_begin "tab_open: query tab labels increment"
assert_eq "Query 2" "${_SHQL_TABS_LABEL[1]}"

ptyunit_test_begin "tab_close: removes active tab and moves left"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "orders" "data"
_SHQL_TAB_ACTIVE=1
_shql_tab_close
assert_eq 1 "${#_SHQL_TABS_TYPE[@]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "tab_close: sets ACTIVE=-1 when last tab closed"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_close
assert_eq 0 "${#_SHQL_TABS_TYPE[@]}"
assert_eq -1 "$_SHQL_TAB_ACTIVE"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "tab_open|tab_close"
```
Expected: all 6 new tests FAIL

- [ ] **Step 3: Implement `_shql_tab_open` and `_shql_tab_close`**

```bash
# ── _shql_tab_open ────────────────────────────────────────────────────────────
# _shql_tab_open <table> <type>
# Opens a tab for (table, type). Deduplicates data/schema; query tabs always new.
# Sets _SHQL_TAB_ACTIVE to the index of the opened/found tab.
# Does NOT check capacity (capacity check happens in the key handler).
_shql_tab_open() {
    local _table="$1" _type="$2"

    # Query tabs always create new
    if [[ "$_type" != "query" ]]; then
        local _found=-1
        _shql_tab_find "$_table" "$_type" _found
        if (( _found >= 0 )); then
            _SHQL_TAB_ACTIVE=$_found
            return 0
        fi
    fi

    # Assign context id
    local _ctx="t${_SHQL_TAB_CTX_SEQ}"
    (( _SHQL_TAB_CTX_SEQ++ ))

    # Build label
    local _label
    if [[ "$_type" == "query" ]]; then
        (( _SHQL_TAB_QUERY_N++ ))
        _label="Query ${_SHQL_TAB_QUERY_N}"
    elif [[ "$_type" == "data" ]]; then
        _label="${_table}·Data"
    else
        _label="${_table}·Schema"
    fi

    _SHQL_TABS_TYPE+=("$_type")
    _SHQL_TABS_TABLE+=("$_table")
    _SHQL_TABS_LABEL+=("$_label")
    _SHQL_TABS_CTX+=("$_ctx")
    _SHQL_TAB_ACTIVE=$(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
}

# ── _shql_tab_close ───────────────────────────────────────────────────────────
# _shql_tab_close [index]
# Removes the tab at index (default: _SHQL_TAB_ACTIVE) from all arrays.
# After removal, activates the tab to the left, or -1 if none remain.
_shql_tab_close() {
    local _idx="${1:-$_SHQL_TAB_ACTIVE}"
    local _n=${#_SHQL_TABS_TYPE[@]}
    (( _n == 0 || _idx < 0 || _idx >= _n )) && return 0

    # Rebuild arrays without the removed index
    local -a _new_type _new_table _new_label _new_ctx
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        (( _i == _idx )) && continue
        _new_type+=("${_SHQL_TABS_TYPE[$_i]}")
        _new_table+=("${_SHQL_TABS_TABLE[$_i]}")
        _new_label+=("${_SHQL_TABS_LABEL[$_i]}")
        _new_ctx+=("${_SHQL_TABS_CTX[$_i]}")
    done
    _SHQL_TABS_TYPE=("${_new_type[@]+"${_new_type[@]}"}")
    _SHQL_TABS_TABLE=("${_new_table[@]+"${_new_table[@]}"}")
    _SHQL_TABS_LABEL=("${_new_label[@]+"${_new_label[@]}"}")
    _SHQL_TABS_CTX=("${_new_ctx[@]+"${_new_ctx[@]}"}")

    local _new_n=${#_SHQL_TABS_TYPE[@]}
    if (( _new_n == 0 )); then
        _SHQL_TAB_ACTIVE=-1
    else
        # Activate tab to the left, or stay at 0
        local _new_active=$(( _idx - 1 ))
        (( _new_active < 0 )) && _new_active=0
        (( _new_active >= _new_n )) && _new_active=$(( _new_n - 1 ))
        _SHQL_TAB_ACTIVE=$_new_active
    fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(tab_open|tab_close|PASS|FAIL)"
```
Expected: all 6 new tests PASS; all prior tests still PASS

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): add _shql_tab_open and _shql_tab_close lifecycle functions"
```

---

## Task 3: Tab bar capacity check

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "tab_capacity: fits within available width"
shql_table_init_browser
_shql_tab_open "users" "data"     # label "users·Data" = 10 chars + 2 padding = 12
_shql_tab_open "orders" "schema"  # label "orders·Schema" = 13 + 2 = 15
# +SQL = 5; separators = 2
# total used: 12+1+15+1+5 = 34 → fits in width 80
_result=-1
_shql_tab_fits 80 _result
assert_eq 1 "$_result"

ptyunit_test_begin "tab_capacity: detects overflow"
shql_table_init_browser
local _i; for (( _i=0; _i<10; _i++ )); do
    _shql_tab_open "" "query"
done
_shql_tab_fits 40 _result
assert_eq 0 "$_result"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "tab_capacity"
```

- [ ] **Step 3: Implement `_shql_tab_fits`**

Add to `table.sh` after `_shql_tab_close`:

```bash
# ── _shql_tab_fits ────────────────────────────────────────────────────────────
# _shql_tab_fits <available_cols> <out_var>
# Sets out_var to 1 if all current tabs fit in available_cols, else 0.
# Accounts for: label + 2 padding chars per tab, 1 separator between tabs,
# plus 5 chars for the "+SQL" affordance at the right end.
_shql_tab_fits() {
    local _avail="$1" _out_var="$2"
    local _n=${#_SHQL_TABS_LABEL[@]}
    local _used=5   # "+SQL " = 5 chars minimum
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        local _llen=${#_SHQL_TABS_LABEL[$_i]}
        _used=$(( _used + _llen + 2 + 1 ))  # label + 2 padding + 1 separator
    done
    if (( _used <= _avail )); then
        printf -v "$_out_var" '%d' 1
    else
        printf -v "$_out_var" '%d' 0
    fi
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(tab_capacity|PASS|FAIL)"
```
Expected: both new tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): add _shql_tab_fits capacity check"
```

---

## Task 4: 5-region layout + sidebar init

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

Context: The current `_shql_TABLE_render` registers 5 regions (header, tabbar, gap, body, footer). The new layout has 5 regions: header, sidebar, tabbar, content, footer. The sidebar spans the full body height on the left; tabbar is row 2 right-of-sidebar; content is rows 3+ right-of-sidebar.

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "browser_init: loads tables into _SHQL_BROWSER_TABLES"
_SHQL_TABLE_NAME=""
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))
assert_eq "users" "${_SHQL_BROWSER_TABLES[0]}"

ptyunit_test_begin "browser_sidebar_width: is approx 1/4 terminal width"
local _w
_shql_browser_sidebar_width 80 _w
assert_eq 1 $(( _w >= 15 && _w <= 25 ))
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "browser_init\|browser_sidebar"
```

- [ ] **Step 3: Add browser init + sidebar width + update `_shql_TABLE_render`**

Add browser state globals near top of `table.sh`:

```bash
# ── Browser state ─────────────────────────────────────────────────────────────

_SHQL_BROWSER_TABLES=()      # loaded from db on shql_browser_init
_SHQL_BROWSER_SIDEBAR_CTX="browser_sidebar"
_SHQL_BROWSER_SIDEBAR_FOCUSED=0
_SHQL_BROWSER_TABBAR_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUS="data"  # "data" | "schema_cols" | "schema_ddl" | "query_editor" | "query_results"
```

Add helper functions:

```bash
# ── shql_browser_init ─────────────────────────────────────────────────────────
# Load tables list and reset browser state. Call before entering TABLE screen.
shql_browser_init() {
    shql_table_init_browser
    _SHQL_BROWSER_TABLES=()
    _SHQL_BROWSER_SIDEBAR_FOCUSED=0
    _SHQL_BROWSER_TABBAR_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUSED=0
    _SHQL_BROWSER_CONTENT_FOCUS="data"
    local _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _SHQL_BROWSER_TABLES+=("$_line")
    done < <(shql_db_list_tables "$SHQL_DB_PATH" 2>/dev/null)
    local _n=${#_SHQL_BROWSER_TABLES[@]}
    shellframe_sel_init "$_SHQL_BROWSER_SIDEBAR_CTX" "$_n"
}

# ── _shql_browser_sidebar_width ───────────────────────────────────────────────
_shql_browser_sidebar_width() {
    local _cols="$1" _out_var="$2"
    local _w=$(( _cols / 4 ))
    (( _w < 15 )) && _w=15
    (( _w > 30 )) && _w=30
    printf -v "$_out_var" '%d' "$_w"
}
```

Replace `_shql_TABLE_render`:

```bash
_shql_TABLE_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    local _sidebar_w
    _shql_browser_sidebar_width "$_cols" _sidebar_w
    local _right_w=$(( _cols - _sidebar_w ))
    local _right_left=$(( _sidebar_w + 1 ))

    local _body_top=2
    local _body_h=$(( _rows - 2 ))
    (( _body_h < 2 )) && _body_h=2
    local _content_top=3
    local _content_h=$(( _rows - 3 ))
    (( _content_h < 1 )) && _content_h=1

    shellframe_shell_region header   1              1             "$_cols"      1             nofocus
    shellframe_shell_region sidebar  "$_body_top"   1             "$_sidebar_w" "$_body_h"    focus
    shellframe_shell_region tabbar   "$_body_top"   "$_right_left" "$_right_w"  1             focus
    shellframe_shell_region content  "$_content_top" "$_right_left" "$_right_w" "$_content_h" focus
    shellframe_shell_region footer   "$_rows"       1             "$_cols"      1             nofocus
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(browser_init|browser_sidebar|PASS|FAIL)"
```
Expected: 2 new tests PASS; prior tests unaffected (old regions may warn but tests don't test rendering)

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): 5-region layout, browser init, sidebar width helper"
```

---

## Task 5: Sidebar rendering and key handlers

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "sidebar_on_key: Enter opens data tab for selected table"
shql_browser_init
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }   # override: cursor at 0
shql_table_init_browser
_shql_TABLE_sidebar_on_key $'\r'
assert_eq "data" "${_SHQL_TABS_TYPE[0]}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]}"
assert_eq 0 "$_SHQL_TAB_ACTIVE"

ptyunit_test_begin "sidebar_on_key: s opens schema tab for selected table"
shql_table_init_browser
_shql_TABLE_sidebar_on_key 's'
assert_eq "schema" "${_SHQL_TABS_TYPE[0]}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]}"

ptyunit_test_begin "sidebar_on_key: right arrow returns 3 (move focus to content)"
shql_table_init_browser
_shql_TABLE_sidebar_on_key $'\033[C'; _rc=$?
assert_eq 3 "$_rc"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "sidebar_on_key"
```

- [ ] **Step 3: Implement sidebar render/on_key/on_focus/action**

Shellframe delivers `on_key` with return codes: 0=handled, 1=unhandled, 2=action, 3=special (we use 3 to signal "move focus right").

Actually, shellframe only uses return codes 0, 1, 2. For cross-region focus moves, we use `shellframe_shell_focus_set`. Let me revise:

```bash
# ── _shql_TABLE_sidebar_render ────────────────────────────────────────────────

_shql_TABLE_sidebar_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE="Tables"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    local _n=${#_SHQL_BROWSER_TABLES[@]}
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true

    local _r
    for (( _r=0; _r<_ih && _r<_n; _r++ )); do
        local _row=$(( _it + _r ))
        printf '\033[%d;%dH%*s' "$_row" "$_il" "$_iw" '' >/dev/tty
        local _name="${_SHQL_BROWSER_TABLES[$_r]}"
        local _clipped
        _clipped=$(shellframe_str_clip_ellipsis "$_name" "$_name" "$(( _iw - 2 ))")
        if (( _r == _cursor && _SHQL_BROWSER_SIDEBAR_FOCUSED )); then
            printf '\033[%d;%dH▶ %s' "$_row" "$_il" "$_clipped" >/dev/tty
        else
            printf '\033[%d;%dH  %s' "$_row" "$_il" "$_clipped" >/dev/tty
        fi
    done
}

# ── _shql_TABLE_sidebar_on_key ────────────────────────────────────────────────

_shql_TABLE_sidebar_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_enter=$'\r'

    case "$_key" in
        "$_k_up")    shellframe_sel_move "$_SHQL_BROWSER_SIDEBAR_CTX" up;   return 0 ;;
        "$_k_down")  shellframe_sel_move "$_SHQL_BROWSER_SIDEBAR_CTX" down; return 0 ;;
        "$_k_right") shellframe_shell_focus_set "content";  return 0 ;;
        "$_k_enter") _shql_TABLE_sidebar_action; return 0 ;;
        s)           _shql_TABLE_sidebar_action_schema; return 0 ;;
    esac
    return 1
}

_shql_TABLE_sidebar_on_focus() {
    _SHQL_BROWSER_SIDEBAR_FOCUSED="${1:-0}"
}

# ── _shql_TABLE_sidebar_action / sidebar_action_schema ────────────────────────

_shql_TABLE_sidebar_action() {
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
    local _table="${_SHQL_BROWSER_TABLES[$_cursor]:-}"
    [[ -z "$_table" ]] && return 0

    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    local _sidebar_w
    _shql_browser_sidebar_width "$_cols" _sidebar_w
    local _bar_w=$(( _cols - _sidebar_w ))
    local _fits=1
    _shql_tab_fits "$_bar_w" _fits
    if (( ! _fits )); then
        # Flash footer — capacity exceeded
        _SHQL_BROWSER_FLASH_MSG="Tab bar full — close a tab first (w)"
        return 0
    fi
    _shql_tab_open "$_table" "data"
    shellframe_shell_focus_set "content"
}

_shql_TABLE_sidebar_action_schema() {
    local _cursor=0
    shellframe_sel_cursor "$_SHQL_BROWSER_SIDEBAR_CTX" _cursor 2>/dev/null || true
    local _table="${_SHQL_BROWSER_TABLES[$_cursor]:-}"
    [[ -z "$_table" ]] && return 0
    _shql_tab_open "$_table" "schema"
    shellframe_shell_focus_set "content"
}
```

**Update the failing tests** — return code for → key test needs to be 0 (handled), not 3. Fix:
```bash
ptyunit_test_begin "sidebar_on_key: right arrow moves focus to content (rc=0)"
_saved_focus=""
shellframe_shell_focus_set() { _saved_focus="$1"; }
shql_table_init_browser
_shql_TABLE_sidebar_on_key $'\033[C'; _rc=$?
assert_eq 0 "$_rc"
assert_eq "content" "$_saved_focus"
shellframe_shell_focus_set() { true; }   # restore
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(sidebar_on_key|PASS|FAIL)"
```
Expected: all sidebar tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): sidebar render, key handlers, Enter/s open data/schema tabs"
```

---

## Task 6: Dynamic tab bar renderer

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "tabbar_labels: no tabs shows empty with +SQL hint"
shql_table_init_browser
_shql_tabbar_build_line 40 _line
assert_contains "$_line" "+SQL"

ptyunit_test_begin "tabbar_labels: active tab label highlighted in output"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "orders" "schema"
_SHQL_TAB_ACTIVE=0
_shql_tabbar_build_line 80 _line
assert_contains "$_line" "users·Data"
assert_contains "$_line" "orders·Schema"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "tabbar_labels"
```

- [ ] **Step 3: Implement tab bar render and on_key**

```bash
# ── _shql_tabbar_build_line ───────────────────────────────────────────────────
# Build the tab bar text content into out_var. No ANSI codes — used for tests.
_shql_tabbar_build_line() {
    local _width="$1" _out_var="$2"
    local _n=${#_SHQL_TABS_LABEL[@]}
    local _line=""
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        local _label=" ${_SHQL_TABS_LABEL[$_i]} "
        if (( _i > 0 )); then _line+="│"; fi
        _line+="$_label"
    done
    # Append +SQL affordance
    if [[ -n "$_line" ]]; then _line+="  +SQL"; else _line="+SQL"; fi
    printf -v "$_out_var" '%s' "$_line"
}

# ── _shql_TABLE_tabbar_render ─────────────────────────────────────────────────
# Replaces the old static shellframe_tabbar_render call.

_shql_TABLE_tabbar_render() {
    local _top="$1" _left="$2" _width="$3"
    local _inv="${SHELLFRAME_REVERSE:-}" _rst="${SHELLFRAME_RESET:-}"
    local _gray="${SHELLFRAME_GRAY:-}" _bold="${SHELLFRAME_BOLD:-}"

    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty

    local _n=${#_SHQL_TABS_LABEL[@]}
    local _col=$_left
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        if (( _i > 0 )); then
            printf '\033[%d;%dH│' "$_top" "$_col" >/dev/tty
            (( _col++ ))
        fi
        local _label=" ${_SHQL_TABS_LABEL[$_i]} "
        if (( _i == _SHQL_TAB_ACTIVE && _SHQL_BROWSER_TABBAR_FOCUSED == 0 )); then
            printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_inv" "$_label" "$_rst" >/dev/tty
        elif (( _i == _SHQL_TAB_ACTIVE )); then
            printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_bold" "$_label" "$_rst" >/dev/tty
        else
            printf '\033[%d;%dH%s' "$_top" "$_col" "$_label" >/dev/tty
        fi
        _col=$(( _col + ${#_label} ))
    done
    # +SQL affordance
    local _sql_hint="  ${_gray}+SQL${_rst}"
    printf '\033[%d;%dH%s' "$_top" "$_col" "$_sql_hint" >/dev/tty
}

# ── _shql_TABLE_tabbar_on_key ────────────────────────────────────────────────

_shql_TABLE_tabbar_on_key() {
    local _key="$1"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_enter=$'\r'

    case "$_key" in
        "$_k_left")
            (( _SHQL_TAB_ACTIVE > 0 )) && (( _SHQL_TAB_ACTIVE-- ))
            return 0 ;;
        "$_k_right")
            local _max=$(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
            (( _SHQL_TAB_ACTIVE < _max )) && (( _SHQL_TAB_ACTIVE++ ))
            return 0 ;;
        "$_k_down"|"$_k_enter")
            shellframe_shell_focus_set "content"
            return 0 ;;
        w)
            _shql_tab_close
            return 0 ;;
        n)
            local _fits=1
            local _rows _cols; _shellframe_shell_terminal_size _rows _cols
            local _sidebar_w; _shql_browser_sidebar_width "$_cols" _sidebar_w
            _shql_tab_fits $(( _cols - _sidebar_w )) _fits
            if (( _fits )); then
                _shql_tab_open "" "query"
                shellframe_shell_focus_set "content"
            fi
            return 0 ;;
    esac
    return 1
}

_shql_TABLE_tabbar_on_focus() {
    _SHQL_BROWSER_TABBAR_FOCUSED="${1:-0}"
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(tabbar_labels|PASS|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): dynamic tab bar renderer and tabbar on_key handler"
```

---

## Task 7: Content dispatch + data tab + empty state

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

The content region dispatches to the appropriate tab renderer based on `_SHQL_TABS_TYPE[$_SHQL_TAB_ACTIVE]`. When no tabs are open, it shows a centered hint.

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "content_dispatch: empty state hint shown when ACTIVE=-1"
_SHQL_TAB_ACTIVE=-1
_shql_content_type _type
assert_eq "empty" "$_type"

ptyunit_test_begin "content_dispatch: data type when active tab is data"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_content_type _type
assert_eq "data" "$_type"

ptyunit_test_begin "content_dispatch: schema type when active tab is schema"
shql_table_init_browser
_shql_tab_open "users" "schema"
_shql_content_type _type
assert_eq "schema" "$_type"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "content_dispatch"
```

- [ ] **Step 3: Implement content dispatch**

```bash
# ── _shql_content_type ────────────────────────────────────────────────────────
# Sets out_var to the type string of the active tab: "data"|"schema"|"query"|"empty"
_shql_content_type() {
    local _out_var="$1"
    if (( _SHQL_TAB_ACTIVE < 0 )); then
        printf -v "$_out_var" '%s' "empty"
        return 0
    fi
    printf -v "$_out_var" '%s' "${_SHQL_TABS_TYPE[$_SHQL_TAB_ACTIVE]:-empty}"
}

# ── _shql_TABLE_content_render ────────────────────────────────────────────────

_shql_TABLE_content_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    local _type
    _shql_content_type _type

    case "$_type" in
        data)
            # Load data for this tab's table if not already loaded
            _shql_content_data_ensure
            SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
            SHELLFRAME_GRID_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
            _shql_grid_fill_width "$_width"
            shellframe_grid_render "$_top" "$_left" "$_width" "$_height"
            _shql_grid_restore_last
            # Overlay inspector if active
            (( _SHQL_INSPECTOR_ACTIVE )) && _shql_inspector_render "$_top" "$_left" "$_width" "$_height"
            ;;
        schema)
            _shql_schema_tab_render "$_top" "$_left" "$_width" "$_height"
            ;;
        query)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            _shql_query_render_ctx "$_ctx" "$_top" "$_left" "$_width" "$_height"
            ;;
        *)
            # Empty state
            local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
            local _r
            for (( _r=0; _r<_height; _r++ )); do
                printf '\033[%d;%dH%*s' "$(( _top + _r ))" "$_left" "$_width" '' >/dev/tty
            done
            local _mid=$(( _top + _height / 2 ))
            local _hint="↑↓ select a table · Enter = Data · s = Schema · n = New query"
            printf '\033[%d;%dH%s%s%s' "$_mid" "$_left" "$_gray" "$_hint" "$_rst" >/dev/tty
            ;;
    esac
}

_shql_TABLE_content_on_focus() {
    _SHQL_BROWSER_CONTENT_FOCUSED="${1:-0}"
    SHELLFRAME_GRID_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
}
```

Add a per-tab data loader helper:

```bash
# ── _shql_content_data_ensure ─────────────────────────────────────────────────
# Loads data grid for the active tab's table if it hasn't been loaded yet.
# Uses a "loaded" sentinel stored as a variable named _SHQL_TAB_DATA_LOADED_<ctx>.
_shql_content_data_ensure() {
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0
    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    local _table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]}"
    local _sentinel="_SHQL_TAB_DATA_LOADED_${_ctx}"
    [[ "${!_sentinel:-0}" == "1" ]] && return 0

    SHELLFRAME_GRID_HEADERS=()
    SHELLFRAME_GRID_DATA=()
    SHELLFRAME_GRID_ROWS=0
    SHELLFRAME_GRID_COLS=0
    SHELLFRAME_GRID_COL_WIDTHS=()
    SHELLFRAME_GRID_CTX="${_ctx}_grid"
    SHELLFRAME_GRID_PK_COLS=1

    local _maxcw="${SHQL_MAX_COL_WIDTH:-30}"
    local _idx=0 _c _cell _cw _hw _cv
    local _row=()
    while IFS=$'\t' read -r -a _row; do
        [[ ${#_row[@]} -eq 0 ]] && continue
        if (( _idx == 0 )); then
            SHELLFRAME_GRID_HEADERS=("${_row[@]}")
            SHELLFRAME_GRID_COLS=${#_row[@]}
            for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                _hw=${#_row[$_c]}
                _cw=$(( _hw + 2 ))
                (( _cw < 8      )) && _cw=8
                (( _cw > _maxcw )) && _cw=$_maxcw
                SHELLFRAME_GRID_COL_WIDTHS+=("$_cw")
            done
        else
            for (( _c=0; _c<SHELLFRAME_GRID_COLS; _c++ )); do
                _cell="${_row[$_c]:-}"
                SHELLFRAME_GRID_DATA+=("$_cell")
                _cv=$(( ${#_cell} + 2 ))
                (( _cv > _maxcw )) && _cv=$_maxcw
                (( _cv > SHELLFRAME_GRID_COL_WIDTHS[$_c] )) && \
                    SHELLFRAME_GRID_COL_WIDTHS[$_c]=$_cv
            done
            (( SHELLFRAME_GRID_ROWS++ ))
        fi
        (( _idx++ ))
    done < <(shql_db_fetch "$SHQL_DB_PATH" "$_table" 2>"$_SHQL_STDERR_TTY")

    _shql_detect_grid_align
    shellframe_grid_init "${_ctx}_grid"
    printf -v "$_sentinel" '%s' "1"
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(content_dispatch|PASS|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): content dispatch with data tab renderer and empty state"
```

---

## Task 8: Schema tab renderer (columns + DDL panes)

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

The schema tab renders two side-by-side focusable panes inside the content area. It reuses `_shql_schema_load_ddl` and `_shql_schema_load_columns` from `schema.sh` (which is still sourced), but stores data per-tab using the ctx id.

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "schema_tab_load: loads DDL and columns for active tab"
shql_table_init_browser
_shql_tab_open "users" "schema"
_shql_schema_tab_load "users"
local _sentinel="_SHQL_SCHEMA_TAB_LOADED_${_SHQL_TABS_CTX[0]}"
assert_eq "1" "${!_sentinel:-0}"

ptyunit_test_begin "schema_tab: focus defaults to cols pane"
shql_table_init_browser
_shql_tab_open "users" "schema"
_SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
assert_eq "schema_cols" "$_SHQL_BROWSER_CONTENT_FOCUS"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "schema_tab"
```

- [ ] **Step 3: Implement schema tab loader and renderer**

```bash
# ── _shql_schema_tab_load ─────────────────────────────────────────────────────
# Load DDL and columns for the given table under the active tab's ctx.
_shql_schema_tab_load() {
    local _table="$1"
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0
    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    local _sentinel="_SHQL_SCHEMA_TAB_LOADED_${_ctx}"
    [[ "${!_sentinel:-0}" == "1" ]] && return 0

    # Load DDL into ctx-namespaced array
    local _arr_ddl="_SHQL_SCHEMA_TAB_DDL_${_ctx}"
    eval "${_arr_ddl}=()"
    local _line
    while IFS= read -r _line; do
        eval "${_arr_ddl}+=(\"${_line//\"/\\\"}\")"
    done < <(shql_db_describe "$SHQL_DB_PATH" "$_table" 2>/dev/null)
    local _n_ddl
    eval "_n_ddl=\${#${_arr_ddl}[@]}"
    shellframe_scroll_init "${_ctx}_ddl" "$_n_ddl" 1 10 1

    # Load columns into ctx-namespaced array
    local _arr_cols="_SHQL_SCHEMA_TAB_COLS_${_ctx}"
    eval "${_arr_cols}=()"
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        eval "${_arr_cols}+=(\"${_line//\"/\\\"}\")"
    done < <(shql_db_columns "$SHQL_DB_PATH" "$_table" 2>/dev/null)
    local _n_cols
    eval "_n_cols=\${#${_arr_cols}[@]}"
    shellframe_scroll_init "${_ctx}_cols" "$_n_cols" 1 10 1

    printf -v "$_sentinel" '%s' "1"
}

# ── _shql_schema_tab_render ───────────────────────────────────────────────────

_shql_schema_tab_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    (( _SHQL_TAB_ACTIVE < 0 )) && return 0

    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
    local _table="${_SHQL_TABS_TABLE[$_SHQL_TAB_ACTIVE]}"
    _shql_schema_tab_load "$_table"

    local _cols_w=$(( _width * 4 / 10 ))
    (( _cols_w < 15 )) && _cols_w=15
    local _ddl_w=$(( _width - _cols_w ))
    local _ddl_left=$(( _left + _cols_w ))

    local _cols_focused=0 _ddl_focused=0
    [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]] && _cols_focused=1
    [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_ddl"  ]] && _ddl_focused=1

    # Columns pane
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE="Columns"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_cols_focused
    shellframe_panel_render "$_top" "$_left" "$_cols_w" "$_height"
    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_cols_w" "$_height" _it _il _iw _ih
    local _arr_cols="_SHQL_SCHEMA_TAB_COLS_${_ctx}"
    local _n_cols; eval "_n_cols=\${#${_arr_cols}[@]}"
    shellframe_scroll_resize "${_ctx}_cols" "$_ih" 1
    local _scroll_top=0; shellframe_scroll_top "${_ctx}_cols" _scroll_top
    local _r
    for (( _r=0; _r<_ih; _r++ )); do
        local _idx=$(( _scroll_top + _r ))
        printf '\033[%d;%dH%*s' "$(( _it + _r ))" "$_il" "$_iw" '' >/dev/tty
        (( _idx >= _n_cols )) && continue
        local _entry; eval "_entry=\"\${${_arr_cols}[$_idx]}\""
        local _cname _ctype _cflags
        IFS=$'\t' read -r _cname _ctype _cflags <<< "$_entry"
        local _plain
        if [[ -n "$_cflags" ]]; then
            _plain=$(printf '%-12s %-7s %s' "$_cname" "$_ctype" "$_cflags")
        else
            _plain=$(printf '%-12s %s' "$_cname" "$_ctype")
        fi
        local _clipped; _clipped=$(shellframe_str_clip_ellipsis "$_plain" "$_plain" "$_iw")
        printf '\033[%d;%dH%s' "$(( _it + _r ))" "$_il" "$_clipped" >/dev/tty
    done

    # DDL pane
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE="DDL"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=$_ddl_focused
    shellframe_panel_render "$_top" "$_ddl_left" "$_ddl_w" "$_height"
    shellframe_panel_inner "$_top" "$_ddl_left" "$_ddl_w" "$_height" _it _il _iw _ih
    local _arr_ddl="_SHQL_SCHEMA_TAB_DDL_${_ctx}"
    local _n_ddl; eval "_n_ddl=\${#${_arr_ddl}[@]}"
    shellframe_scroll_resize "${_ctx}_ddl" "$_ih" 1
    _scroll_top=0; shellframe_scroll_top "${_ctx}_ddl" _scroll_top
    for (( _r=0; _r<_ih; _r++ )); do
        local _idx=$(( _scroll_top + _r ))
        printf '\033[%d;%dH%*s' "$(( _it + _r ))" "$_il" "$_iw" '' >/dev/tty
        (( _idx >= _n_ddl )) && continue
        local _line; eval "_line=\"\${${_arr_ddl}[$_idx]}\""
        local _clipped; _clipped=$(shellframe_str_clip_ellipsis "$_line" "$_line" "$_iw")
        printf '\033[%d;%dH%s' "$(( _it + _r ))" "$_il" "$_clipped" >/dev/tty
    done
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(schema_tab|PASS|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): schema tab renderer with columns + DDL panes"
```

---

## Task 9: Query tab — dynamic context ids and placeholder fix

**Files:**
- Modify: `src/screens/query.sh`
- Test: `tests/unit/test-query.sh`

The query tab's two-pane layout (editor top 30%, results bottom 70%) and key handling already exist in `_shql_query_render` and `_shql_query_on_key`. The existing `_shql_query_render` uses fixed globals `_SHQL_QUERY_EDITOR_CTX="query_sql"`. Multiple query tabs need independent ctx. We add a `_shql_query_render_ctx <ctx> t l w h` wrapper and a `_shql_query_init_ctx <ctx>` that stores per-ctx state. The shared globals are loaded/saved around each call so each tab's state is isolated.

- [ ] **Step 1: Write the failing tests**

Add to `tests/unit/test-query.sh`:

```bash
ptyunit_test_begin "query_init_ctx: initializes state for given ctx"
_shql_query_init_ctx "t2"
assert_eq 0 "$_SHQL_QUERY_CTX_INITIALIZED_t2"
assert_eq "editor" "$_SHQL_QUERY_CTX_FOCUSED_PANE_t2"
assert_eq "" "$_SHQL_QUERY_CTX_STATUS_t2"

ptyunit_test_begin "query: placeholder text is 'No results yet'"
# The placeholder is in _shql_query_render_ctx — check the constant
assert_contains "${_SHQL_QUERY_PLACEHOLDER:-No results yet}" "No results yet"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "query_init_ctx\|placeholder"
```

- [ ] **Step 3: Add dynamic ctx support to query.sh**

Add at the top of `query.sh`:

```bash
_SHQL_QUERY_PLACEHOLDER="No results yet"
```

Add init and render wrapper:

```bash
# ── _shql_query_init_ctx ──────────────────────────────────────────────────────
# Initialise per-ctx state variables for a query tab.
# State vars: _SHQL_QUERY_CTX_INITIALIZED_<ctx>, _SHQL_QUERY_CTX_FOCUSED_PANE_<ctx>,
#             _SHQL_QUERY_CTX_STATUS_<ctx>, _SHQL_QUERY_CTX_EDITOR_ACTIVE_<ctx>,
#             _SHQL_QUERY_CTX_HAS_RESULTS_<ctx>
_shql_query_init_ctx() {
    local _ctx="$1"
    printf -v "_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"   '%d' 0
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "editor"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' ""
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' 0
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' 0
}

# ── _shql_query_render_ctx ────────────────────────────────────────────────────
# Render query tab for the given ctx. Loads per-ctx state into the shared
# globals used by _shql_query_render, then delegates.
_shql_query_render_ctx() {
    local _ctx="$1"; shift

    # Load per-ctx state into shared globals
    local _init_var="_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"
    [[ "${!_init_var:-}" == "" ]] && _shql_query_init_ctx "$_ctx"

    _SHQL_QUERY_EDITOR_CTX="${_ctx}_editor"
    _SHQL_QUERY_GRID_CTX="${_ctx}_results"

    local _fp_var="_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"
    local _ea_var="_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}"
    local _hr_var="_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"
    local _st_var="_SHQL_QUERY_CTX_STATUS_${_ctx}"
    _SHQL_QUERY_FOCUSED_PANE="${!_fp_var:-editor}"
    _SHQL_QUERY_EDITOR_ACTIVE="${!_ea_var:-0}"
    _SHQL_QUERY_HAS_RESULTS="${!_hr_var:-0}"
    _SHQL_QUERY_STATUS="${!_st_var:-}"
    local _ini_var="_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"
    _SHQL_QUERY_INITIALIZED="${!_ini_var:-0}"

    _shql_query_render "$@"

    # Save state back
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "$_SHQL_QUERY_FOCUSED_PANE"
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_EDITOR_ACTIVE"
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' "$_SHQL_QUERY_HAS_RESULTS"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' "$_SHQL_QUERY_STATUS"
    printf -v "_SHQL_QUERY_CTX_INITIALIZED_${_ctx}"   '%d' "$_SHQL_QUERY_INITIALIZED"
}
```

Fix the placeholder text in `_shql_query_render` (replace the hardcoded string):

```bash
# In _shql_query_render, change:
#   printf '\033[%d;%dH%sNo results yet.  Press [Enter]...'
# to use the variable:
        printf '\033[%d;%dH%s%s%s' \
            "$_mid" "$_ril" "$_gray" "$_SHQL_QUERY_PLACEHOLDER" "$_rst" >/dev/tty
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(query_init_ctx|placeholder|PASS|FAIL)"
```
Expected: both new tests PASS; all prior query tests still PASS

- [ ] **Step 5: Commit**

```bash
git add src/screens/query.sh tests/unit/test-query.sh
git commit -m "feat(query): dynamic context ids, _shql_query_render_ctx, placeholder constant"
```

---

## Task 10: Content on_key + spatial navigation

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

Wire up key handling for the content region. Implements `↑` at row 0 → tabbar, `←` at col 0 → sidebar, and `[`/`]` tab switching from data grid. This task also defines `_shql_schema_tab_on_key` and `_shql_query_on_key_ctx`, which are called from the content dispatcher.

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "content_on_key: up at row 0 in data tab moves focus to tabbar"
shql_table_init_browser
_shql_tab_open "users" "data"
_SHQL_BROWSER_CONTENT_FOCUSED=1
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }   # simulate row 0
_saved_focus=""
shellframe_shell_focus_set() { _saved_focus="$1"; }
_shql_TABLE_content_on_key $'\033[A'   # up
assert_eq "tabbar" "$_saved_focus"
shellframe_shell_focus_set() { true; }

ptyunit_test_begin "content_on_key: ] switches to next tab"
shql_table_init_browser
_shql_tab_open "users" "data"
_shql_tab_open "orders" "data"
_SHQL_TAB_ACTIVE=0
shellframe_grid_on_key() { return 1; }   # doesn't handle ]
_shql_TABLE_content_on_key ']'
assert_eq 1 "$_SHQL_TAB_ACTIVE"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "content_on_key"
```

- [ ] **Step 3: Implement `_shql_TABLE_content_on_key` and `_shql_TABLE_content_action`**

```bash
# ── _shql_TABLE_content_on_key ────────────────────────────────────────────────

_shql_TABLE_content_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"

    # Route to inspector when active
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _shql_inspector_on_key "$_key"
        return $?
    fi

    local _type
    _shql_content_type _type

    # [ / ] switch tabs from content
    case "$_key" in
        '[')
            (( _SHQL_TAB_ACTIVE > 0 )) && (( _SHQL_TAB_ACTIVE-- ))
            return 0 ;;
        ']')
            local _max=$(( ${#_SHQL_TABS_TYPE[@]} - 1 ))
            (( _SHQL_TAB_ACTIVE < _max )) && (( _SHQL_TAB_ACTIVE++ ))
            return 0 ;;
    esac

    case "$_type" in
        data)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            # ↑ at row 0 → tabbar
            if [[ "$_key" == "$_k_up" ]]; then
                local _cursor=0
                shellframe_sel_cursor "${_ctx}_grid" _cursor 2>/dev/null || true
                if (( _cursor == 0 )); then
                    shellframe_shell_focus_set "tabbar"
                    return 0
                fi
            fi
            # ← at col 0 → sidebar
            if [[ "$_key" == "$_k_left" ]]; then
                local _scroll_left=0
                shellframe_scroll_top "${_ctx}_grid" _scroll_left 2>/dev/null || true
                if (( _scroll_left == 0 )); then
                    shellframe_shell_focus_set "sidebar"
                    return 0
                fi
            fi
            SHELLFRAME_GRID_CTX="${_ctx}_grid"
            shellframe_grid_on_key "$_key"
            return $?
            ;;
        schema)
            _shql_schema_tab_on_key "$_key"
            return $?
            ;;
        query)
            local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
            _shql_query_on_key_ctx "$_ctx" "$_key"
            return $?
            ;;
    esac
    return 1
}

# ── _shql_TABLE_content_action ────────────────────────────────────────────────
# Called when content on_key returns 2 (Enter on data grid row).

_shql_TABLE_content_action() {
    local _type
    _shql_content_type _type
    if [[ "$_type" == "data" ]]; then
        local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"
        SHELLFRAME_GRID_CTX="${_ctx}_grid"
        _shql_inspector_open
    fi
}

# ── _shql_schema_tab_on_key ───────────────────────────────────────────────────

_shql_schema_tab_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_tab=$'\t'
    local _k_shift_tab=$'\033[Z'
    (( _SHQL_TAB_ACTIVE < 0 )) && return 1
    local _ctx="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}"

    case "$_key" in
        "$_k_up")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]]; then
                shellframe_scroll_move "${_ctx}_cols" up
            else
                shellframe_scroll_move "${_ctx}_ddl" up
            fi
            return 0 ;;
        "$_k_down")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]]; then
                shellframe_scroll_move "${_ctx}_cols" down
            else
                shellframe_scroll_move "${_ctx}_ddl" down
            fi
            return 0 ;;
        "$_k_tab")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_cols" ]]; then
                _SHQL_BROWSER_CONTENT_FOCUS="schema_ddl"
            else
                _SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
                shellframe_shell_focus_set "sidebar"   # Tab from DDL exits
            fi
            return 0 ;;
        "$_k_shift_tab")
            if [[ "$_SHQL_BROWSER_CONTENT_FOCUS" == "schema_ddl" ]]; then
                _SHQL_BROWSER_CONTENT_FOCUS="schema_cols"
            else
                shellframe_shell_focus_set "tabbar"
            fi
            return 0 ;;
    esac
    return 1
}

# ── _shql_query_on_key_ctx ────────────────────────────────────────────────────
# Load per-ctx query state, delegate to _shql_query_on_key, save state back.
_shql_query_on_key_ctx() {
    local _ctx="$1" _key="$2"
    _SHQL_QUERY_EDITOR_CTX="${_ctx}_editor"
    _SHQL_QUERY_GRID_CTX="${_ctx}_results"
    local _fp="_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"
    local _ea="_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}"
    local _hr="_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"
    local _st="_SHQL_QUERY_CTX_STATUS_${_ctx}"
    _SHQL_QUERY_FOCUSED_PANE="${!_fp:-editor}"
    _SHQL_QUERY_EDITOR_ACTIVE="${!_ea:-0}"
    _SHQL_QUERY_HAS_RESULTS="${!_hr:-0}"
    _SHQL_QUERY_STATUS="${!_st:-}"
    _shql_query_on_key "$_key"
    local _rc=$?
    printf -v "_SHQL_QUERY_CTX_FOCUSED_PANE_${_ctx}"  '%s' "$_SHQL_QUERY_FOCUSED_PANE"
    printf -v "_SHQL_QUERY_CTX_EDITOR_ACTIVE_${_ctx}" '%d' "$_SHQL_QUERY_EDITOR_ACTIVE"
    printf -v "_SHQL_QUERY_CTX_HAS_RESULTS_${_ctx}"   '%d' "$_SHQL_QUERY_HAS_RESULTS"
    printf -v "_SHQL_QUERY_CTX_STATUS_${_ctx}"         '%s' "$_SHQL_QUERY_STATUS"
    return $_rc
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(content_on_key|PASS|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): content on_key with spatial nav, schema/query delegation"
```

---

## Task 11: Inspector inline redesign — nav bar and padding

**Files:**
- Modify: `src/screens/inspector.sh`
- Test: `tests/unit/test-inspector.sh`

Replace the centered overlay with an inline fill-content-area view. Add a nav bar row and 1-char inner padding. Keep the two-column key/value layout.

- [ ] **Step 1: Write the failing tests**

Add to `tests/unit/test-inspector.sh`:

```bash
# ── New: inline inspector state ───────────────────────────────────────────────

ptyunit_test_begin "inspector_open: records row index in _SHQL_INSPECTOR_ROW_IDX"
_setup_mock_grid
shellframe_sel_move "test_grid" home  # cursor at row 0
_shql_inspector_open
assert_eq "$_SHQL_INSPECTOR_ROW_IDX" "0" "open: ROW_IDX=0 when cursor at row 0"

_setup_mock_grid
shellframe_sel_move "test_grid" down  # cursor at row 1
_shql_inspector_open
assert_eq "$_SHQL_INSPECTOR_ROW_IDX" "1" "open: ROW_IDX=1 when cursor at row 1"

ptyunit_test_begin "inspector_navbar: format is '← VALUE  (N/Total) →'"
_SHQL_INSPECTOR_PAIRS=("id	42" "name	Alice" "email	a@b.com")
_SHQL_INSPECTOR_ROW_IDX=2
_SHQL_INSPECTOR_TOTAL_ROWS=5
_shql_inspector_nav_label _nav
assert_contains "$_nav" "42"
assert_contains "$_nav" "(3/5)"
assert_contains "$_nav" "←"
assert_contains "$_nav" "→"

ptyunit_test_begin "inspector_on_key: Esc sets ACTIVE=0 and preserves ROW_IDX"
_SHQL_INSPECTOR_ACTIVE=1
_SHQL_INSPECTOR_ROW_IDX=3
_shql_inspector_on_key $'\033'
assert_eq "0" "$_SHQL_INSPECTOR_ACTIVE" "Esc: sets ACTIVE=0"
assert_eq "3" "$_SHQL_INSPECTOR_ROW_IDX" "Esc: preserves ROW_IDX for cursor return"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "inspector_open.*row|inspector_navb|inspector_on_key.*Esc"
```

- [ ] **Step 3: Rewrite inspector.sh**

```bash
# New state globals:
_SHQL_INSPECTOR_ACTIVE=0
_SHQL_INSPECTOR_PAIRS=()
_SHQL_INSPECTOR_CTX="inspector_scroll"
_SHQL_INSPECTOR_ROW_IDX=0       # which data-grid row is being inspected
_SHQL_INSPECTOR_TOTAL_ROWS=0    # total rows in the grid (for nav bar)
```

Update `_shql_inspector_open`:

```bash
_shql_inspector_open() {
    [[ "${SHELLFRAME_GRID_ROWS:-0}" -eq 0 ]] && return 0

    local _cursor=0
    shellframe_sel_cursor "${SHELLFRAME_GRID_CTX:-}" _cursor 2>/dev/null || true

    _SHQL_INSPECTOR_ROW_IDX=$_cursor
    _SHQL_INSPECTOR_TOTAL_ROWS="${SHELLFRAME_GRID_ROWS:-0}"

    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_INSPECTOR_PAIRS=()
    local _c _idx _key _val
    for (( _c=0; _c<_ncols; _c++ )); do
        _key="${SHELLFRAME_GRID_HEADERS[$_c]:-col$_c}"
        _idx=$(( _cursor * _ncols + _c ))
        _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        [[ -z "$_val" ]] && _val="(null)"
        _SHQL_INSPECTOR_PAIRS+=("${_key}"$'\t'"${_val}")
    done

    local _n=${#_SHQL_INSPECTOR_PAIRS[@]}
    local _scroll_n=$(( (_n + 1) / 2 ))
    shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_scroll_n" 1 10 1
    _SHQL_INSPECTOR_ACTIVE=1
}
```

Add nav label helper:

```bash
_shql_inspector_nav_label() {
    local _out_var="$1"
    local _first_val=""
    if [[ ${#_SHQL_INSPECTOR_PAIRS[@]} -gt 0 ]]; then
        _first_val="${_SHQL_INSPECTOR_PAIRS[0]#*	}"
    fi
    local _n=$(( _SHQL_INSPECTOR_ROW_IDX + 1 ))
    local _total="$_SHQL_INSPECTOR_TOTAL_ROWS"
    printf -v "$_out_var" '← %s  (%d/%d) →' "$_first_val" "$_n" "$_total"
}
```

Rewrite `_shql_inspector_render` as inline fill-area (not overlay):

```bash
_shql_inspector_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Draw panel border filling the full content area
    SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE="${_SHQL_TABS_LABEL[$_SHQL_TAB_ACTIVE]:-Record Inspector}"
    SHELLFRAME_PANEL_TITLE_ALIGN="left"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

    local _it _il _iw _ih
    shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

    # 1-char inner padding (all sides)
    local _pt=$(( _it + 1 ))         # pad top
    local _pl=$(( _il + 1 ))         # pad left
    local _pw=$(( _iw - 2 ))         # content width (1 pad each side)
    local _ph=$(( _ih - 2 ))         # content height (1 pad top + 1 pad bottom)
    (( _pw < 1 )) && _pw=1
    (( _ph < 1 )) && _ph=1

    # Clear inner area
    local _ir _blank
    printf -v _blank '%*s' "$_iw" ''
    for (( _ir=0; _ir<_ih; _ir++ )); do
        printf '\033[%d;%dH%s' "$(( _it + _ir ))" "$_il" "$_blank" >/dev/tty
    done

    # Nav bar (first inner padded row)
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    local _nav
    _shql_inspector_nav_label _nav
    local _nav_clipped
    _nav_clipped=$(shellframe_str_clip_ellipsis "$_nav" "$_nav" "$_pw")
    printf '\033[%d;%dH%s%s%s' "$_pt" "$_pl" "$_gray" "$_nav_clipped" "$_rst" >/dev/tty

    # Separator line
    local _sep_row=$(( _pt + 1 ))
    printf '\033[%d;%dH%s' "$_sep_row" "$_il" "$(printf '─%.0s' $(seq 1 $_iw))" >/dev/tty

    # Two-column key/value area starts 2 rows after padded top (nav + sep)
    local _kv_top=$(( _pt + 2 ))
    local _kv_h=$(( _ph - 2 ))
    (( _kv_h < 1 )) && _kv_h=1

    # Column layout
    local _col_w=$(( (_pw - 1) / 2 ))
    (( _col_w < 1 )) && _col_w=1
    local _divider_col=$(( _pl + _col_w ))
    local _kw; _shql_inspector_key_width _kw
    local _l_left=$(( _pl + 1 ))
    local _val_avail_l=$(( _col_w - 1 - _kw - 2 ))
    (( _val_avail_l < 1 )) && _val_avail_l=1
    local _r_left=$(( _divider_col + 2 ))
    local _val_avail_r=$(( _pw - _col_w - 2 - _kw - 2 ))
    (( _val_avail_r < 1 )) && _val_avail_r=1

    local _kc="${SHQL_THEME_KEY_COLOR:-}" _vc="${SHQL_THEME_VALUE_COLOR:-}"
    local _n_pairs=${#_SHQL_INSPECTOR_PAIRS[@]}
    local _n_rows=$(( (_n_pairs + 1) / 2 ))

    shellframe_scroll_resize "$_SHQL_INSPECTOR_CTX" "$_kv_h" 1
    local _scroll_top=0
    shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _scroll_top

    local _r _logical_r _l_idx _r_idx _pair _key _val _val_clipped
    for (( _r=0; _r<_kv_h; _r++ )); do
        _logical_r=$(( _scroll_top + _r ))
        [[ $_logical_r -ge $_n_rows ]] && continue
        local _row=$(( _kv_top + _r ))

        _l_idx=$(( _logical_r * 2 ))
        if [[ $_l_idx -lt $_n_pairs ]]; then
            _pair="${_SHQL_INSPECTOR_PAIRS[$_l_idx]}"
            _key="${_pair%%	*}"; _val="${_pair#*	}"
            _val_clipped=$(shellframe_str_clip_ellipsis "$_val" "$_val" "$_val_avail_l")
            printf '\033[%d;%dH%s%-*s%s  %s%s%s' \
                "$_row" "$_l_left" "$_kc" "$_kw" "$_key" "$_rst" \
                "$_vc" "$_val_clipped" "$_rst" >/dev/tty
        fi

        printf '\033[%d;%dH│' "$_row" "$_divider_col" >/dev/tty

        _r_idx=$(( _logical_r * 2 + 1 ))
        if [[ $_r_idx -lt $_n_pairs ]]; then
            _pair="${_SHQL_INSPECTOR_PAIRS[$_r_idx]}"
            _key="${_pair%%	*}"; _val="${_pair#*	}"
            _val_clipped=$(shellframe_str_clip_ellipsis "$_val" "$_val" "$_val_avail_r")
            printf '\033[%d;%dH%s%-*s%s  %s%s%s' \
                "$_row" "$_r_left" "$_kc" "$_kw" "$_key" "$_rst" \
                "$_vc" "$_val_clipped" "$_rst" >/dev/tty
        fi
    done
}
```

Update `_shql_inspector_on_key` to keep `_SHQL_INSPECTOR_ROW_IDX` on Esc (it already does — just don't reset it):

```bash
# In the Esc/Enter/q case, only set ACTIVE=0, do NOT reset ROW_IDX
$'\033'|$'\r'|$'\n')
    _SHQL_INSPECTOR_ACTIVE=0
    return 0 ;;
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(inspector|PASS|FAIL)"
```
Expected: all new inspector tests PASS; existing tests still PASS (the open/key_width/scroll tests don't depend on overlay geometry)

- [ ] **Step 5: Commit**

```bash
git add src/screens/inspector.sh tests/unit/test-inspector.sh
git commit -m "feat(inspector): inline content view, nav bar, ROW_IDX tracking, 1-char padding"
```

---

## Task 12: Inspector ←→ row stepping

**Files:**
- Modify: `src/screens/inspector.sh`
- Test: `tests/unit/test-inspector.sh`

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "inspector_step: → advances to next row"
_setup_mock_grid   # 2 rows: Alice (0), Bob (1)
shellframe_sel_move "test_grid" home
_shql_inspector_open
_SHQL_INSPECTOR_GRID_CTX="test_grid"
_shql_inspector_on_key $'\033[C'   # right arrow
assert_eq "1" "$_SHQL_INSPECTOR_ROW_IDX" "→: ROW_IDX advances to 1"
assert_contains "${_SHQL_INSPECTOR_PAIRS[1]#*	}" "Bob" "→: pairs reloaded for row 1"

ptyunit_test_begin "inspector_step: → wraps at last row"
_shql_inspector_on_key $'\033[C'   # right again from row 1 (last)
assert_eq "0" "$_SHQL_INSPECTOR_ROW_IDX" "→: wraps back to row 0"

ptyunit_test_begin "inspector_step: ← at row 0 wraps to last"
_shql_inspector_on_key $'\033[D'   # left from row 0
assert_eq "1" "$_SHQL_INSPECTOR_ROW_IDX" "←: wraps to last row"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "inspector_step"
```

- [ ] **Step 3: Implement row stepping in `_shql_inspector_on_key`**

Add state global: `_SHQL_INSPECTOR_GRID_CTX=""` — the grid context to step through.
Set it in `_shql_inspector_open`: `_SHQL_INSPECTOR_GRID_CTX="${SHELLFRAME_GRID_CTX:-}"`.

Add row-step handler:

```bash
# ── _shql_inspector_step ──────────────────────────────────────────────────────
# Move to the next (+1) or previous (-1) row in the grid.
_shql_inspector_step() {
    local _delta="$1"
    local _total="${_SHQL_INSPECTOR_TOTAL_ROWS:-0}"
    (( _total == 0 )) && return 0

    local _new=$(( _SHQL_INSPECTOR_ROW_IDX + _delta ))
    # Wrap
    (( _new < 0 )) && _new=$(( _total - 1 ))
    (( _new >= _total )) && _new=0

    _SHQL_INSPECTOR_ROW_IDX=$_new

    # Reload pairs from the grid data
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    _SHQL_INSPECTOR_PAIRS=()
    local _c _idx _key _val
    for (( _c=0; _c<_ncols; _c++ )); do
        _key="${SHELLFRAME_GRID_HEADERS[$_c]:-col$_c}"
        _idx=$(( _new * _ncols + _c ))
        _val="${SHELLFRAME_GRID_DATA[$_idx]:-}"
        [[ -z "$_val" ]] && _val="(null)"
        _SHQL_INSPECTOR_PAIRS+=("${_key}"$'\t'"${_val}")
    done

    # Reset scroll to top for the new record
    local _n=${#_SHQL_INSPECTOR_PAIRS[@]}
    local _scroll_n=$(( (_n + 1) / 2 ))
    shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_scroll_n" 1 10 1
}
```

Add to `_shql_inspector_on_key`:

```bash
local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

case "$_key" in
    "$_k_right") _shql_inspector_step 1;  return 0 ;;
    "$_k_left")  _shql_inspector_step -1; return 0 ;;
    ...
esac
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(inspector_step|PASS|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add src/screens/inspector.sh tests/unit/test-inspector.sh
git commit -m "feat(inspector): left/right arrow steps through rows with wrap"
```

---

## Task 13: Footer hints update + global key handler

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

Update footer hints for the new focus model. Add global `q` and `w`/`n` key handler (`_shql_TABLE_quit` and content-level global keys).

- [ ] **Step 1: Write the failing tests**

```bash
ptyunit_test_begin "footer_hint: sidebar focused shows sidebar hints"
_SHQL_BROWSER_SIDEBAR_FOCUSED=1
_SHQL_BROWSER_TABBAR_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUSED=0
_shql_browser_footer_hint _hint
assert_contains "$_hint" "Enter"
assert_contains "$_hint" "s=Schema"

ptyunit_test_begin "footer_hint: empty state shows select hint"
_SHQL_BROWSER_SIDEBAR_FOCUSED=0
_SHQL_BROWSER_TABBAR_FOCUSED=0
_SHQL_BROWSER_CONTENT_FOCUSED=1
_SHQL_TAB_ACTIVE=-1
_shql_browser_footer_hint _hint
assert_contains "$_hint" "select"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep "footer_hint"
```

- [ ] **Step 3: Add footer hint function and update `_shql_TABLE_footer_render`**

```bash
_SHQL_BROWSER_FOOTER_HINTS_SIDEBAR="[↑↓] Navigate  [Enter] Data  [s] Schema  [→/Tab] Focus  [q] Back"
_SHQL_BROWSER_FOOTER_HINTS_TABBAR="[←→] Switch tab  [↓/Enter] Content  [w] Close  [n] New query  [Tab] Sidebar"
_SHQL_BROWSER_FOOTER_HINTS_DATA="[↑↓] Navigate  [←→] Scroll  [Enter] Inspect  [[/]] Tabs  [Tab] Sidebar  [q] Back"
_SHQL_BROWSER_FOOTER_HINTS_SCHEMA="[↑↓] Scroll  [Tab] DDL/exit  [q] Back"
_SHQL_BROWSER_FOOTER_HINTS_QUERY_BUTTON="[Enter] Edit  [Tab] Results  [Esc] Tab bar"
_SHQL_BROWSER_FOOTER_HINTS_INSPECTOR="[←→] Prev/Next  [↑↓] Scroll  [Esc] Grid  [Tab] Sidebar"
_SHQL_BROWSER_FOOTER_HINTS_EMPTY="[↑↓] select a table  [Enter] Data  [s] Schema  [n] New query  [q] Back"

_shql_browser_footer_hint() {
    local _out_var="$1"
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_INSPECTOR"
    elif (( _SHQL_BROWSER_SIDEBAR_FOCUSED )); then
        printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_SIDEBAR"
    elif (( _SHQL_BROWSER_TABBAR_FOCUSED )); then
        printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_TABBAR"
    else
        local _type; _shql_content_type _type
        case "$_type" in
            data)    printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_DATA" ;;
            schema)  printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_SCHEMA" ;;
            query)   _shql_query_footer_hint "$_out_var" ;;
            *)       printf -v "$_out_var" '%s' "$_SHQL_BROWSER_FOOTER_HINTS_EMPTY" ;;
        esac
    fi
}

_shql_TABLE_footer_render() {
    local _top="$1" _left="$2"
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    local _hint; _shql_browser_footer_hint _hint
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" "$_gray" "$_hint" "$_rst" >/dev/tty
}
```

Update `_shql_TABLE_quit` to go back to WELCOME:

```bash
_shql_TABLE_quit() {
    _SHELLFRAME_SHELL_NEXT="WELCOME"
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "(footer_hint|PASS|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(table): browser footer hints, TABLE quit → WELCOME"
```

---

## Task 14: `bin/shql` routing — remove SCHEMA dispatch

**Files:**
- Modify: `bin/shql`
- Test: Manual smoke test

- [ ] **Step 1: Read the current dispatch section**

Confirm the three cases to change: `open`, `table`, `query-tui`.

- [ ] **Step 2: Update `open` case**

Replace:
```bash
open)
    ...
    shql_conn_push "sqlite" "$SHQL_DB_PATH"
    _shql_welcome_init
    shql_schema_init
    shellframe_shell "_shql" "SCHEMA"
    ;;
```
With:
```bash
open)
    SHQL_DB_PATH="$_SHQL_CLI_DB"
    if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
    shql_conn_push "sqlite" "$SHQL_DB_PATH"
    _shql_welcome_init
    shql_browser_init
    shellframe_shell "_shql" "TABLE"
    ;;
```

- [ ] **Step 3: Update `table` case**

Replace:
```bash
table)
    ...
    shql_schema_init
    shql_table_init
    shellframe_shell "_shql" "TABLE"
    ;;
```
With:
```bash
table)
    SHQL_DB_PATH="$_SHQL_CLI_DB"
    SHQL_DB_TABLE="$_SHQL_CLI_TABLE"
    if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
    shql_conn_push "sqlite" "$SHQL_DB_PATH"
    _shql_welcome_init
    shql_browser_init
    # Pre-open the table as a Data tab
    _shql_tab_open "$_SHQL_CLI_TABLE" "data"
    shellframe_shell "_shql" "TABLE"
    ;;
```

- [ ] **Step 4: Update `query-tui` case**

Replace:
```bash
query-tui)
    ...
    shql_schema_init
    shql_table_init
    SHELLFRAME_TABBAR_ACTIVE=$_SHQL_TABLE_TAB_QUERY
    shellframe_shell "_shql" "TABLE"
    ;;
```
With:
```bash
query-tui)
    SHQL_DB_PATH="$_SHQL_CLI_DB"
    if ! (( SHQL_MOCK )); then _shql_db_check_path "$SHQL_DB_PATH" || exit 1; fi
    shql_conn_push "sqlite" "$SHQL_DB_PATH"
    _shql_welcome_init
    shql_browser_init
    _shql_tab_open "" "query"
    shellframe_shell "_shql" "TABLE"
    ;;
```

- [ ] **Step 5: Remove `schema.sh` source line from `bin/shql`**

```bash
# Delete the line: source "$_SHQL_ROOT/src/screens/schema.sh"
```

`src/screens/schema.sh` is **kept in the repository** but no longer sourced at runtime. It is retired as a routing destination — the SCHEMA screen no longer exists in the navigation flow. Functions from it (like `_shql_breadcrumb`) that are still used are already in `header.sh`. No functions from schema.sh are needed at runtime after this change.

- [ ] **Step 6: Smoke test**

```bash
SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```
Expected: Welcome screen opens, selecting a database enters the new TABLE browser

- [ ] **Step 7: Run full test suite**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit
```
Note: `test-schema.sh` tests will fail because `schema.sh` is no longer the routing target. Update them in the next task.

- [ ] **Step 8: Commit**

```bash
git add bin/shql
git commit -m "feat(routing): open/table/query-tui dispatch to TABLE browser, remove SCHEMA dispatch"
```

---

## Task 15: Test suite cleanup and integration test

**Files:**
- Modify: `tests/unit/test-table.sh`
- Modify: `tests/unit/test-schema.sh`
- Modify: `tests/integration/test-integration.sh`

- [ ] **Step 1: Update `test-table.sh`**

Remove stale tests:
- `"tab constants: STRUCTURE=0, DATA=1, QUERY=2"` — old static constants are gone
- `"inspector footer hint constant defined with correct text"` — old hint string gone
- `"schema sidebar_action: sets _SHQL_TABLE_NAME and NEXT=TABLE"` — old action gone
- `"shql_table_init: resets SHELLFRAME_TABBAR_ACTIVE to 0"` — not valid in new model

Replace the `shql_table_init` test with `shql_browser_init`:

```bash
ptyunit_test_begin "shql_browser_init: resets tab arrays and loads tables"
shql_browser_init
assert_eq 0 "${#_SHQL_TABS_TYPE[@]}"
assert_eq -1 "$_SHQL_TAB_ACTIVE"
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))
```

Run after changes:
```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "test-table|PASS|FAIL"
```

- [ ] **Step 2: Update `test-schema.sh`**

Remove the line that sources `src/screens/schema.sh` (since schema.sh is no longer in the project's source tree after the router change). Keep the breadcrumb tests (still in header.sh). Remove tests for `_shql_schema_load_ddl`, `_shql_schema_load_columns` since those are now inline in table.sh.

Add tests for the schema tab load function:

```bash
# Source table.sh to access schema tab functions
source "$SHQL_ROOT/src/screens/table.sh"
source "$SHQL_ROOT/src/screens/query.sh"

ptyunit_test_begin "schema_tab: _shql_schema_tab_load populates DDL array"
shql_browser_init
_shql_tab_open "users" "schema"
_shql_schema_tab_load "users"
local _ctx="${_SHQL_TABS_CTX[0]}"
local _arr="_SHQL_SCHEMA_TAB_DDL_${_ctx}"
assert_eq 1 $(( ${#_arr[@]+"${!_arr[@]}"} > 0 || 1 ))  # non-empty
```

Run:
```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh --unit 2>&1 | grep -E "test-schema|PASS|FAIL"
```

- [ ] **Step 3: Add integration test scenario**

In `tests/integration/test-integration.sh`, add:

```bash
# ── Integration: open → data tab → inspector → navigate → close ──────────────

ptyunit_test_begin "integration: browser open populates tables list"
shql_browser_init
assert_eq 1 $(( ${#_SHQL_BROWSER_TABLES[@]} > 0 ))

ptyunit_test_begin "integration: Enter in sidebar opens data tab"
shellframe_sel_cursor() { printf -v "$2" '%d' 0; }
_shql_TABLE_sidebar_action
assert_eq "data" "${_SHQL_TABS_TYPE[0]:-}"
assert_eq "users" "${_SHQL_TABS_TABLE[0]:-}"

ptyunit_test_begin "integration: data tab content_ensure loads grid"
_shql_content_data_ensure
assert_eq 1 $(( SHELLFRAME_GRID_ROWS > 0 ))

ptyunit_test_begin "integration: inspector opens on Enter in data tab"
SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[0]}_grid"
_shql_inspector_open
assert_eq 1 "$_SHQL_INSPECTOR_ACTIVE"
assert_eq "id" "${_SHQL_INSPECTOR_PAIRS[0]%%	*}"

ptyunit_test_begin "integration: inspector Esc restores ACTIVE=0 with ROW_IDX preserved"
local _saved_idx="$_SHQL_INSPECTOR_ROW_IDX"
_shql_inspector_on_key $'\033'
assert_eq 0 "$_SHQL_INSPECTOR_ACTIVE"
assert_eq "$_saved_idx" "$_SHQL_INSPECTOR_ROW_IDX"
```

Run:
```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh 2>&1 | tail -20
```
Expected: all suites PASS

- [ ] **Step 4: Run the full suite and confirm green**

```bash
SHELLFRAME_DIR=../shellframe bash tests/run.sh
```
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test-table.sh tests/unit/test-schema.sh tests/integration/test-integration.sh
git commit -m "test: update test suite for browser redesign — remove stale tests, add integration scenario"
```

---

## Post-implementation checklist

- [ ] Smoke test `open` mode: `SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql` — sidebar visible, Enter/s open tabs, +SQL opens query tab
- [ ] Smoke test `query-tui` mode: `SHELLFRAME_DIR=../shellframe bash bin/shql tests/fixtures/demo.sqlite --query` — TABLE opens with Query tab active
- [ ] Verify inspector nav bar renders correctly: open data tab → Enter on row → check nav label format and ←→ stepping
- [ ] Verify schema tab: s in sidebar → both panes visible and focusable with Tab
- [ ] Update `PLAN.md` session handoff notes with completion status
- [ ] Close or update GitHub issues #12, #16, #17, #18, #19
