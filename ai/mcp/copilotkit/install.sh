#!/bin/bash

# install mcp-clickhouse
mkdir -p external
git clone https://github.com/ClickHouse/mcp-clickhouse external/mcp-clickhouse
cd external/mcp-clickhouse
uv sync     
uv add fastmcp
cd -

# install application dependencies
npm install
