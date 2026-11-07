# Decision 0002: Use one transactional modular monolith

**Status:** Accepted baseline

## Context

Journal posting, reservation state, available-funds constraints, and per-book sequence boundaries must change atomically. Provider calls and report/import work have different latency and failure behavior and cannot hold financial locks.

## Decision

Keep the initial API, worker, and database migrations in one independently deployable product with explicit module ownership. PostgreSQL guarded functions own financial acceptance. Provider I/O, parsing, and report construction happen outside the financial transaction.

## Consequences

- Each route is scoped to one application capability and invokes explicit typed operations.
- Runtime roles cannot directly change protected financial tables.
- A per-book serialization lock is an accepted initial limit; any finer-grained scheme needs equivalent invariant evidence and measured workload data.
- The API and worker can use separate runtime identities while sharing the approved schema and durable outbox.

The decision follows the reviewed Day 03 architecture contract and may be revisited only with coherent proof that its atomicity properties remain intact.
