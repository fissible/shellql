#!/usr/bin/env bash
# bootstrap.sh — Install fissible consumer dependencies
if [[ "$(uname)" == "Darwin" ]]; then
    brew install fissible/tap/ptyunit 2>/dev/null || brew upgrade fissible/tap/ptyunit
fi
