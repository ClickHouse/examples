# Live tests

Use a dedicated example schema and the runtime environment with TEST_OWNER_PASSWORD added only to a private test.env file. Stop the normal app first. Tests start the actual production server through scripts/start.mjs and use the real oRPC HTTP client.

Integration creates randomly numbered owned product/quote fixtures and deletes them in finally. It temporarily adds a constraint that applies only to its own quote ID to prove delete/insert replacement rollback; use this only on a dedicated schema. Browser tests create their own quote using the eight seeded products and remove it afterward. They do not reset either seeded quote. Screenshot paths default to /tmp/quote-catalogue-evidence or TEST_EVIDENCE_DIR.

Owner credentials remain outside browser code and normal runtime configuration. The real Kysely/pg probe supports valid CA and a deliberately wrong hostname; a wrong-CA control changes only PG_CA_CERT_PATH to an unrelated test CA. Probe failures are expected negative controls, not passing results.
