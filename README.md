# Journalwick

Journalwick is a standalone, multi-currency ledger and reconciliation product for finance operators, reviewers, integration engineers, and auditors. It makes accepted financial state exact, inspectable, and safe under retries, concurrency, and uncertain provider outcomes.

This repository is the application workspace selected by the user: `/home/musa/Documents/portfolio-projects/journalwick`. Its reviewed Day 03 build contract is maintained separately in `/home/musa/Documents/github-legend/Implementation/Day-03-Journalwick/`.

## Status

The project scope, architecture, and design are mapped. The first API liveness route, synthetic finance overview, checksum-checked migration commands, identity/organization/audit foundation, books/currencies/accounts/periods foundation, and operation/proposal identity schema are implemented. The baseline defines 68 blocking acceptance scenarios; all remain `not_run` until actual scoped evidence is recorded.

The Python package, application import, CLI identity, console production build, console lint, Python type/lint checks, and migration-runner unit checks have passed. The API liveness route responds directly and through the same-origin Vite proxy. The primary local database contains migrations `0001` through `0003`; no financial product command is implemented or accepted yet.

## Architecture and design

- [Product scope](docs/PRODUCT_SCOPE.md)
- [Capability map](docs/CAPABILITY_MAP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Console design system](docs/DESIGN_SYSTEM.md)
- [Implementation plan](tasks/plan.md)
- [Task tracker](tasks/todo.md)
- [Skill research and installation record](docs/SKILLS.md)
- [Resolved toolchain and host prerequisites](docs/TOOLCHAIN.md)
- [Current implementation status](docs/STATUS.md)
- [Source blueprint and workspace decision](docs/decisions/0001-workspace.md)

## Product boundaries

PostgreSQL is the financial authority. Journals are append-only, money is exact integer minor units tied to immutable currency definitions, and provider effects are handled through durable intent and verified observations. A timeout does not prove a transfer failed; unresolved exposure remains visible and reserved. The local fixture is synthetic and does not imply production readiness or financial certification.

## Planned local endpoints

The Day 03 baseline assigns the API to `127.0.0.1:8003`, the console to `http://localhost:5203`, and a dedicated PostgreSQL 18 development database to `127.0.0.1:55003`. The API and console use those reserved ports; PostgreSQL tools run through `scripts/dev-postgres`. Recheck ports and prerequisites before starting local services.

## Build status

See `tasks/todo.md` and [current implementation status](docs/STATUS.md). The local PostgreSQL 18.6 cluster is a trusted synthetic fixture. It does not stand in for the managed TLS/IAM release topology. Do not treat a synthetic provider fixture, successful frontend build, or documentation check as acceptance of the ledger or a release.

## Local database migrations

Use the dedicated migrator role for schema status and application. The runtime role in `.env.example` is intentionally not allowed to apply migrations.

```bash
JOURNALWICK_DATABASE_URL=postgresql://journalwick_migrator@127.0.0.1:55003/journalwick uv run journalwick db status
JOURNALWICK_DATABASE_URL=postgresql://journalwick_migrator@127.0.0.1:55003/journalwick uv run journalwick db migrate
```

Each migration is checksum-checked, applied under a dedicated advisory lock, and recorded in the same transaction as its schema changes. The command currently supports the local DSN profile; managed database IAM authentication remains unfinished.
