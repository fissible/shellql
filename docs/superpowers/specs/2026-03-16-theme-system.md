# Theme System: basic + uranium

**Date:** 2026-03-16

---

## Goal

Introduce a lightweight theme system so ShellQL's visual style — panel border style, field key/value colors, header bar background — can be switched at startup via `SHQL_THEME=<name>`. Ship two themes: `basic` (current aesthetic) and `uranium` (rounded borders, green keys, cyan values).

## Architecture

A theme is a `.sh` file in `src/themes/` that sets `SHQL_THEME_*` variables. The loader `src/theme.sh` exposes `shql_theme_load <name>` which sources the appropriate file. `bin/shql` calls `shql_theme_load "${SHQL_THEME:-basic}"` after sourcing `theme.sh`, before sourcing any screen files.

Themes are load-time only — no runtime switching.

---

## Theme Variables

| Variable | Type | Purpose |
|---|---|---|
| `SHQL_THEME_PANEL_STYLE` | string | Panel border style passed to `SHELLFRAME_PANEL_STYLE` before each ShellQL panel render. Values: `"single"` or `"rounded"`. |
| `SHQL_THEME_KEY_COLOR` | ANSI escape | Color for field key text (inspector left column). May be empty string (no color). |
| `SHQL_THEME_VALUE_COLOR` | ANSI escape | Color for field value text (inspector right column). May be empty string. |
| `SHQL_THEME_VALUE_ACCENT_COLOR` | ANSI escape | Color for accented/special values. Reserved for future use; set in themes now. |
| `SHQL_THEME_HEADER_BG` | ANSI escape | Fill color/attribute for the header bar row. |
| `SHQL_THEME_RESET` | ANSI escape | Reset sequence. Always `$'\033[0m'`. Defined in each theme for consistency. |

Defaults: if a theme file omits a variable, fallback logic in each consumer uses `${SHQL_THEME_KEY_COLOR:-}` etc. (empty = no coloring). This makes adding new variables to existing themes non-breaking.

---

## Theme Files

### `src/themes/basic.sh`

Preserves current visual behavior exactly. Uses shellframe's existing bold/reset globals where they exist.

`SHELLFRAME_BOLD`, `SHELLFRAME_RESET`, and `SHELLFRAME_REVERSE` are all set by shellframe's `src/draw.sh` (via `tput`). The `:-` fallbacks below are a safety net for test environments where shellframe is not fully sourced.

```bash
SHQL_THEME_PANEL_STYLE="single"
SHQL_THEME_KEY_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_VALUE_COLOR="${SHELLFRAME_RESET:-}"
SHQL_THEME_VALUE_ACCENT_COLOR="${SHELLFRAME_BOLD:-}"
SHQL_THEME_HEADER_BG="${SHELLFRAME_REVERSE:-$'\033[7m'}"
SHQL_THEME_RESET="${SHELLFRAME_RESET:-$'\033[0m'}"
```

### `src/themes/uranium.sh`

```bash
SHQL_THEME_PANEL_STYLE="rounded"
SHQL_THEME_KEY_COLOR=$'\033[32m'           # green
SHQL_THEME_VALUE_COLOR=$'\033[96m'         # bright cyan
SHQL_THEME_VALUE_ACCENT_COLOR=$'\033[93m'  # amber/gold
SHQL_THEME_HEADER_BG=$'\033[7m'            # reverse video (same as basic for now)
SHQL_THEME_RESET=$'\033[0m'
```

---

## Loader: `src/theme.sh`

```bash
#!/usr/bin/env bash
# src/theme.sh — ShellQL theme loader

SHQL_THEME="${SHQL_THEME:-basic}"

shql_theme_load() {
    local _name="${1:-basic}"
    local _file="${_SHQL_ROOT}/src/themes/${_name}.sh"
    if [[ ! -f "$_file" ]]; then
        printf 'shql: unknown theme "%s", falling back to basic\n' "$_name" >&2
        _file="${_SHQL_ROOT}/src/themes/basic.sh"
    fi
    source "$_file" || true
}
```

