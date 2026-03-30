# Welcome Screen Tiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat-list welcome screen with a responsive grid of connection tiles showing metadata, with arrow-key + mouse navigation and context menus.

**Architecture:** The welcome screen (`src/screens/welcome.sh`) is fully rewritten. Tile rendering is done directly with `shellframe_fb_put`/`shellframe_fb_fill` — no new shellframe widget. Metadata (table count, file size, relative date) is collected at init time. Context menus reuse the existing `shellframe_cmenu` widget. The form and delete-confirmation overlays are preserved as-is.

**Tech Stack:** Bash 3.2+, shellframe framebuffer API, shellframe context-menu widget, `stat` for file size, `sqlite3` for table count.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/screens/welcome.sh` | Rewrite | Tile grid render, nav, mouse, context menu, metadata collection |
| `src/themes/basic.sh` | Modify | Add 4 tile theme variables |
| `src/themes/cascade.sh` | Modify | Add 4 tile theme variables |
| `src/themes/uranium.sh` | Modify | Add 4 tile theme variables |
| `tests/unit/test-welcome.sh` | Rewrite | Tests for metadata helpers, grid math, tile navigation |

---

### Task 1: Add Tile Theme Variables

**Files:**
- Modify: `src/themes/basic.sh`
- Modify: `src/themes/cascade.sh`
- Modify: `src/themes/uranium.sh`

- [ ] **Step 1: Add tile variables to basic.sh**

Append after the `SHQL_THEME_FOOTER_BG` line:

```bash
# ── Tiles (welcome screen) ───────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;236m'                  # neutral dark gray
SHQL_THEME_TILE_BORDER=$'\033[38;5;242m'              # medium gray borders
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;5;17m'          # dark navy blue
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;5;68m'      # steel blue border
```

- [ ] **Step 2: Add tile variables to cascade.sh**

Append after `SHQL_THEME_FOOTER_BG`:

```bash
# ── Tiles (welcome screen) ───────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;236m'
SHQL_THEME_TILE_BORDER=$'\033[38;5;242m'
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;5;54m'          # dark purple (matches cursor)
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;5;140m'     # muted purple
```

- [ ] **Step 3: Add tile variables to uranium.sh**

Append after `SHQL_THEME_FOOTER_BG`:

```bash
# ── Tiles (welcome screen) ───────────────────────────────────────────────
SHQL_THEME_TILE_BG=$'\033[48;5;236m'
SHQL_THEME_TILE_BORDER=$'\033[38;5;242m'
SHQL_THEME_TILE_SELECTED_BG=$'\033[48;2;30;70;20m'    # dark green tint
SHQL_THEME_TILE_SELECTED_BORDER=$'\033[38;2;80;186;42m' # uranium green
```

- [ ] **Step 4: Commit**

```bash
git add src/themes/basic.sh src/themes/cascade.sh src/themes/uranium.sh
git commit -m "feat(theme): add tile variables for welcome screen"
```

---

### Task 2: Metadata Helper Functions

**Files:**
- Modify: `src/screens/welcome.sh` (add functions at top, before render)
- Test: `tests/unit/test-welcome.sh`

- [ ] **Step 1: Write tests for metadata helpers**

Replace the entire contents of `tests/unit/test-welcome.sh` with:

```bash
#!/usr/bin/env bash
# tests/unit/test-welcome.sh — Unit tests for welcome screen tile logic

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_HOME/assert.sh"

# ── Minimal shellframe stubs ─────────────────────────────────────────────────

shellframe_sel_init()    { true; }
shellframe_sel_set()     { true; }
shellframe_sel_cursor()  { printf -v "$2" '%d' "${_MOCK_CURSOR:-0}"; }
shellframe_scroll_init() { true; }
shellframe_scroll_top()  { printf -v "$2" '%d' 0; }
shellframe_list_init()   { true; }
shellframe_cmenu_init()  { true; }
shellframe_shell_focus_set() { true; }
shellframe_shell_mark_dirty() { true; }
shellframe_cur_init()    { true; }
shellframe_cur_text()    { printf -v "$2" '%s' ""; }

SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE='' SHELLFRAME_GRAY=''
SHELLFRAME_KEY_UP=$'\033[A' SHELLFRAME_KEY_DOWN=$'\033[B'
SHELLFRAME_KEY_LEFT=$'\033[D' SHELLFRAME_KEY_RIGHT=$'\033[C'
SHELLFRAME_KEY_ENTER=$'\n' SHELLFRAME_KEY_ESC=$'\033'
SHELLFRAME_KEY_HOME=$'\033[H' SHELLFRAME_KEY_END=$'\033[F'
SHELLFRAME_KEY_TAB=$'\t' SHELLFRAME_KEY_SHIFT_TAB=$'\033[Z'
SHELLFRAME_MOUSE_SHIFT=0 SHELLFRAME_MOUSE_CTRL=0 SHELLFRAME_MOUSE_BUTTON=0
_SHQL_ROOT="$SHQL_ROOT"

source "$SHQL_ROOT/src/theme.sh"
shql_theme_load basic

SHQL_MOCK=1
source "$SHQL_ROOT/src/state.sh"
source "$SHQL_ROOT/src/db_mock.sh"
source "$SHQL_ROOT/src/screens/welcome.sh"

# ── Test: _shql_welcome_human_size ───────────────────────────────────────────

ptyunit_test_begin "human_size: bytes"
assert_eq "512 B" "$(_shql_welcome_human_size 512)"

ptyunit_test_begin "human_size: kilobytes"
assert_eq "48 KB" "$(_shql_welcome_human_size 49152)"

ptyunit_test_begin "human_size: megabytes"
assert_eq "2.1 MB" "$(_shql_welcome_human_size 2202009)"

ptyunit_test_begin "human_size: gigabytes"
assert_eq "1.5 GB" "$(_shql_welcome_human_size 1610612736)"

ptyunit_test_begin "human_size: zero"
assert_eq "0 B" "$(_shql_welcome_human_size 0)"

# ── Test: _shql_welcome_relative_date ────────────────────────────────────────

ptyunit_test_begin "relative_date: empty string returns empty"
assert_eq "" "$(_shql_welcome_relative_date "")"

# ── Test: _shql_welcome_tile_cols ────────────────────────────────────────────

ptyunit_test_begin "tile_cols: 80 cols → 3"
assert_eq "3" "$(_shql_welcome_tile_cols 80)"

