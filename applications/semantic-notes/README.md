# Semantic notes

A trusted local notebook using FastAPI, SQLModel, Sentence Transformers and pgvector on **ClickHouse Managed Postgres**. Add short titled notes, edit them with an observed revision, and retrieve excerpts by meaning. The application returns stored notes and cosine distances; it does not generate answers.

The CPU model is `sentence-transformers/all-MiniLM-L6-v2`, fixed at public revision `1110a243fdf4706b3f48f1d95db1a4f5529b4d41`. Only allowlisted model files and safetensors weights are downloaded; remote custom code is disabled. After the explicit download, application startup is offline. A full collection specification fixes model ID, revision, 384 dimensions, float32 values, normalized embeddings, 256 tokens including special tokens, and document formatting (`title + two newlines + body`). Source metadata and database metadata must match at startup.

## Behavior and limits

- At most 100 notes, enforced by a collection row lock and database quota trigger. Listing shows 12 notes per page.
- Title: 1–120 characters. Body: 1–4,096 characters. Both together must fit the actual tokenizer's 256-token limit, including special tokens. Inputs are rejected before encoding rather than silently truncated. Controls and lone Unicode surrogates are rejected; body permits newline/tab.
- Search text: 1–512 characters and the same tokenizer bound. Results: 1–10. Optional literal title substring: at most 80 characters. `%` and `_` are escaped rather than interpreted as filter wildcards.
- Exact cosine search over the small collection, ordered by distance then UUID. There is no approximate index or measured recall/latency claim.
- Two admitted embedding jobs per process; shared model access is serialized because `encode()` changes model state. Excess jobs receive 429. Cancellation keeps the permit until the actual worker completes. CPU inference runs outside the event loop and before database acquisition; blocking database work also runs in a thread.
- Edit saves text, vector and incremented revision in one transaction. A stale revision receives 409 and the form keeps submitted text until explicit reload. Slow older embedding work cannot overwrite a newer edit.
- Requests are bounded to 16 KiB including streamed bodies. Unsafe browser/API requests require the fixed `Origin: http://127.0.0.1:8000`. Numeric form fields have digit limits before conversion; duplicate and unknown fields are rejected.

This is a single trusted operator's loopback workbench, without application authentication or user isolation. Bind to `127.0.0.1:8000`, use one Uvicorn worker, and open that exact address. Do not expose it through a public proxy. The shared runtime database role is trusted: PostgreSQL enforces shape, nonzero vectors, collection metadata and quota, but cannot establish that a direct writer used the matching text/model or observed revision.

## 1. Native Linux CPU setup

Tested on Ubuntu 24.04 ARM64 with Python 3.12.3. Install Python virtual-environment support and the PostgreSQL client using your Linux package manager. Run commands from this application directory:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pip check
export MODEL_CACHE_DIR="$PWD/.local/model-cache"
.venv/bin/python -m scripts.model_preflight --download
```

The lock pins the full runtime dependency graph and `torch==2.14.1+cpu` from the official CPU wheel index. `requirements.in` records direct dependencies; `requirements.txt` records the resolved versions. The preflight downloads the pinned public model, runs real CPU inference, checks finite/nonzero 384-dimensional values, compares related/unrelated synthetic texts, and proves 256 tokens accepted / 257 rejected. Complete this before allocating a billable service. Keep the cache: application startup does not download missing weights.

## 2. Create a dedicated Cloud service

Install/configure [clickhousectl](https://github.com/ClickHouse/clickhousectl) with your Cloud API credentials. Confirm supported region/size in current [Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/). The tested fixture used `c6gd.large`, AWS `us-east-1`, PostgreSQL 18 and no HA. Service creation is billable; there is no free-running-service assumption.

```bash
mkdir -p .private
chmod 700 .private
clickhousectl cloud postgres create \
  --name semantic-notes-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none \
  --tag purpose=semantic-notes --org-id YOUR_ORG_ID \
  --json > .private/create.json
