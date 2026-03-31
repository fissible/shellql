# ShellQL — Implementation Plan

This plan tracks the phased build-out of ShellQL. Phase 1–4 work primarily in
fissible/shellframe. Phase 5–6 work is ShellQL-specific.

For the full component design rationale, see the shellframe PROJECT.md.

---

## Phase 1–4: Shellframe primitives (tracked in fissible/shellframe)

ShellQL cannot be built until these shellframe components exist:

| Component               | Shellframe Issue | Status  |
|-------------------------|-----------------|---------|
| Component contract      | [#1](https://github.com/fissible/shellframe/issues/1) | ✓ closed |
| Layout contract         | [#2](https://github.com/fissible/shellframe/issues/2) | ✓ closed |
| Focus model             | [#3](https://github.com/fissible/shellframe/issues/3) | ✓ closed |
| Keyboard input module   | [#4](https://github.com/fissible/shellframe/issues/4) | ✓ closed |
| Selection model         | [#5](https://github.com/fissible/shellframe/issues/5) | ✓ closed |
| Cursor model            | [#6](https://github.com/fissible/shellframe/issues/6) | ✓ closed |
| Clipping helpers        | [#7](https://github.com/fissible/shellframe/issues/7) | ✓ closed |
| Text primitive          | [#8](https://github.com/fissible/shellframe/issues/8) | ✓ closed |
| Box/Panel               | [#9](https://github.com/fissible/shellframe/issues/9) | ✓ closed |
| Scroll container        | [#10](https://github.com/fissible/shellframe/issues/10) | ✓ closed |
| Selectable list         | [#11](https://github.com/fissible/shellframe/issues/11) | ✓ closed |
| Input field             | [#12](https://github.com/fissible/shellframe/issues/12) | ✓ closed |
| Tab bar                 | [#13](https://github.com/fissible/shellframe/issues/13) | ✓ closed |
| Modal/dialog            | [#14](https://github.com/fissible/shellframe/issues/14) | ✓ closed |
| Tree view               | [#15](https://github.com/fissible/shellframe/issues/15) | open |
| Text editor             | [#16](https://github.com/fissible/shellframe/issues/16) | open |
| Data grid               | [#17](https://github.com/fissible/shellframe/issues/17) | open |
| App shell               | [#18](https://github.com/fissible/shellframe/issues/18) | ✓ closed |
| Form widget             | [#36](https://github.com/fissible/shellframe/issues/36) | ✓ closed (2026-03-30) |
| Toast widget + TTL tick | [#37](https://github.com/fissible/shellframe/issues/37) | ✓ closed (2026-03-30) |
| Autocomplete layer      | [#38](https://github.com/fissible/shellframe/issues/38) | open |

---

## Phase 5: ShellQL mock screens

Build with fake data (SHQL_MOCK=1) to validate the framework before any SQLite work.

### 5.1 Welcome screen — [shellql#1](https://github.com/fissible/shellql/issues/1) ✓ closed
- Recent files list (selectable list)
- Open database action
- Empty state message
- **Effort:** M (half day)
- **Status:** Done — `src/screens/welcome.sh`, `src/state.sh`, `src/db_mock.sh`, `bin/shql` (minimal)

### 5.2 Schema browser — [shellql#2](https://github.com/fissible/shellql/issues/2) ✓ closed
- Sidebar: tree view of tables/views/indexes
- Main pane: selected object DDL/details
- **Effort:** M (half day)
- **Status:** Done — `src/screens/schema.sh`; Tab switches panes, q returns to welcome

### 5.3 Table view — [shellql#3](https://github.com/fissible/shellql/issues/3) ✓ closed
- Tab bar: Structure / Data / Query
- Data tab: data grid with mock rows
- Structure tab: schema DDL text (scrollable)
- Query tab: placeholder ("coming in Phase 5.4")
- **Effort:** L (1 day)
- **Status:** Done — `src/screens/table.sh`; Enter on schema table → TABLE; q → SCHEMA

### 5.4 Query screen — [shellql#4](https://github.com/fissible/shellql/issues/4) ✓ closed
- Multiline text editor (SQL input)
- Results data grid
- Status/error area below
- **Effort:** M (half day)
- **Status:** Done — `src/screens/query.sh`; Ctrl-D runs SQL, results grid appears, Tab switches panes, Esc/q returns to tab bar

### 5.5 Record inspector — [shellql#5](https://github.com/fissible/shellql/issues/5) ✓ closed
- Modal or side panel
- Key/value layout from row data
- Scroll for long values
- **Effort:** S (1–2h)
- **Status:** Done — `src/screens/inspector.sh`; Enter on data row → centered "Row Inspector" overlay; ↑/↓/PgUp/PgDn scroll; Esc/Enter/q dismiss

---

## Phase 6: SQLite integration

Wire real sqlite3 behind the adapter seam defined in db.sh.

### 6.1 Mock adapter — [shellql#6](https://github.com/fissible/shellql/issues/6) ✓ done
- `src/db_mock.sh` with fixture data for all adapter functions
- **Effort:** S (1–2h)
- **Status:** Done — `src/db_mock.sh`; implements `shql_mock_load_recent`, `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query` with fixture data

### 6.2 CLI entry point (`bin/shql`) — [shellql#8](https://github.com/fissible/shellql/issues/8) ✓ done
- Argument parsing for all modes (open, -q, --query, table, pipe, databases)
- **Effort:** M (half day)
- **Status:** Done — `src/cli.sh` (`shql_cli_parse` + `shql_cli_format_table`), `bin/shql` (7-mode dispatch), `tests/unit/test-cli.sh` (42 assertions)

### 6.3 SQLite adapter (`src/db.sh`) — [shellql#7](https://github.com/fissible/shellql/issues/7) ✓ done
- `shql_db_list_tables`
- `shql_db_describe`
- `shql_db_fetch`
- `shql_db_query`
- Error handling and output formatting
- **Effort:** L (1 day)
- **Status:** Done — `src/json.sh`, `src/config.sh`, `src/db.sh`, unit + integration tests

### 6.4 Discovery mode ✓ done
- Connection registry backed by `$SHQL_DATA_DIR/shellql.db`
- `src/connections.sh`: `shql_conn_init`, `shql_conn_push`, `shql_conn_migrate`, `shql_conn_list`, `shql_conn_load_recent`
- sigil aggregation (graceful no-op until `sigil list --type database --porcelain` is available)
- **Effort:** L (1 day actual)

### 6.5 Integration tests — [shellql#9](https://github.com/fissible/shellql/issues/9) ✓ done
- Real sqlite3 round-trips
- All CLI modes
- **Effort:** M (half day)
- **Status:** Done — `tests/integration/test-integration.sh`; 19 assertions (query-out, pipe, databases round-trip, error paths)

### 6.6 Name resolution — [shellql#10](https://github.com/fissible/shellql/issues/10) ✓ done
- `shql_conn_resolve_name` in `src/connections.sh`
- Pre-dispatch guard in `bin/shql`
- **Effort:** S (1–2h)
- **Status:** Done — 9 unit assertions added to `tests/unit/test-connections.sh`

---

## Dependency graph

```
shellframe primitives (P1–P4)
       │
       ├── Mock screens (P5) ─────→ validate framework
       │
       └── SQLite adapter (P6.2)
               │
               └── CLI entry point (P6.1) + Discovery (P6.3)
                          │
                          └── Integration tests (P6.4)
```

---

## Milestone targets

| Milestone                       | Condition                                        |
|---------------------------------|--------------------------------------------------|
| M1: Shellframe ready for ShellQL | All Phase 1–4 shellframe issues closed           |
| M2: Mock app complete           | All Phase 5 screens working with mock adapter    |
| M3: ShellQL v0.1 alpha          | Phase 6 complete; all integration tests passing  |

---

## Session handoff notes
> Update this section at the end of each session.

_Last updated: 2026-03-25 (Layout enhancements — padding, footer status bar, Relations header)_

**v0.3.0 released. Browser redesign + cascade theme complete. Layout enhancements shipped.**

Completed 2026-03-22 (Phase 6.1):
- `src/db_mock.sh` — fixture data for all adapter functions (`shql_mock_load_recent`, `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query`)

Completed 2026-03-22 (Phase 6.2):
- `src/cli.sh` — `shql_cli_parse` (7-mode arg resolution: welcome/open/table/query-tui/query-out/pipe/databases); `shql_cli_format_table` (MySQL-style box output); idempotency guard; pipe detection via `[ -p /dev/stdin ]`
- `bin/shql` — Sources `cli.sh`; replaces stub parser + dispatch with full 7-mode `case` statement; TTY probe (`exec 9>/dev/tty`) with `/dev/stderr` fallback for non-TUI error routing
- `tests/unit/test-cli.sh` — 42 assertions (35 parser + 7 formatter)

Completed 2026-03-22 (Phase 6.3):
- `src/json.sh` — JSON get/set backed by `sqlite3 :memory:`; idempotency guard
- `src/config.sh` — Config read/write via json.sh; two-tier `fetch_limit` default (1000 no-file / 500 key-absent); sqlite3 detection guard
- `src/db.sh` — Real SQLite adapter: `shql_db_list_tables`, `shql_db_describe`, `shql_db_fetch`, `shql_db_query`; DB path validation; row buffering + truncation warning; SELECT wrapping
- `tests/unit/test-json.sh`, `tests/unit/test-config.sh` — PATH-stub sqlite3; 20 unit tests
- `tests/integration/test-db.sh` — Real sqlite3, 24 integration tests

Also 2026-03-22:
- `tests/fixtures/demo.sqlite` — test database matching mock schema (users, orders, products, categories)
- shellframe#24 (windowed panel mode) — implemented and merged to shellframe main; issue closed

Completed 2026-03-22 (Phase 6.4 — branch `feature/phase-6.4-discovery`):
- `src/connections.sh` — full connection registry: `shql_conn_init` (schema bootstrap, shellql.db), `shql_conn_push` (id-preserving upsert + last_accessed update), `shql_conn_migrate` (one-time flat-file migration), `shql_conn_list` (local + sigil aggregate, sorted by last_used), `shql_conn_load_recent` (populates SHQL_RECENT_* arrays)
- `src/db_mock.sh` — extended `shql_mock_load_recent` to populate SHQL_RECENT_NAMES/DETAILS/SOURCES/REFS
- `src/state.sh` — removed old `shql_state_load_recent`, `shql_state_push_recent`, `SHQL_HISTORY_FILE`, `SHQL_RECENT_MAX`; added 4 new SHQL_RECENT_* array globals
- `bin/shql` — sources connections.sh; calls shql_conn_init + shql_conn_migrate at startup; replaces shql_state_push_recent with shql_conn_push; databases dispatch now shows 5-column table with header
- `src/screens/welcome.sh` — uses SHQL_RECENT_NAMES for display; resolves path via connections.id (local) or sigil (sigil source) on Enter
- `tests/unit/test-connections.sh` — 30 unit tests covering all 5 public functions
- `tests/integration/test-connections.sh` — 5 integration tests (push/list/sort/dedup round-trips)
- **Total: 174/174 assertions passing (169 unit + 5 integration)**
- **Cross-repo dependency:** `sigil list --type database --porcelain` not yet implemented; graceful no-op until added

**Run (real mode):** `SHELLFRAME_DIR=../shellframe bash bin/shql tests/fixtures/demo.sqlite`
**Run (query):** `SHELLFRAME_DIR=../shellframe bash bin/shql tests/fixtures/demo.sqlite -q "SELECT * FROM users"`
**Run (databases):** `SHELLFRAME_DIR=../shellframe bash bin/shql databases`
**Run tests:** `SHELLFRAME_DIR=../shellframe bash tests/run.sh`

Completed 2026-03-22 (Phase 6.5):
- `tests/integration/test-integration.sh` — 19 assertions: query-out (exit 0, formatted table + Alice, porcelain), pipe (exit 0 + data, porcelain), databases round-trip (path appears, porcelain variant), error paths (missing DB file, bad SQL)
- ptyunit submodule updated to v1.0.0
- **Total: 217/217 assertions passing (198 unit + 19 integration)**

Completed 2026-03-23 (Phase 6.6):
- `src/connections.sh` — `shql_conn_resolve_name`: loops `SHQL_RECENT_DETAILS`/`SHQL_RECENT_SOURCES`, three basename-matching rules (exact, strip `.sqlite`, strip `.db`), local-source-only gate
- `bin/shql` — pre-dispatch resolution block: fires when `_SHQL_CLI_DB` is set but not an existing file, skips in mock mode
- `tests/unit/test-connections.sh` — 9 new assertions (6 test cases)
- **Total: 226/226 assertions passing (178 unit + 48 integration)**
- v0.3.0 tagged and released

**Cross-repo:** `sigil list --type database --porcelain` — filed as [fissible/sigil-workspace#16](https://github.com/fissible/sigil-workspace/issues/16). ShellQL gracefully no-ops until this lands.

**Follow-up tickets (self-nominated):**
- UI fixes — data tab perf, row highlight, focus indicators, query tab layout

Completed 2026-03-23 (ptyunit consumer migration):
- `tests/ptyunit/` submodule removed
- `bootstrap.sh` — `brew install fissible/tap/ptyunit 2>/dev/null || brew upgrade`
- `tests/run.sh` — resolves `PTYUNIT_HOME` from Homebrew, delegates to `$PTYUNIT_HOME/run.sh`
- All 14 test files updated: `source "$PTYUNIT_HOME/assert.sh"` (was `$TESTS_DIR/ptyunit/assert.sh`)
- `check-deps.sh` + `.claude/settings.json` — SessionStart hook for drift detection
- `.github/workflows/ci.yml` — `bootstrap-command: bash bootstrap.sh`, `test-command: bash tests/run.sh`
- 207/207 assertions pass (unit only; integration requires `SHELLFRAME_DIR` in env)

**Completed 2026-03-24 (shellql#11 — welcome back-nav):**
- `src/screens/welcome.sh` — extracted `_shql_welcome_init`; `shql_welcome_run` delegates to it
- `bin/shql` — `open`/`table`/`query-tui` dispatch blocks call `_shql_welcome_init` after `shql_conn_push`
- `src/connections.sh` — fixed IFS whitespace collapsing in `shql_conn_load_recent`: read fields 1-4 + merged _rest, extract ref_id via `${_rest##*$'\t'}`; fixes empty SHQL_DB_PATH when last_used is absent
- `tests/unit/test-welcome.sh` — updated stale SHQL_RECENT_FILES refs; added 2 tests for `_shql_welcome_init`
- `tests/unit/test-connections.sh` — added regression test for the IFS collapsing bug
- **Total: 181/181 assertions passing**

**Completed 2026-03-24 (UI polish sprint — #16 #17 #18 #19):**
- shellframe `src/widgets/grid.sh` — `SHELLFRAME_GRID_COL_ALIGN=()`: per-column alignment ("left"/"right"/"center"); inline cell render path eliminates subshell forks for the common case (text fits column width), reducing frame lag from ~450ms → near-zero for normal data sets
- shellframe `tests/unit/test-grid.sh` — 2 new alignment render tests; 1009/1009 pass
- `src/screens/schema.sh` — 3-pane layout (sidebar | columns | DDL); `_shql_schema_load_columns` populates `_SHQL_SCHEMA_COLUMNS` from `shql_db_columns`; `_shql_SCHEMA_columns_render` draws name/type/flags panel; `_shql_schema_load_ddl` triggers column reload (closes #19)
- `src/db.sh` — `shql_db_columns <db> <table>`: PRAGMA table_info → TSV rows of name/type/flags
- `src/db_mock.sh` — mock `shql_db_columns` for all 4 fixture tables
- `src/screens/table.sh` — `_shql_detect_grid_align`: scans `SHELLFRAME_GRID_DATA` to infer right (int/float) / center (bool) / left (text) per column; sets `SHELLFRAME_GRID_COL_ALIGN`; `_shql_table_data_footer_hint`: "Rows X–Y of Z" from scroll_top + terminal size; `SHQL_MAX_COL_WIDTH` env var replaces hardcoded 30 (closes #16 #17 #18)
- `src/screens/query.sh` — same `SHQL_MAX_COL_WIDTH` + `_shql_detect_grid_align` call in `_shql_query_run`
- `tests/unit/test-schema.sh` — 6 new tests (db_columns mock, load_columns, load_ddl trigger); 199/199 pass
- **Total: 199/199 shellql unit assertions passing**

**Completed 2026-03-24 (Browser Redesign — 15 tasks):**
- Evolved TABLE screen into persistent browser: sidebar + dynamic tabs + inline record inspector
- Dynamic tab arrays (`_SHQL_TABS_TYPE/TABLE/LABEL/CTX[]`), lifecycle functions, tab bar renderer
- Sidebar uses `shellframe_list_render` with table/view icons (`▤`/`◉`)
- Content dispatch routes to data/schema/query renderers based on active tab type
- Inspector redesigned as inline content view with nav bar, ←→ row stepping
- `bin/shql` routing updated: open/table/query-tui dispatch to TABLE browser
- `welcome.sh` updated: `shql_browser_init` + TABLE (was `shql_schema_init` + SCHEMA)
- **319/319 assertions passing (264 unit + 55 integration)**

**Completed 2026-03-24 (Cascade Theme + UX polish):**
- New "cascade" theme: dark purple header, gray content bg (236), alternating row stripes (238), dim cursor (60), blue sidebar cursor (25), muted blue headers (74)
- shellframe enhancements: `SHELLFRAME_GRID_BG`, `GRID_STRIPE_BG`, `GRID_CURSOR_STYLE`, `GRID_HEADER_STYLE`, `GRID_HEADER_BG`, `SHELLFRAME_LIST_BG`, `LIST_CURSOR_STYLE`, `SHELLFRAME_EDITOR_BG`
- Esc timeout reduced to 50ms on bash 4+ (was 1s)
- Grid line-clear uses positional space-fill (no more `\033[2K` wiping sidebar)
- Grid bg preserved through separator resets (`$_bg_rst`, `$_row_bg_rst`)
- Grid cursor row fills full width with cursor bg (no cell gaps)
- Query tab: spatial arrow nav, error page in Results panel, error keeps editor in typing mode, per-ctx SQL re-run on tab switch
- `shql_db_list_objects` — returns name + type for sidebar icons
- Content area nofocus when no tabs open; +SQL auto-select on tabbar focus
- Tab focus: only active tab gets accent color; sub-pane focus gated on content region
- Dark surface below last data row; padding row above grid headers
- Inspector: grid header visible above, ↑ at scroll top dismisses, themed backgrounds, focus accent border

**Completed 2026-03-25 (Layout enhancements):**
- Viewport padding: 1-row/1-col buffer on all edges when >= 50x50 (TABLE + WELCOME screens)
- Footer status bar: two-row footer — "Connected to <db>" (left) + "H:MM am — Query returned N rows in Xms" (right) above key hints
- "Relations" header above table list in sidebar
- Welcome screen padding: same 50x50 logic

**Completed 2026-03-26 (Sidebar rendering artifacts — uranium theme):**
- `src/screens/table.sh` — moved "Relations" direct-write header inside the `"none"` border branch; it was firing unconditionally, causing the written text to bleed over the panel top-border on every frame after the first (framebuffer diff skipped re-emitting unchanged panel border cells)
- `src/themes/uranium.sh` — added `SHQL_THEME_SIDEBAR_CURSOR_BG` (green bg + black text, matches header); without it the cursor fell back to reverse-video, making the bold `│` panel border visually merge into the highlight on the selected row while appearing prominently on non-selected rows

**Completed 2026-03-26 (Phase 7F framebuffer migration — visual regression fix):**
- Root cause: shellframe v0.3.0 introduced per-cell framebuffer diff rendering. All widget render functions must write cells via `shellframe_fb_print/fill/put`; `shellframe_screen_flush` emits `\033[0m${cell}` per changed cell only. Direct-write `printf >/dev/tty` bypasses this: (1) cascade-theme bg fills disappeared on the second frame because flush skipped unchanged cells; (2) tab switching caused flush to emit erasure spaces that overwrote directly-written new content.
- `shellframe/src/panel.sh` — added `SHELLFRAME_PANEL_CELL_ATTRS` global; prepended to border cell attrs in `shellframe_panel_render`. Callers use this instead of the broken `printf '%s' "$_cbg" >/dev/tty` pre-render pattern.
- `src/screens/header.sh`, `welcome.sh`, `table.sh`, `schema.sh`, `query.sh`, `inspector.sh` — all direct-write render functions converted to framebuffer API. Multi-byte UTF-8 box-drawing chars (`─`, `│`) use `shellframe_fb_put` in a loop.
- 264/264 shellql unit assertions pass. 1233/1233 shellframe unit assertions pass.

**Completed 2026-03-27 (Rendering bug fixes — mark_dirty + deferred editor write):**
- All shellql key handlers that change visible state now call `shellframe_shell_mark_dirty` before `return 0` — fixes one-keypress rendering lag (inspector.sh, table.sh, query.sh)
- Editor/results placeholder text now includes content background color (`${_cbg}`, `${_rbg}`) to prevent SGR-reset black backgrounds on cascade theme
- shellframe `editor.sh`: deferred fd3 write prevents `shellframe_screen_flush` from erasing editor content when switching from data tabs (grid cells in PREV treated as erasures). Also removed subshell forks from `_shellframe_ed_line_segments` and `_shellframe_ed_vrow_count` (out_var pattern) for typing latency
- New test file: `tests/unit/test-db-mock.sh`; expanded inspector/schema/theme/welcome test coverage
- **371/371 shellql unit assertions pass. 1233/1233 shellframe unit assertions pass.**

**Completed 2026-03-30 (Welcome screen tile grid — PR #33 merged):**
- `src/themes/basic.sh`, `cascade.sh`, `uranium.sh` — tile-specific theme variables (border, selected, focused, metadata)
- `src/screens/welcome.sh` — full rewrite: responsive tile grid with box-drawn borders, arrow-key + mouse navigation, context menus, per-connection metadata (file size, table count)
- `tests/unit/test-welcome.sh` — expanded to cover tile grid behavior; 34/34 passing
- `src/connections.sh` — added `shql_conn_create`, `shql_conn_update`, `shql_conn_delete`, `shql_conn_touch` (full CRUD for named connections)
- `src/screens/query.sh` — row detail panel (Enter on grid row opens key/value view, ←→ navigates rows, ↑ from top / Esc / q dismisses); fast-path editor re-render during typing (bypasses full draw cycle)
- `src/screens/inspector.sh` — fixed `shellframe_str_clip_ellipsis` calls to output-var API
- `bin/shql` — added `SHQL_DEBUG` crash diagnostic export
- `docs/v1-issue-specs.md` — v1.0 issue specs drafted (Tier 0 shellframe primitives + Tier 1 DML features)
- **CI fixed**: `bootstrap.sh` macOS-only brew guard; `tests/run.sh` sibling-ptyunit fallback; `ci.yml` inlined with shellframe checkout + `SHELLFRAME_DIR`
- **417/417 shellql unit assertions pass.**

**Completed 2026-03-30 (Inspector/query detail word-wrap — bug fix):**
- `src/screens/util.sh` — new shared screen utility; `_shql_word_wrap value avail` fills `_SHQL_WRAP_LINES[]` with word-boundary-wrapped lines; long words fall back to character-break; embedded newlines treated as word separators
- `src/screens/inspector.sh` — switched from two-column to single-column layout (doubles available value width); word-wrap via `_shql_word_wrap` replaces character-slicing; display-row map now stores pre-wrapped line text in `_dr_text[]`; scroll total updated each frame without resetting position
- `src/screens/query.sh` — same word-wrap applied to `_shql_query_detail_render`
- `bin/shql` — sources `util.sh` before other screens
- `tests/unit/test-inspector.sh` — 13 new assertions: 10 for `_shql_word_wrap` unit tests, 2 for render word-wrap integration; **432/432 passing**
- **Self-nominated bug**: TEXT field values were hard-clipped mid-word with `shellframe_str_clip_ellipsis`; no path to see full content

**Completed 2026-03-30 (v1 DML + Form + Toast — shellframe#36, #37, shellql#13, #14, #15, #22):**
- `shellframe/src/widgets/toast.sh` — new toast queue widget: `shellframe_toast_show/tick/render/clear`; newest-first, capped at 3, style→color mapping; 11 unit assertions
- `shellframe/src/widgets/form.sh` — new multi-field form widget: Tab/Shift-Tab traversal, scroll, readonly skip, error row, Enter=submit (rc=2)/Esc=cancel (rc=1); 18 unit assertions
- `shellframe/shellframe.sh` — sources `form.sh` and `toast.sh`
- `shellql/src/screens/dml.sh` — new DML module: state globals, SQL builders (`_shql_dml_build_insert/update/delete`), validation, form open/render/on_key overlay; `shellframe_confirm` inline for delete; eval-based array-by-name for bash 3.2 compat; 23 unit assertions
- `shellql/src/db_mock.sh` — added `shql_db_columns` mock (users/products/orders/fallback with name+type+flags TSV)
- `shellql/src/screens/table.sh` — Esc hierarchy: tabbar Esc→sidebar, sidebar Esc/q→`_shql_quit_confirm`, content `q`→tabbar; DML overlay + toast render; `i`/`e`/`d` hooks in data content handler
- `shellql/bin/shql` — sources `dml.sh` after `inspector.sh`
- `shellql/tests/unit/test-esc-hierarchy.sh` — 7 assertions; `shellql/tests/unit/test-dml.sh` — 23 assertions
- **462/462 shellql unit assertions pass. 1325/1325 shellframe unit assertions pass.**

**[shellql#12](https://github.com/fissible/shellql/issues/12) — CLOSED** (`[o]` open database dialog)

**Completed 2026-03-30 (UX fixes — toast, inspector, close-file confirm):**
- `shellframe/src/shell.sh` — `shellframe_toast_tick` wired into draw loop + idle-timeout path; toasts now auto-dismiss
- `shellframe/src/widgets/toast.sh` — TTL reduced from 30→5; added `SHELLFRAME_TOAST_{SUCCESS,ERROR,WARNING,INFO}_COLOR` overrides for dark-theme backgrounds
- `shellframe/src/widgets/input-field.sh` — fixed `SHELLFRAME_FIELD_BG` threading in focused render so typed text doesn't revert to black background on cascade theme
- `shellql/src/themes/cascade.sh` — cascade toast colors: dark green/red/amber/gray bg + white text
- `shellql/src/screens/inspector.sh` — removed ←/→ row-stepping nav bar; Esc/Enter/q close the inspector; kv content fills full inner area
- `shellql/src/screens/table.sh` — replaced `shellframe_confirm` (fd 3 incompatible with event loop) with inline `_SHQL_QUIT_CONFIRM_ACTIVE` overlay + `focus_set` + rc=2/action routing; renamed prompt to "Close file?"; reset in `shql_table_init`
- `shellql/src/db.sh` — fixed `[notnull]` bracket quoting in `shql_db_columns` SQLite query (was silently returning 0 rows on some SQLite versions, causing empty DML forms)
- **453/453 shellql unit assertions pass.**

**Completed 2026-03-30 (additional fixes + polish):**
- `shellframe/src/shell.sh` — `shellframe_toast_tick` wired into draw loop + idle-timeout path; toasts now auto-dismiss
- `shellframe/src/widgets/toast.sh` — TTL reduced 30→5; `SHELLFRAME_TOAST_{SUCCESS,ERROR,WARNING,INFO}_COLOR` overrides for dark themes
- `shellframe/src/widgets/input-field.sh` — fixed `SHELLFRAME_FIELD_BG` threading so typed text doesn't revert to black on cascade theme
- `shellql/src/themes/cascade.sh` — cascade toast colors (dark green/red/amber/gray bg + white text)
- `shellql/src/screens/inspector.sh` — removed ←/→ row-stepping nav bar; kv content fills full inner area
- `shellql/src/screens/table.sh` — replaced `shellframe_confirm` (fd3-incompatible) with inline `_SHQL_QUIT_CONFIRM_ACTIVE` overlay
- `shellql/src/db.sh` — fixed `[notnull]` bracket quoting in `shql_db_columns` (was silently returning 0 rows on some SQLite versions)
- **453/453 shellql unit assertions pass.**
- **GitHub housekeeping:** shellframe#36, #37, shellql#22–#25 closed (2026-03-30)

---

## v1.0 Remaining Work

| Issue | Feature | Effort | Deps |
|-------|---------|--------|------|
| [shellql#26](https://github.com/fissible/shellql/issues/26) | Truncate table | XS | confirm.sh (exists) |
| [shellql#27](https://github.com/fissible/shellql/issues/27) | Drop table/view | S | confirm.sh (exists) |
| [shellql#28](https://github.com/fissible/shellql/issues/28) | Create table (SQL template) | S | none |
| [shellql#29](https://github.com/fissible/shellql/issues/29) | Export CSV | S–M | none |
| [shellql#32](https://github.com/fissible/shellql/issues/32) | First data tab focus bug | XS–S | none |
| [shellframe#38](https://github.com/fissible/shellframe/issues/38) | Autocomplete layer | M | input-field, context-menu |
| [shellql#30](https://github.com/fissible/shellql/issues/30) | SQL type-ahead | L | shellframe#38 |
| [shellql#31](https://github.com/fissible/shellql/issues/31) | Enrich context menus | XS | all DML/DDL above |

**Build order:**
1. shellql#26 + #27 + #28 + #32 — parallel (DDL ops + focus bug, all short)
2. shellql#29 + shellframe#38 — parallel (export independent; autocomplete independent)
3. shellql#30 — after shellframe#38
4. shellql#31 — last, after all actions exist

**Next:** shellql#26 + #27 + #28 + #32 (Session A — DDL + focus bug)
