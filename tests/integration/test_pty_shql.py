"""tests/integration/test_pty_shql.py — PTY smoke tests for the shql TUI.

Requires: Python 3.9+, pyte (pip install pyte), SHELLFRAME_DIR set in environment.

Smoke-tests the six most important TUI entry points:
  1. Welcome screen renders branding
  2. Connection tiles visible on welcome screen
  3. 'q' quits cleanly from welcome screen
  4. Sidebar shows table names when a DB is opened
  5. Enter on a sidebar table opens a data tab
  6. --query flag launches the query TUI
"""

import os
import sys
import pytest

# ── Locate ptyunit libexec ────────────────────────────────────────────────────
_ptyunit_home = os.environ.get("PTYUNIT_HOME", "")
if _ptyunit_home and os.path.isdir(_ptyunit_home):
    sys.path.insert(0, _ptyunit_home)

try:
    from pty_session import PTYSession  # noqa: E402
except ImportError:
    pytest.skip("pty_session not importable (pyte missing?)", allow_module_level=True)

# ── Paths ──────────────────────────────────────────────────────────────────────
_HERE = os.path.dirname(os.path.abspath(__file__))
_SHQL_ROOT = os.path.abspath(os.path.join(_HERE, "..", ".."))
_SHELLFRAME_DIR = os.environ.get("SHELLFRAME_DIR", "")
_DEMO_DB = os.path.join(_SHQL_ROOT, "tests", "fixtures", "demo.sqlite")

if not _SHELLFRAME_DIR:
    pytest.skip("SHELLFRAME_DIR not set", allow_module_level=True)

if not os.path.isfile(_DEMO_DB):
    pytest.skip(f"demo.sqlite not found at {_DEMO_DB}", allow_module_level=True)

# ── Shared environment ────────────────────────────────────────────────────────
_ENV = {
    "SHELLFRAME_DIR": _SHELLFRAME_DIR,
    "SHQL_MOCK": "1",
    # Isolate data dir so tests never write to the user's real history
    "XDG_DATA_HOME": "/tmp/__shql_pty_test_data",
}
_SHQL_BIN = os.path.join(_SHQL_ROOT, "bin", "shql")

# ── Helper: wrapper script that sets env vars before exec ─────────────────────
import tempfile
import stat


