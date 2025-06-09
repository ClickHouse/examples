#!/bin/bash

# install mcp-clickhouse
mkdir -p external
git clone https://github.com/ClickHouse/mcp-clickhouse external/mcp-clickhouse

# install mcp-clickhouse
pushd external/mcp-clickhouse
python -m venv .venv
source .venv/bin/activate
uv sync     
uv add fastmcp
popd

# install application dependencies
yarn install
