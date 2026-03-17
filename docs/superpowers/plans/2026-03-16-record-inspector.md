# Record Inspector Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a centered key/value overlay panel to the TABLE screen that appears when the user presses Enter on a data grid row, scrollable with ↑/↓, dismissed with Enter/Esc/q.

**Architecture:** New `src/screens/inspector.sh` owns all inspector state and logic. `src/screens/table.sh` is modified in three targeted places: body render (overlay call), body on_key (guard), and footer (hint branch). A new `_shql_TABLE_body_action` function triggers the open. The inspector overlays the body region by rendering on top of the existing grid content — no region layout changes needed.

**Tech Stack:** bash 3.2+, shellframe composable widget API (scroll.sh, panel.sh, clip.sh)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `src/screens/inspector.sh` | **Create** | Inspector state, open, render, on_key |
| `src/screens/table.sh` | **Modify** | body_action (new), body_render overlay call, body_on_key guard, footer hint branch |
| `bin/shql` | **Modify** | Source inspector.sh |
| `tests/unit/test-inspector.sh` | **Create** | All inspector unit tests |

---

## Task 1: Create `src/screens/inspector.sh` — state and open

**Files:**
- Create: `src/screens/inspector.sh`

- [ ] **Step 1: Write failing tests for `_shql_inspector_open`**

Create `tests/unit/test-inspector.sh`:

```bash
#!/usr/bin/env bash
# shellql/tests/unit/test-inspector.sh — Record inspector unit tests

_SHQL_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${_SHQL_ROOT}/../shellframe}"

source "$_SHELLFRAME_DIR/src/clip.sh"
source "$_SHELLFRAME_DIR/src/draw.sh"
source "$_SHELLFRAME_DIR/src/selection.sh"
source "$_SHELLFRAME_DIR/src/scroll.sh"
source "$_SHELLFRAME_DIR/src/panel.sh"
source "$_SHELLFRAME_DIR/src/widgets/list.sh"
source "$_SHQL_ROOT/src/state.sh"
SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"
source "$_SHQL_ROOT/src/screens/inspector.sh"
source "$_SHQL_ROOT/tests/ptyunit/assert.sh"

ptyunit_test_begin "inspector"

# ── Helpers ───────────────────────────────────────────────────────────────────

_setup_mock_grid() {
    SHELLFRAME_GRID_HEADERS=("id" "name" "email")
    SHELLFRAME_GRID_COLS=3
    SHELLFRAME_GRID_ROWS=2
    SHELLFRAME_GRID_DATA=("1" "Alice" "alice@example.com" "2" "Bob" "")
    SHELLFRAME_GRID_CTX="test_grid"
    shellframe_sel_init "test_grid" 2
    shellframe_sel_move "test_grid" home
}

# ── Test: open builds correct pairs ──────────────────────────────────────────

_setup_mock_grid
_shql_inspector_open
assert_eq "${#_SHQL_INSPECTOR_PAIRS[@]}" "3" "open: builds 3 pairs for 3 columns"
assert_eq "${_SHQL_INSPECTOR_PAIRS[0]%%	*}" "id"    "open: first key is 'id'"
assert_eq "${_SHQL_INSPECTOR_PAIRS[0]#*	}"  "1"     "open: first value is '1'"
assert_eq "${_SHQL_INSPECTOR_PAIRS[1]%%	*}" "name"  "open: second key is 'name'"
assert_eq "${_SHQL_INSPECTOR_PAIRS[1]#*	}"  "Alice" "open: second value is 'Alice'"
assert_eq "${_SHQL_INSPECTOR_PAIRS[2]%%	*}" "email" "open: third key is 'email'"
assert_eq "${_SHQL_INSPECTOR_PAIRS[2]#*	}"  "alice@example.com" "open: third value is email"
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "1" "open: sets ACTIVE=1"

# ── Test: open uses (null) for empty cells ────────────────────────────────────

_setup_mock_grid
shellframe_sel_move "test_grid" down   # move to row 1 (Bob, "")
_shql_inspector_open
assert_eq "${_SHQL_INSPECTOR_PAIRS[2]#*	}" "(null)" "open: empty cell renders as (null)"

# ── Test: open guards against empty grid ─────────────────────────────────────

_SHQL_INSPECTOR_ACTIVE=0
SHELLFRAME_GRID_ROWS=0
_shql_inspector_open
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "open: does not activate on empty grid"

# Restore for further tests
_setup_mock_grid

# ── Test: on_key scroll ───────────────────────────────────────────────────────

_SHQL_INSPECTOR_ACTIVE=1
_SHQL_INSPECTOR_PAIRS=("a	1" "b	2" "c	3" "d	4" "e	5")
shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 5 1 3 1

_shql_inspector_on_key $'\033[B'  # down
_top=0
shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _top
assert_eq "$_top" "1" "on_key: down moves scroll top to 1"

_shql_inspector_on_key $'\033[A'  # up
shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _top
assert_eq "$_top" "0" "on_key: up moves scroll top back to 0"

# ── Test: on_key dismiss keys ─────────────────────────────────────────────────

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key $'\033'
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "on_key: Esc sets ACTIVE=0"
_rc=$?
assert_eq "$_rc" "0" "on_key: Esc returns 0"

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key $'\r'
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "on_key: Enter sets ACTIVE=0"

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key 'q'
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "on_key: q sets ACTIVE=0"

# Verify q returns 0 (not 1 — would leak to global quit handler)
_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key 'q'
_rc=$?
assert_eq "$_rc" "0" "on_key: q returns 0 not 1"

# ── Test: on_key passes unknown keys through ──────────────────────────────────

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key 'x'
_rc=$?
assert_eq "$_rc" "1" "on_key: unknown key returns 1"

# ── Test: key column width ────────────────────────────────────────────────────

_SHQL_INSPECTOR_PAIRS=("id	1" "name	Alice" "email	a@b.com")
_shql_inspector_key_width _kw
assert_eq "$_kw" "5" "key_width: max key length is 'email'=5"

_SHQL_INSPECTOR_PAIRS=("x	1")
_shql_inspector_key_width _kw
assert_eq "$_kw" "8" "key_width: min clamped to 8"

_SHQL_INSPECTOR_PAIRS=("averylongcolumnname	val" "b	2")
_shql_inspector_key_width _kw
assert_eq "$_kw" "20" "key_width: max clamped to 20"

ptyunit_test_summary
```

