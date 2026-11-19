#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$SCRIPT_DIR/macos_input.swift"
BINARY=/private/tmp/defold_player_macos_input
export SWIFT_MODULECACHE_PATH=/private/tmp/defold_player_swift_cache
export CLANG_MODULE_CACHE_PATH=/private/tmp/defold_player_clang_cache

if [ ! -x "$BINARY" ] || [ "$SOURCE" -nt "$BINARY" ]; then
    /usr/bin/swiftc -O "$SOURCE" -o "$BINARY"
fi
exec "$BINARY" "$@"
