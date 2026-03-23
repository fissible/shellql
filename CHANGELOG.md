# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
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

