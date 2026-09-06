#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d node_modules ]; then
  npm ci --silent 1>&2
fi

exec node --import tsx src/client-tour.ts
