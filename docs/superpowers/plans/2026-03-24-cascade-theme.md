# Cascade Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "cascade" theme to ShellQL with dark purple header, gray content background, borderless sidebar with table/view icons, alternating grid row stripes, and a dimmer cursor highlight.

**Architecture:** Two-phase approach — shellframe grid enhancements first (stripe bg + cursor style), then the shellql theme file and rendering changes. The theme is opt-in via `SHQL_THEME=cascade`. All new globals default to empty/off so existing themes are unaffected.

**Tech Stack:** bash 3.2+, shellframe widgets, 256-color ANSI escapes (`\033[48;5;Nm`), ptyunit tests

---

## File Map

| File | Change type | Responsibility |
|------|-------------|---------------|
| `shellframe/src/widgets/grid.sh` | Modified | Add `SHELLFRAME_GRID_STRIPE_BG` and `SHELLFRAME_GRID_CURSOR_STYLE` support |
| `shellframe/tests/unit/test-grid.sh` | Modified | Tests for stripe and cursor style globals |
| `src/themes/cascade.sh` | Created | All cascade theme token definitions + 256-color detection |
| `src/db.sh` | Modified | New `shql_db_list_objects` function (name + type) |
| `src/db_mock.sh` | Modified | Mock `shql_db_list_objects` |
| `src/screens/table.sh` | Modified | Sidebar border conditional, icons, content bg fill, wire theme tokens to grid |
| `tests/unit/test-table.sh` | Modified | Tests for sidebar icons, content bg |
| `tests/unit/test-schema.sh` | Modified | Test for `shql_db_list_objects` mock |

### Pre-existing functions referenced by this plan

- `shql_db_list_tables` — in `src/db.sh` (line 27); returns table names only
- `_shql_TABLE_sidebar_render` — in `src/screens/table.sh` (line 324); renders sidebar panel + list
- `_shql_TABLE_content_render` — in `src/screens/table.sh`; dispatches to data/schema/query/empty
- `_shql_TABLE_tabbar_render` — in `src/screens/table.sh`; renders tab bar with border line
- `shql_browser_init` — in `src/screens/table.sh` (line 293); loads tables list
- `shellframe_grid_render` — in `shellframe/src/widgets/grid.sh` (line 128); renders the data grid
- `shellframe_list_render` — in `shellframe/src/widgets/list.sh` (line 61); renders sidebar list

### Test commands

```bash
# shellframe tests (from shellql dir)
SHELLFRAME_DIR=../shellframe bash ../shellframe/tests/run.sh --unit

# shellql tests
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit

# visual smoke test
SHQL_THEME=cascade SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```

---

## Task 1: Shellframe grid — stripe background support

**Files:**
- Modify: `shellframe/src/widgets/grid.sh`
- Modify: `shellframe/tests/unit/test-grid.sh` (or create if absent)

Add `SHELLFRAME_GRID_STRIPE_BG` — when set, apply it as background to even-numbered data rows.

- [ ] **Step 1: Write the failing test**

In shellframe's test directory, find or create `tests/unit/test-grid.sh`. Add:

```bash
ptyunit_test_begin "grid: SHELLFRAME_GRID_STRIPE_BG default is empty"
assert_eq "" "${SHELLFRAME_GRID_STRIPE_BG:-}"
```

- [ ] **Step 2: Run test to verify it passes (baseline)**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/run.sh --unit 2>&1 | tail -5
```

- [ ] **Step 3: Add stripe support to grid render**

In `shellframe/src/widgets/grid.sh`, find the global declarations section near the top (around line 60) and add:

```bash
SHELLFRAME_GRID_STRIPE_BG=""
```

In the data row render loop (around line 303), after the line:

```bash
printf '\033[%d;%dH%*s\033[%d;%dH' "$_row" "$_left" "$_width" '' "$_row" "$_left" >&3
```

Add stripe background for even rows. Insert **after** `[[ "$_ridx" -ge "$_nrows" ]] && continue` (so only data-bearing rows get striped):

```bash
# Apply stripe background to even data rows
if [[ -n "${SHELLFRAME_GRID_STRIPE_BG:-}" ]] && (( _ridx % 2 == 1 )); then
    printf '\033[%d;%dH%s%*s' "$_row" "$_left" "$SHELLFRAME_GRID_STRIPE_BG" "$_width" '' >&3
    printf '\033[%d;%dH' "$_row" "$_left" >&3