`_SHQL_ROOT` is already set by `bin/shql` before any source calls. The `|| true` on the final `source` prevents `set -e` from aborting if the fallback path is also missing (degenerate case; not expected in normal operation). If both the requested theme file and `basic.sh` are missing, all `SHQL_THEME_*` variables remain unset; consumers' `:-` fallbacks produce empty strings and the app renders without color rather than aborting.

In `test-theme.sh`, set `_SHQL_ROOT` to the repo root before calling `shql_theme_load` — the variable name is `_SHQL_ROOT` (with leading underscore), matching the convention in `bin/shql`.

---

## Integration Points

### 1. Panel style — `schema.sh` and `inspector.sh`

Every place that sets `SHELLFRAME_PANEL_STYLE="single"` before a `shellframe_panel_render` call changes to:

```bash
SHELLFRAME_PANEL_STYLE="${SHQL_THEME_PANEL_STYLE:-single}"
```

Affected sites:
- `src/screens/schema.sh` — sidebar panel render (the `SHELLFRAME_PANEL_STYLE="single"` assignment before `shellframe_panel_render`).
- `src/screens/inspector.sh` — overlay panel render. In `_shql_inspector_render`, the save/restore block contains two assignments: line 121 saves `SHELLFRAME_PANEL_STYLE` to a local (do not change), and line 126 sets `SHELLFRAME_PANEL_STYLE="single"` immediately before `shellframe_panel_render` (change this one).

`src/screens/table.sh` has no `shellframe_panel_render` call today and requires no change.

### 2. Inspector key/value colors — `src/screens/inspector.sh`

In `_shql_inspector_render`, the key/value row printf changes from:

```bash
local _bold="${SHELLFRAME_BOLD:-$'\033[1m'}"
local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"
# ...
printf '...%s%-*s%s  %s' "$_bold" "$_kw" "$_key" "$_rst" "$_val_clipped"
```

to:

```bash
local _kc="${SHQL_THEME_KEY_COLOR:-}"
local _vc="${SHQL_THEME_VALUE_COLOR:-}"
local _rst="${SHQL_THEME_RESET:-$'\033[0m'}"
# ...
printf '...%s%-*s%s  %s%s%s' "$_kc" "$_kw" "$_key" "$_rst" "$_vc" "$_val_clipped" "$_rst"
```

### 3. Header bar — `src/screens/header.sh`

`_shql_header_render` uses `${SHQL_THEME_HEADER_BG:-$'\033[7m'}` for the reverse-video fill. This supersedes the `_rev="${SHELLFRAME_REVERSE:-...}"` local shown in the companion spec's code sample — use the theme variable, not the shellframe global directly.

---

## `bin/shql` Source Order

The block below shows only the module-loading section. The argument-parsing block that follows it in `bin/shql` is unchanged.

```bash
source "$_SHQL_ROOT/src/state.sh"

# adapter (mock or real)
if (( SHQL_MOCK )); then
    source "$_SHQL_ROOT/src/db_mock.sh"
else
    source "$_SHQL_ROOT/src/db.sh" 2>/dev/null || true
fi

# theme: must come after shellframe (SHELLFRAME_* globals populated)
# and before screen files (theme vars must exist when screens are sourced)
source "$_SHQL_ROOT/src/theme.sh"
shql_theme_load "${SHQL_THEME:-basic}"

# screens (header.sh added here — see companion inspector+header spec)
source "$_SHQL_ROOT/src/screens/header.sh"
source "$_SHQL_ROOT/src/screens/welcome.sh"
source "$_SHQL_ROOT/src/screens/schema.sh"
source "$_SHQL_ROOT/src/screens/table.sh"
source "$_SHQL_ROOT/src/screens/inspector.sh"

# ... argument parsing below unchanged ...
```

---

## Test Impact

### Unit test preambles

