#!/usr/bin/env bash
# check-deps.sh — report fissible dependency drift at session start
if ! command -v brew &>/dev/null; then exit 0; fi

if ! brew list --versions ptyunit &>/dev/null; then
    echo "DRIFT: ptyunit is not installed. Run: bash bootstrap.sh"
    exit 0
fi

if [[ -n "$(brew outdated ptyunit 2>/dev/null)" ]]; then
    echo "DRIFT: ptyunit has an update available. Run: bash bootstrap.sh"
else
    echo "OK: ptyunit is up to date ($(brew list --versions ptyunit))"
fi