fi
```

Note: `_ridx % 2 == 1` stripes the second, fourth, etc. rows (0-indexed). Placed after the empty-row `continue`, so only rows with data are striped. The stripe paints the background, then repositions the cursor for cell content to overwrite.

- [ ] **Step 4: Run shellframe tests**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/run.sh --unit 2>&1 | tail -5
```

Expected: all pass (existing grid behavior unchanged when `SHELLFRAME_GRID_STRIPE_BG` is empty).

- [ ] **Step 5: Commit in shellframe**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe
git add src/widgets/grid.sh
git commit -m "feat(grid): add SHELLFRAME_GRID_STRIPE_BG for alternating row backgrounds"
```

---

## Task 2: Shellframe grid — custom cursor style

**Files:**
- Modify: `shellframe/src/widgets/grid.sh`

Add `SHELLFRAME_GRID_CURSOR_STYLE` — when set, use it instead of `$_rev` (reverse video) for the cursor row.

- [ ] **Step 1: Write the test**

In shellframe's grid test file, add:

```bash
ptyunit_test_begin "grid: SHELLFRAME_GRID_CURSOR_STYLE default is empty"
assert_eq "" "${SHELLFRAME_GRID_CURSOR_STYLE:-}"
```

- [ ] **Step 2: Add the global declaration**

In `shellframe/src/widgets/grid.sh`, near the stripe global, add:

```bash
SHELLFRAME_GRID_CURSOR_STYLE=""
```

- [ ] **Step 3: Modify cursor row rendering**

In the data row loop, find the line (around line 326):

```bash
(( _is_cursor )) && printf '\033[%d;%dH%s' "$_row" "$_left" "$_rev" >&3
```

Replace with:

```bash
if (( _is_cursor )); then
    local _cursor_attr="${SHELLFRAME_GRID_CURSOR_STYLE:-$_rev}"
    printf '\033[%d;%dH%s' "$_row" "$_left" "$_cursor_attr" >&3
fi
```

- [ ] **Step 4: Run shellframe tests**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/run.sh --unit 2>&1 | tail -5
```

Expected: all pass (default falls back to `$_rev`).

- [ ] **Step 5: Commit in shellframe**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe
git add src/widgets/grid.sh
git commit -m "feat(grid): add SHELLFRAME_GRID_CURSOR_STYLE for custom cursor highlight"
```

---

## Task 3: Create cascade theme file

**Files:**
- Create: `src/themes/cascade.sh`

- [ ] **Step 1: Create the theme file**

```bash
#!/usr/bin/env bash
# src/themes/cascade.sh — Cascade theme (dark purple header, gray content, dim cursor)
#
# Requires 256-color terminal. Falls back to basic theme if unsupported.

# ── 256-color detection ───────────────────────────────────────────────────────
_shql_cascade_colors=$(tput colors 2>/dev/null || printf '0')
if (( _shql_cascade_colors < 256 )); then
    source "${_SHQL_ROOT}/src/themes/basic.sh"
    return 0
fi

# ── Panel styling ─────────────────────────────────────────────────────────────
SHQL_THEME_PANEL_STYLE="single"
SHQL_THEME_PANEL_STYLE_FOCUSED="double"

# ── Text colors ───────────────────────────────────────────────────────────────
SHQL_THEME_KEY_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_VALUE_COLOR="${SHELLFRAME_RESET:-}"
SHQL_THEME_VALUE_ACCENT_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_RESET=$'\033[0m'

# ── Header bar: dark purple background, white text ────────────────────────────
SHQL_THEME_HEADER_BG=$'\033[48;5;53m\033[97m'

# ── Sidebar ───────────────────────────────────────────────────────────────────
SHQL_THEME_SIDEBAR_BORDER="none"
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "

# ── Content area: dark gray background ────────────────────────────────────────
SHQL_THEME_CONTENT_BG=$'\033[48;5;236m'

# ── Grid: alternating stripes + dim cursor ────────────────────────────────────
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;238m'
SHQL_THEME_CURSOR_BG=$'\033[48;5;240m'
SHQL_THEME_CURSOR_BOLD=$'\033[1m'

