#!/usr/bin/env bash
set -u
umask 077

tmp=""     # global on purpose: the EXIT trap runs after main returns, when a local would be gone

usage() { printf 'usage: %s [-v] FILE\n' "${0##*/}" >&2; exit 2; }
die()   { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

main() {
    local OPTIND=1 verbose=0 opt
    while getopts ":vh" opt; do
        case $opt in
            v) verbose=1 ;;
            h) usage ;;
            *) usage ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -eq 1 ] || usage

    tmp=$(mktemp -d) || die "cannot create a temp directory"
    trap 'rm -rf "$tmp"' EXIT

    exec 9>"${TMPDIR:-/tmp}/${0##*/}.lock"
    flock -n 9 || die "another instance is running"

    [ -r "$1" ] || die "cannot read '$1'"
    (( verbose )) && printf 'processing %s (temp dir %s)\n' "$1" "$tmp" >&2
    sleep "${WL_SLEEP:-0}"
    printf 'done: %s lines\n' "$(wc -l < "$1")"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
