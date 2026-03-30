#!/usr/bin/env bash
# shellql/tests/unit/test-inspector.sh — Record inspector unit tests

_SHQL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${_SHQL_ROOT}/../shellframe}"

source "$_SHELLFRAME_DIR/src/clip.sh"
source "$_SHELLFRAME_DIR/src/draw.sh"
source "$_SHELLFRAME_DIR/src/selection.sh"
source "$_SHELLFRAME_DIR/src/scroll.sh"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$_SHELLFRAME_DIR/src/panel.sh"
source "$_SHELLFRAME_DIR/src/widgets/list.sh"
source "$_SHQL_ROOT/src/state.sh"
SHQL_MOCK=1
source "$_SHQL_ROOT/src/db_mock.sh"

# Theme preamble (test-inspector.sh uses _SHQL_ROOT; bridge SHQL_ROOT for theme.sh)
SHQL_ROOT="$_SHQL_ROOT"
source "$_SHQL_ROOT/src/theme.sh"
shql_theme_load basic

source "$_SHQL_ROOT/src/screens/inspector.sh"
source "$PTYUNIT_HOME/assert.sh"

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
shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 3 1 2 1

_shql_inspector_on_key $'\033[B'  # down
_top=0
shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _top
assert_eq "$_top" "1" "on_key: down moves scroll top to 1"

_shql_inspector_on_key $'\033[A'  # up
shellframe_scroll_top "$_SHQL_INSPECTOR_CTX" _top
assert_eq "$_top" "0" "on_key: up moves scroll top back to 0"

# ── Test: on_key dismiss keys ─────────────────────────────────────────────────

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key $'\033'; _rc=$?
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "on_key: Esc sets ACTIVE=0"
assert_eq "$_rc" "0" "on_key: Esc returns 0"

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key $'\r'
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "on_key: Enter sets ACTIVE=0"

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key 'q'
assert_eq "$_SHQL_INSPECTOR_ACTIVE" "0" "on_key: q sets ACTIVE=0"

# Verify q returns 0 (not 1 — would leak to global quit handler)
_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key 'q'; _rc=$?
assert_eq "$_rc" "0" "on_key: q returns 0 not 1"

# ── Test: on_key passes unknown keys through ──────────────────────────────────

_SHQL_INSPECTOR_ACTIVE=1
_shql_inspector_on_key 'x'
_rc=$?
assert_eq "$_rc" "1" "on_key: unknown key returns 1"

# ── Test: key column width ────────────────────────────────────────────────────

_SHQL_INSPECTOR_PAIRS=("id	1" "name	Alice" "email	a@b.com")
_shql_inspector_key_width _kw
assert_eq "$_kw" "8" "key_width: max key length is 'email'=5, clamped to min 8"

_SHQL_INSPECTOR_PAIRS=("x	1")
_shql_inspector_key_width _kw
assert_eq "$_kw" "8" "key_width: min clamped to 8"

_SHQL_INSPECTOR_PAIRS=("twelve_chars	val" "b	2")
_shql_inspector_key_width _kw
assert_eq "$_kw" "12" "key_width: mid-range value passes through unclamped"

_SHQL_INSPECTOR_PAIRS=("averylongcolumnnameextra	val" "b	2")
_shql_inspector_key_width _kw
assert_eq "$_kw" "20" "key_width: max clamped to 20"

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

ptyunit_test_begin "inspector_on_key: ↑ at scroll top (0) dismisses inspector"
_SHQL_INSPECTOR_ACTIVE=1
shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 5 1 3 1
# After init scroll top is 0 — pressing up should dismiss
_shql_inspector_on_key $'\033[A'
assert_eq "0" "$_SHQL_INSPECTOR_ACTIVE" "↑ at top: ACTIVE=0"

ptyunit_test_begin "inspector_on_key: ↑ when scroll_top>0 scrolls up (not dismiss)"
_SHQL_INSPECTOR_ACTIVE=1
shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 5 1 3 1
shellframe_scroll_move "$_SHQL_INSPECTOR_CTX" down   # top becomes 1
_shql_inspector_on_key $'\033[A'   # up from top=1
assert_eq "1" "$_SHQL_INSPECTOR_ACTIVE" "↑ not at top: stays active"

ptyunit_test_begin "inspector_on_key: page_up returns 0"
_SHQL_INSPECTOR_ACTIVE=1
shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 10 1 3 1
_shql_inspector_on_key $'\033[5~'; _rc=$?
assert_eq "0" "$_rc" "page_up: returns 0"

ptyunit_test_begin "inspector_on_key: page_down returns 0"
_shql_inspector_on_key $'\033[6~'; _rc=$?
assert_eq "0" "$_rc" "page_down: returns 0"

# ── Test: _shql_inspector_render (fb render) ──────────────────────────────────

ptyunit_test_begin "inspector_render: writes cells to framebuffer"
_setup_mock_grid
_shql_inspector_open
_SHQL_INSPECTOR_ACTIVE=1
shellframe_fb_frame_start 24 80
_shql_inspector_render 1 1 60 20
assert_eq 1 $(( ${#_SF_FRAME_DIRTY[@]} > 0 )) "render: framebuffer has dirty cells"

ptyunit_test_begin "inspector_render: panel title contains 'Record'"
assert_contains "$SHELLFRAME_PANEL_TITLE" "Record" "render: PANEL_TITLE set to Record..."

# ── Word-wrap: long values expand scroll total beyond pair count ──────────────

ptyunit_test_begin "inspector_render: short values — scroll total equals pair count"
SHELLFRAME_GRID_HEADERS=("id" "name")
SHELLFRAME_GRID_COLS=2
SHELLFRAME_GRID_ROWS=1
SHELLFRAME_GRID_DATA=("1" "Alice")
SHELLFRAME_GRID_CTX="test_grid"
shellframe_sel_init "test_grid" 1
shellframe_sel_move "test_grid" home
_shql_inspector_open
shellframe_fb_frame_start 40 80
_shql_inspector_render 1 1 60 30
_rows_var="_SHELLFRAME_SCROLL_${_SHQL_INSPECTOR_CTX}_ROWS"
assert_eq "2" "${!_rows_var}" "render: 2 short-value pairs → scroll total is 2"

ptyunit_test_begin "inspector_render: long value wraps — scroll total exceeds pair count"
SHELLFRAME_GRID_HEADERS=("id" "notes")
SHELLFRAME_GRID_COLS=2
SHELLFRAME_GRID_ROWS=1
# notes value is 120 chars — will need multiple display rows in a 60-wide panel
SHELLFRAME_GRID_DATA=("1" "$(printf '%0.s-' {1..120})")
SHELLFRAME_GRID_CTX="test_grid"
shellframe_sel_init "test_grid" 1
shellframe_sel_move "test_grid" home
_shql_inspector_open
shellframe_fb_frame_start 40 80
_shql_inspector_render 1 1 60 30
_rows_var="_SHELLFRAME_SCROLL_${_SHQL_INSPECTOR_CTX}_ROWS"
assert_eq 1 $(( ${!_rows_var} > 2 )) "render: 120-char notes → scroll total > 2 (wraps)"

ptyunit_test_summary
