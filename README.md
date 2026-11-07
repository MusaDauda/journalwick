# Journalwick

Journalwick is a standalone, multi-currency ledger and reconciliation product for finance operators, reviewers, integration engineers, and auditors. It keeps financial records exact and inspectable across retries, concurrent requests, and uncertain provider outcomes.

## Status

Under active development. The API liveness endpoint, synthetic finance overview, migration runner, and initial identity, organization, account, period, operation, and proposal schemas are implemented. A draft journal migration includes a wallet-transfer posting path under local verification.

The primary development database contains migrations `0001` through `0003`. The console currently displays labeled synthetic data. Authentication, complete financial workflows, provider integrations, deployment, and recovery remain unfinished. The [acceptance checklist](docs/acceptance/gate.json) contains 68 scenarios; none has been marked passed.

## Stack

- Python 3.12, FastAPI, Pydantic, and Psycopg 3.
- PostgreSQL 18 with guarded functions and checksum-checked SQL migrations.
- React, TypeScript, Vite, React Router, TanStack Query, and Zod.
- pytest, Vitest, Playwright, Ruff, mypy, and Oxlint.

## Local development

Install Python dependencies with `uv sync --locked`. See [PostgreSQL setup](docs/LOCAL_POSTGRES.md) for the isolated development database and bootstrap commands.

Start the API from the repository root:

```bash
uv run fastapi dev --host 127.0.0.1 --port 8003
```

Start the console in a separate terminal:

```bash
cd apps/console
npm ci --ignore-scripts
npm run dev
```

The console runs at `http://localhost:5203` and proxies `/api` to `127.0.0.1:8003`. PostgreSQL uses `127.0.0.1:55003`. The liveness endpoint is `/api/v1/health/live`; readiness reports the incomplete schema until the remaining migrations are released.

## Architecture and design

- [Product scope](docs/PRODUCT_SCOPE.md)
- [Capability map](docs/CAPABILITY_MAP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Console design system](docs/DESIGN_SYSTEM.md)
- [Implementation plan](tasks/plan.md)
- [Task tracker](tasks/todo.md)
- [Resolved toolchain and host prerequisites](docs/TOOLCHAIN.md)
- [Current implementation status](docs/STATUS.md)

## Product boundaries

PostgreSQL is the financial authority. Journals are append-only, money is exact integer minor units tied to immutable currency definitions, and provider effects are handled through durable intent and verified observations. A timeout does not prove a transfer failed; unresolved exposure remains visible and reserved. The local fixture is synthetic and does not imply production readiness or financial certification.

## Local database migrations

Use the dedicated migrator role for schema status and application. The runtime role in `.env.example` is intentionally not allowed to apply migrations.

```bash
JOURNALWICK_DATABASE_URL=postgresql://journalwick_migrator@127.0.0.1:55003/journalwick uv run journalwick db status
JOURNALWICK_DATABASE_URL=postgresql://journalwick_migrator@127.0.0.1:55003/journalwick uv run journalwick db migrate
```

Each migration is checksum-checked, applied under a dedicated advisory lock, and recorded in the same transaction as its schema changes. The command currently supports the local DSN profile; managed database IAM authentication remains unfinished.
