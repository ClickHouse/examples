# Verification record

Verified on **17 September 2026** against a dedicated ClickHouse Managed Postgres
service. Application source revision:
[`c4232ce0fa5dc15591b1ca035c78780b095f41a2`](https://github.com/ClickHouse/examples/commit/c4232ce0fa5dc15591b1ca035c78780b095f41a2).
This report was added afterward; no application or test changes were required
following the clean reproduction below.

## Environment

| Component | Observed version/configuration |
| --- | --- |
| Development environment | Fresh OrbStack isolated Ubuntu 24.04.5, Linux aarch64 |
| Isolation | File sharing/host integration disabled; network isolation enabled; no SSH-agent forwarding or host Docker socket |
| Bun / Bun.SQL | 1.4.2, runtime revision `744846f84` |
| Hono | 4.13.8 |
| TypeScript / Bun types | 7.0.2 / 1.4.2 |
| clickhousectl | 0.5.0 |
| psql | 16.15 |
| Managed Postgres | PostgreSQL 18.6, AWS eu-west-1, m6gd.large, no HA |
| Database connection | Direct endpoint, port 5432, database `postgres`, verified TLS 1.3 |

Cloud provisioning ran from the authenticated host. All Bun execution, dependency
installation, type checking, tests, and HTTP serving ran inside the isolated
Linux machine. No project dependencies were installed on macOS. The VM received
only the new database's task-specific credentials, not Cloud API credentials.
Resource IDs, endpoints, credentials, and deployment receipts are kept private.

## Clean setup and reproduction

The [README](../README.md) service creation, readiness, CA download, role setup,
ordered migration, grants, and seed steps were executed against the real service.
The administrator, migrator, and runtime logins were exercised separately.

After the first successful acceptance run, the API was stopped and
[`cleanup.sql`](../sql/cleanup.sql) was applied. Queries confirmed **zero example
schemas and zero example roles**. Bootstrap, migration, grants, and seed were
then applied again. Reapplying grants succeeded; reapplying seed inserted zero
rows and preserved existing quantities.

A `git archive` of the source revision above was extracted into a new directory
inside the VM, with no existing `node_modules`. Only the CA and explicit runtime
and test environment files were copied into its private deployment directory.
The following commands ran from that clean directory:

```sh
bun install --frozen-lockfile --ignore-scripts
bun run typecheck
bun run test:unit
bun --env-file=.deployment/app.env --env-file=.deployment/test.env run test:integration
bun audit
```

The two environment files separate runtime configuration from the privileged
fixture connection. The README's equivalent single test file contains both.

| Check | Result |
| --- | --- |
| Frozen dependency installation, scripts disabled | Passed |
| Type checking | Passed |
| Unit suite | 11 passed, 0 failed; 130 assertions |
| Managed Postgres integration and TLS suites | 17 passed, 0 failed; 373 assertions |
| Locked dependency audit | No known vulnerabilities reported; 26 packages checked |
| SQL cleanup and recreation | Passed; original seed quantities restored |
| Local documentation links and whitespace | Passed |

The audit is a dated registry result, not a guarantee about future advisories.
GitHub CI independently runs the frozen install, type check, and unit suite.
Managed-service tests require explicit credentials and are not silently skipped
or represented as CI coverage.

## Observed application behavior

The integration suite used two application instances with independent database
pools and the restricted runtime role:

- **32 competing requests, 9 units:** exactly 9 reservations committed; 23 requests
  received insufficient-inventory conflicts. Available stock was zero and active
  reservation quantities totaled 9.
- **24 concurrent retries:** one reservation and one idempotency record committed;
  all responses had identical bytes, and 23 carried the replay header.
- Different inputs under the same successful key conflicted. Different clients
  could reuse a key independently but could not read or release each other's
  reservation.
- **20 concurrent releases:** stock returned exactly once and every release
  returned the same released state. Replaying the original POST preserved its
  original creation response.
- A rejected reservation left no key. Retrying it after stock was released could
  succeed.
- Real database constraints injected failures after the stock decrement during
  creation and after the stock increment during release. Both transactions fully
  rolled back; removing the test constraint allowed the retry to succeed.
- Runtime permissions prohibited administrative operations, fixture insertion,
  deletion, and truncation. Missing authentication, invalid payloads, and oversized
  bodies were rejected. Test fixtures and temporary constraints were removed.

The actual `src/server.ts` entry point was also started and exercised with `curl`:
unauthenticated inventory returned 401; creation and exact replay returned 201;
a second client's lookup returned 404; changed inputs returned 409; release and
repeat release returned 200. Mug inventory followed **10 → 8 → 10**. SIGTERM
stopped the server with exit code 0. After restart, POST still replayed the
original response while GET returned the current released state.

## TLS findings and verification limits

The downloaded provider CA bundle contained two roots with the same subject.
`psql` and OpenSSL verified the full bundle, but Bun 1.4.2 returned
`CERT_SIGNATURE_FAILURE`. The connection factory now tries the full bundle and,
only for that failure, verifies individual supplied anchors. All attempts retain
certificate and hostname verification; no fallback disables TLS checks. The
clean tests used the unmodified downloaded bundle.

An unrelated valid CA was rejected with a certificate verification error. The
wrong-hostname check reached the same numeric endpoint while expecting its IP
identity. An independent OpenSSL connection to that numeric endpoint first
verified its actual DNS identity, and a fresh Bun connection with the proper DNS
name succeeded afterward. The negative Bun probe still failed with ambient
`PGSSLMODE=verify-ca`, confirming the application's explicit mode took precedence.

Bun reported an empty `Error` with `errno: 0` for that hostname probe, rather than
a specific hostname-mismatch code. The positive controls support the rejection
result, but the runtime error itself does not identify its exact cause. Retest
this behavior when upgrading Bun or changing the provider's certificate chain.
A fallback-selected CA remains selected until process restart; refresh the bundle
and restart after a CA rotation.

Cloud service deletion was **not executed**: the dedicated service was retained
for further example work. Schema/role cleanup was verified separately. No public
hosting deployment, load-capacity benchmark, automatic reservation expiry, or
external article publication is claimed. The paired [article](article.md) is
included with the runnable code; its Engineering Resources publication is a
separate editorial step.
