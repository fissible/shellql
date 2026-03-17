# UI Polish: Inspector Two-Column Layout + Header Breadcrumb Bar

**Date:** 2026-03-16

---

## Scope

Two independent visual improvements:

1. **Record Inspector** — replace single-column key/value layout with two-column layout to better use the landscape modal width.
2. **Header bar** — replace per-screen bold-text labels with a shared reverse-video breadcrumb bar that shows navigation context consistently.

---

## 1. Inspector Two-Column Layout

### Problem

`_shql_inspector_render` renders pairs in a single column. The modal is ~2/3 of terminal width, but content (key + short value) only fills the leftmost portion, leaving the right half visually empty.

### Design

**Layout math (worked example with `_inner_w=40`, `_kw=8`):**

```
_col_w = (_inner_w - 1) / 2 = (40 - 1) / 2 = 19   (bash integer division)

Left column:
  starts at  : _inner_left + 1         (1-char left pad)
  usable      : _col_w - 1 = 18        (col width minus the 1-char pad)
  val_avail_l : usable - _kw - 2 = 8   (subtract key width + 2-space separator)

Divider `│` at: _inner_left + _col_w   (= _inner_left + 19)

Right column:
  starts at  : _inner_left + _col_w + 2   (past divider + 1-char pad)
  usable      : _inner_w - _col_w - 2 = 40 - 19 - 2 = 19   (remaining inner width minus divider and pad)
  val_avail_r : usable - _kw - 2 = 9
```

Left and right val_avail are computed separately. Right column has 1 extra usable char when `_inner_w` is even because `_col_w` rounds down — this is fine.

Guard: `(( _col_w < 1 )) && _col_w=1`. Both `_val_avail_l` and `_val_avail_r` must be clamped: `(( v < 1 )) && v=1`.

**Scroll model change:**

- Total logical rows changes from `_n` to `ceil(_n / 2)`.
- Bash expression: `_scroll_n=$(( (_n + 1) / 2 ))`
- `shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" "$_scroll_n" 1 10 1`
- Each rendered row `r` draws pair `2*(scroll_top + r)` on the left and `2*(scroll_top + r) + 1` on the right.
- Odd pair count: last left-column row has no right pair — leave right side blank (the clear loop already blanked it).
- `shellframe_scroll_resize "$_SHQL_INSPECTOR_CTX" "$_inner_h" 1` in `_shql_inspector_render` is **unchanged** — its argument is the physical viewport row count (`_inner_h`), not the total logical row count. Do not replace it with `_scroll_n`.

**Divider per row:** Render `│` at absolute column `_inner_left + _col_w` on the same row in the content loop.

**Visual structure per row:**
```
 key        value          │  key        value
```

### Files

- Modify: `src/screens/inspector.sh` — `_shql_inspector_render` and `_shql_inspector_open` functions.
- Modify: `tests/unit/test-inspector.sh`:
  - The on_key scroll test at line 67 manually calls `shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 5 1 3 1`. After the change, `_shql_inspector_open` would init with `ceil(5/2)=3` total rows, not 5. The on_key test bypasses `_shql_inspector_open` and sets up the scroll context directly, so its manual init must be updated to 3 total rows (or kept at a value that makes scroll-down still move top to 1 with viewport=3). Update to `shellframe_scroll_init "$_SHQL_INSPECTOR_CTX" 3 1 2 1` so the down-key test (scroll from top=0 to top=1) remains valid. The `_SHQL_INSPECTOR_PAIRS=(...)` assignment on the preceding line is **unchanged** — that array is not consumed by the on_key scroll test (which bypasses `_shql_inspector_open`), so its element count is irrelevant here.
  - No change needed to the `key_width` or `open`/`on_key` dismiss tests — those are unaffected.

---

## 2. Header Breadcrumb Bar

### Problem

Each screen has its own `_shql_SCREEN_header_render` function using the same pattern (bold label, left-aligned, terminal background). This is visually weak (no separation from content), inconsistent across screens, and leaves the right side unused.

### Design

**Shared renderer** in `src/screens/header.sh`:

