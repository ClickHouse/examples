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