- [ ] **Step 2: Run tests — confirm they fail (inspector.sh does not exist)**

```bash
cd /path/to/shellql
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit 2>&1 | grep -E "FAIL|ERROR|test-inspector"
```
Expected: error sourcing `src/screens/inspector.sh` or test failures.

- [ ] **Step 3: Create `src/screens/inspector.sh` with state globals, `_shql_inspector_open`, `_shql_inspector_on_key`, `_shql_inspector_key_width`**

```bash
#!/usr/bin/env bash
# shellql/src/screens/inspector.sh — Record inspector overlay
#
# REQUIRES: shellframe sourced, src/state.sh sourced.
#
# Renders a centered key/value overlay panel over the TABLE body region.
# Triggered by Enter on a data grid row (_shql_TABLE_body_action).
#
# ── State globals ──────────────────────────────────────────────────────────────
#   _SHQL_INSPECTOR_ACTIVE   — 0|1: whether the overlay is visible
#   _SHQL_INSPECTOR_PAIRS    — array of "key<TAB>value" strings (one per column)
#   _SHQL_INSPECTOR_CTX      — scroll context name
#
# ── Public functions ───────────────────────────────────────────────────────────
#   _shql_inspector_open          — build pairs from current grid cursor row
#   _shql_inspector_render t l w h — draw overlay (call from body_render)
#   _shql_inspector_on_key key    — handle keys (call from body_on_key guard)
#   _shql_inspector_key_width out — compute key column width into out_var

_SHQL_INSPECTOR_ACTIVE=0
_SHQL_INSPECTOR_PAIRS=()
_SHQL_INSPECTOR_CTX="inspector_scroll"

# ── _shql_inspector_open ──────────────────────────────────────────────────────

_shql_inspector_open() {
    # Guard: nothing to inspect in an empty table
    [[ "${SHELLFRAME_GRID_ROWS:-0}" -eq 0 ]] && return 0

    # PRECONDITION: SHELLFRAME_GRID_CTX must be set to the active grid context
    # before calling this function (done by _shql_TABLE_body_action).
    # shellframe_sel_cursor uses SHELLFRAME_GRID_CTX to locate the selection state.

    # Read current cursor row (out-var form — no subshell)
    local _cursor=0
    shellframe_sel_cursor "${SHELLFRAME_GRID_CTX:-}" _cursor 2>/dev/null || true

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
    shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_n" 1 10 1
    _SHQL_INSPECTOR_ACTIVE=1
}

# ── _shql_inspector_key_width ─────────────────────────────────────────────────

# Compute key column width: max key length across all pairs, bounded [8, 20].
# Stores result via printf -v into the named output variable.
_shql_inspector_key_width() {
    local _out_var="$1"
    local _max=0 _pair _key _klen
    for _pair in "${_SHQL_INSPECTOR_PAIRS[@]+"${_SHQL_INSPECTOR_PAIRS[@]}"}"; do
        _key="${_pair%%	*}"
        _klen=${#_key}
        (( _klen > _max )) && _max=$_klen
    done
    (( _max < 8  )) && _max=8
    (( _max > 20 )) && _max=20
    printf -v "$_out_var" '%d' "$_max"
}

# ── _shql_inspector_on_key ────────────────────────────────────────────────────

_shql_inspector_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"

    case "$_key" in
        "$_k_up")   shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" up;        return 0 ;;
        "$_k_down") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" down;      return 0 ;;
        "$_k_pgup") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" page_up;   return 0 ;;
        "$_k_pgdn") shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" page_down; return 0 ;;
        $'\033'|$'\r'|$'\n'|q)
            # Return 0 (not 1) so the key does NOT fall through to the global
            # quit handler, which would navigate away from TABLE while the
            # inspector is still open.
            _SHQL_INSPECTOR_ACTIVE=0
            return 0
            ;;
    esac
    return 1
}

# ── _shql_inspector_render ────────────────────────────────────────────────────

_shql_inspector_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _bold="${SHELLFRAME_BOLD:-$'\033[1m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"

    # ── Panel dimensions (centered) ──
    local _panel_w=$(( _width * 2 / 3 ))
    (( _panel_w < 40           )) && _panel_w=40
    (( _panel_w > _width - 4   )) && _panel_w=$(( _width - 4 ))
    (( _panel_w < 1            )) && _panel_w=1

    local _panel_h=$(( _height * 3 / 4 ))
    (( _panel_h < 10           )) && _panel_h=10
    (( _panel_h > _height - 2  )) && _panel_h=$(( _height - 2 ))
    (( _panel_h < 1            )) && _panel_h=1

    local _panel_top=$(( _top  + (_height - _panel_h) / 2 ))
    local _panel_left=$(( _left + (_width  - _panel_w) / 2 ))

    # ── Draw panel border ──
    local _save_pstyle="$SHELLFRAME_PANEL_STYLE"
    local _save_ptitle="$SHELLFRAME_PANEL_TITLE"
    local _save_ptalign="$SHELLFRAME_PANEL_TITLE_ALIGN"
    local _save_pfocused="$SHELLFRAME_PANEL_FOCUSED"

    SHELLFRAME_PANEL_STYLE="single"
    SHELLFRAME_PANEL_TITLE="Row Inspector"
    SHELLFRAME_PANEL_TITLE_ALIGN="center"
    SHELLFRAME_PANEL_FOCUSED=1
    shellframe_panel_render "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h"

    # Get inner content bounds via panel API
    local _inner_top _inner_left _inner_w _inner_h
    shellframe_panel_inner "$_panel_top" "$_panel_left" "$_panel_w" "$_panel_h" \
        _inner_top _inner_left _inner_w _inner_h

    SHELLFRAME_PANEL_STYLE="$_save_pstyle"
    SHELLFRAME_PANEL_TITLE="$_save_ptitle"
    SHELLFRAME_PANEL_TITLE_ALIGN="$_save_ptalign"
    SHELLFRAME_PANEL_FOCUSED="$_save_pfocused"

    # ── Clear inner area ──
    local _ir
    for (( _ir=0; _ir<_inner_h; _ir++ )); do
        printf '\033[%d;%dH\033[2K' "$(( _inner_top + _ir ))" "$_inner_left" >/dev/tty
    done

    # ── Compute key column width ──
    local _kw
    _shql_inspector_key_width _kw
    local _val_avail=$(( _inner_w - _kw - 2 ))
    (( _val_avail < 1 )) && _val_avail=1

    # ── Update scroll viewport to actual height ──
    shellframe_scroll_resize "$_SHQL_INSPECTOR_CTX" "$_inner_h" 1
    local _scroll_top=0
    shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _scroll_top

    # ── Render key/value rows ──
    local _n=${#_SHQL_INSPECTOR_PAIRS[@]}
    local _r _idx _pair _key _val _val_clipped
    for (( _r=0; _r<_inner_h; _r++ )); do
        _idx=$(( _scroll_top + _r ))
        [[ $_idx -ge $_n ]] && continue
        _pair="${_SHQL_INSPECTOR_PAIRS[$_idx]}"
        _key="${_pair%%	*}"
        _val="${_pair#*	}"
        # shellframe_str_clip_ellipsis raw rendered width
        # raw and rendered are the same for plain text (no ANSI escapes in cell values)
        _val_clipped=$(shellframe_str_clip_ellipsis "$_val" "$_val" "$_val_avail")
        printf '\033[%d;%dH%s%-*s%s  %s' \
            "$(( _inner_top + _r ))" "$_inner_left" \
            "$_bold" "$_kw" "$_key" "$_rst" \
            "$_val_clipped" >/dev/tty
    done
}
```

