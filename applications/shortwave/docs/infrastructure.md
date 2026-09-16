# Infrastructure and private state

Each deployment owns one ClickHouse Cloud analytics service, one ClickHouse
Managed Postgres service, a Postgres CDC ClickPipe, a Cloudflare Worker with a
scheduled handler, a Hyperdrive configuration, and its origin CA registration.
Clerk and the DNS zone may be shared with other deployments and are not deleted
by database cleanup.

Use [the explicit CLI walkthrough](../README.md#deploy-your-own-instance) to create
resources and apply the checked-in SQL files. Store actual
organization/account/resource IDs, hostnames, service responses, and credentials
only in the ignored .deployment directory. Never copy private state into public
source, screenshots, or release evidence.

Cloud management credentials provision services. The Postgres migration login
owns application tables; ClickHouse schema changes use the CLI's service Query
API credential. Runtime database credentials have only the permissions the app needs.
Workers receives runtime secrets and the Hyperdrive binding; it does not need
Cloud management credentials. Postgres connections verify the service CA.
Hyperdrive query caching is disabled to preserve current redirects and ownership.

ClickHouse ingress must allow the deployment environment and hosted runtime.
Shared Cloudflare ranges are broader than a single Worker identity; TLS and
restricted database credentials remain required. Inspect the actual policy and
preserve unrelated entries when adding approved access.

The [operations guide](operations.md) covers status, recovery, rotation, and
cleanup. Local shutdown does not remove billable Cloud resources. The examples
repository contains no inventory of a particular operator's deployment.
