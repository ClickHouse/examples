# clickhousectl example validation

Validated **6 September 2026** in the OrbStack Linux ARM64 VM, in a separate worktree from the MCP refresh. Scope: the single maintained example under `ai/clickhousectl`, `agentic-sla-scaling`.

## Versions and results

| Component/check | Result |
|---|---|
| clickhousectl 0.4.2 | Installed CLI help checked for create/get/query/scale/prometheus/delete/auth/skills and local server commands. No Cloud requests made. |
| ClickHouse 26.8.2.7 | Isolated local server, native client and benchmark used for the SQL checks below. |
| Claude Code 2.1.263 | Installed in a temporary VM directory; version and help confirmed the model, tools, allowlist and strict MCP configuration flags. No live model conversation. |
| Bash 5.3.9 / ShellCheck 0.11.0 | `bash -n` and `shellcheck -x` passed for all five shell files. |
| Python 3.14.4 | All 14 offline script regression tests passed, including their malformed-response and configuration subcases. |
| Documentation | Relative README links resolve; both READMEs link signup/trial CTAs to `https://clickhouse.com/cloud`; Git whitespace checks pass. |

## Runtime evidence

- Loaded `schema.sql` with `--param_rows=100000`, then loaded it again: `sla_demo.events` still contained exactly **100,000 rows**.
- Executed the actual `dashboard.sql` and `analytics.sql` on that fixture. The dashboard returned one purchase aggregate; the analytics query returned 20 user groups.
- Flushed local query logs and executed the actual `sla.sql` through a configured single-replica `default` cluster: it returned one successful initial dashboard query, no errors, and a measured 3 ms p99. This small-fixture timing is not a Cloud performance claim.
- Ran the same aggregation over a temporary fixture containing 99 successful 50 ms requests and one 400 ms request, plus failures, a QueryStart, an internal request, an old completion and a different workload. It returned **100 completed, 2 failed, p99=400 ms**. The empty fixture returned `0, 0, 0`, which the shell regression verifies is rendered as `NO_DATA`, not `OK`.
- Verified `CLICKHOUSE_PASSWORD` authentication with a temporary password-protected SQL user through both `clickhouse client` and a one-iteration `clickhouse benchmark` request. The user was removed afterward.
- Offline script checks cover empty/undersampled windows, equality at the target, breach handoff, failed/malformed Query API responses, separately reported query failures, missing/failed metrics, replica labels, invalid settings/concurrency, shared SQL, credentials outside process arguments, frontend error propagation and agent exit-code propagation. Both the Cloud CLI and model executable are test doubles in these checks.

## Reproduce the checks

From `ai/clickhousectl/agentic-sla-scaling`:

```bash
python3 -m unittest discover -s tests -v
shellcheck -x ./*.sh
for script in ./*.sh; do bash -n "$script"; done
```

For the SQL regression, start a local server in a disposable directory, then pass its native port to the fixture check. This check creates only a session-scoped temporary table and does not need Cloud credentials or a `default` cluster:

```bash
# In a separate empty directory; retain it as the local server's project root.
clickhousectl local server start sla-check --version 26.8.2.7 --tcp-port 19000

# Back in ai/clickhousectl/agentic-sla-scaling:
python3 tests/check_snapshot_sql.py --port 19000

# Back in the server's project root, after testing:
clickhousectl local server stop sla-check
clickhousectl local server remove sla-check
```

The Cloud README contains the small schema/workload smoke check. Local equivalents use `--host 127.0.0.1 --port 19000` without `--secure`. To query actual local logs with `sla.sql`, additionally configure a local `system.query_log` and a `default` cluster pointing at that server; the temporary-table SQL regression above does not verify cluster discovery or log flushing.

## Not validated

- Creating, authenticating to, scaling, stopping or deleting a real Cloud service; Cloud tier/profile eligibility, Query API permissions or real Prometheus metric availability.
- The 200M-row load, the default horizontal/vertical concurrency, a repeatable Cloud SLA breach, or recovery after scaling.
- Claude's live evidence gathering, permission enforcement, model availability, scaling decision or post-change verification. The requested one-action/size limits are prompt instructions, not enforced infrastructure controls.
- macOS runtime behavior. All example execution stayed in the Linux VM.

No Cloud service or model-provider spend was incurred by this validation. The temporary local SQL server was stopped and removed after the checks. The existing MCP sandbox server was left running.

## Companion content

A bounded search of the available ClickHouse docs checkout and public ClickHouse site did not identify a direct article/docs companion for this example. No external content was edited. Before publishing a companion, align its setup, latency definition, optional scaling decision, workload caveats and stop/delete distinction with this README.

References checked: [CLI](https://github.com/ClickHouse/clickhousectl), [Claude CLI](https://code.claude.com/docs/en/cli-reference), [Cloud scaling](https://clickhouse.com/docs/manage/scaling), [query log](https://clickhouse.com/docs/operations/system-tables/query_log), and [Cloud trial](https://clickhouse.com/cloud).