- [ ] **Step 4: Run tests**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit 2>&1 | tail -5
```
Expected: all inspector tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/screens/inspector.sh tests/unit/test-inspector.sh
git commit -m "Add record inspector: state, open, on_key, render (shellql#5)"
```

---

## Task 2: Wire inspector into `table.sh`

**Files:**
- Modify: `src/screens/table.sh`

The three integration points are:
1. New `_shql_TABLE_body_action` — triggers `_shql_inspector_open`
2. `_shql_TABLE_body_render` — calls `_shql_inspector_render` at end when active
3. `_shql_TABLE_body_on_key` — intercepts all keys when inspector is active
4. `_shql_TABLE_footer_render` — shows inspector hint when active

- [ ] **Step 1: Verify the current test suite passes before touching table.sh**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit 2>&1 | tail -3
```
Expected: all existing tests pass.

- [ ] **Step 2: Add `_shql_TABLE_body_action` to `table.sh`**

Add after `_shql_TABLE_body_on_focus` (around line 290):

```bash
# ── _shql_TABLE_body_action ───────────────────────────────────────────────────
# Called by shellframe shell when body on_key returns 2 (Enter on grid row).

_shql_TABLE_body_action() {
    local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    [[ "$_tab" != "$_SHQL_TABLE_TAB_DATA" ]] && return 0
    SHELLFRAME_GRID_CTX="$_SHQL_TABLE_GRID_CTX"
    _shql_inspector_open
}
```

- [ ] **Step 3: Add inspector overlay call to `_shql_TABLE_body_render`**

In `_shql_TABLE_body_render`, add at the very end (after the `case` block):

```bash
    # Overlay the record inspector if active
    (( _SHQL_INSPECTOR_ACTIVE )) && _shql_inspector_render "$@"
