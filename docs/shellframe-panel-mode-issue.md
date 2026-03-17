# Issue: Panel rendering modes: add `windowed` mode with dedicated title bar row

## Repo: fissible/shellframe

## Problem

Today `shellframe_panel_render` supports one rendering structure: a border with an optional title embedded in the top border line. There is no way for a caller to request a different panel *structure* — e.g. a dedicated title bar row inside the panel (Windows-style modal), as distinct from the title-in-border approach.

This limits theme systems in consumers. A theme that wants modals to look like windowed dialogs has no mechanism to express that.

## Proposed solution: `SHELLFRAME_PANEL_MODE`

Add a new global `SHELLFRAME_PANEL_MODE` controlling the panel's structural template:

| Value | Behaviour |
|---|---|
| `framed` (default) | Current behaviour — title embedded in top border line. No change to existing callers. |
| `windowed` | Title rendered in a dedicated full-width row immediately inside the top border, styled with `SHELLFRAME_PANEL_TITLE_BG`. Content area starts one row lower. |

### Windowed visual structure

```
╭──────────────────────────────╮   ← border (style applies)
│  Row Inspector               │   ← title bar row (SHELLFRAME_PANEL_TITLE_BG fill + title text)
│                              │   ← content area (_inner_top starts here)
│  id        1                 │
│  name      Alice             │
╰──────────────────────────────╯
```

### New globals

```bash
SHELLFRAME_PANEL_MODE="framed"       # framed (default) | windowed
SHELLFRAME_PANEL_TITLE_BG=""         # ANSI escape for title bar background in windowed mode
                                     # e.g. $'\033[1;30;102m' — bold dark text on bright green
                                     # empty → terminal default (no color)
```

### `shellframe_panel_inner` adjustment

`shellframe_panel_inner` already reads `SHELLFRAME_PANEL_STYLE` to decide the border offset. It should additionally read `SHELLFRAME_PANEL_MODE`:

```bash
# windowed mode: title bar row consumes 1 inner row
local _title_row=0
[[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1

printf -v "$_out_top"    '%d' "$(( _top  + _border + _title_row ))"
printf -v "$_out_height" '%d' "$(( _height - _border * 2 - _title_row ))"
# _out_left and _out_width unchanged
```

This means existing callers that never set `SHELLFRAME_PANEL_MODE` get identical inner bounds — fully backward compatible.

### `shellframe_panel_render` addition

When `SHELLFRAME_PANEL_MODE=windowed`, after drawing the top border (without a title in the border line), render the title bar row:

```bash
if [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]]; then
    local _title_row=$(( _top + _border ))
    local _title_bg="${SHELLFRAME_PANEL_TITLE_BG:-}"
    local _title_rst="${SHELLFRAME_RESET:-$'\033[0m'}"
    local _title_text=" ${_title}"
    local _title_tlen=${#_title_text}
    local _title_pad=$(( _width - _border * 2 - _title_tlen ))
    (( _title_pad < 0 )) && _title_pad=0
    local _title_spaces
    printf -v _title_spaces '%*s' "$_title_pad" ''
    printf '\033[%d;%dH%s%s%s%s%s' \
        "$_title_row" "$(( _left + _border ))" \
        "${_on}${_vr}${_off}" \
        "$_title_bg" "$_title_text" "$_title_spaces" "$_title_rst" >/dev/tty
    # right border char for title row
    printf '\033[%d;%dH%s' \
        "$_title_row" "$(( _left + _width - 1 ))" \
        "${_on}${_vr}${_off}" >/dev/tty
fi
```

## Consumer integration (ShellQL example)

ShellQL's theme system would add:

```bash
# src/themes/uranium.sh
SHQL_THEME_PANEL_MODE="windowed"
SHQL_THEME_PANEL_TITLE_BG=$'\033[1;30;102m'   # bold dark text on bright green

# src/themes/basic.sh
SHQL_THEME_PANEL_MODE="framed"
SHQL_THEME_PANEL_TITLE_BG=""
```

And panel renders in ShellQL would add:

```bash
SHELLFRAME_PANEL_MODE="${SHQL_THEME_PANEL_MODE:-framed}"
SHELLFRAME_PANEL_TITLE_BG="${SHQL_THEME_PANEL_TITLE_BG:-}"
```

The same save/restore pattern already used for `SHELLFRAME_PANEL_STYLE` applies.

## Backward compatibility

- `SHELLFRAME_PANEL_MODE` defaults to `"framed"` — no existing caller is affected
- `shellframe_panel_inner` inner bounds are unchanged for `framed` mode
- `SHELLFRAME_PANEL_TITLE` continues to work in `framed` mode exactly as today; in `windowed` mode it moves from the border line into the title bar row

## Out of scope for this issue

- Layout engine integration (panel size negotiation with the title row)
- Animated or multi-row title bars
- Per-side padding within the title bar
