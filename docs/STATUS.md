# Journalwick implementation status

Updated 2026-11-07. This is a local progress note, not a substitute for the Day 03 acceptance gate.

## Current state

- M0 scope/design map is complete and committed.
- The Python 3.12 package, `journalwick` CLI identity, environment settings, FastAPI process liveness endpoint, and non-secret `.env.example` exist.
- The React/TypeScript console has a responsive finance overview with an explicitly synthetic dataset, exact string-based money formatting/entry parsing, accessible native dialogs, and search scoped to the selected demo book.
- A separate PostgreSQL 18.6 user-space cluster and `journalwick` database are provisioned under ignored `.local/`; the trusted development roles/schemas and `btree_gist` support extension are present. `scripts/fetch-postgres18`, `scripts/dev-postgres`, and `scripts/bootstrap-dev-db` capture the setup path.
- `journalwick db status` and `journalwick db migrate` use a dedicated migrator identity, advisory lock, contiguous migration series, recorded SHA-256 checksums, and one transaction per migration. Migration `0001_identity_organization_and_audit` creates the initial identity, organization, enrollment, operating-state, and audit foundations.
- Migration `0002_books_currencies_accounts_and_periods` defines books, per-book financial/evidence state, curated versioned currency definitions, exact template/currency eligibility, scoped accounts and roles, setup approvals, lifecycle restrictions, and non-overlapping periods. It is committed as `9b25ae3` and applied to the primary local database.
- The primary local `journalwick` database has `0001` applied from source revision `424c697035caedde3a8ca5643dfa89366c1d2179` and `0002` applied from source revision `9b25ae3ed821880f5dea975291968ea46bf611ce`. The six later baseline migrations are not authored yet.
- All 68 copied acceptance checks remain `not_run`.

## Observed local verification

The following were observed on this workspace and source state:

- `uv run journalwick --version` returned `journalwick 0.1.0`.
- Importing `journalwick.main:app` returned title `Journalwick API` and version `0.1.0`.
- `npm run build` passed with Vite 8.3.6 and TypeScript 5.9.3.
- `npm run lint` passed with Oxlint.
- `uv run ruff check src/journalwick tests` and `uv run mypy src/journalwick` passed.
- `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run pytest tests/test_migration_runner.py` passed all 6 focused runner tests. This host's ROS-provided pytest plugin fails to load because its `lark` dependency is absent, so test execution disables unrelated host plugin auto-loading.
- `GET /api/v1/health/live` returned `{"status":"alive","service":"journalwick"}` directly and through the Vite `/api` proxy.
- The local `journalwick` database reports PostgreSQL 18.6 and accepts connections on `127.0.0.1:55003`; role/schema bootstrap completed through the project script.
- A browser preview confirmed the overview, fixture label, exact amount display, book-scoped search, no-match state, and mobile navigation. Search matches exact synthetic references after a duplicate-key issue was corrected.
- In an isolated PostgreSQL 18.6 verification database, migrations `0001` and `0002` applied and appeared in `db status`. Targeted checks refused cross-organization role/account/template bindings, mismatched account/template accounting identity, an ineligible template currency, active meaning changes, long-lived setup approvals, duplicate active restriction sources, and concurrent overlapping periods. Runtime table writes and schema `CREATE` were denied. A changed applied checksum was refused; invalid migration SQL rolled back its preceding DDL and did not record success; the runtime role was refused migration commands; and a service principal could not be linked as a human user. The verification database is temporary local evidence only.
- The primary database reports `0001` and `0002` at their recorded source revisions above. API readiness returns 503 `SCHEMA_INCOMPLETE` with the database available because later baseline migrations and kernel functions are not present yet.

These checks cover scaffolding, the first two schema foundations, migration authority, and a synthetic console slice only. No passkey ceremony, journal command, provider sandbox, release image, cloud deployment, or recovery drill has passed.

## Local prerequisites still missing

Docker/Podman and Terraform are not installed on the inspected host. The filesystem has about 2.0 GB free. PostgreSQL was extracted from the signed PGDG repository into user space; the cluster uses loopback trust and is for synthetic development only.

## Recent commits

- `9733517` — `docs: define Journalwick scope and delivery map`
- `d0ee8ad` — `chore: lock the Python and console toolchains`
- `c3a41e9` — `feat: add API process liveness route`
- `4474916` — `feat: add synthetic ledger overview and scoped search`
- `a56300d` — `chore: add isolated PostgreSQL 18 development runtime`
- `424c697` — `feat: add migration runner and identity foundations`
- `118714e` — `docs: record identity migration verification`
- `9b25ae3` — `feat: add scoped book and account setup schema`

The rootless database setup, role/schema bootstrap, bounded API pool/readiness checks, migration runner, and first two schema migrations are committed and applied locally. The next schema milestone is operation identity, receipts, proposals, and approvals in migration `0003`.
