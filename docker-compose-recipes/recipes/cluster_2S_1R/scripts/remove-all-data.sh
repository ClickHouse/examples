#!/usr/bin/env bash


find fs/volumes/clickhouse-0?/var/lib/clickhouse/* -maxdepth 0 | xargs rm -rf
find fs/volumes/clickhouse-keeper-0?/var/lib/clickhouse/* -maxdepth 0 | xargs rm -rf