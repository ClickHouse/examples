Run tests inside the Linux VM against a dedicated asset-audit database. The API must be stopped: the suites start the real production API and need its configured port. Supply runtime variables from .env.example plus TEST_OWNER_PASSWORD in a separate private test environment. No test is silently skipped when credentials are absent.

The integration test creates a uniquely numbered sheet and removes it afterward. It verifies restart persistence, revision races, invalid quantities, incomplete/duplicate rows, origin/host checks, immutable finalization and runtime permissions. To prove transaction rollback after a late row error, it temporarily adds one fixture-scoped check constraint; it removes that constraint in finally. Do not run it against a shared production schema.

The browser test uses Chromium installed inside the VM. It edits real AG Grid cells, checks invalid-entry feedback, saves/reloads, filters/sorts, demonstrates a two-tab conflict, and finalizes through PrimeNG's dialog. Evidence screenshots go to TEST_EVIDENCE_DIR (default /tmp/asset-audit-browser).

The db:probe Ace command uses the application's Lucid configuration. Successful query, wrong CA and wrong servername runs are deliberate positive/negative controls; preserve each result separately.
