# Journalwick implementation status

Updated 2026-11-08. This is a local progress note, not a substitute for the Day 03 acceptance gate.

## Current state

- M0 scope/design map is complete and committed.
- The Python 3.12 package, `journalwick` CLI identity, environment settings, FastAPI process liveness endpoint, and non-secret `.env.example` exist.
- The React/TypeScript console has a responsive finance overview with an explicitly synthetic dataset, exact string-based money formatting/entry parsing, accessible native dialogs, and search scoped to the selected demo book.
- A separate PostgreSQL 18.6 user-space cluster and `journalwick` database are provisioned under ignored `.local/`; the trusted development roles/schemas plus `btree_gist` and `pgcrypto` support extensions are present. `scripts/fetch-postgres18`, `scripts/dev-postgres`, and `scripts/bootstrap-dev-db` capture the setup path.
- `journalwick db status` and `journalwick db migrate` use a dedicated migrator identity, advisory lock, contiguous migration series, recorded SHA-256 checksums, and one transaction per migration. Migration `0001_identity_organization_and_audit` creates the initial identity, organization, enrollment, operating-state, and audit foundations.
- Migration `0002_books_currencies_accounts_and_periods` defines books, per-book financial/evidence state, curated versioned currency definitions, exact template/currency eligibility, scoped accounts and roles, setup approvals, lifecycle restrictions, and non-overlapping periods. It is committed as `9b25ae3` and applied to the primary local database.
- Migration `0003_operations_proposals_and_approvals` defines business/step identities, command receipts, economic recognition uniqueness, posting templates, immutable proposal versions, and scoped reviewer approvals. It is committed as `76093b3` and applied to the primary database.
- The primary local `journalwick` database has `0001`–`0003` applied from source revisions `424c697035caedde3a8ca5643dfa89366c1d2179`, `9b25ae3ed821880f5dea975291968ea46bf611ce`, and `76093b3e5f3883ca8e32b3972a958b28d2d90326`. Migration `0004` is in active development and is not released; migrations `0005`–`0008` are not authored yet.
- The migration command applies only the explicitly released prefix and reports an authored unreleased file as `draft`.
- Draft migration `0004` contains append-only journal/posting tables, correction records, database-side hashes, and a guarded manual wallet-transfer path. It supports only the documented two-line wallet-transfer template subset and has not been released or applied to the primary database.
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
- In an isolated PostgreSQL 18.6 verification database, migrations `0001`–`0003` applied and appeared in `db status`. Targeted checks refused cross-organization role/account/template bindings, mismatched account/template accounting identity, an ineligible template currency, active meaning changes, long-lived setup approvals, duplicate active restriction sources, and concurrent overlapping periods. Operations/proposals checks confirmed request-key and economic-fact uniqueness, exact proposal hash binding, immutable approved payloads, and one-way receipt/approval transitions. Runtime table writes and schema `CREATE` were denied. A changed applied checksum was refused; invalid migration SQL rolled back its preceding DDL and did not record success; the runtime role was refused migration commands; and a service principal could not be linked as a human user. The verification database is temporary local evidence only.
- The primary database reports `0001`–`0003` at their recorded source revisions above. API readiness returns 503 `SCHEMA_INCOMPLETE` with the database available because later baseline migrations and kernel functions are not present yet.
- On a newly created isolated local database, `db migrate` applied only released migrations `0001`–`0003` and `db status` reported the authored `0004` as `draft`.
- A focused PostgreSQL integration suite exercised the draft wallet-transfer path with synthetic sessions and opening data. It checked balanced posting, accepted retry, stale membership, cross-book reviewer roles, session revocation, mismatched step-up/step identity, template mismatch, insufficient funds, and missing account state. A separate two-connection check held the book lock until both spends were waiting: one 7,000-unit spend succeeded and the other was refused against a 10,000-unit balance.
- `uv run ruff check src/journalwick tests scripts/provision_verification_db.py`, `uv run mypy src/journalwick`, and the focused migration/journal suite passed. The suite reported 20 passing checks on the selected local verification databases.

These checks cover scaffolding, the first three released schema foundations, a draft kernel slice, migration authority, and a synthetic console slice only. No full product journey, actual passkey ceremony, provider sandbox, release image, cloud deployment, or recovery drill has passed.

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
- `0a68ff8` — `docs: record book and account schema verification`
- `76093b3` — `feat: add operation and proposal identity schema`
- `caf4db5` — `chore: add trusted PostgreSQL hash support`
- `2b2349e` — `fix: keep draft migrations out of the release path`

The rootless database setup, role/schema bootstrap, bounded API pool/readiness checks, migration runner, and first three schema migrations are committed and applied locally. The next schema milestone is to finish and release migration `0004`, including its remaining template grammar, command families, cross-adapter canonicalization, and acceptance evidence.