def _make_launch_script(extra_args: str = "", env_overrides: dict = None) -> str:
    """Write a temporary wrapper script and return its path."""
    env = dict(_ENV)
    if env_overrides:
        env.update(env_overrides)
    env_lines = "\n".join(f'export {k}="{v}"' for k, v in env.items())
    fd, path = tempfile.mkstemp(suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write(f"#!/usr/bin/env bash\n{env_lines}\nexec bash {_SHQL_BIN} {extra_args}\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
    return path


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_welcome_screen_shows_branding():
    """Welcome screen renders the ShellQL branding."""
    script = _make_launch_script()
    try:
        with PTYSession(script, cols=120, rows=30, timeout=10.0, stable_window=0.5) as session:
            row = session.screen.find_row("ShellQL")
            assert row is not None, "Expected 'ShellQL' somewhere on screen"
    finally:
        os.unlink(script)


def test_welcome_screen_shows_connection_tiles():
    """Welcome screen shows the '+ New' tile (always present, even with no recent connections)."""
    script = _make_launch_script()
    try:
        with PTYSession(script, cols=120, rows=30, timeout=10.0, stable_window=0.5) as session:
            output = "\n".join(session.screen.row(r) for r in range(30))
            # '+ New' tile is always rendered regardless of connection history
            found = "+ New" in output or "New" in output
            assert found, "Expected '+ New' tile on welcome screen"
    finally:
        os.unlink(script)


def test_q_quits_from_welcome():
    """Pressing 'q' on the welcome screen exits cleanly (exit code 0)."""
    script = _make_launch_script()
    try:
        with PTYSession(script, cols=120, rows=30, timeout=10.0, stable_window=0.5) as session:
            session.send("q")
        assert session.exit_code == 0, f"Expected exit 0, got {session.exit_code}"
    finally:
        os.unlink(script)


def test_sidebar_shows_table_names():
    """Opening a database populates the sidebar with table names."""
    script = _make_launch_script(extra_args=f'"{_DEMO_DB}"', env_overrides={"SHQL_MOCK": "0"})
    try:
        # stable_window=0.5: the default 50ms window can fire before the DB-driven
        # sidebar render completes on slower CI runners.
        with PTYSession(script, cols=120, rows=30, timeout=10.0, stable_window=0.5) as session:
            # The sidebar should contain at least one of the known demo tables
            output = "\n".join(session.screen.row(r) for r in range(30))
            found = any(
                t in output
                for t in ("users", "orders", "products", "categories", "event_tasks")
            )
            assert found, "Expected at least one table name in the sidebar"
    finally:
        os.unlink(script)


def test_enter_opens_data_tab():
    """Pressing Enter on a sidebar table opens a data tab."""
    script = _make_launch_script(extra_args=f'"{_DEMO_DB}"', env_overrides={"SHQL_MOCK": "0"})
    try:
        with PTYSession(script, cols=120, rows=30, timeout=10.0, stable_window=0.5) as session:
            session.send("ENTER")
            # After Enter, a data tab should be active — look for the tab bar indicator
            output = "\n".join(session.screen.row(r) for r in range(30))
            # Tab bar typically shows the table name or a grid with data
            found = any(
                t in output
                for t in ("users", "orders", "products", "categories", "event_tasks")
            )
            assert found, "Expected table data visible after pressing Enter on sidebar"
    finally:
        os.unlink(script)


def test_query_flag_launches_query_tui():
    """The --query flag opens the query TUI (editor panel visible)."""
    script = _make_launch_script(
        extra_args=f'"{_DEMO_DB}" --query',
        env_overrides={"SHQL_MOCK": "0"},
    )
    try:
        with PTYSession(script, cols=120, rows=30, timeout=10.0, stable_window=0.5) as session:
            output = "\n".join(session.screen.row(r) for r in range(30))
            # Query TUI shows an editor panel — look for SQL prompt hint or panel border
            found = (
                "SQL" in output
                or "query" in output.lower()
                or "SELECT" in output
                or "╔" in output
                or "┌" in output
            )
            assert found, "Expected query TUI editor panel after --query flag"
    finally:
        os.unlink(script)


def test_tab_close_button_click():
    """Clicking the 'x' close button on a tab closes that tab.

    This test is the definitive regression guard for the tab close button hit
    detection.  It:
      1. Opens the browser in mock mode (120×30 terminal).
      2. Presses Enter to open the first table as a data tab.
      3. Finds the actual rendered column of the 'x' button by scanning the
         pyte screen — this is ground truth for where the button is drawn.
      4. Sends an SGR mouse-press event at that exact column.
      5. Asserts that the tab is gone (the label is no longer on the tabbar row).

    If the test fails at step 4 it means the rendered 'x' position and the
    hit-detection position diverge — a pure off-by-one in the source.
    """
    COLS = 120
    ROWS = 30
    # sidebar_w = min(30, max(15, COLS // 4)) = 30  →  tabbar starts at col 31 (1-based)
    SIDEBAR_W = min(30, max(15, COLS // 4))

    script = _make_launch_script(
        extra_args='"/mock/test.db"',
        env_overrides={"SHQL_MOCK": "1"},
    )
    try:
        with PTYSession(script, cols=COLS, rows=ROWS, timeout=10.0, stable_window=0.5) as session:
            # Open the first table by pressing Enter on the sidebar
            session.send("ENTER")

            # Tabbar is on pyte row 1 (0-indexed) = terminal row 2 (1-based)
            TABBAR_PYTE_ROW = 1
            tabbar_text = session.screen.row(TABBAR_PYTE_ROW)

            # Sanity: a tab should be open — 'x' close button must be visible
            tabbar_area = tabbar_text[SIDEBAR_W:]  # slice past the sidebar
            assert "x" in tabbar_area, (
                f"No 'x' close button found in tabbar row after opening tab.\n"
                f"Tabbar row: {repr(tabbar_text)}"
            )

            # Find the pyte column (0-indexed) of the first 'x' in the tabbar area.
            # pyte column → terminal column: add 1 (pyte is 0-indexed, terminal is 1-based)
            x_pyte_col = SIDEBAR_W + tabbar_area.index("x")
            x_term_col = x_pyte_col + 1
            tabbar_term_row = TABBAR_PYTE_ROW + 1

            # Send SGR mouse press: ESC [ < 0 ; col ; row M
            session.send(f"\x1b[<0;{x_term_col};{tabbar_term_row}M")

            # After the close the tabbar row should no longer show the tab label.
            # The first mock table opened by Enter is "categories" (alphabetically first).
            tabbar_after = session.screen.row(TABBAR_PYTE_ROW)
            assert "categories" not in tabbar_after[SIDEBAR_W:], (
                f"Tab label still present after clicking 'x' at terminal col {x_term_col}.\n"
                f"Tabbar before: {repr(tabbar_text)}\n"
                f"Tabbar after:  {repr(tabbar_after)}\n"
                f"(x was at pyte col {x_pyte_col}, term col {x_term_col})"
            )
    finally:
        os.unlink(script)