# ── Tab bar ───────────────────────────────────────────────────────────────────
SHQL_THEME_TAB_ACTIVE=""          # normal text (blends with content bg)
SHQL_THEME_TAB_INACTIVE_BG=$'\033[7m'  # inverted
```

- [ ] **Step 2: Verify theme loads without error**

```bash
SHQL_THEME=cascade SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash -c 'source bin/shql; echo "loaded"' 2>&1 || true
```

This will fail because bin/shql enters the TUI, but it tests that the source chain works. A simpler check:

```bash
SHELLFRAME_DIR=../shellframe bash -c '
  _SHQL_ROOT=.
  source ../shellframe/shellframe.sh
  source src/themes/cascade.sh
  echo "HEADER_BG=${SHQL_THEME_HEADER_BG:+set}"
  echo "CONTENT_BG=${SHQL_THEME_CONTENT_BG:+set}"
  echo "STRIPE_BG=${SHQL_THEME_ROW_STRIPE_BG:+set}"
'
```

Expected: all three print "set".

- [ ] **Step 3: Commit**

```bash
git add src/themes/cascade.sh
git commit -m "feat(theme): add cascade theme — dark purple header, gray content, dim cursor"
```

---

## Task 4: `shql_db_list_objects` — tables and views with type

**Files:**
- Modify: `src/db.sh`
- Modify: `src/db_mock.sh`
- Test: `tests/unit/test-schema.sh`

Add a new function that returns `name\ttype` (table or view) so the sidebar can prepend icons.

- [ ] **Step 1: Write the failing test**

In `tests/unit/test-schema.sh`, add before `ptyunit_test_summary`:

```bash
# ── Test: shql_db_list_objects mock returns name and type ─────────────────────

ptyunit_test_begin "db_list_objects: mock returns at least 4 objects"
_objs=$(shql_db_list_objects "/mock/test.db")
_obj_count=$(printf '%s\n' "$_objs" | wc -l | tr -d ' ')
assert_eq 1 $(( _obj_count >= 4 ))

ptyunit_test_begin "db_list_objects: first object is a table"
_first=$(printf '%s\n' "$_objs" | head -1)
assert_contains "$_first" "table"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | grep "db_list_objects"
```

Expected: FAIL (function not defined).

- [ ] **Step 3: Add `shql_db_list_objects` to `src/db.sh`**

After `shql_db_list_tables`, add:

```bash
# ── shql_db_list_objects ──────────────────────────────────────────────────────
# shql_db_list_objects <db_path>
# Print name TAB type, one per line. type is "table" or "view".

shql_db_list_objects() {
    local _db="$1"
    _shql_db_check_path "$_db" || return 1
    sqlite3 -separator $'\t' "$_db" \
        "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY type, name"
}
```

- [ ] **Step 4: Add mock `shql_db_list_objects` to `src/db_mock.sh`**

After the existing `shql_db_list_tables` mock, add:

```bash
# shql_db_list_objects <db_path>
# Print name TAB type (table or view).
shql_db_list_objects() {
    printf '%s\t%s\n' categories table
    printf '%s\t%s\n' orders     table
    printf '%s\t%s\n' products   table
    printf '%s\t%s\n' users      table
    printf '%s\t%s\n' active_users view
}
```

- [ ] **Step 5: Run tests**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | grep -E "db_list_objects|PASS|FAIL"
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add src/db.sh src/db_mock.sh tests/unit/test-schema.sh
git commit -m "feat(db): add shql_db_list_objects — returns name + type for sidebar icons"
```

---

## Task 5: Sidebar — conditional border removal and icons

**Files:**
- Modify: `src/screens/table.sh`
- Test: `tests/unit/test-table.sh`

When `SHQL_THEME_SIDEBAR_BORDER == "none"`, skip the panel border. Prepend icons from theme tokens to table/view names in `SHELLFRAME_LIST_ITEMS`.

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test-table.sh`, before the `ptyunit_test_summary` line, add:

```bash
# ── Test: sidebar icons ──────────────────────────────────────────────────────

ptyunit_test_begin "browser_init: sidebar items have table icon when theme sets it"
SHQL_THEME_TABLE_ICON="▤ "
SHQL_THEME_VIEW_ICON="◉ "
shql_browser_init
assert_contains "${_SHQL_BROWSER_SIDEBAR_ITEMS[0]}" "▤"

