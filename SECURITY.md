# Security policy

## Scope and intended use

This repository contains **illustrative example code** that accompanies ClickHouse
blog posts, talks, and documentation. The examples are meant to be **cloned and run
locally** by developers evaluating ClickHouse. They are **not** hosted services, and
nothing here is deployed to a live, internet-facing environment by ClickHouse.

Because of this, the practical risk of most dependency vulnerabilities (CVEs) reported
against these examples is low: there is no long-running, internet-exposed service for an
attacker to reach. The examples are nonetheless useful references, so we keep them
available rather than deleting them.

**Treat every example as a starting point, not production-ready code.** Before using any
of it in a real deployment, audit and update its dependencies and review it for your own
security requirements.

## How we handle Dependabot alerts

We triage dependency alerts by how actively an example is maintained:

- **Actively maintained examples** receive security patches. We prefer minimal,
  in-range (patch/minor) updates that resolve the advisory without changing behaviour.
  Major-version bumps are applied only after the example has been smoke-tested.
- **Unmaintained examples** (no meaningful update in ~18 months) are marked with an
  "Unmaintained" notice in their README and their alerts are dismissed (via Dependabot
  auto-triage rules scoped to the example's path). The code is preserved as a
  point-in-time reference; run it at your own risk after updating dependencies.

We do **not** blanket-merge Dependabot pull requests, as that can both break working
examples and introduce supply-chain risk. Updates are reviewed before merging.

## Reporting a vulnerability

This repository holds example code only. To report a security issue in **ClickHouse
itself**, please follow the process at <https://github.com/ClickHouse/ClickHouse/security/policy>
(security@clickhouse.com). For an issue specific to an example here, open a GitHub issue.
