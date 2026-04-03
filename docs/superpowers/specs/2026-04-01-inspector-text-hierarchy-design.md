# Inspector text hierarchy + panel FG bleed fix

**Date:** 2026-04-01
**Status:** Approved

## Problem

Two related issues, same root cause:

1. **Panel border FG bleed.** When a panel is focused, `SHELLFRAME_PANEL_CELL_ATTRS` includes the theme accent foreground color. The side-border characters emit this FG escape, and since subsequent grid/inspector cells only set background (never foreground), the accent color bleeds into all cell text on those rows. This makes all grid data appear in the accent color (purple in cascade, green in uranium) when focused, and terminal default FG when unfocused — a jarring brightness transition.

2. **Inspector key/value indistinct.** Because both keys and values render without explicit foreground (relying entirely on bleed or terminal default), they look identical. `SHQL_THEME_VALUE_COLOR` is defined but never applied.

## Design

### Fix 1 — panel.sh: reset FG after side border characters

Append `\033[39m` (default foreground reset) after each side-border put:

```bash
shellframe_fb_put "$_row" "$_left"               "${_on}${_vr}"$'\033[39m'
shellframe_fb_put "$_row" "$(( _left + _width - 1 ))" "${_on}${_vr}"$'\033[39m'
```

Top/bottom borders are on different row numbers from cell content; no fix needed there.

### Fix 2 — inspector.sh: apply VALUE_COLOR and null styling

```bash
local _vc="${SHQL_THEME_VALUE_COLOR:-}"
local _null_style="${SHELLFRAME_GRAY:-}"
# ...
if [[ "$_val_chunk" == "(null)" ]]; then
    shellframe_fb_print "$_row" "$_val_left" "$_val_chunk" "${_ibg}${_null_style}"
else
    shellframe_fb_print "$_row" "$_val_left" "$_val_chunk" "${_ibg}${_vc}"
fi
```

### Fix 3 — cascade theme: Option B key/value colors

```bash
SHQL_THEME_KEY_COLOR=$'\033[38;5;140m\033[1m'  # muted purple (grid header color) + bold
SHQL_THEME_VALUE_COLOR=$'\033[97m'              # bright white
```

### Fix 4 — uranium theme: Option B key/value colors

```bash
SHQL_THEME_KEY_COLOR=$'\033[38;2;80;186;42m\033[1m'  # uranium green + bold
SHQL_THEME_VALUE_COLOR=$'\033[97m'                     # bright white
```

## Outcome

- Grid data cells: terminal default FG (consistent focused/unfocused)
- Focus indicated by panel border single→double only (no text color change)
- Inspector: keys = accent + bold, values = bright white, nulls = dim gray
- Consistent across cascade and uranium themes
