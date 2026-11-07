# Local PostgreSQL development fixture

This workspace uses a user-space PostgreSQL 18.6 installation because the host does not provide Docker or passwordless system package installation. The server is isolated to this project, binds only to `127.0.0.1:55003`, and stores its files under ignored `.local/postgresql18/`.

## Provision the binaries

On Ubuntu 22.04 amd64, run `scripts/fetch-postgres18`. It downloads the PostgreSQL 18.6 server, client, and libpq packages from the official PGDG repository, verifies the repository signing-key fingerprint, and extracts the packages into `.local/` without modifying system packages or running their installation scripts.

This installer is deliberately limited to Ubuntu 22.04 amd64 and PostgreSQL 18.6 package version `18.6-1.pgdg22.04+2`. Update the pinned version and verify the official repository metadata before changing it.

## Initialize and run the development cluster

```bash
./scripts/dev-postgres version
./scripts/dev-postgres init
./scripts/dev-postgres start
./scripts/bootstrap-dev-db
./scripts/dev-postgres ready
```

`init` refuses to replace any existing data directory. The bootstrap installs `btree_gist` for the period exclusion constraint and `pgcrypto` for database-side SHA-256 validation, both in the owner-controlled `jw_support` schema. Migrations verify the expected extension schema and interfaces before relying on them.

The cluster uses trusted loopback authentication for the local synthetic fixture. It is not an acceptable production authentication mode and does not prove that a hostile local process cannot select another database role.

Useful local commands:

```bash
./scripts/dev-postgres status
./scripts/dev-postgres psql -d journalwick -c 'select current_user, version()'
./scripts/dev-postgres stop
```

The API runtime URL in `.env.example` contains no password and is intended only for this trusted local fixture. Environment loading remains explicit; source no secrets or real provider credentials in `.env.example`.

## Standard container setup

The Day 03 baseline also specifies `infra/compose.dev.yaml` with a dedicated PostgreSQL 18 image/volume. That path remains to be authored and verified. Do not substitute an unrelated portfolio database or remove this fixture's files with `down -v`.
