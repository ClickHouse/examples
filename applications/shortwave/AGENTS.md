# Agent instructions

## Project context

- Shortwave is a link-shortener example; see the [deployment and release checklist](docs/v1-readiness.md). Cloudflare Workers is the implemented host. Keep local development in the isolated VM.
- Start with [README.md](README.md); read the relevant brief, architecture, or setup document linked there. Keep proposals distinct from settled decisions.
- Use TanStack, Click UI, and Clerk. Deploy both databases and ClickPipes in ClickHouse Cloud; use `clickhousectl` for Cloud provisioning and orchestration. Use Wrangler for Cloudflare resources. `pg_clickhouse` and ClickStack remain proposals.

## Implementation and deployment contract

- Keep deployer hostnames, resource IDs, personal paths, and credentials out of the public example. Generate configuration from explicit inputs; keep `.deployment`, `.private`, `.secrets`, environment files and credential-bearing logs private.
- Document infrastructure as explicit `clickhousectl` and Wrangler commands in README and the hosting guide. Keep database setup in SQL files passed to the CLI; do not add JavaScript provisioning wrappers. Review inputs before creation and verify the built Worker config matches the recorded account, bindings and hostnames before deployment.
- Postgres owns authorization and redirects. ClickPipes owns `cdc_links`; never apply the local metadata fixture to Cloud. Preserve CDC version/delete handling and event-ID deduplication across delivery retries.
- Separate runtime, migration, and management credentials. Preserve TLS verification and account isolation. Reuse recorded resources on setup retries; reconcile ambiguous outcomes before retrying, and target cleanup by recorded IDs. Never delete a receipt to force recreation.
- For assessments, deliver findings and acceptance criteria. For implementation requests, finish authorized work and verification; follow the user's scope over conflicting skill advice and identify concrete blockers.
- Run relevant checks in the VM: `npm test`, `npm run typecheck`, and `npm run build:workers`. Live integration/browser checks require their documented Cloud fixtures. Report passed, skipped, and unverified checks separately; publication requires the fresh-deployment checklist.

## Development sandbox

- This VM workflow is for maintainer/agent development. Public deployment instructions assume CLI tools on the reader's laptop; see [maintainer environment](docs/maintainer-environment.md) for our setup.

- Before installing dependencies or running application code, create a dedicated OrbStack Linux VM using the CLI. Reuse `link-shortener-dev` only after checking its isolation settings with `orb info`.

  ```sh
  orb list
  orb create --isolated --isolate-network ubuntu:noble link-shortener-dev
  orb info link-shortener-dev
  orb -m link-shortener-dev -w /home sh -lc 'mkdir -p "$HOME/link-shortener"'
  orb -m link-shortener-dev -w /home sh -lc 'cd "$HOME/link-shortener" && <command>'
  ```

- Create only if absent; replace `<command>` with the intended command. Verify flags with installed CLI help if needed; do not silently fall back to an unisolated machine.
- Copy source into the VM's own filesystem with `scripts/vm.sh push`. Use `scripts/install-tools.sh` inside Linux for the pinned tools; run dependency installs, development servers, builds and tests there. Keep caches, `node_modules` and build output inside the VM; databases remain in ClickHouse Cloud.
- Keep host mounts, SSH-agent forwarding, host command execution, and host Docker sockets disabled. Transfer only project files and explicitly needed credentials; copy reviewed source changes back without generated files or secrets.
- Host-side document/source editing, read-only inspection, and OrbStack management are fine. Do not install project dependencies on macOS. Documentation-only tasks do not require starting a VM.

## Keep changes reviewable

- UI copy: use plain task names. Do not add promotional subtitles, taglines, or routine explanatory captions unless the user requests them. Helper text must resolve a concrete ambiguity or explain an actionable state; audit new visible strings before handover.
- Update the relevant documentation when decisions change. Link to authoritative sources for platform claims; mark untested commands and unresolved assumptions.
- For code changes, run appropriate checks inside the VM; report what passed and what remains unverified. For documentation, check links and consistency. See README for build, typecheck, and test commands.
- Keep this file short and operational. Put architecture, setup walkthroughs, and task history in `docs/`, not here.
