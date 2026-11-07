# Journalwick task tracker

Every item stays open until the named behavior exists in this repository and has the scoped evidence required by the Day 03 gate. A local synthetic fixture never passes a live-provider or deployment check.

## M0 — Scope and product design

- [x] Record user-selected workspace and preserve the handbook repository.
- [x] Map the baseline capabilities, dependency order, architecture, and console design direction.
- [x] Keep this scope aligned with the 68-scenario source gate.

## M1 — Reproducible independent repository

- [x] Create Python 3.12 `uv` package and lock; verify import/package/CLI identity.
- [x] Create React/TypeScript console and npm lock using supported Node 24/Vite versions.
- [ ] Finish safe settings profiles and log redaction; environment example and no-secret gitignore rules are present.
- [x] Add local API/console ports and strict same-origin development proxy.
- [x] Resolve an isolated PostgreSQL 18.6 local runtime and dedicated `journalwick` database under `.local/`.

## M2 — Database foundation and migration authority

- [ ] Implement typed DB settings, role-specific pools, transaction ownership, and safe diagnostics.
- [x] Implement migration IDs/checksums/status/locking and checksum refusal.
- [x] Create restrictive development roles and `jw`, `jw_api`, `jw_private`, `jw_support` schemas.
- [ ] Implement baseline schema and foreign-key/constraint inventory through reviewed migrations.
- [ ] Verify runtime/worker/reporter/recovery grants and direct-DML/private-function denials.

## M3 — Independent access and governance

- [ ] Implement first-owner bootstrap, passkey enrollment/assertion verification, sessions, CSRF, origin, and session revocation.
- [ ] Implement organization governance separately from financial book roles.
- [ ] Implement scoped capabilities, creator/reviewer separation, role revocation freshness, and audit events.
- [ ] Implement immutable currencies/accounts/templates/periods/setup manifest and reviewed activation/opening balance.

## M4 — Financial kernel and first integrated slice

- [ ] Implement exact amount parsing and versioned currency units across Python, SQL, API, and TypeScript.
- [ ] Implement canonical idempotency bytes/hashes, operation receipts, accepted retry recovery, and payload-conflict behavior.
- [ ] Implement typed template parsing and database-authoritative expansion.
- [ ] Implement proposals, current approval validation, atomic balanced journals, per-book sequences, and projection reconstruction.
- [ ] Implement spending predicates, reservations, partial captures/releases, allocation conservation, and safe expiry.
- [ ] Deliver the first setup/opening/reserve/capture/release journey end to end through the console.

## M5 — Provider and reconciliation workflows

- [ ] Implement provider attempts, durable outbox, lease/fence transitions, and synthetic provider profile.
- [ ] Implement verified, minimized Stripe/Paystack observations and provider unit conversion.
- [ ] Implement unknown outcome, lookup, retry, duplicate, out-of-order evidence, and original instruction identity behavior.
- [ ] Implement bounded statement staging/import, deterministic matching, reconciliation runs/cases/resolutions.
- [ ] Implement FX, fees, refunds, disputes, settlement distinctions, corrections, and financial loss handling.

## M6 — Reports, console, and operations

- [ ] Complete all role-appropriate console screens, including empty/stale/conflict/unknown/unavailable states.
- [ ] Implement report snapshots, explicit historical boundaries, append-only audit/history, and encrypted export retention.
- [ ] Implement close preparation/review/abandon/strict close.
- [ ] Add measured health/queue behavior, runbooks, immutable image, and source/image/schema release identity.
- [ ] Add managed database IAM/TLS and separate API/worker/migration/recovery deployment identities.
- [ ] Add protected backup restore, stale authority quarantine, external dispatch inventory, projection rebuild, and rollback drills.

## M7 — Acceptance and handoff

- [ ] Work through Day 03 A01–A68. Store sanitized observation records under `docs/acceptance/`.
- [ ] Mark external/provider/deployment/recovery evidence blocked or not_run when required capability is absent.
- [ ] Align README, architecture decisions, demonstration script, and claims to actual observed behavior.
- [ ] Do not call the baseline finished while required behavior is missing or required evidence is unexecuted.
