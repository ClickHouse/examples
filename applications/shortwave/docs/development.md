# Development and checks

Both databases and ClickPipes run in ClickHouse Cloud. A local web server is for
editing and testing the application against those Cloud resources.

Install the [tools in README](../README.md#1-install-tools-clone-the-repo-and-sign-in)
and run `npm ci` in your checkout. The commands below run from the project root.

## Run the application

Follow [Cloud setup](../README.md#deploy-your-own-instance) first. Copy its runtime values
into your local application environment, then add Clerk development
keys and the local app origin using [.env.example](../.env.example) as a reference.
Do not add Cloud API keys or migration passwords to the runtime environment.

```sh
umask 077
cp .deployment/runtime.env .env
# Edit .env privately: add Clerk development keys and APP_URL=http://localhost:4317.
npm run dev
```

Open http://localhost:4317. Use Clerk development keys for local work, browser
automation and hosted evaluation. See [Clerk setup](hosting.md#1-prepare-a-domain-and-authentication)
for production launch configuration.

If this Cloud data stack has no deployed scheduler, deliver its durable events
from a second terminal:

```sh
npm run events:flush -- --watch
```

Do not leave this local flusher running when testing Workers cron or fixture
outbox assertions. Hosted operation must work without the development machine.

## Checks

```sh
npm test
npm run types:workers
npm run typecheck
npm run build:workers
npx wrangler deploy --dry-run
npm audit
```

The ordinary unit run skips live integration suites. It covers URL/domain
validation, previews, request isolation, CDC fixture locking, and cleanup scope.
CI does not need Cloud or Clerk credentials.

Live tests require isolated Cloud test resources and configured .env values:

```sh
npm run test:integration
npx playwright install --with-deps chromium
npm run dev
# In another terminal:
npm run test:browser
```

Browser tests use Clerk development keys, official test helpers, and reserved
`+clerk_test` addresses. They create synthetic users and clean their Postgres
fixtures; raw ClickHouse test events expire under the normal TTL. Traces and
videos are disabled to avoid retaining authentication tokens. Keep generated
screenshots private until their content has been reviewed.

Integration tests must not race a global outbox delivery process. Use a separate
Cloud test deployment, or coordinate a pause of every flusher including Workers
cron. Report skipped checks separately from passing checks.

The default `npm run build` and `npm start` use the Node adapter for local
validation. The release hosting path is Workers. Review changes to package-lock.json,
src/routeTree.gen.ts and worker-configuration.d.ts before committing generated files.

Apply schema changes with the explicit `clickhousectl` file commands in README.
See [migration order and upgrade records](../migrations/README.md); there is no
JavaScript migration runner or automatic migration ledger.

## Browser download troubleshooting

Interactive hosted acceptance can use your usual browser. Record whether a check
was a manual journey or an automated Playwright run.

Use `npx playwright install --with-deps chromium` to install the browser and
system dependencies. If the download times out, consult
[Playwright browser installation](https://playwright.dev/docs/browsers) for proxy,
certificate and timeout settings. Inspect the artifacts required by the installed
Playwright version with:

```sh
npx playwright install --dry-run chromium
```

If you install that matching browser separately, set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` to its executable path before running
`npm run test:browser`. This override is supported by the
[Playwright configuration](../playwright.config.ts). Keep downloaded binaries and
caches out of version control.
