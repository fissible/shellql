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
assert_eq "1.5 MB" "$(_shql_welcome_human_size 1572864)"

ptyunit_test_begin "human_size: gigabytes"
assert_eq "1.5 GB" "$(_shql_welcome_human_size 1610612736)"

ptyunit_test_begin "human_size: zero"
assert_eq "0 B" "$(_shql_welcome_human_size 0)"

# ── Test: _shql_welcome_relative_date ────────────────────────────────────────

ptyunit_test_begin "relative_date: empty string returns empty"
assert_eq "" "$(_shql_welcome_relative_date "")"

# ── Test: _shql_welcome_tile_cols ────────────────────────────────────────────

ptyunit_test_begin "tile_cols: 80 cols -> 3"
assert_eq "3" "$(_shql_welcome_tile_cols 80)"

ptyunit_test_begin "tile_cols: 120 cols -> 4"
assert_eq "4" "$(_shql_welcome_tile_cols 120)"

ptyunit_test_begin "tile_cols: 200 cols -> 4 (capped)"
assert_eq "4" "$(_shql_welcome_tile_cols 200)"

ptyunit_test_begin "tile_cols: 50 cols -> 1 (minimum)"
assert_eq "1" "$(_shql_welcome_tile_cols 50)"

ptyunit_test_begin "tile_cols: 52 cols -> 2"
assert_eq "2" "$(_shql_welcome_tile_cols 52)"

# ── Test: _shql_welcome_shorten_path ─────────────────────────────────────────

ptyunit_test_begin "shorten_path: replaces HOME with ~"
_result=$(_shql_welcome_shorten_path "$HOME/projects/app.db")
assert_eq "~/projects/app.db" "$_result"

ptyunit_test_begin "shorten_path: truncates long paths"
_long="$HOME/very/deeply/nested/directory/structure/database.db"
_result=$(_shql_welcome_shorten_path "$_long" 20)
# Should be <= 20 chars
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
_SHQL_WELCOME_CURSOR=1
_SHQL_WELCOME_TILE_COLS=3
_SHQL_WELCOME_TILE_COUNT=5
_shql_welcome_cursor_move down
assert_eq "4" "$_SHQL_WELCOME_CURSOR"

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
_hit=99
_shql_welcome_hit_tile 4 5 _hit
assert_eq "0" "$_hit"

ptyunit_test_begin "hit_tile: click in gap returns -1"
_shql_welcome_hit_tile 4 26 _hit
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

# ── Test: tiles_action on new-connection tile opens create form ──────────────

ptyunit_test_begin "tiles_action: new-connection tile opens create form"
shql_mock_load_recent
_shql_welcome_reload
_SHQL_WELCOME_CURSOR=${#SHQL_RECENT_NAMES[@]}  # the "New" tile
_SHQL_WELCOME_FORM_ACTIVE=0
_shql_WELCOME_tiles_action
assert_eq "1" "$_SHQL_WELCOME_FORM_ACTIVE"

# ── Test: tiles_action on connection tile sets DB path ───────────────────────

ptyunit_test_begin "tiles_action: connection tile sets SHQL_DB_PATH"
shql_browser_init() { true; }
SHQL_MOCK=1
shql_mock_load_recent
_shql_welcome_reload
_SHQL_WELCOME_CURSOR=0
_SHELLFRAME_SHELL_NEXT=""
_shql_WELCOME_tiles_action
assert_contains "$SHQL_DB_PATH" "app.db"
assert_eq "TABLE" "$_SHELLFRAME_SHELL_NEXT"

# ── Render tests (require shellframe framebuffer) ────────────────────────────

_SHELLFRAME_DIR="${SHELLFRAME_DIR:-${SHQL_ROOT}/../shellframe}"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$SHQL_ROOT/src/screens/header.sh"

# Helper: extract stripped text from a framebuffer row
_fb_row_text() {
    local _row="$1"
    local _raw="${_SF_ROW_CURR[$_row]:-}"
    printf '%s' "$_raw" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g' | tr -d $'\033'
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
