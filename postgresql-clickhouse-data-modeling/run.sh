#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker compose up -d