ptyunit_test_begin "browser_init: sidebar items have no icon when theme unset"
SHQL_THEME_TABLE_ICON=""
SHQL_THEME_VIEW_ICON=""
shql_browser_init
# First char should NOT be an icon
_first_char="${_SHQL_BROWSER_SIDEBAR_ITEMS[0]:0:1}"
assert_eq "u" "$_first_char"
```

- [ ] **Step 2: Run to verify they fail**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | grep "sidebar.*icon"
```

- [ ] **Step 3: Add file-scope declarations for new arrays**

In `src/screens/table.sh`, near the existing `_SHQL_BROWSER_TABLES=()` declaration (around line 53), add:

```bash
_SHQL_BROWSER_OBJECT_TYPES=()
_SHQL_BROWSER_SIDEBAR_ITEMS=()
```

These must exist at file scope so `set -u` in tests does not crash on first access.

- [ ] **Step 4: Update `shql_browser_init` to load objects with types and build icon-prefixed items**

In `src/screens/table.sh`, modify `shql_browser_init`. Replace the current table-loading block:

```bash
    local _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _SHQL_BROWSER_TABLES+=("$_line")
    done < <(shql_db_list_tables "$SHQL_DB_PATH" 2>/dev/null)
```

With:

```bash
    _SHQL_BROWSER_OBJECT_TYPES=()
    _SHQL_BROWSER_SIDEBAR_ITEMS=()
    local _line _obj_name _obj_type
    while IFS=$'\t' read -r _obj_name _obj_type; do
        [[ -z "$_obj_name" ]] && continue
        _SHQL_BROWSER_TABLES+=("$_obj_name")
        _SHQL_BROWSER_OBJECT_TYPES+=("${_obj_type:-table}")
        local _icon=""
        if [[ "$_obj_type" == "view" ]]; then
            _icon="${SHQL_THEME_VIEW_ICON:-}"
        else
            _icon="${SHQL_THEME_TABLE_ICON:-}"
        fi
        _SHQL_BROWSER_SIDEBAR_ITEMS+=("${_icon}${_obj_name}")
    done < <(shql_db_list_objects "$SHQL_DB_PATH" 2>/dev/null)
```

- [ ] **Step 5: Update sidebar render to use `_SHQL_BROWSER_SIDEBAR_ITEMS`**

In `_shql_TABLE_sidebar_render`, change the list items assignment from:

```bash
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_TABLES[@]+"${_SHQL_BROWSER_TABLES[@]}"}")
```

To:

```bash
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
```

- [ ] **Step 6: Add conditional border removal**

In `_shql_TABLE_sidebar_render`, wrap the panel render in a conditional:

```bash
    if [[ "${SHQL_THEME_SIDEBAR_BORDER:-}" == "none" ]]; then
        # No panel border — render list directly in the full region
        SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
        SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
        SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_list_render "$_top" "$_left" "$_width" "$_height"
    else
        SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
        SHELLFRAME_PANEL_TITLE="Tables"
        SHELLFRAME_PANEL_TITLE_ALIGN="left"
        SHELLFRAME_PANEL_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_panel_render "$_top" "$_left" "$_width" "$_height"

        local _it _il _iw _ih
        shellframe_panel_inner "$_top" "$_left" "$_width" "$_height" _it _il _iw _ih

        SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
        SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
        SHELLFRAME_LIST_FOCUSED=$_SHQL_BROWSER_SIDEBAR_FOCUSED
        shellframe_list_render "$_it" "$_il" "$_iw" "$_ih"
    fi
```

This replaces the entire current body of `_shql_TABLE_sidebar_render`.

- [ ] **Step 7: Update list init in `shql_browser_init`**

Change the list init to use sidebar items:

```bash
    SHELLFRAME_LIST_CTX="$_SHQL_BROWSER_SIDEBAR_CTX"
    SHELLFRAME_LIST_ITEMS=("${_SHQL_BROWSER_SIDEBAR_ITEMS[@]+"${_SHQL_BROWSER_SIDEBAR_ITEMS[@]}"}")
    shellframe_list_init "$_SHQL_BROWSER_SIDEBAR_CTX"
```