chmod 600 .private/create.json
```

The creation receipt contains credentials once. Keep it private. Read its `id`, then repeat the following status command until `state` is `running`; do not start migrations while it is `creating`:

```bash
clickhousectl cloud postgres get YOUR_SERVICE_ID --org-id YOUR_ORG_ID --json
clickhousectl cloud postgres certs get YOUR_SERVICE_ID \
  --org-id YOUR_ORG_ID --output .private/ca.pem
```

Create four separate private environment files, using the receipt without printing credentials:

```bash
python3 - <<'PY'
import json, secrets, shlex
from pathlib import Path
p = Path('.private')
r = json.loads((p / 'create.json').read_text())
base = {'PGHOST': r['hostname'], 'PGPORT': '5432', 'PGDATABASE': 'postgres',
        'PGSSLROOTCERT': str((p / 'ca.pem').resolve()), 'PGSSLMODE': 'verify-full'}
owner_password, app_password = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
files = {
    'admin.env': {**base, 'PGUSER': r['username'], 'PGPASSWORD': r['password'],
                  'PG_MIGRATION_PASSWORD': owner_password, 'PG_APP_PASSWORD': app_password},
    'migration.env': {**base, 'PGUSER': 'semantic_owner', 'PGPASSWORD': owner_password},
    'runtime.env': {**base, 'PGUSER': 'semantic_app', 'PGPASSWORD': app_password,
                    'MODEL_CACHE_DIR': str(Path('.local/model-cache').resolve()),
                    'HF_HUB_OFFLINE': '1', 'TOKENIZERS_PARALLELISM': 'false',
                    'APP_ORIGIN': 'http://127.0.0.1:8000'},
    'test.env': {'TEST_OWNER_USER': 'semantic_owner', 'TEST_OWNER_PASSWORD': owner_password},
}
for name, values in files.items():
    f = p / name
    f.write_text(''.join(k + '=' + shlex.quote(v) + '\n' for k, v in values.items()))
    f.chmod(0o600)
PY
```

`.env.example` lists the runtime fields. The application does not load environment files implicitly. `set -a` below exports values to child processes.

## 3. Administrator bootstrap and owner migrations

Use a dedicated service. Bootstrap creates two login roles, installs `vector`, creates the owned schema and removes public schema/database creation privileges. It is intentionally a one-time script, not an idempotent role reset.

```bash
# Setup shell only; close it before starting the application.
set -a
source .private/admin.env
set +a
psql -X -v ON_ERROR_STOP=1 -f scripts/bootstrap.sql

set -a
source .private/migration.env
set +a
.venv/bin/alembic upgrade head
psql -X -v ON_ERROR_STOP=1 -f scripts/grants.sql
```

The runtime role receives schema usage, reads, note inserts and selected note updates. It receives `UPDATE(id)` on the fixed singleton collection solely to authorize `FOR UPDATE`; its CHECK permits only ID 1. It cannot modify model metadata, delete notes, install extensions or alter schema. The SQLAlchemy pool registers pgvector types on every actual psycopg connection and requires `sslmode=verify-full` with the Cloud CA.

Migration lifecycle verification on an empty test notebook:

```bash
# Owner shell; downgrade deletes all notes.
.venv/bin/alembic downgrade base
.venv/bin/alembic upgrade head
psql -X -v ON_ERROR_STOP=1 -f scripts/grants.sql
```

## 4. Run and use the notebook

Open a **fresh shell** so administrator/test passwords are absent from the application process:

```bash
set -a
source .private/runtime.env
set +a
.venv/bin/python -m scripts.seed     # optional, run once: adds three actually embedded notes
.venv/bin/python -m uvicorn semantic_notes.app:app --host 127.0.0.1 --port 8000
```

The seed is additive: repeating it adds three more notes.

Visit [the local notebook](http://127.0.0.1:8000). Add a note, search for a paraphrase, edit the note, then reload. Opening the same note in two tabs demonstrates the explicit stale-save conflict. API documentation is at `/docs`; unsafe API clients must send the fixed Origin header:

```bash
curl --fail-with-body http://127.0.0.1:8000/api/search \
  -H 'Origin: http://127.0.0.1:8000' -H 'Content-Type: application/json' \
  -d '{"q":"A journal helps me remember the books I read","k":3}'
