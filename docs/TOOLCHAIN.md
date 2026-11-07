# Toolchain and host prerequisites

Inspected on 2026-11-07. Historical version numbers in this file are a record of this setup pass; the committed lockfiles are the reproducible source for dependency resolution.

## Resolved local toolchain

| Tool | Selected version | Notes |
|---|---:|---|
| Python | 3.12.14 | Provisioned by uv; system Python is 3.10.12 |
| uv | 0.12.17 | Python package, lock, and environment manager |
| Node.js | 24.19.0 | Current supported Vite runtime |
| npm | 11.17.0 | Pinned in the console package metadata |
| Vite | 8.3.6 | Vite's current guide requires Node 20.19+ or 22.12+; Node 24.19 satisfies it |
| React / React DOM | 19.3.1 | Created from the current React TypeScript Vite template |
| TypeScript | 5.9.3 | Selected because `openapi-typescript` declares a TypeScript 5.x peer range; avoid bypassing npm's peer check |
| TanStack Query | 5.107.1 | Scoped async query state |
| React Router | 7.18.5 | Console navigation |
| Zod | 4.6.7 | Runtime validation of untrusted API data |
| OpenAPI TypeScript | 7.13.0 | Generated API types from the actual FastAPI OpenAPI schema |
| FastAPI | 0.162.2 | API and OpenAPI source |
| Psycopg / pool | 3.3.8 / 3.3.3 | PostgreSQL adapter and bounded connection pools |
| PostgreSQL target | 18 | Required by the Day 03 development baseline; server/client tools are not installed yet |

`apps/console/package-lock.json` and `uv.lock` record the complete resolved dependency graphs. npm installs used `--ignore-scripts`; dependency lifecycle scripts have not been run.

## Host findings

- `python3` is 3.10.12, but uv already has CPython 3.12.14 available and uses that for this project.
- `node` is 24.19.0 and `npm` is 11.17.0.
- `psql`, `pg_isready`, Docker, Podman, and Terraform were not found on `PATH`.
- No listener was present on the planned API `8003`, console `5203`, or PostgreSQL `55003` ports during the initial inspection.
- The filesystem had 3.1 GB free at 97% usage before package installation and about 2.3 GB free afterward. Recheck before downloading a PostgreSQL image, browser, or release toolchain.
- Memory was 15 GiB total with 3.9 GiB available at inspection.

The console can be built without a database, but that does not establish backend readiness or financial acceptance. Resolve an isolated PostgreSQL 18 runtime before schema, transaction, and database-role work. Do not stop an unidentified service or remove another project's data to free space.