ptyunit_test_begin "tile_cols: 120 cols → 4"
assert_eq "4" "$(_shql_welcome_tile_cols 120)"

ptyunit_test_begin "tile_cols: 200 cols → 4 (capped)"
assert_eq "4" "$(_shql_welcome_tile_cols 200)"

ptyunit_test_begin "tile_cols: 50 cols → 1 (minimum)"
assert_eq "1" "$(_shql_welcome_tile_cols 50)"

ptyunit_test_begin "tile_cols: 52 cols → 2"
assert_eq "2" "$(_shql_welcome_tile_cols 52)"

# ── Test: _shql_welcome_shorten_path ─────────────────────────────────────────

ptyunit_test_begin "shorten_path: replaces HOME with ~"
_result=$(_shql_welcome_shorten_path "$HOME/projects/app.db")
assert_eq "~/projects/app.db" "$_result"

ptyunit_test_begin "shorten_path: truncates long paths"
_long="$HOME/very/deeply/nested/directory/structure/database.db"
_result=$(_shql_welcome_shorten_path "$_long" 20)
# Should end with …/database.db and be ≤ 20 chars
assert_le "${#_result}" 20

# ── Test: tile cursor navigation ─────────────────────────────────────────────

ptyunit_test_begin "cursor nav: right wraps to next row"
_SHQL_WELCOME_CURSOR=2
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=6
_shql_welcome_cursor_move right
assert_eq "3" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: right at end of row wraps"
_SHQL_WELCOME_CURSOR=2
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move right
assert_eq "3" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: down moves by column count"
_SHQL_WELCOME_CURSOR=1
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move down
assert_eq "4" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: down clamps to last tile"
_SHQL_WELCOME_CURSOR=4
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=6
_shql_welcome_cursor_move down
assert_eq "5" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: up moves by column count"
_SHQL_WELCOME_CURSOR=4
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move up
assert_eq "1" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: up at row 0 is no-op"
_SHQL_WELCOME_CURSOR=1
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move up
assert_eq "1" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: left wraps to prev row"
_SHQL_WELCOME_CURSOR=3
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move left
assert_eq "2" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: left at 0 is no-op"
_SHQL_WELCOME_CURSOR=0
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move left
assert_eq "0" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: home jumps to 0"
_SHQL_WELCOME_CURSOR=5
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move home
assert_eq "0" "$_SHQL_WELCOME_CURSOR"

ptyunit_test_begin "cursor nav: end jumps to last"
_SHQL_WELCOME_CURSOR=0
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=9
_shql_welcome_cursor_move end
assert_eq "8" "$_SHQL_WELCOME_CURSOR"

# ── Test: _shql_welcome_hit_tile ─────────────────────────────────────────────

ptyunit_test_begin "hit_tile: click on first tile"
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=6
_SHQL_WELCOME_GRID_TOP=3
_SHQL_WELCOME_GRID_LEFT=1
_SHQL_WELCOME_TILE_W=26
_SHQL_WELCOME_TILE_H=6
_SHQL_WELCOME_SCROLL_TOP=0
local _hit
_shql_welcome_hit_tile 4 5 _hit
assert_eq "0" "$_hit"

ptyunit_test_begin "hit_tile: click in gap returns -1"
_shql_welcome_hit_tile 4 27 _hit
assert_eq "-1" "$_hit"

# ── Test: init populates data ────────────────────────────────────────────────

ptyunit_test_begin "_shql_welcome_init: populates SHQL_RECENT_NAMES"
SHQL_RECENT_NAMES=()
_shql_welcome_init
assert_gt "${#SHQL_RECENT_NAMES[@]}" 0

ptyunit_test_begin "_shql_welcome_init: sets tile count (connections + new)"
assert_gt "$_SHQL_WELCOME_TILE_COUNT" "${#SHQL_RECENT_NAMES[@]}"

# ── Test: quit ───────────────────────────────────────────────────────────────

ptyunit_test_begin "quit: sets _SHELLFRAME_SHELL_NEXT=__QUIT__"
_SHELLFRAME_SHELL_NEXT=""
_shql_WELCOME_quit
assert_eq "__QUIT__" "$_SHELLFRAME_SHELL_NEXT"

# ── Render tests (require shellframe framebuffer) ────────────────────────────

_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${SHQL_ROOT}/../shellframe}"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$SHQL_ROOT/src/screens/header.sh"

# Helper: extract stripped text from a framebuffer row
_fb_row_text() {
    local _row="$1" _out="" _i _cols="${_SF_FRAME_COLS:-80}"
    for (( _i=0; _i<_cols; _i++ )); do
        local _idx=$(( (_row-1)*_cols + _i ))
        _out+="${_SF_FRAME_CURR[${_idx}]:-}"
    done
    printf '%s' "$_out" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g' | tr -d $'\033'
}

ptyunit_test_begin "header_render: row contains 'ShellQL'"
shellframe_fb_frame_start 30 80
SHQL_DRIVER="" SHQL_DB_PATH="" SHQL_DB_HOST="" SHQL_DB_NAME=""
_shql_WELCOME_header_render 1 1 80
_text=$(_fb_row_text 1)
assert_contains "$_text" "ShellQL"

ptyunit_test_begin "footer_render: row contains 'Navigate'"
shellframe_fb_frame_start 30 80
_shql_WELCOME_footer_render 30 1 80
_text=$(_fb_row_text 30)
assert_contains "$_text" "Navigate"

ptyunit_test_begin "footer_render: row contains 'Quit'"
assert_contains "$_text" "Quit"

ptyunit_test_summary
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/allenmccabe/lib/fissible/shellql && bash tests/run.sh --unit`
Expected: FAIL — functions `_shql_welcome_human_size`, `_shql_welcome_tile_cols`, etc. not yet defined.

- [ ] **Step 3: Implement metadata helpers in welcome.sh**

Add these functions after the constants section (after line 37 `_SHQL_WELCOME_ITEMS=()`), replacing that line and the `_shql_welcome_format_items` function. These are pure utility functions used by the tile renderer:

```bash
# ── Tile grid state ──────────────────────────────────────────────────────────

_SHQL_WELCOME_CURSOR=0           # index of selected tile (0-based)
_SHQL_WELCOME_TILE_COLS=3        # columns in current layout
_SHQL_WELCOME_TILE_COUNT=0       # total tiles (connections + "new" tile)
_SHQL_WELCOME_TILE_W=26          # computed tile width
_SHQL_WELCOME_TILE_H=6           # fixed tile height (border + 4 lines + border)
_SHQL_WELCOME_GRID_TOP=3         # first row of tile grid
_SHQL_WELCOME_GRID_LEFT=1        # first col of tile grid
_SHQL_WELCOME_SCROLL_TOP=0       # vertical scroll offset (in rows, not tiles)

