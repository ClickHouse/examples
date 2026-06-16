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
