# Path definitions: host to connect to, session setup SQL, containers to restart for a "cold" run.
path_host()  { case $1 in plain|ch) echo lab-pgch;; duckdb|duckdb_tuned|duckdb_parquet) echo lab-pgduck;; lake) echo lab-pglake;; esac; }
path_setup() { case $1 in
  plain)  echo "SET search_path = public;";;
  duckdb) echo "SET duckdb.force_execution = true; SET search_path = public;";;
  duckdb_tuned) echo "SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET duckdb.max_workers_per_postgres_scan = 4; SET duckdb.threads_for_postgres_scan = 4; SET search_path = public;";;
  duckdb_parquet) echo "SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET search_path = duckpq, public;";;
  lake)   echo "SET search_path = ice, public;";;
  ch)     echo "SET search_path = ch, public;";;
esac; }
path_containers() { case $1 in
  plain) echo lab-pgch;; ch) echo "lab-ch lab-pgch";; duckdb|duckdb_tuned|duckdb_parquet) echo lab-pgduck;; lake) echo "lab-pgduck-server lab-pglake";;
esac; }
wait_ready() { # wait_ready <path>: Postgres up, plus pgduck_server / ClickHouse where the path needs them
  wait_pg $(path_host $1) >/dev/null
  if [ "$1" = lake ]; then
    for _ in $(seq 1 180); do docker exec lab-pgduck-server psql -X -q -p 5332 -h /home/postgres/pgduck_socket_dir -c "select 1" >/dev/null 2>&1 && break; sleep 1; done; sleep 2
  fi
  if [ "$1" = ch ]; then
    for _ in $(seq 1 60); do docker exec lab-ch clickhouse-client --password lab -q "select 1" >/dev/null 2>&1 && break; sleep 1; done
  fi
}
cold_reset() { # cold_reset <path>: restart the path's processes with empty caches
  if [ "$1" = lake ]; then
    docker stop lab-pglake lab-pgduck-server >/dev/null
    docker run --rm -v lab-pglake-cache:/c $IMG_CLIENT sh -c 'rm -rf /c/* && chown 1001:1001 /c'
    drop_os_caches
    docker start lab-pgduck-server >/dev/null; sleep 2; docker start lab-pglake >/dev/null
  else
    for c in $(path_containers $1); do docker restart $c >/dev/null; done
    drop_os_caches
  fi
  wait_ready $1
}
wait_lake_cache() { # after a warm-up query, wait until pg_lake's cache manager has downloaded the files it read
  local prev=-1 n
  for _ in $(seq 1 90); do
    n=$(psql_c lab-pglake -tAc "SELECT coalesce(sum(file_size),0) FROM lake_file_cache.list()" 2>/dev/null || echo 0)
    [ "$n" != 0 ] && [ "$n" = "$prev" ] && break; prev=$n; sleep 5
  done
  echo "pg_lake file cache: $n bytes"
}
