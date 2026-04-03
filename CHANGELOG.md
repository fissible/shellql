# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
## [1.0.0] - 2026-04-03

### Added
- Focus indicators — double border + dim on unfocused panes (shellql#14)
- Two-state editor model — button state + typing state (shellql#13)
- Data grid fills full terminal width (shellql#20)
- Context-sensitive footer hints per focused region (shellql#21)
- Results panel border + instructional empty state (shellql#15)
- Columns list pane — name/type/flags split (shellql#19)
- Column alignment, row range footer, max-width config (#16 #17 #18)
- Add tab state arrays and _shql_tab_find
- Add _shql_tab_open and _shql_tab_close lifecycle functions
- Add _shql_tab_fits capacity check
- 5-region layout, browser init, sidebar width helper, content region stubs
- Sidebar render, key handlers, Enter/s open data/schema tabs
- Dynamic tab bar renderer and tabbar on_key handler
- Content dispatch with data tab renderer and empty state
- Schema tab renderer with columns + DDL panes
- Dynamic context ids, _shql_query_render_ctx, placeholder constant
- Content on_key with spatial nav, schema/query delegation
- Inline content view, nav bar, ROW_IDX tracking, 1-char padding
- Left/right arrow steps through rows with wrap
- Browser footer hints, TABLE quit → WELCOME
- Open/table/query-tui dispatch to TABLE browser, remove SCHEMA dispatch
- Add cascade theme — dark purple header, gray content, dim cursor
- Add shql_db_list_objects — returns name + type for sidebar icons
- Theme-driven icons and conditional border removal
- Tabbar token wiring, content bg fill, grid stripe/cursor wiring
- Spatial arrow key navigation between panes
- Tab text uses focus/accent color when tabbar is focused
- Grid header visible above inspector, ↑ to dismiss
- Blue header text, lighter header bg, header border
- Styled error page in Results panel + footer flash
- Darker surface below last data row
- Viewport padding — 1-row/1-col buffer when >= 50x50
- Two-row footer — status bar + key hints
- "Relations" header above table list
- Viewport padding — 1-row/1-col buffer when >= 50x50
- Add tile variables for welcome screen
- Replace flat list with responsive tile grid
- Add connection CRUD and query row detail panel
- Add shql_db_columns mock for DML tests
- SQL builders, validation, insert/update/delete form overlay (shellql#13,#14,#15)
- Wire i/e/d keys, DML overlay render, and toast into table screen (shellql#13,#14,#15)
- Truncate table via T key with inline confirm overlay (shellql#26)
- Drop table/view via X key with inline confirm overlay (shellql#27)
- Create table SQL template via c key in sidebar (shellql#28)
- Replace [i] +Row with New Row button in gap row, relocate DML hints below grid
- Make New Row button clickable — extend tabbar region to cover gap row
- WHERE filter overlay with operator cycling (shellql#35)
- Multi-filter support + fix printf -v scope bug in apply
- Add IN, NOT IN, BETWEEN, NOT BETWEEN operators
- Clickable/focusable column headers with ORDER BY toggling (shellql#36)
- Right-aligned filter pills; fix overlay reset on re-click
- Add CSV and SQL dump export overlay (shellql#29)
- Add --help flag and update README
- Refresh keybindings and DML rows-affected feedback
- Enrich context menus, schema hints, and polish (shellql#31)
- Add SQL autocomplete provider (shellql#30)
- WHERE filter, multi-filter pills, DDL actions, autocomplete, export, v1 polish

### Fixed
- Pre-load recent list on back-nav from open/table/query-tui modes
- Preserve ref_id when last_used is empty in load_recent
- Resolve 9 TUI rendering and interaction bugs
- Wire SHQL_THEME_CONTENT_BG to SHELLFRAME_GRID_BG
- Use scroll_left (not scroll_top) for horizontal scroll check
- Cascade tab styling, sidebar cursor, grid bg preservation
- Esc routing, SQL panel accent color, editor focus bg
- Enter key handles both CR and LF; panel focus-only styling
- +SQL auto-select, content nofocus when empty, title bar, blue cursor
- Center placeholder, remove examples, content bg, focus accent
- Content bg on panels, disabled editor look, purple headers
- Sidebar dark gray bg (234), editor typing bg (235)
- Editor/results use EDITOR_BG (235), Esc is instant
- Tab gaps use content bg instead of black
- Remove tab-content border line, fix +SQL focus style
- Data grid headers muted blue/cyan (110) instead of purple
- Grid header needs height>=3 to render
- Only active tab gets focus color; add padding row
- Padding row above content fills with content bg
- Themed backgrounds, new title, nav bar gradation
- Themed bg on key/value text, focus color border
- Data row cursor uses muted purple (54) instead of gray
- Readable header blue (74), muted cursor purple (60)
- Horizontally center empty content help text
- Crash on Enter in editor — _rst unbound under set -u
- On error, focus returns to editor instead of results
- Center placeholder text, stay in typing mode on error
- Re-run SQL when tab switch steals grid globals
- Sub-pane focus requires content region to be focused
- Revert viewport padding, header says ShellQL, footer has connection
- Value text uses inner bg instead of black
- Stop direct-write header bleeding into panel border; uranium cursor bg
- Migrate all direct-write render functions to framebuffer API
- Use BASH_SOURCE[0] in test-inspector.sh path resolution
- Add mark_dirty calls and fix black-bg placeholders
- Add shellframe checkout and fix ptyunit discovery for Linux
- Complete uranium theme with all required variables
- Word-wrap long TEXT values instead of truncating
- Word-wrap long TEXT values instead of truncating
- Sidebar Esc/q → confirm, tabbar Esc → sidebar, content q → tabbar (shellql#22)
- Inline confirm overlays, toast colors, inspector nav removal
- Stub tput in uranium theme test to fix CI (no 256-color TTY)
- +Row button above data grid, inspector up-arrow dismiss
- Apply CREATE TABLE template after editor lazy-init (shellql#28)
- Remove empty-state center hint to eliminate ghost artifact
- Clear framebuffer PREV on query tab close to eliminate editor ghost
- Mark_dirty on operator cycle; render grid behind WHERE overlay
- Printf -v scope bug; add filter pills; fresh form for + Filter
- Call mark_dirty on Tab/Shift-Tab focus change in WHERE overlay
- Use _ctx_active instead of undefined _ctx in overlay call
- Sync _SHQL_TABLE_BODY_FOCUSED in content_on_focus (shellql#32)
- Widen sorted columns by 2 to fit ↑/↓ indicator without overlap
- Account for 1-px column separators in overlay and hit-test loops
- Header Enter key and row highlight while in header focus mode
- Sort indicators disappear when scrolling; perf improvements
## [0.3.0] - 2026-03-23

### Added
- Add shql_conn_init with schema bootstrap
- Add shql_conn_push with id-preserving upsert
- Add shql_conn_migrate with all-or-nothing transaction
- Add shql_conn_list with local+sigil aggregation
- Add shql_conn_load_recent
- Extend shql_mock_load_recent to populate SHQL_RECENT_* arrays
- Wire connections.sh into startup and dispatch
- Switch to SHQL_RECENT_* arrays from connection registry
- Phase 6.4 — connection registry (shql_conn_*)
- Add shql_conn_resolve_name (shellql#10)
- Wire name resolution into bin/shql dispatch (shellql#10)

### Changed
- Replace recent-files functions with SHQL_RECENT_* arrays

### Fixed
- Add explicit NOT NULL to id column
- Capture sqlite3 rc; fix idempotency test assertion
- Escape _driver and _port in push SQL to prevent injection
- Guard blank-file rename in migrate; surface errors on failure
- Suppress expected error in failure test to preserve runner parse
- Use pipe instead of here-string in sigil loop; use cached sqlite3 path
- Add sqlite3 guard; fix flaky sort-order assertions
## [0.2.0] - 2026-03-23

### Added
- Add query.sh with init/run/footer/on_key/render + unit tests
- Wire Query tab to query.sh; remove placeholder stub
- Source query.sh in bin/shql
- Add JSON get/set utilities backed by sqlite3 :memory:
- Add config read/write backed by json.sh; two-tier fetch_limit default
- Add real SQLite adapter with fetch_limit and truncation warning
- Source json.sh and config.sh in bin/shql before SHQL_MOCK guard
- Add shql_cli_parse with 7-mode argument resolution
- Add shql_cli_format_table with MySQL-style box output
- Wire cli.sh; implement all 7 dispatch modes
- Add Worker role section to CLAUDE.md

### Fix
- Use $SHQL_THEME directly in shql_theme_load call (theme.sh already sets default)

### Fixed
- Update shql_db_query fixture to 3-col/3-row
- Surface db truncation warnings in table and query views
- Add permissions: contents: write to release workflow caller

### Inspector
- Two-column layout, ceil(N/2) scroll model, theme key/value colors

### Theme
- Uranium header RGB(80,186,42); add SHQL_THEME_TABBAR_BG for grey inactive tabs