# Metadata arrays (parallel to SHQL_RECENT_*)
_SHQL_WELCOME_META_SIZE=()       # human-readable file size
_SHQL_WELCOME_META_TABLES=()     # table count string
_SHQL_WELCOME_META_LAST=()       # relative date string

# Context menu state
_SHQL_WELCOME_CMENU_ACTIVE=0
_SHQL_WELCOME_CMENU_PREV_FOCUS=""

# ── _shql_welcome_human_size ─────────────────────────────────────────────────
# Convert bytes to human-readable string: "48 KB", "2.1 MB", "1.5 GB"

_shql_welcome_human_size() {
    local _bytes="$1"
    if (( _bytes == 0 )); then
        printf '0 B'; return
    elif (( _bytes < 1024 )); then
        printf '%d B' "$_bytes"; return
    elif (( _bytes < 1048576 )); then
        printf '%d KB' $(( _bytes / 1024 )); return
    elif (( _bytes < 1073741824 )); then
        local _mb=$(( _bytes / 1048576 ))
        local _frac=$(( (_bytes % 1048576) * 10 / 1048576 ))
        printf '%d.%d MB' "$_mb" "$_frac"; return
    else
        local _gb=$(( _bytes / 1073741824 ))
        local _frac=$(( (_bytes % 1073741824) * 10 / 1073741824 ))
        printf '%d.%d GB' "$_gb" "$_frac"; return
    fi
}

# ── _shql_welcome_relative_date ──────────────────────────────────────────────
# Convert ISO8601 timestamp to relative string: "Today", "Yesterday", "3 days ago"

_shql_welcome_relative_date() {
    local _iso="$1"
    [[ -z "$_iso" ]] && return 0

    # Parse date to epoch — try GNU date first, then macOS date
    local _epoch=0
    if date -d "$_iso" +%s >/dev/null 2>&1; then
        _epoch=$(date -d "$_iso" +%s 2>/dev/null)
    elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "$_iso" +%s >/dev/null 2>&1; then
        _epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$_iso" +%s 2>/dev/null)
    else
        printf '%s' "${_iso%%T*}"; return
    fi

    local _now
    _now=$(date +%s)
    local _diff=$(( _now - _epoch ))
    local _days=$(( _diff / 86400 ))

    if (( _days == 0 )); then
        printf 'Today'
    elif (( _days == 1 )); then
        printf 'Yesterday'
    elif (( _days < 7 )); then
        printf '%d days ago' "$_days"
    elif (( _days < 14 )); then
        printf 'Last week'
    elif (( _days < 30 )); then
        printf '%d weeks ago' $(( _days / 7 ))
    else
        # Show month + day
        if date -d "$_iso" +"%b %d" >/dev/null 2>&1; then
            date -d "$_iso" +"%b %d" 2>/dev/null
        else
            printf '%s' "${_iso%%T*}"
        fi
    fi
}

# ── _shql_welcome_tile_cols ──────────────────────────────────────────────────
# Compute number of tile columns for a given terminal width.
# min tile width = 26, capped at 4 columns.

_shql_welcome_tile_cols() {
    local _width="$1"
    local _cols=$(( _width / 26 ))
    (( _cols < 1 )) && _cols=1
    (( _cols > 4 )) && _cols=4
    printf '%d' "$_cols"
}

# ── _shql_welcome_shorten_path ───────────────────────────────────────────────
# Replace $HOME with ~, truncate from left if over max_len.

_shql_welcome_shorten_path() {
    local _path="$1" _max="${2:-40}"
    # Replace HOME with ~
    if [[ "$_path" == "$HOME"* ]]; then
        _path="~${_path#"$HOME"}"
    fi
    if (( ${#_path} > _max )); then
        _path="…${_path:$(( ${#_path} - _max + 1 ))}"
    fi
    printf '%s' "$_path"
}
```

- [ ] **Step 4: Run tests to verify helpers pass**

Run: `cd /Users/allenmccabe/lib/fissible/shellql && bash tests/run.sh --unit`
Expected: Helper tests pass. Navigation and hit_tile tests still fail (functions not yet defined).

- [ ] **Step 5: Commit**

```bash
git add src/screens/welcome.sh tests/unit/test-welcome.sh
git commit -m "feat(welcome): add metadata helpers — human_size, relative_date, tile_cols, shorten_path"
```

---

### Task 3: Tile Cursor Navigation

**Files:**
- Modify: `src/screens/welcome.sh`
- Test: `tests/unit/test-welcome.sh` (tests already written in Task 2)

- [ ] **Step 1: Implement cursor movement**

Add after the metadata helpers in `welcome.sh`:

```bash
# ── _shql_welcome_cursor_move ────────────────────────────────────────────────
# Move tile cursor in direction: up, down, left, right, home, end.

_shql_welcome_cursor_move() {
    local _dir="$1"
    local _c="$_SHQL_WELCOME_CURSOR"
    local _cols="$_SHQL_WELCOME_TILE_COLS"
    local _n="$_SHQL_WELCOME_TILE_COUNT"

    case "$_dir" in
        right)
            (( _c + 1 < _n )) && (( _c++ ))
            ;;
        left)
            (( _c > 0 )) && (( _c-- ))
            ;;
        down)
            local _next=$(( _c + _cols ))
            if (( _next < _n )); then
                _c="$_next"
            elif (( _c / _cols < (_n - 1) / _cols )); then
                # On a row above the last row — clamp to last tile
                _c=$(( _n - 1 ))
            fi
            ;;
        up)
            local _prev=$(( _c - _cols ))
            (( _prev >= 0 )) && _c="$_prev"
            ;;
        home)
            _c=0
            ;;
        end)
            _c=$(( _n - 1 ))
            (( _c < 0 )) && _c=0
            ;;
    esac

    _SHQL_WELCOME_CURSOR="$_c"
}

# ── _shql_welcome_hit_tile ───────────────────────────────────────────────────
# Given a mouse click at (mrow, mcol), return the tile index or -1.

