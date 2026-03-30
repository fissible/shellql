#!/usr/bin/env bash
# shellql/src/screens/util.sh — Shared screen utilities
#
# Sourced before all screen files. Functions here are available to every screen.

# ── _shql_word_wrap ───────────────────────────────────────────────────────────
# Word-wrap $1 to lines of at most $2 visible characters, filling
# _SHQL_WRAP_LINES with the resulting lines.
#
# Wraps at word boundaries (spaces). Words longer than $2 are character-broken.
# Embedded newlines are treated as word separators (collapsed to spaces).
#
# Usage:
#   _shql_word_wrap "$value" "$avail"
#   for line in "${_SHQL_WRAP_LINES[@]}"; do ...; done

_SHQL_WRAP_LINES=()

_shql_word_wrap() {
    local _val="$1" _avail="$2"
    _SHQL_WRAP_LINES=()

    if [[ -z "$_val" ]]; then
        _SHQL_WRAP_LINES=("")
        return 0
    fi
    (( _avail < 1 )) && { _SHQL_WRAP_LINES=("$_val"); return 0; }

    # Normalize embedded newlines to spaces
    local _norm="${_val//$'\n'/ }"

    local _words=()
    local _IFS_SAVE="$IFS"
    IFS=' ' read -ra _words <<< "$_norm"
    IFS="$_IFS_SAVE"

    local _line="" _llen=0 _word _wlen _chunk
    for _word in "${_words[@]}"; do
        _wlen=${#_word}
        (( _wlen == 0 )) && continue

        if (( _llen == 0 )); then
            if (( _wlen <= _avail )); then
                _line="$_word"
                _llen=$_wlen
            else
                # Word longer than avail: character-break
                while (( ${#_word} > 0 )); do
                    _chunk="${_word:0:$_avail}"
                    _SHQL_WRAP_LINES+=("$_chunk")
                    _word="${_word:$_avail}"
                done
            fi
        else
            if (( _llen + 1 + _wlen <= _avail )); then
                _line+=" $_word"
                (( _llen += 1 + _wlen ))
            else
                _SHQL_WRAP_LINES+=("$_line")
                _line="" _llen=0
                if (( _wlen <= _avail )); then
                    _line="$_word"
                    _llen=$_wlen
                else
                    # Word longer than avail: character-break
                    while (( ${#_word} > 0 )); do
                        _chunk="${_word:0:$_avail}"
                        _SHQL_WRAP_LINES+=("$_chunk")
                        _word="${_word:$_avail}"
                    done
                fi
            fi
        fi
    done

    [[ -n "$_line" ]] && _SHQL_WRAP_LINES+=("$_line")
    (( ${#_SHQL_WRAP_LINES[@]} == 0 )) && _SHQL_WRAP_LINES=("")
}
