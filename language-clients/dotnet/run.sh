#!/usr/bin/env bash
# Builds if needed and runs the tour. Assumes the CLICKHOUSE_* variables are exported.
set -euo pipefail
cd "$(dirname "$0")"

if command -v dotnet >/dev/null 2>&1; then
  dotnet=dotnet
elif [[ -n "${DOTNET_ROOT:-}" && -x "$DOTNET_ROOT/dotnet" ]]; then
  dotnet="$DOTNET_ROOT/dotnet"
elif [[ -x "$HOME/.dotnet/dotnet" ]]; then
  dotnet="$HOME/.dotnet/dotnet"
else
  echo "dotnet SDK not found; install .NET or set DOTNET_ROOT" >&2
  exit 1
fi

exec "$dotnet" run -c Release --project ClientTour.csproj --verbosity quiet --nologo