```

The full function becomes:

```bash
_shql_TABLE_body_render() {
    local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    case "$_tab" in
        "$_SHQL_TABLE_TAB_DATA")      _shql_table_data_render "$@" ;;
        "$_SHQL_TABLE_TAB_QUERY")     _shql_table_query_render "$@" ;;
        *)                            _shql_table_structure_render "$@" ;;
    esac
    # Overlay the record inspector if active
    (( _SHQL_INSPECTOR_ACTIVE )) && _shql_inspector_render "$@"
}
```

- [ ] **Step 4: Add inspector guard to `_shql_TABLE_body_on_key`**

At the very top of `_shql_TABLE_body_on_key` (before the `[` / `]` tab-switch block), add:

```bash
    # Route all keys to the inspector when it is open
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _shql_inspector_on_key "$1"
        return $?
    fi
```

- [ ] **Step 5: Add inspector footer hint to `_shql_TABLE_footer_render`**

Add a new constant near the other hint strings at the top of table.sh:

```bash
_SHQL_TABLE_FOOTER_HINTS_INSPECTOR="[↑↓] Scroll  [PgUp/PgDn] Page  [Enter/Esc/q] Close"
```

(The hint includes `q` since it is a valid dismiss key — intentionally more complete than the spec text.)

In `_shql_TABLE_footer_render`, add a check before the existing `if (( _SHQL_TABLE_TABBAR_FOCUSED ))` branch:

```bash
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _hint="$_SHQL_TABLE_FOOTER_HINTS_INSPECTOR"
    elif (( _SHQL_TABLE_TABBAR_FOCUSED )); then