Tests that source ShellQL screen modules now also need `SHQL_THEME_*` variables defined. In each affected test file, after the shellframe stubs are declared and before any ShellQL module is sourced, add:

```bash
# Declare shellframe color globals as empty (stubs don't set them; basic.sh uses :- fallbacks)
SHELLFRAME_BOLD='' SHELLFRAME_RESET='' SHELLFRAME_REVERSE=''
source "$SHQL_ROOT/src/theme.sh"
shql_theme_load basic
```

This must come **after** the shellframe function stubs (so they're defined) and **before** `source "$SHQL_ROOT/src/screens/*.sh"` calls.

Test files using `set -u` (notably `test-welcome.sh` and `test-schema.sh`) must declare `SHELLFRAME_BOLD`, `SHELLFRAME_RESET`, and `SHELLFRAME_REVERSE` as shown above before sourcing `theme.sh`. Without these declarations, `basic.sh`'s `${SHELLFRAME_BOLD:-}` expansions would fail under `-u` if the variables were never set. The explicit `=''` assignments prevent this.

Note: `theme.sh` internally uses `_SHQL_ROOT`. The bridge direction depends on which variable the test file already defines:
- `test-table.sh` and `test-schema.sh` define `SHQL_ROOT` (no underscore) — add `_SHQL_ROOT="$SHQL_ROOT"` before sourcing `theme.sh`.
- `test-inspector.sh` already defines `_SHQL_ROOT` (with underscore) and never defines `SHQL_ROOT` — add `SHQL_ROOT="$_SHQL_ROOT"` instead (inverted bridge).

Affected test files: `test-inspector.sh`, `test-table.sh`, `test-schema.sh`. (`test-welcome.sh` does not source any screen file that references `SHQL_THEME_*` and requires no change.)

### New test file: `tests/unit/test-theme.sh`

Three assertions:
1. `shql_theme_load basic` sets `SHQL_THEME_PANEL_STYLE="single"`.
2. `shql_theme_load uranium` sets `SHQL_THEME_PANEL_STYLE="rounded"`.
3. `shql_theme_load nonexistent` falls back gracefully — exits 0, prints a warning to stderr, and `SHQL_THEME_PANEL_STYLE` equals `"single"`. Precondition: run this assertion after test 1 (`shql_theme_load basic`) so `SHQL_THEME_PANEL_STYLE` is already `"single"` before the fallback call. The fallback re-sources `basic.sh`, so the value remains `"single"`.

No shellframe dependencies. Preamble:
```bash
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SHQL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SHQL_ROOT="$_SHQL_ROOT"
source "$TESTS_DIR/ptyunit/assert.sh"
source "$_SHQL_ROOT/src/theme.sh"
```

---

## Files Summary

| Action | File |
|---|---|
| Create | `src/theme.sh` |
| Create | `src/themes/basic.sh` |
| Create | `src/themes/uranium.sh` |
| Create | `src/screens/header.sh` *(from inspector+header spec)* |
| Modify | `bin/shql` — source order + `shql_theme_load` call |
| Modify | `src/screens/inspector.sh` — panel style + key/value colors |
| Modify | `src/screens/schema.sh` — panel style |
| Modify | `src/screens/welcome.sh` — header wrapper *(from inspector+header spec)* |
| Modify | `src/screens/table.sh` — header wrapper *(from inspector+header spec)* |
| Create | `tests/unit/test-theme.sh` |
| Modify | `tests/unit/test-inspector.sh` — add theme preamble |
| Modify | `tests/unit/test-table.sh` — add theme preamble |
| Modify | `tests/unit/test-schema.sh` — add theme preamble |

---

## Out of Scope

- Runtime theme switching (no keybind, no menu).
- Theming the tab bar, grid header row, or list selection highlight — those use shellframe globals directly and are not yet mapped to `SHQL_THEME_*`.
- 256-color or true-color support — all color values are standard 16-color ANSI.
- Theme discovery / listing themes from disk.