_shql_welcome_hit_tile() {
    local _mrow="$1" _mcol="$2" _out_var="$3"
    local _gtop="$_SHQL_WELCOME_GRID_TOP"
    local _gleft="$_SHQL_WELCOME_GRID_LEFT"
    local _tw="$_SHQL_WELCOME_TILE_W"
    local _th="$_SHQL_WELCOME_TILE_H"
    local _cols="$_SHQL_WELCOME_TILE_COLS"
    local _n="$_SHQL_WELCOME_TILE_COUNT"
    local _scroll="$_SHQL_WELCOME_SCROLL_TOP"

    # Adjust for scroll
    local _vrow=$(( _mrow - _gtop + _scroll ))
    local _vcol=$(( _mcol - _gleft ))

    (( _vrow < 0 || _vcol < 0 )) && { printf -v "$_out_var" '%d' -1; return; }

    local _tile_row=$(( _vrow / _th ))
    local _tile_col=$(( _vcol / _tw ))

    # Check if click is in the gap between tiles (last char of tile width)
    local _within_col=$(( _vcol % _tw ))
    if (( _within_col >= _tw - 1 && _tile_col < _cols - 1 )); then
        printf -v "$_out_var" '%d' -1; return
    fi

    (( _tile_col >= _cols )) && { printf -v "$_out_var" '%d' -1; return; }

    local _idx=$(( _tile_row * _cols + _tile_col ))
    if (( _idx >= 0 && _idx < _n )); then
        printf -v "$_out_var" '%d' "$_idx"
    else
        printf -v "$_out_var" '%d' -1
    fi
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/allenmccabe/lib/fissible/shellql && bash tests/run.sh --unit`
Expected: All navigation and hit_tile tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/screens/welcome.sh
git commit -m "feat(welcome): add tile cursor navigation and hit-tile detection"
```

---

### Task 4: Tile Rendering

**Files:**
- Modify: `src/screens/welcome.sh` — rewrite render, footer, empty-state functions

- [ ] **Step 1: Rewrite `_shql_WELCOME_render` (screen layout)**

Replace the existing `_shql_WELCOME_render` function:

```bash
_shql_WELCOME_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols

    # Header: 1 row
    shellframe_shell_region header 1 1 "$_cols" 1 nofocus

    # Section label + tile grid: rows 2..N-1
    local _body_top=2
    local _body_h=$(( _rows - 2 ))
    (( _body_h < 1 )) && _body_h=1
    shellframe_shell_region tiles "$_body_top" 1 "$_cols" "$_body_h" focus

    # Footer: 1 row
    shellframe_shell_region footer "$_rows" 1 "$_cols" 1 nofocus

    # Overlay: form (create / edit)
    if (( _SHQL_WELCOME_FORM_ACTIVE )); then
        shellframe_shell_region form 1 1 "$_cols" "$_rows" focus
    fi

    # Overlay: delete confirmation
    if (( _SHQL_WELCOME_DELETE_ACTIVE )); then
        shellframe_shell_region confirm 1 1 "$_cols" "$_rows" focus
    fi

    # Overlay: context menu
    if (( _SHQL_WELCOME_CMENU_ACTIVE )); then
        shellframe_shell_region cmenu 1 1 "$_cols" "$_rows" focus
    fi
}
```

- [ ] **Step 2: Implement `_shql_WELCOME_tiles_render`**

This is the main tile grid renderer. Add it after the render function:

```bash
_shql_WELCOME_tiles_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Update grid geometry
    _SHQL_WELCOME_TILE_COLS=$(_shql_welcome_tile_cols "$_width")
    _SHQL_WELCOME_TILE_W=$(( _width / _SHQL_WELCOME_TILE_COLS ))
    _SHQL_WELCOME_GRID_TOP=$(( _top + 1 ))   # skip section label row
    _SHQL_WELCOME_GRID_LEFT="$_left"

    # Section label
    local _gray="${SHELLFRAME_GRAY:-}"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " ""
    shellframe_fb_print "$_top" "$(( _left + 1 ))" "Recent Connections" "$_gray"

    # Tile area background
    local _grid_top=$(( _top + 1 ))
    local _grid_h=$(( _height - 1 ))
    local _r
    for (( _r=0; _r<_grid_h; _r++ )); do
        shellframe_fb_fill "$(( _grid_top + _r ))" "$_left" "$_width" " " ""
    done

    local _n="$_SHQL_WELCOME_TILE_COUNT"
    (( _n == 0 )) && return 0

    local _tw="$_SHQL_WELCOME_TILE_W"
    local _th="$_SHQL_WELCOME_TILE_H"
    local _cols="$_SHQL_WELCOME_TILE_COLS"
    local _nconn=${#SHQL_RECENT_NAMES[@]}
    local _i

    for (( _i=0; _i<_n; _i++ )); do
        local _row=$(( _i / _cols ))
        local _col=$(( _i % _cols ))

        local _ty=$(( _grid_top + _row * _th - _SHQL_WELCOME_SCROLL_TOP ))
        local _tx=$(( _left + _col * _tw ))

        # Skip tiles fully above or below viewport
        (( _ty + _th <= _grid_top )) && continue
        (( _ty >= _grid_top + _grid_h )) && continue

        local _is_selected=$(( _i == _SHQL_WELCOME_CURSOR ))
        local _inner_w=$(( _tw - 3 ))  # border + padding each side + gap
        (( _inner_w < 4 )) && _inner_w=4

        if (( _i < _nconn )); then
            _shql_welcome_render_conn_tile "$_ty" "$_tx" "$_tw" "$_th" "$_i" "$_is_selected" "$_inner_w"
        else
            _shql_welcome_render_new_tile "$_ty" "$_tx" "$_tw" "$_th" "$_is_selected"
        fi
    done
}
```

- [ ] **Step 3: Implement `_shql_welcome_render_conn_tile`**

```bash
_shql_welcome_render_conn_tile() {
    local _ty="$1" _tx="$2" _tw="$3" _th="$4" _idx="$5" _sel="$6" _iw="$7"
    local _gray="${SHELLFRAME_GRAY:-$'\033[2m'}"

    # Select styles
    local _bg _border _rst=$'\033[0m'
    if (( _sel )); then
        _bg="${SHQL_THEME_TILE_SELECTED_BG:-$'\033[48;5;17m'}"
        _border="${SHQL_THEME_TILE_SELECTED_BORDER:-$'\033[38;5;68m'}"
    else
        _bg="${SHQL_THEME_TILE_BG:-$'\033[48;5;236m'}"
        _border="${SHQL_THEME_TILE_BORDER:-$'\033[38;5;242m'}"
    fi

    # Border characters
    local _tl _tr _bl _br _h _v
    if (( _sel )); then
        _tl='╔' _tr='╗' _bl='╚' _br='╝' _h='═' _v='║'
    else
        _tl='┌' _tr='┐' _bl='└' _br='┘' _h='─' _v='│'
    fi

    # Top border
    local _hline=""
    local _hi
    for (( _hi=0; _hi<_tw-3; _hi++ )); do _hline+="$_h"; done
    shellframe_fb_put "$_ty" "$_tx" "${_border}${_bg}${_tl}"
    shellframe_fb_print "$_ty" "$(( _tx + 1 ))" "$_hline" "${_border}${_bg}"
    shellframe_fb_put "$_ty" "$(( _tx + _tw - 2 ))" "${_border}${_bg}${_tr}"

    # Content rows (4 lines)
    local _name="${SHQL_RECENT_NAMES[$_idx]}"
    local _path
    _path=$(_shql_welcome_shorten_path "${SHQL_RECENT_DETAILS[$_idx]}" "$_iw")
    local _meta="${_SHQL_WELCOME_META_TABLES[$_idx]:-?} tables · ${_SHQL_WELCOME_META_SIZE[$_idx]:-?}"
    local _last="${_SHQL_WELCOME_META_LAST[$_idx]:-}"
    local _icon="${SHQL_THEME_TABLE_ICON:-🗄 }"

    # Line 1: icon + name
    local _name_display="${_icon}${_name}"
    local _name_style="${_bg}"
    (( _sel )) && _name_style="${_bg}${SHELLFRAME_BOLD:-$'\033[1m'}"
    _shql_welcome_tile_row "$(( _ty + 1 ))" "$_tx" "$_tw" "$_v" "$_bg" "$_border" "$_name_display" "$_name_style" "$_iw"

    # Line 2: path
    _shql_welcome_tile_row "$(( _ty + 2 ))" "$_tx" "$_tw" "$_v" "$_bg" "$_border" "$_path" "${_bg}${_gray}" "$_iw"

    # Line 3: metadata
    _shql_welcome_tile_row "$(( _ty + 3 ))" "$_tx" "$_tw" "$_v" "$_bg" "$_border" "$_meta" "${_bg}${_gray}" "$_iw"

    # Line 4: last opened
    _shql_welcome_tile_row "$(( _ty + 4 ))" "$_tx" "$_tw" "$_v" "$_bg" "$_border" "$_last" "${_bg}${_gray}" "$_iw"

    # Bottom border
    shellframe_fb_put "$(( _ty + 5 ))" "$_tx" "${_border}${_bg}${_bl}"
    shellframe_fb_print "$(( _ty + 5 ))" "$(( _tx + 1 ))" "$_hline" "${_border}${_bg}"
    shellframe_fb_put "$(( _ty + 5 ))" "$(( _tx + _tw - 2 ))" "${_border}${_bg}${_br}"
}

# Render one content row inside a tile: │ text padded │
_shql_welcome_tile_row() {
    local _row="$1" _tx="$2" _tw="$3" _v="$4" _bg="$5" _border="$6"
    local _text="$7" _style="$8" _iw="$9"

    shellframe_fb_put "$_row" "$_tx" "${_border}${_bg}${_v}"
    # Truncate text if too long
    local _display="$_text"
    if (( ${#_display} > _iw )); then
        _display="${_display:0:$(( _iw - 1 ))}…"
    fi
    shellframe_fb_print "$_row" "$(( _tx + 1 ))" " ${_display}" "$_style"
    # Pad remaining space
    local _pad=$(( _iw - ${#_display} ))
    local _pi
    for (( _pi=0; _pi<_pad; _pi++ )); do
        shellframe_fb_put "$_row" "$(( _tx + 2 + ${#_display} + _pi ))" "${_bg} "
    done
    shellframe_fb_put "$_row" "$(( _tx + _tw - 2 ))" "${_border}${_bg}${_v}"
}
```

- [ ] **Step 4: Implement `_shql_welcome_render_new_tile`**

```bash
_shql_welcome_render_new_tile() {
    local _ty="$1" _tx="$2" _tw="$3" _th="$4" _sel="$5"
    local _gray="${SHELLFRAME_GRAY:-$'\033[2m'}"

    local _bg _border
    if (( _sel )); then
        _bg="${SHQL_THEME_TILE_SELECTED_BG:-$'\033[48;5;17m'}"
        _border="${SHQL_THEME_TILE_SELECTED_BORDER:-$'\033[38;5;68m'}"
    else
        _bg="${SHQL_THEME_TILE_BG:-$'\033[48;5;236m'}"
        _border="${SHQL_THEME_TILE_BORDER:-$'\033[38;5;242m'}"
    fi

    local _iw=$(( _tw - 3 ))
    (( _iw < 4 )) && _iw=4

    # Dashed border characters
    local _tl='┌' _tr='┐' _bl='└' _br='┘' _v='╎'
    local _hline=""
    local _hi
    for (( _hi=0; _hi<_tw-3; _hi++ )); do _hline+="╌"; done

    # Top border (dashed)
    shellframe_fb_put "$_ty" "$_tx" "${_border}${_bg}${_tl}"
    shellframe_fb_print "$_ty" "$(( _tx + 1 ))" "$_hline" "${_border}${_bg}"
    shellframe_fb_put "$_ty" "$(( _tx + _tw - 2 ))" "${_border}${_bg}${_tr}"

    # Empty rows + centered label
    local _label="+ New Connection"
    local _label_row=$(( _ty + _th / 2 ))
    local _ri
    for (( _ri=1; _ri<_th-1; _ri++ )); do
        local _cr=$(( _ty + _ri ))
        shellframe_fb_put "$_cr" "$_tx" "${_border}${_bg}${_v}"
        local _pi
        for (( _pi=0; _pi<_iw+1; _pi++ )); do
            shellframe_fb_put "$_cr" "$(( _tx + 1 + _pi ))" "${_bg} "
        done
        shellframe_fb_put "$_cr" "$(( _tx + _tw - 2 ))" "${_border}${_bg}${_v}"
    done
    # Overwrite center row with label
    local _lpad=$(( (_iw - ${#_label}) / 2 + 1 ))
    (( _lpad < 1 )) && _lpad=1
    shellframe_fb_print "$_label_row" "$(( _tx + _lpad ))" "$_label" "${_bg}${_gray}"

    # Bottom border (dashed)
    shellframe_fb_put "$(( _ty + _th - 1 ))" "$_tx" "${_border}${_bg}${_bl}"
    shellframe_fb_print "$(( _ty + _th - 1 ))" "$(( _tx + 1 ))" "$_hline" "${_border}${_bg}"
    shellframe_fb_put "$(( _ty + _th - 1 ))" "$(( _tx + _tw - 2 ))" "${_border}${_bg}${_br}"
}
```

- [ ] **Step 5: Rewrite footer render**

Replace the existing `_shql_WELCOME_footer_render`:

```bash
_shql_WELCOME_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    local _bg="${SHQL_THEME_FOOTER_BG:-}"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "$_bg"
    local _hints="[↑↓←→] Navigate  [Enter] Open  [n] New  [e] Edit  [d] Delete  [q] Quit"
    shellframe_fb_print "$_top" "$_left" " $_hints" "$_bg"
}
```

- [ ] **Step 6: Run render tests**

Run: `cd /Users/allenmccabe/lib/fissible/shellql && bash tests/run.sh --unit`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/screens/welcome.sh
git commit -m "feat(welcome): tile grid rendering with box-drawn borders"
```

---

### Task 5: Keyboard + Mouse Handlers

**Files:**
- Modify: `src/screens/welcome.sh` — add/replace on_key, on_mouse, on_focus, action handlers

- [ ] **Step 1: Implement `_shql_WELCOME_tiles_on_key`**

Replace the old `_shql_WELCOME_list_on_key` and related functions with:

```bash
_shql_WELCOME_tiles_on_key() {
    local _key="$1"
    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_enter="${SHELLFRAME_KEY_ENTER:-$'\n'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"

    if [[ "$_key" == "$_k_up" ]]; then
        _shql_welcome_cursor_move up
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_down" ]]; then
        _shql_welcome_cursor_move down
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_left" ]]; then
        _shql_welcome_cursor_move left
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_right" ]]; then
        _shql_welcome_cursor_move right
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_home" ]]; then
        _shql_welcome_cursor_move home
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_end" ]]; then
        _shql_welcome_cursor_move end
        shellframe_shell_mark_dirty; return 0
    elif [[ "$_key" == "$_k_enter" ]]; then
        _shql_WELCOME_tiles_action
        return 0
    fi

    case "$_key" in
        n) _shql_welcome_form_open "create"; return 0 ;;
        e) _shql_welcome_form_open "edit";   return 0 ;;
        d) _shql_welcome_delete_open;        return 0 ;;
    esac

    return 1
}

