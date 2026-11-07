# Journalwick implementation status

Updated 2026-11-07. This is a local progress note, not a substitute for the Day 03 acceptance gate.

## Current state

- M0 scope/design map is complete and committed.
- The Python 3.12 package, `journalwick` CLI identity, environment settings, FastAPI process liveness endpoint, and non-secret `.env.example` exist.
- The React/TypeScript console has a responsive finance overview with an explicitly synthetic dataset, exact string-based money formatting/entry parsing, accessible native dialogs, and search scoped to the selected demo book.
- A separate PostgreSQL 18.6 user-space cluster and `journalwick` database are provisioned under ignored `.local/`; the trusted development roles/schemas and `btree_gist` support extension are present. `scripts/fetch-postgres18`, `scripts/dev-postgres`, and `scripts/bootstrap-dev-db` capture the setup path.
- All 68 copied acceptance checks remain `not_run`.

## Observed local verification

The following were observed on this workspace and source state:

- `uv run journalwick --version` returned `journalwick 0.1.0`.
- Importing `journalwick.main:app` returned title `Journalwick API` and version `0.1.0`.
- `npm run build` passed with Vite 8.3.6 and TypeScript 5.9.3.
- `npm run lint` passed with Oxlint.
- `uv run ruff check src/journalwick` and `uv run mypy src/journalwick` passed.
- `GET /api/v1/health/live` returned `{"status":"alive","service":"journalwick"}` directly and through the Vite `/api` proxy.
- The local `journalwick` database reports PostgreSQL 18.6 and accepts connections on `127.0.0.1:55003`; role/schema bootstrap completed through the project script.
- A browser preview confirmed the overview, fixture label, exact amount display, book-scoped search, no-match state, and mobile navigation. Search matches exact synthetic references after a duplicate-key issue was corrected.

These checks cover scaffolding, trusted development role/schema bootstrap, and a synthetic console slice only. No pytest suite, application schema migration/function, passkey ceremony, journal command, provider sandbox, release image, cloud deployment, or recovery drill has passed.

## Local prerequisites still missing

Docker/Podman and Terraform are not installed on the inspected host. The filesystem has about 2.0 GB free. PostgreSQL was extracted from the signed PGDG repository into user space; the cluster uses loopback trust and is for synthetic development only.

## Recent commits

- `9733517` — `docs: define Journalwick scope and delivery map`
- `d0ee8ad` — `chore: lock the Python and console toolchains`
- `c3a41e9` — `feat: add API process liveness route`
- `4474916` — `feat: add synthetic ledger overview and scoped search`

The next implementation milestone is the migration runner and first reviewed schema migration; PostgreSQL setup scripts and status documentation are being finalized before that work.
