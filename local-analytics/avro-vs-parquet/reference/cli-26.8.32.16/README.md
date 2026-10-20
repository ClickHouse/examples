# CLI-managed reference run: 26.8.32.16

Run `20261020-cli-03`, 2026-10-20. Official CLI 0.4.2 actually installed the managed engine inside an isolated image; the runner invoked `/root/.clickhouse/versions/26.8.32.16/clickhouse`. The version and SHA **0d0719833575d7f930580bba7769069d4bc054a8af037e8b8bc3955f7368f937** were declared before measurements. [Managed setup](managed-setup.json).

Same Apple M4 Pro/24 GiB host, OrbStack Linux arm64, 2-CPU/3-GiB cap, 500,000 deterministic 20-field records, direct-file pread projections, Zstandard codec family and seven alternating repeats. The engine patch and managed executable lifecycle differ from the [original run](../original-26.8.31.2/README.md); both remain distinct observations.

The full and selected-column ordered-output hashes match the original logical records. Inferred types and row count/range/sum pass. File sizes and traced read volumes match the original. All timed guest block-read bytes are zero; the positive/warm I/O control passes. Timings and RSS changed and are advisory, without a causal attribution or exact timing contract. [Full resource table](summary-table.md).

This pack contains the manifest, actual stored metadata/inferred types, correctness, all 28 raw samples, target-file read totals, I/O/schema controls, a validation summary and synthetic validator-test results. Full per-call traces and logs are generated under ignored `artifacts/` when the workflow runs. The committed trace references retain requested/returned bytes and unique-range totals; individual calls are omitted to keep the packs compact. `validation-summary.json` retains the validation status, check count, volume comparisons and advisory resource comparisons. No dataset binaries are committed.