_shql_WELCOME_tiles_on_focus() {
    : # tiles always have focus when active
}

_shql_WELCOME_tiles_action() {
    local _c="$_SHQL_WELCOME_CURSOR"
    local _nconn=${#SHQL_RECENT_NAMES[@]}

    # "New Connection" tile
    if (( _c >= _nconn )); then
        _shql_welcome_form_open "create"
        return 0
    fi

    # Open connection — same logic as old _shql_WELCOME_list_action
    local _src="${SHQL_RECENT_SOURCES[$_c]:-local}"
    local _ref="${SHQL_RECENT_REFS[$_c]:-}"
    if (( ${SHQL_MOCK:-0} )); then
        SHQL_DB_PATH="${SHQL_RECENT_DETAILS[$_c]:-mock.db}"
    elif [ "$_src" = "local" ]; then
        local _db="${_SHQL_CONN_DB:-$SHQL_DATA_DIR/shellql.db}"
        SHQL_DB_PATH=$("${_SHQL_SQLITE3:-sqlite3}" "$_db" \
            "SELECT path FROM connections WHERE id='${_ref//\'/\'\'}'")
        shql_conn_touch "$_ref"
    else
        SHQL_DB_PATH=$(sigil get "$_ref" path 2>/dev/null)
    fi
    shql_browser_init
    _SHELLFRAME_SHELL_NEXT="TABLE"
}
```

- [ ] **Step 2: Implement `_shql_WELCOME_tiles_on_mouse`**

```bash
_shql_WELCOME_tiles_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5" _rleft="$6" _rwidth="$7" _rheight="$8"

    [[ "$_action" != "press" ]] && return 0

    # Scroll wheel
    if (( _button == 64 )); then
        (( _SHQL_WELCOME_SCROLL_TOP > 0 )) && (( _SHQL_WELCOME_SCROLL_TOP -= _SHQL_WELCOME_TILE_H ))
        (( _SHQL_WELCOME_SCROLL_TOP < 0 )) && _SHQL_WELCOME_SCROLL_TOP=0
        shellframe_shell_mark_dirty; return 0
    elif (( _button == 65 )); then
        local _total_rows=$(( ((_SHQL_WELCOME_TILE_COUNT + _SHQL_WELCOME_TILE_COLS - 1) / _SHQL_WELCOME_TILE_COLS) * _SHQL_WELCOME_TILE_H ))
        local _max_scroll=$(( _total_rows - (_rheight - 1) ))
        (( _max_scroll < 0 )) && _max_scroll=0
        (( _SHQL_WELCOME_SCROLL_TOP += _SHQL_WELCOME_TILE_H ))
        (( _SHQL_WELCOME_SCROLL_TOP > _max_scroll )) && _SHQL_WELCOME_SCROLL_TOP="$_max_scroll"
        shellframe_shell_mark_dirty; return 0
    fi

    # Hit test
    local _hit=-1
    _shql_welcome_hit_tile "$_mrow" "$_mcol" _hit
    (( _hit < 0 )) && return 0

    _SHQL_WELCOME_CURSOR="$_hit"

    # Shift+click or right-click → context menu
    if (( _button == 2 || (_button == 0 && SHELLFRAME_MOUSE_SHIFT) )); then
        local _nconn=${#SHQL_RECENT_NAMES[@]}
        if (( _hit < _nconn )); then
            _shql_welcome_cmenu_open "$_hit" "$_mrow" "$_mcol"
        fi
        shellframe_shell_mark_dirty
        return 0
    fi

    # Left click → open
    if (( _button == 0 )); then
        _shql_WELCOME_tiles_action
        return 0
    fi

    shellframe_shell_mark_dirty
    return 0
}
```

- [ ] **Step 3: Commit**

```bash
git add src/screens/welcome.sh
git commit -m "feat(welcome): keyboard and mouse handlers for tile grid"
```

---

### Task 6: Context Menu + Metadata Init

**Files:**
- Modify: `src/screens/welcome.sh` — context menu wiring, metadata collection, init rewrite

- [ ] **Step 1: Implement context menu functions**

```bash
_shql_welcome_cmenu_open() {
    local _idx="$1" _arow="$2" _acol="$3"
    SHELLFRAME_CMENU_ITEMS=("Open" "Edit" "Delete" "Copy Path")
    SHELLFRAME_CMENU_ANCHOR_ROW="$_arow"
    SHELLFRAME_CMENU_ANCHOR_COL="$_acol"
    SHELLFRAME_CMENU_CTX="welcome_cmenu"
    SHELLFRAME_CMENU_FOCUSED=1
    SHELLFRAME_CMENU_STYLE="single"
    SHELLFRAME_CMENU_BG=""
    SHELLFRAME_CMENU_RESULT=-1
    shellframe_cmenu_init "welcome_cmenu"
    _SHQL_WELCOME_CMENU_ACTIVE=1
    _SHQL_WELCOME_CMENU_PREV_FOCUS="tiles"
    shellframe_shell_focus_set "cmenu"
    shellframe_shell_mark_dirty
}

_shql_welcome_cmenu_dismiss() {
    _SHQL_WELCOME_CMENU_ACTIVE=0
    shellframe_shell_focus_set "$_SHQL_WELCOME_CMENU_PREV_FOCUS"
    shellframe_shell_mark_dirty
}

_shql_WELCOME_cmenu_render() {
    SHELLFRAME_CMENU_FOCUSED=1
    shellframe_cmenu_render "$@"
}

_shql_WELCOME_cmenu_on_key() {
    shellframe_cmenu_on_key "$1"
    local _rc=$?
    if (( _rc == 2 )); then
        local _result="$SHELLFRAME_CMENU_RESULT"
        _shql_welcome_cmenu_dismiss
        (( _result < 0 )) && return 0
        case "$_result" in
            0) _shql_WELCOME_tiles_action ;;         # Open
            1) _shql_welcome_form_open "edit" ;;      # Edit
            2) _shql_welcome_delete_open ;;           # Delete
            3) _shql_welcome_copy_path ;;             # Copy Path
        esac
        return 0
    fi
    (( _rc == 0 )) && shellframe_shell_mark_dirty
    return "$_rc"
}

