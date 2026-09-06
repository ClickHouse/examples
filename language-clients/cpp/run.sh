#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

configure_args=(-DCMAKE_BUILD_TYPE=Release)
if command -v brew >/dev/null 2>&1; then
    openssl_root="$(brew --prefix openssl@3 2>/dev/null || true)"
    if [ -n "$openssl_root" ] && [ -d "$openssl_root" ]; then
        configure_args+=("-DOPENSSL_ROOT_DIR=$openssl_root")
    fi
fi

# Build chatter goes to stderr so stdout carries only the tour's output.
cmake -S . -B build "${configure_args[@]}" 1>&2
cmake --build build --parallel 1>&2

exec ./build/client_tour
