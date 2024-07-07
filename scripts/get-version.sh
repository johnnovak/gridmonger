#!/usr/bin/env bash

usage() {
    printf "%s\n" "\
Usage: $0 TYPE

Print Gridmonger version information.

TYPE must be one of:
  version            Current Gridmonger version without 'v' prefix
                     (e.g., 1.1.0, 1.2.0-alpha)

  hash               Minimum 5-char long Git hash of the currently checked
                     out commit; can be longer to guarantee uniqueness
                     (e.g., da3c5, c22ef8)

  version-and-hash   Version and Git hash concatenated with a dash
                     (e.g., 1.1.0-da3c5, 1.2.0-alpha-c22ef8)
"
}

if [ "$#" -lt 1 ]; then
    usage
    exit 0
fi

ROOT=$(git rev-parse --show-toplevel)

VERSION=$(cat "$ROOT/CURRENT_VERSION")

GIT_HASH=$(git rev-parse --short=5 HEAD)

case $1 in
    version)          echo "$VERSION" ;;
    hash)             echo "$GIT_HASH" ;;
    version-and-hash) echo "$VERSION-$GIT_HASH" ;;
    *)                usage; exit 1 ;;
esac