```

(Remove the existing standalone `if (( _SHQL_TABLE_TABBAR_FOCUSED ))` and replace the whole block.)

The full updated function:

```bash
_shql_TABLE_footer_render() {
    local _top="$1" _left="$2"
    local _gray="${SHELLFRAME_GRAY:-}" _rst="${SHELLFRAME_RESET:-}"
    printf '\033[%d;%dH\033[2K' "$_top" "$_left" >/dev/tty
    local _hint
    if (( _SHQL_INSPECTOR_ACTIVE )); then
        _hint="$_SHQL_TABLE_FOOTER_HINTS_INSPECTOR"
    elif (( _SHQL_TABLE_TABBAR_FOCUSED )); then
        _hint="$_SHQL_TABLE_FOOTER_HINTS_TABBAR"
    else
        local _tab="${SHELLFRAME_TABBAR_ACTIVE:-0}"
        case "$_tab" in
            "$_SHQL_TABLE_TAB_DATA")      _hint="$_SHQL_TABLE_FOOTER_HINTS_DATA" ;;
            "$_SHQL_TABLE_TAB_STRUCTURE") _hint="$_SHQL_TABLE_FOOTER_HINTS_STRUCTURE" ;;
            *)                            _hint="$_SHQL_TABLE_FOOTER_HINTS_QUERY" ;;
        esac
    fi
    printf '\033[%d;%dH%s%s%s' "$_top" "$_left" "$_gray" "$_hint" "$_rst" >/dev/tty
}
```

- [ ] **Step 6: Reset `_SHQL_INSPECTOR_ACTIVE` in `shql_table_init`**

In `shql_table_init`, add a reset so re-entering TABLE always starts with the inspector closed:

```bash
shql_table_init() {
    _SHQL_TABLE_TABBAR_FOCUSED=0
    _SHQL_TABLE_BODY_FOCUSED=0
    SHELLFRAME_TABBAR_ACTIVE=0
    _SHQL_INSPECTOR_ACTIVE=0    # ← add this line

    _shql_table_load_ddl
    _shql_table_load_data
}
```

- [ ] **Step 7: Run full unit test suite**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit 2>&1 | tail -5
```
Expected: all tests pass (no regressions).

- [ ] **Step 8: Commit**

```bash
git add src/screens/table.sh
git commit -m "Wire record inspector into TABLE screen (shellql#5)"
```

---

## Task 3: Source `inspector.sh` in `bin/shql`

**Files:**
- Modify: `bin/shql`

- [ ] **Step 1: Add source line to `bin/shql`**

After the line that sources `table.sh`, add:

```bash
source "$_SHQL_ROOT/src/screens/inspector.sh"
```

- [ ] **Step 2: Smoke test**

```bash
SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```

Navigate: open a recent file → schema browser → Enter on a table → Data tab → navigate to a row → Enter.
Expected: centered "Row Inspector" panel appears with key/value pairs. ↑/↓ scrolls. Esc/Enter/q dismisses.

- [ ] **Step 3: Run full test suite one final time**

```bash
SHELLFRAME_DIR=../shellframe bash tests/ptyunit/run.sh --unit 2>&1 | tail -5
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add bin/shql
git commit -m "Source inspector.sh in bin/shql (shellql#5)"
```

---

## Task 4: Close issue and update docs

- [ ] **Step 1: Update `PLAN.md` — mark Phase 5.5 closed**

In `PLAN.md`, change the status of Phase 5.5 (shellql#5) from open to `✓ closed` and add a status line:

```
### 5.5 Record inspector — [shellql#5](https://github.com/fissible/shellql/issues/5) ✓ closed
- **Status:** Done — `src/screens/inspector.sh`; Enter on data row → inspector overlay; ↑/↓ scroll; Esc/Enter/q dismiss
```

- [ ] **Step 2: Run `/save` to commit docs, push, and update session handoff**

```bash
/save
```
