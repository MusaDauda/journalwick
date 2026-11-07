# Journalwick

Journalwick is a standalone, multi-currency ledger and reconciliation product for finance operators, reviewers, integration engineers, and auditors. It makes accepted financial state exact, inspectable, and safe under retries, concurrency, and uncertain provider outcomes.

This repository is the application workspace selected by the user: `/home/musa/Documents/portfolio-projects/journalwick`. Its reviewed Day 03 build contract is maintained separately in `/home/musa/Documents/github-legend/Implementation/Day-03-Journalwick/`.

## Status

The project scope, architecture, and design are mapped. The first API liveness route and synthetic finance overview are implemented. The baseline defines 68 blocking acceptance scenarios; all remain `not_run` until actual scoped evidence is recorded.

The Python package, application import, CLI identity, console production build, console lint, and Python type/lint checks have passed. The local health route responds directly and through the same-origin Vite proxy. No database-backed behavior is implemented or accepted yet.

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

The Day 03 baseline assigns the API to `127.0.0.1:8003`, the console to `http://localhost:5203`, and a dedicated PostgreSQL 18 development database to `127.0.0.1:55003`. Current host inspection found Python 3.12 available through uv and Node 24 installed; PostgreSQL client/server tools, Docker, and Terraform were not present. Recheck ports and prerequisites before starting local services.

## Build status

See `tasks/todo.md`. Do not treat a starter screen, synthetic provider fixture, successful frontend build, or documentation check as acceptance of the ledger or a release.