```bash
_shql_header_render() {
    local _top="$1" _left="$2" _width="$3" _crumbs="$4"
    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"
    # Use ASCII separator > to avoid multi-byte length mismatch in ${#_crumbs}
    # The caller is responsible for passing ASCII-safe breadcrumb strings.
    local _text=" ${_crumbs}"
    local _tlen=${#_text}
    local _pad=$(( _width - _tlen ))
    (( _pad < 0 )) && _pad=0
    local _spaces
    printf -v _spaces '%*s' "$_pad" ''
    printf '\033[%d;%dH%s%s%s%s' \
        "$_top" "$_left" "$_rev" "$_text" "$_spaces" "$_rst" >/dev/tty
}
```

**`›` character and `${#_crumbs}` width:**
The UTF-8 character `›` (U+203A, 3 bytes) causes `${#_crumbs}` to return a character count, not a byte count, in UTF-8 locales — but the terminal advances the cursor by visual column width (1 column per `›`). In bash under UTF-8 locale, `${#string}` counts characters, so `›` counts as 1. This matches its 1-column visual width, so the padding formula is correct. The implementation may use `›` in the breadcrumb strings.

**`_left=1` invariant:** All three `shellframe_shell_region header` calls use `_left=1`. `_shql_header_render` fills `_width` columns starting from `_left`. Because `_left=1` always, the reverse-video bar extends from the left terminal edge. No `\033[2K` is needed or emitted.

**`SHELLFRAME_REVERSE`** is not defined by shellframe's own globals — use `${SHELLFRAME_REVERSE:-$'\033[7m'}` as a safe default, consistent with the pattern used throughout shellframe widgets.

**Breadcrumb per screen:**

| Screen  | Breadcrumb content |
|---------|--------------------|
| Welcome | `ShellQL` |
| Schema  | `ShellQL  ›  <basename of SHQL_DB_PATH>` |
| Table   | `ShellQL  ›  <basename of SHQL_DB_PATH>  ›  <_SHQL_TABLE_NAME>` |

**Per-screen header functions** become thin wrappers (existing `\033[2K` line removed — `_shql_header_render` handles clearing via fill):

```bash
# welcome.sh
_shql_WELCOME_header_render() {
    _shql_header_render "$1" "$2" "$3" "ShellQL"
}

# schema.sh
_shql_SCHEMA_header_render() {
    local _db; _db="$(basename "${SHQL_DB_PATH:-<no database>}")"
    _shql_header_render "$1" "$2" "$3" "ShellQL  ›  ${_db}"
}

# table.sh
_shql_TABLE_header_render() {
    local _db; _db="$(basename "${SHQL_DB_PATH:-<no database>}")"
    _shql_header_render "$1" "$2" "$3" "ShellQL  ›  ${_db}  ›  ${_SHQL_TABLE_NAME:-<none>}"
}
```

### Files

- Create: `src/screens/header.sh` — `_shql_header_render` function only.
- Modify: `src/screens/welcome.sh` — replace `_shql_WELCOME_header_render` body.
- Modify: `src/screens/schema.sh` — replace `_shql_SCHEMA_header_render` body.
- Modify: `src/screens/table.sh` — replace `_shql_TABLE_header_render` body.
- Modify: `bin/shql` — add `source "$_SHQL_ROOT/src/screens/header.sh"` immediately before the `source "$_SHQL_ROOT/src/screens/welcome.sh"` line.
- No dedicated test file for `_shql_header_render`. Render functions that write exclusively to `/dev/tty` are not unit-tested in this project (consistent with `_shql_inspector_render`, `_shql_TABLE_body_render`, etc. — none of which have unit tests). The reverse-video escape and breadcrumb content are verified by the smoke test.

---

## Testing

- Existing unit tests (`test-inspector.sh`, `test-table.sh`, `test-schema.sh`, `test-welcome.sh`) must still pass after changes.
- `test-inspector.sh`: update the on_key scroll test's manual `shellframe_scroll_init` call (see above).
- Smoke test: `SHQL_MOCK=1 SHELLFRAME_DIR=../shellframe bash bin/shql` — verify header bar is reverse-video on all three screens; verify inspector shows two columns with `│` divider.

---

## Out of Scope

- Right-aligned content in header (db size, row count, etc.) — future enhancement.
- Fallback rendering for terminals where reverse video is unsupported.
- Color beyond reverse video — no 256-color or true-color additions.
