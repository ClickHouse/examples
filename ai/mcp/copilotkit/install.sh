#!/bin/sh
set -eu
npm ci --ignore-scripts
uv tool run --python 3.13 --from mcp-clickhouse==0.6.0 python -c 'import mcp_clickhouse'
