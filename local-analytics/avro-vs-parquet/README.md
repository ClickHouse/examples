# Avro vs Parquet: reproduce a selective file-read example

Runnable companion to [Avro vs Parquet](https://clickhouse.com/resources/engineering/avro-vs-parquet). This example keeps a small, controlled observation reproducible. It is not a universal format benchmark, and no timing or winner is a promised result.

**Recorded reference:** the CLI-managed ClickHouse 26.8.32.16 run completed all 28 samples and correctness/mechanism checks. Its executable was pinned by version and SHA-256 before measurement.

It generates 500,000 deterministic event records with 20 fields, writes Avro and Parquet using the same ClickHouse build and Zstandard codec family, then consumes two columns or all 20 through direct-file queries. Output correctness, inferred types, row counts and order are checked outside the timing measurements. The file-read traces distinguish bytes returned by `pread64` from Linux guest block I/O. Nothing is sent to ClickHouse Cloud or another service.

## Requirements and scope

- Local OrbStack Docker context named `orbstack`, Linux arm64, and host Python 3 standard library. The orchestrator refuses a remote Docker endpoint.
- The Docker build downloads official software. Runtime containers have no network access, credential or directory mounts, exposed ports or additional capabilities.
- Official ClickHouse base image pinned by arm64 digest; executed managed engine **26.8.32.16**, Apache Avro Python 1.12.2, official `clickhousectl` 0.4.2. The runner invokes the CLI-managed executable rather than the unused binary in the base image. Ubuntu helper-package versions are recorded; their apt repository is not snapshot-pinned.
- 2 CPUs, 3 GiB memory and swap limit, 256 PIDs. Per-query limits are 1.5 GB memory, 30 seconds, 600,000 scanned rows and 1.5 GB scanned bytes.
- Warm OS page cache, fresh process per query, common explicit `storage_file_read_method=pread`, same query settings, seven alternating repetitions of each of four cases. No cold-cache or predicate-pruning result.

The CLI manages the binary; the workload then invokes its resolved executable as native `clickhouse local`. A server is not necessary for direct-file queries. Setup records CLI help, install/which JSON, the managed path and SHA-256, the engine version, and a comparison with the original image binary. The first CLI install selects the default inside the image, so no `local use` command or global executable symlink is needed. Ephemeral `DO_NOT_TRACK=1` disables collection without changing telemetry settings. All CLI configuration is inside the isolated image.

Setup uses the supported `local install 26.8` resolver with **strict exact output guards**. Before any measurement, setup requires version **26.8.32.16** and SHA-256 **0d0719833575d7f930580bba7769069d4bc054a8af037e8b8bc3955f7368f937**. That pin was declared after inspecting the installer output and before the new run. Future drift must stop for review. The series resolver can advance; the output guards prevent a different patch from being measured silently. No version chasing, cache seeding or automatic engine fallback occurs.

## Agent-friendly lifecycle

Choose a unique run ID. The orchestrator refuses to overwrite an existing run or run its measurements twice.

```sh
python3 reproduce.py all --id 20261020-review-01
```

This performs setup, run, validation and stop. It prints one machine-readable JSON result. Complete artifacts go to `artifacts/<id>/`, which is ignored by Git. The container is stopped even after a measured-run or validation failure; it remains available for inspection.

To operate the stages individually:

```sh
python3 reproduce.py setup --id 20261020-review-02
python3 reproduce.py run --id 20261020-review-02
python3 reproduce.py validate --id 20261020-review-02
python3 reproduce.py status --id 20261020-review-02
python3 reproduce.py cleanup --id 20261020-review-02
```

Cleanup verifies the run's ownership label and stops only its named container. It preserves files, the stopped container and images. It never prunes Docker, changes shared containers, installs host packages or alters host shell configuration. For eventual removal, inspect the exact retained container and explicitly remove that container yourself after review.

## Review the output

`validation.json` is the verdict. Exit codes are **0** for passed checks, **2** for `review_required`, and **1** for failed correctness/setup. A changed observation is not repaired by tuning settings until it agrees.

The cheap validator control test runs without Docker or a benchmark:

```sh
python3 test_validation.py
```

Its complete, missing-sample, corrupted-hash and changed-cache inputs are explicitly synthetic test fixtures. Passing that test does not mean the CLI-managed benchmark has run.

Hard checks include exact engine and CLI versions, use of the managed executable, identical settings, resource caps and architecture, 28 samples covering every format/projection/repetition, finite measurements, exact logical-output hashes, inferred types, row count/range/sum, and expected schema-resolution outcomes. The fixture is fixed rather than a general benchmark generator.

A human review is required when the cache regime or I/O counter control differs, format file sizes differ by more than 1%, or traced file-read volumes differ by more than 5% from the current pinned-run reference. The exact managed engine version and declared SHA are hard checks. The column-selection mechanism is checked separately: Avro's narrow read should still traverse approximately the full stream, and Parquet's narrow read should fetch substantially less than its full read. These thresholds identify a changed experiment; they are not format guarantees.

**Timings, CPU and memory are advisory and hardware-dependent.** No elapsed-time threshold or desired speed ratio determines success. `results/summary-table.md` reports query time, whole-process wall time, CPU, RSS and ClickHouse tracked memory separately. `max_threads=1` does not make every reader helper thread serial. Millisecond measurements, especially the small Parquet projection, have limited resolution.

Important files under each run:

- `setup/managed.json`: CLI, managed binary/version/hash and image-binary comparison.
- `results/manifest.json`, `packages.txt`, `settings.jsonl`: actual conditions.
- `results/correctness.json`, `projection-correctness.json`, `row-type-invariants.json`: independent correctness gates.
- `results/schema-resolution.json`: new reader field with default succeeds, missing default raises `SchemaResolutionException`, omitted writer field succeeds.
- `results/raw-measurements.json` and `run-*.stderr`: all 28 raw samples and engine events.
- `results/validated-file-reads.json`, `trace-*.strace`: target-file calls, requested/returned bytes, union of ranges; unfinished/resumed calls paired by PID.
- `results/io-counter-control.json`: a separate owned 16 MiB file, targeted eviction advice, then warm reread. No global cache flush.
- `results/avro-metadata.json`, `parquet-metadata.jsonl`: actual stored schemas, codecs and layout.
- `validation.json`, `state.json`, command stdout/stderr, container/image inspections: orchestration evidence.

`SelectedBytes` or query-log `read_bytes` is not physical storage I/O. `pread64` bytes include cached reads, metadata and overlap. `/proc/<pid>/io` read bytes and `ru_inblock` describe Linux guest accounting, not the laptop SSD. A warm run can return many file bytes while reporting zero guest block reads.

## Reference observations

The [CLI-managed reference run](reference/cli-26.8.32.16/README.md) contains the observations used by the article. Machine validation compares new runs with that reference; timing, CPU and RSS deltas are advisory. Record values are deterministic; Avro's random sync marker can change binary file hashes between runs. Stable correctness hashes refer to ordered RowBinary output, not byte-identical Avro files.

The reference implementation selected common pread reads to make I/O independently traceable; untouched ClickHouse-local defaults use mmap in this build. Parquet's 100,000-row layout setting is a target: the observed file has four row groups of 130,818 / 130,818 / 130,818 / 107,546 rows. Both formats use Zstandard, but internal compression levels were not independently proved equal. Data is synthetic, flat and non-null. No write-throughput, Kafka/registry, second-engine, S3, pruning, nested-data or concurrent-workload claim is tested.

The reference describes observations on the recorded environment. Treat different timings or memory use as data to inspect, and explain changes rather than tuning toward a preferred result.
