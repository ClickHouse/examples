#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mvn -q -DskipTests package 1>&2
exec java -jar target/client-tour-jdbc.jar