- [ ] **Step 8: Run tests**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | tail -5
```

All tests must pass.

- [ ] **Step 9: Commit**

```bash
git add src/screens/table.sh tests/unit/test-table.sh
git commit -m "feat(sidebar): theme-driven icons and conditional border removal"
```

---

## Task 6: Tab bar — wire theme tokens for tab styling

**Files:**
- Modify: `src/screens/table.sh`

Wire `SHQL_THEME_TAB_ACTIVE` and `SHQL_THEME_TAB_INACTIVE_BG` into `_shql_TABLE_tabbar_render` so the cascade theme controls tab appearance. `SHQL_THEME_TAB_INACTIVE_BG` supersedes the older `SHQL_THEME_TABBAR_BG` token.

- [ ] **Step 1: Update tab rendering in `_shql_TABLE_tabbar_render`**

Find the active tab rendering block:

```bash
        if (( _i == _SHQL_TAB_ACTIVE )); then
            _SHQL_TABBAR_ACTIVE_X0=$_col
            _SHQL_TABBAR_ACTIVE_X1=$(( _col + ${#_label} ))
            # Active tab: normal text (blends with content below)
            printf '\033[%d;%dH%s' "$_top" "$_col" "$_label" >/dev/tty
        else
            # Inactive tabs: inverted (black text, white background)
            printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_inv" "$_label" "$_rst" >/dev/tty
        fi
```

Replace with:

```bash
        if (( _i == _SHQL_TAB_ACTIVE )); then
            _SHQL_TABBAR_ACTIVE_X0=$_col
            _SHQL_TABBAR_ACTIVE_X1=$(( _col + ${#_label} ))
            # Active tab: theme-controlled or plain text (blends with content)
            local _tab_style="${SHQL_THEME_TAB_ACTIVE:-}"
            if [[ -n "$_tab_style" ]]; then
                printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_tab_style" "$_label" "$_rst" >/dev/tty
            else
                printf '\033[%d;%dH%s' "$_top" "$_col" "$_label" >/dev/tty
            fi
        else
            # Inactive tabs: theme-controlled or inverted
            local _itab_style="${SHQL_THEME_TAB_INACTIVE_BG:-${SHQL_THEME_TABBAR_BG:-$_inv}}"
            printf '\033[%d;%dH%s%s%s' "$_top" "$_col" "$_itab_style" "$_label" "$_rst" >/dev/tty
        fi
```

- [ ] **Step 2: Run tests**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add src/screens/table.sh
git commit -m "feat(tabbar): wire SHQL_THEME_TAB_ACTIVE and TAB_INACTIVE_BG tokens"
```

---

## Task 7: Content area background fill + tabbar bg

**Files:**
- Modify: `src/screens/table.sh`

Fill the content area and tab bar row with `SHQL_THEME_CONTENT_BG` before rendering content.

- [ ] **Step 1: Add background fill to content render**

In `_shql_TABLE_content_render`, at the very start of the function (before `_shql_content_type`), add:

```bash
    # Fill content area with theme background
    if [[ -n "${SHQL_THEME_CONTENT_BG:-}" ]]; then
        local _r
        for (( _r=0; _r<_height; _r++ )); do
            printf '\033[%d;%dH%s%*s' "$(( _top + _r ))" "$_left" "$SHQL_THEME_CONTENT_BG" "$_width" '' >/dev/tty
        done
        printf '%s' "${SHQL_THEME_RESET:-$'\033[0m'}" >/dev/tty
    fi
```

- [ ] **Step 2: Add background fill to tabbar render**

In `_shql_TABLE_tabbar_render`, change the line-clear from:

```bash
    printf '\033[%d;%dH%*s' "$_top" "$_left" "$_width" '' >/dev/tty
```

To:

```bash
    if [[ -n "${SHQL_THEME_CONTENT_BG:-}" ]]; then
        printf '\033[%d;%dH%s%*s' "$_top" "$_left" "$SHQL_THEME_CONTENT_BG" "$_width" '' >/dev/tty
        printf '\033[%d;%dH' "$_top" "$_left" >/dev/tty
    else
        printf '\033[%d;%dH%*s' "$_top" "$_left" "$_width" '' >/dev/tty
    fi
```

Also apply it to the border row below (the `─` line). In the content border loop, change:

```bash
    printf '\033[%d;%dH%s' "$_border_row" "$_left" "$_gray" >/dev/tty
```

To:

```bash
    if [[ -n "${SHQL_THEME_CONTENT_BG:-}" ]]; then
        printf '\033[%d;%dH%s%s' "$_border_row" "$_left" "$SHQL_THEME_CONTENT_BG" "$_gray" >/dev/tty
    else
        printf '\033[%d;%dH%s' "$_border_row" "$_left" "$_gray" >/dev/tty
    fi
```

- [ ] **Step 3: Run tests**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | tail -5
```

Expected: all pass (bg fill is visual-only, no logic change).

- [ ] **Step 4: Commit**

```bash
git add src/screens/table.sh
git commit -m "feat(theme): fill content area and tabbar with SHQL_THEME_CONTENT_BG"
```

---

## Task 8: Wire theme tokens to shellframe grid globals

**Files:**
- Modify: `src/screens/table.sh`

Before calling `shellframe_grid_render` in the data tab path, set the shellframe grid globals from theme tokens.

- [ ] **Step 1: Add token wiring before grid render**

In `_shql_TABLE_content_render`, in the `data)` case, find:

```bash
                SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
                SHELLFRAME_GRID_FOCUSED=$_SHQL_BROWSER_CONTENT_FOCUSED
```

After these lines, add:

```bash
                SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
                if [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
                    SHELLFRAME_GRID_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
                else
                    SHELLFRAME_GRID_CURSOR_STYLE=""
                fi
```

- [ ] **Step 2: Add integration test for token propagation**

In `tests/unit/test-table.sh`, before `ptyunit_test_summary`, add:

```bash
# ── Test: theme token propagation to grid globals ────────────────────────────

ptyunit_test_begin "theme_tokens: stripe and cursor propagate to grid globals"
SHQL_THEME_ROW_STRIPE_BG=$'\033[48;5;238m'
SHQL_THEME_CURSOR_BG=$'\033[48;5;240m'
SHQL_THEME_CURSOR_BOLD=$'\033[1m'
SHQL_DB_PATH="/mock/test.db"
shql_browser_init
_shql_tab_open "users" "data"
_shql_content_data_ensure
# Simulate what content render does before grid render
SHELLFRAME_GRID_CTX="${_SHQL_TABS_CTX[$_SHQL_TAB_ACTIVE]}_grid"
SHELLFRAME_GRID_FOCUSED=1
SHELLFRAME_GRID_STRIPE_BG="${SHQL_THEME_ROW_STRIPE_BG:-}"
if [[ -n "${SHQL_THEME_CURSOR_BG:-}" ]]; then
    SHELLFRAME_GRID_CURSOR_STYLE="${SHQL_THEME_CURSOR_BG}${SHQL_THEME_CURSOR_BOLD:-}"
else
    SHELLFRAME_GRID_CURSOR_STYLE=""
fi
assert_contains "$SHELLFRAME_GRID_STRIPE_BG" "238"
assert_contains "$SHELLFRAME_GRID_CURSOR_STYLE" "240"
```

- [ ] **Step 3: Run tests**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh --unit 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 5: Visual smoke test**

```bash
SHQL_THEME=cascade SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```

Verify:
- Dark purple header bar with white text
- Sidebar has no border, table names prefixed with `▤`, view with `◉`
- Content area has gray background
- Data grid rows alternate between two shades of gray
- Cursor highlight is subtle (not full reverse video)
- Active tab blends with content area
- Inactive tabs are inverted

- [ ] **Step 6: Commit**

```bash
git add src/screens/table.sh
git commit -m "feat(theme): wire cascade tokens to shellframe grid stripe/cursor globals"
```

---

## Task 9: Final test suite pass and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run full shellframe tests**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/run.sh 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 2: Run full shellql tests**

```bash
SHELLFRAME_DIR=/Users/allenmccabe/lib/fissible/shellframe bash tests/run.sh 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 3: Run smoke test with basic theme (regression check)**

```bash
SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```

Verify: basic theme still looks and behaves correctly (no icons, borders present, standard cursor).

- [ ] **Step 4: Run smoke test with cascade theme**

```bash
SHQL_THEME=cascade SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql
```

Verify all cascade visuals.

- [ ] **Step 5: Commit any remaining fixes**

```bash
git add -A
git commit -m "test: cascade theme final pass — all suites green"
```