_shql_WELCOME_cmenu_on_focus() {
    SHELLFRAME_CMENU_FOCUSED="${1:-0}"
}

_shql_WELCOME_cmenu_on_mouse() {
    shellframe_cmenu_on_mouse "$@"
    local _rc=$?
    if (( _rc == 1 )); then
        # Click outside menu — dismiss
        local _result="$SHELLFRAME_CMENU_RESULT"
        _shql_welcome_cmenu_dismiss
        return 0
    fi
    if (( _rc == 2 )); then
        local _result="$SHELLFRAME_CMENU_RESULT"
        _shql_welcome_cmenu_dismiss
        (( _result < 0 )) && return 0
        case "$_result" in
            0) _shql_WELCOME_tiles_action ;;
            1) _shql_welcome_form_open "edit" ;;
            2) _shql_welcome_delete_open ;;
            3) _shql_welcome_copy_path ;;
        esac
        return 0
    fi
    shellframe_shell_mark_dirty
    return 0
}

_shql_welcome_copy_path() {
    local _c="$_SHQL_WELCOME_CURSOR"
    local _path="${SHQL_RECENT_DETAILS[$_c]:-}"
    [[ -z "$_path" ]] && return 0
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$_path" | pbcopy
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$_path" | xclip -selection clipboard
    fi
}
```

- [ ] **Step 2: Implement metadata collection in `_shql_welcome_collect_meta`**

```bash
_shql_welcome_collect_meta() {
    _SHQL_WELCOME_META_SIZE=()
    _SHQL_WELCOME_META_TABLES=()
    _SHQL_WELCOME_META_LAST=()

    local _i _n=${#SHQL_RECENT_NAMES[@]}
    for (( _i=0; _i<_n; _i++ )); do
        local _path="${SHQL_RECENT_DETAILS[$_i]}"

        # File size
        local _size="?"
        if [[ -f "$_path" ]]; then
            local _bytes=0
            if stat -f%z "$_path" >/dev/null 2>&1; then
                _bytes=$(stat -f%z "$_path" 2>/dev/null)
            elif stat -c%s "$_path" >/dev/null 2>&1; then
                _bytes=$(stat -c%s "$_path" 2>/dev/null)
            fi
            _size=$(_shql_welcome_human_size "$_bytes")
        fi
        _SHQL_WELCOME_META_SIZE+=("$_size")

        # Table count
        local _tcount="?"
        if [[ -f "$_path" ]] && ! (( ${SHQL_MOCK:-0} )); then
            _tcount=$("${_SHQL_SQLITE3:-sqlite3}" "$_path" \
                "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view')" 2>/dev/null) || _tcount="?"
        elif (( ${SHQL_MOCK:-0} )); then
            _tcount="5"
        fi
        _SHQL_WELCOME_META_TABLES+=("$_tcount")

        # Last opened (relative date)
        local _last=""
        # last_accessed data is in SHQL_RECENT arrays but not directly exposed as timestamp.
        # For now use empty — will be populated when we add timestamp to load_recent.
        _SHQL_WELCOME_META_LAST+=("$_last")
    done
}
```

- [ ] **Step 3: Rewrite `_shql_welcome_reload` and `_shql_welcome_init`**

Replace the existing functions:

```bash
_shql_welcome_reload() {
    if (( ${SHQL_MOCK:-0} )); then
        shql_mock_load_recent
    else
        shql_conn_load_recent
    fi
    _shql_welcome_collect_meta
    _SHQL_WELCOME_TILE_COUNT=$(( ${#SHQL_RECENT_NAMES[@]} + 1 ))  # +1 for "New" tile
    # Clamp cursor
    (( _SHQL_WELCOME_CURSOR >= _SHQL_WELCOME_TILE_COUNT )) && \
        _SHQL_WELCOME_CURSOR=$(( _SHQL_WELCOME_TILE_COUNT - 1 ))
    (( _SHQL_WELCOME_CURSOR < 0 )) && _SHQL_WELCOME_CURSOR=0
}

_shql_welcome_init() {
    _SHQL_WELCOME_CURSOR=0
    _SHQL_WELCOME_SCROLL_TOP=0
    _SHQL_WELCOME_CMENU_ACTIVE=0
    _shql_welcome_reload
}
```

- [ ] **Step 4: Update form/delete to use cursor instead of list selection**

Update `_shql_welcome_form_open` to use `_SHQL_WELCOME_CURSOR` instead of `shellframe_sel_cursor`:

```bash
_shql_welcome_form_open() {
    local _mode="$1"
    _SHQL_WELCOME_FORM_MODE="$_mode"
    _SHQL_WELCOME_FORM_FIELD=0
    _SHQL_WELCOME_FORM_ACTIVE=1

    if [[ "$_mode" == "edit" ]]; then
        local _cursor="$_SHQL_WELCOME_CURSOR"
        local _n=${#SHQL_RECENT_NAMES[@]}
        (( _n == 0 || _cursor >= _n )) && { _SHQL_WELCOME_FORM_ACTIVE=0; return 0; }
        _SHQL_WELCOME_FORM_EDIT_ID="${SHQL_RECENT_REFS[$_cursor]}"
        shellframe_cur_init "welcome_name" "${SHQL_RECENT_NAMES[$_cursor]}"
        shellframe_cur_init "welcome_path" "${SHQL_RECENT_DETAILS[$_cursor]}"
    else
        _SHQL_WELCOME_FORM_EDIT_ID=""
        shellframe_cur_init "welcome_name" ""
        shellframe_cur_init "welcome_path" ""
    fi

    shellframe_shell_focus_set "form"
    shellframe_shell_mark_dirty
}
```

Update `_shql_welcome_form_close` to set focus to "tiles" instead of "list":

```bash
_shql_welcome_form_close() {
    _SHQL_WELCOME_FORM_ACTIVE=0
    shellframe_shell_focus_set "tiles"
    shellframe_shell_mark_dirty
}
```

Update `_shql_welcome_delete_open` to use `_SHQL_WELCOME_CURSOR`:

```bash
_shql_welcome_delete_open() {
    local _n=${#SHQL_RECENT_NAMES[@]}
    (( _n == 0 )) && return 0

    local _cursor="$_SHQL_WELCOME_CURSOR"
    (( _cursor < 0 || _cursor >= _n )) && return 0

    local _name="${SHQL_RECENT_NAMES[$_cursor]}"
    SHELLFRAME_MODAL_TITLE="Delete Connection"
    SHELLFRAME_MODAL_MESSAGE="Remove \"${_name}\" from saved connections?"$'\n'$'\n'"The database file will not be deleted."
    SHELLFRAME_MODAL_BUTTONS=("Delete" "Cancel")
    SHELLFRAME_MODAL_ACTIVE_BTN=1
    SHELLFRAME_MODAL_STYLE="${SHQL_THEME_PANEL_STYLE_FOCUSED:-double}"
    SHELLFRAME_MODAL_INPUT=0
    shellframe_modal_init

    _SHQL_WELCOME_DELETE_ACTIVE=1
    shellframe_shell_focus_set "confirm"
    shellframe_shell_mark_dirty
}
```

Update `_shql_welcome_delete_close` to use "tiles":

```bash
_shql_welcome_delete_close() {
    _SHQL_WELCOME_DELETE_ACTIVE=0
    shellframe_shell_focus_set "tiles"
    shellframe_shell_mark_dirty
}
```

Update delete confirm handler to use cursor:

```bash
_shql_WELCOME_confirm_on_key() {
    shellframe_modal_on_key "$1"
    local _rc=$?
    if (( _rc == 2 )); then
        if (( SHELLFRAME_MODAL_RESULT == 0 )); then
            local _cursor="$_SHQL_WELCOME_CURSOR"
            local _ref="${SHQL_RECENT_REFS[$_cursor]:-}"
            if [[ -n "$_ref" ]]; then
                shql_conn_delete "$_ref"
                _shql_welcome_reload
            fi
        fi
        _shql_welcome_delete_close
        return 0
    fi
    (( _rc == 0 )) && shellframe_shell_mark_dirty
    return "$_rc"
}
```

- [ ] **Step 5: Remove old list-based functions**

Delete these functions that are no longer needed:
- `_shql_welcome_format_items`
- `_shql_WELCOME_list_render`
- `_shql_WELCOME_list_on_key`
- `_shql_WELCOME_list_on_focus`
- `_shql_WELCOME_list_action`
- `_shql_WELCOME_empty_render`
- `_shql_WELCOME_empty_on_key`
- `_shql_WELCOME_empty_on_focus`

Also remove the `_SHQL_LIST_CTX` and `_SHQL_WELCOME_ITEMS` globals.

- [ ] **Step 6: Run all tests**

Run: `cd /Users/allenmccabe/lib/fissible/shellql && bash tests/run.sh --unit`
Expected: All tests pass.

Run: `cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/run.sh --unit`
Expected: All shellframe tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/screens/welcome.sh tests/unit/test-welcome.sh
git commit -m "feat(welcome): context menu, metadata, keyboard/mouse handlers"
```

---

### Task 7: Manual Smoke Test

- [ ] **Step 1: Test with real database**

```bash
cd /Users/allenmccabe/lib/fissible/shellql
bin/shql ~/Desktop/rosewood_and_vine.db
```

Press `q` to return to welcome screen. Verify:
- Tiles render with box borders
- Selected tile has blue background + double border
- Arrow keys navigate between tiles
- Enter opens a connection
- "New Connection" tile is last, with dashed border
- Click opens, Shift+click opens context menu
- Context menu items work: Open, Edit, Delete, Copy Path

- [ ] **Step 2: Test with mock data**

```bash
SHQL_MOCK=1 bin/shql
```

Verify 5 mock connections render as tiles + 1 "New" tile.

- [ ] **Step 3: Test empty state**

Remove all connections or use a fresh data dir:

```bash
SHQL_DATA_DIR=/tmp/shql-test-empty bin/shql
```

Verify centered "No saved databases" message with "New Connection" tile.

- [ ] **Step 4: Test narrow terminal**

Resize terminal to ~50 columns. Verify tiles reflow to fewer columns.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix(welcome): smoke test adjustments"
```

---

### Task 8: Final Cleanup

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/run.sh
cd /Users/allenmccabe/lib/fissible/shellql && bash tests/run.sh
```

Expected: All tests pass.

- [ ] **Step 2: Run Docker matrix (if available)**

```bash
cd /Users/allenmccabe/lib/fissible/shellframe && bash tests/docker/run-matrix.sh
```

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git commit -m "chore(welcome): tile refactor cleanup"
```
