# Run the measurement harness

The [basic example](README.md) runs directly with ClickHouse on your machine. This optional harness captures the extra correctness, resource, and file-read evidence used to compare runs with the [recorded reference](reference/cli-26.8.32.16/README.md).

## Requirements

Use Python 3 and a local Docker engine with Linux containers, cgroup v2, a supported amd64 or arm64 CPU, and at least 2 CPUs and 3 GiB of memory available to Docker. The first build needs internet access.

The harness installs clickhousectl 0.4.2 inside its image. New runs require ClickHouse 26.8.33.8 and its declared architecture-specific SHA-256 in `pins.py`. The committed reference was recorded with 26.8.32.16; those measurements remain unchanged. Setup refuses an unexpected executable or version.

## Run

From this directory, choose a fresh run ID.

```sh
RUN_ID="measured-$(date -u +%Y%m%d%H%M%S)"
python3 reproduce.py all --id "$RUN_ID"
```

The harness uses the current local Docker selection. Add `--context NAME` to choose another local context. TCP and SSH endpoints are refused, and the selected endpoint is retained for subsequent stages.

Setup, measurement, validation, and container stop happen automatically. The container has 2-CPU/3-GiB limits, no runtime network, no host mounts, and no added capabilities. The stopped container and ignored artifacts are retained.

## Inspect the result

```sh
cat "artifacts/$RUN_ID/validation.json"
cat "artifacts/$RUN_ID/results/summary-table.md"
```

Exit code 0 indicates passed checks; 2 means `review_required`; 1 means the run failed. Inspect any review reasons without changing settings to force agreement. Timings are advisory.

Artifacts include the managed executable details under `setup/`, the dataset and query settings, all 28 samples, correctness hashes, raw logs, and file-read traces under `results/`.

The [reference evidence](reference/README.md) describes the recorded environment and measurements. The lightweight controls run without a benchmark or Docker access.

```sh
python3 test_runtime.py
python3 test_validation.py
```