```

Embedding happens before each mutation transaction. If inference fails, no note is saved. If the database transaction fails, text/vector/revision all roll back. A database error produces a static 503 response without another rendering query. There is no upload, arbitrary URL ingestion, model training or generated response.

## 5. Verification

Install helper tools natively; Python Playwright 1.56.0 is pinned:

```bash
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/pip check
.venv/bin/ruff check semantic_notes scripts tests migrations
.venv/bin/ruff format --check semantic_notes scripts tests migrations
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python -m playwright install --with-deps chromium
```

Five local tests cover strict input/revision/vector/model-format boundaries and actual thread cancellation capacity. CI runs these and formatting without Cloud credentials or a model download.

Run Cloud acceptance **before seeding**, against a fresh empty schema with the real runtime server running. In a separate test shell export `.private/runtime.env` and `.private/test.env`, then:

```bash
.venv/bin/python -m tests.cloud_acceptance
EVIDENCE_DIR=/tmp/semantic-notes-evidence \
  .venv/bin/python -m tests.browser_acceptance
```

The Cloud helper creates three real-model fixtures and has 11 cases: independent float64 cosine comparison, revision/competing HTTP row locks, delayed older CPU work, owner-induced deferred commit failure, Origin/token/body/form/Unicode bounds, role/vector/spec checks, database quota, CA/hostname negatives, stable ties and paging. Quota/paging controls reuse actual model vectors and make no semantic-quality claim. Tests mutate their dedicated notebook; they are not production probes. The browser helper adds/edits a real note, checks two-tab stale behavior, searches, and saves desktop/mobile evidence outside the repository.

On 2 October 2026: a clean locked install, five units, ten full Cloud cases plus the final added input-shape case, browser workflow, fresh migration up/down/up and cached-model process replacement passed. Tested FastAPI 0.142.2, SQLModel 0.0.47, SQLAlchemy 2.0.54, psycopg 3.3.6, pgvector-python 0.5.0, Sentence Transformers 6.1.0, Transformers 5.18.0, PyTorch 2.14.1+cpu, PostgreSQL 18.6 and pgvector extension 0.8.6. The reading fixtures ranked ahead of the unrelated garden fixture; these observations establish fixture behavior, not general retrieval accuracy.

For restart verification, stop the original Uvicorn process, wait for it to exit and confirm port 8000 has no listener before starting a replacement from a fresh runtime-only shell. Keep the same model cache and database. Compare saved text, revisions, vector bytes and exact-search results before/after. Cold download/preflight and cached startup are separate observations, not speed benchmarks.

## 6. Cleanup

Stop the application. Delete only the dedicated service you created and verify its ID is absent from `list`:

```bash
clickhousectl cloud postgres delete YOUR_SERVICE_ID --org-id YOUR_ORG_ID
clickhousectl cloud postgres list --org-id YOUR_ORG_ID --json
```

If retaining the service but removing this example, restore administrator credentials from the saved receipt in a setup shell first (`source .private/admin.env` with `set -a`), then drop the example schema/roles after stopping all app/test connections. Do not run role cleanup with runtime credentials. Preserve source/evidence locally; keep receipts, CA files and model cache out of Git.

Sources: [fixed model](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/tree/1110a243fdf4706b3f48f1d95db1a4f5529b4d41), [pgvector Python integration](https://github.com/pgvector/pgvector-python), [pgvector distance operators](https://github.com/pgvector/pgvector), [Cloud extensions](https://clickhouse.com/docs/products/managed-postgres/extensions).
