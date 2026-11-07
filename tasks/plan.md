# Journalwick implementation plan

## Objective

Implement the complete reviewed Day 03 baseline in this user-selected workspace. Preserve the contract's full scope and prove each claim with the evidence defined in the 68-scenario gate.

## Stack

- Python 3.12 package managed by `uv`.
- FastAPI/Uvicorn, Pydantic settings/DTOs, Psycopg 3 connection pools, and explicit SQL migrations/functions.
- PostgreSQL 18 with isolated synthetic development fixture; managed PostgreSQL/IAM/TLS for the release reference.
- React/TypeScript console using Vite, React Router, TanStack Query, Zod, generated API types, Playwright, and axe.
- Cryptography/WebAuthn and provider SDKs are version-locked and used only at their documented boundaries.

Resolve and record actual dependency versions in `uv.lock` and `apps/console/package-lock.json`; do not guess versions in advance.

## Dependency-ordered delivery

1. **Repository and contract:** local workspace ADR, source-to-scope mapping, project instructions, app/package identities, dependency locks, local commands.
2. **Platform and DB:** typed settings/errors/redaction, bounded role-specific pools, unit-of-work, migration checksum runner, PostgreSQL roles/schemas, protected function boundary.
3. **Identity and governance:** passkey ceremony/session/CSRF, one-time bootstrap, recovery, current role and organization/book scoping, currency/account/period setup.
4. **Financial kernel:** canonical operation identities, typed/versioned template grammar, proposals and distinct approvals, journal acceptance, immutable projection and sequences, operation-level spend controls.
5. **Funds workflows:** reservations, partial captures/releases, allocation tree, evidence-linked resolution, corrections, FX, restrictions and period close controls.
6. **First full-stack slice:** console/API/database flow for setup, opening balance, `8000` hold, `5000` capture, `3000` release, exact balances, and safe rejection/retry/conflict states.
7. **Provider boundary:** synthetic profile first, durable outbox and worker fencing, lost-response/unknown-state recovery, verified Stripe/Paystack evidence profiles where actual capability exists.
8. **Reconciliation and losses:** safe statement staging/import, deterministic matching, cases and review, refunds, disputes, fees, settlement and financial-loss workflows.
9. **History and reporting:** scoped readers, reconstruction, immutable audit/revisions, consistent report snapshots, encrypted requester-bound export and retention.
10. **Console completion:** task-based routes for every role, exact string money, current/historical context, responsive and accessible conflict/unknown/unavailable states.
11. **Release and recovery:** image, independent API/worker/migration/recovery identities, Terraform, managed DB/KMS/secret references, runbooks, backup restore, stale authority quarantine, projection rebuild and rollback.
12. **Acceptance and handoff:** execute every applicable blocking gate, record actual pass/fail/not_run/blocked evidence, reconcile README/architecture/demo claims with observed scope.

## High-risk decisions to prove early

- PostgreSQL 18 is required for the selected development baseline; Docker and PostgreSQL tools are absent on the inspected host. Resolve an approved local runtime before database work.
- Financial acceptance uses book-level serialization. No speed claim is made without a measured workload.
- Authorization freshness must be rechecked after lock waits; an accepted result retry is not a new write.
- External provider outcomes can be unknown. Never resend or free exposure based only on timeout, age, or absent lookup data.
- A browser/backend process compromise remains beyond the database function barrier's identity guarantee; state this limit accurately.
- Provider sandbox, public release, cloud restore, and actual recovery capabilities may require real operator credentials/resources; do not simulate their evidence.

## Checkpoints

- Checkpoint A: clean project bootstrap, package identities, current locked versions, and isolated database runtime are reproducible.
- Checkpoint B: actual DB roles/functions deny protected direct DML; exact posting and failed neighboring cases are atomic.
- Checkpoint C: one operator and a distinct reviewer can complete the first account/reservation slice through the browser.
- Checkpoint D: synthetic provider uncertainty, duplicate/reordered observations, and evidence-linked reconciliation are actionable without another financial authority.
- Checkpoint E: reporting and export boundaries, role scopes, recovery/quarantine procedures, and release identities are evidenced.
- Checkpoint F: all applicable blocking Day 03 acceptance declarations have actual evidence or a precise blocked/not_run reason; no missing baseline behavior is hidden by the demo.

## Source mapping

Use `Implementation/Day-03-Journalwick/chapters/71-ordered-file-and-feature-implementation-work-packages.md` for the detailed 29 package sequence, `70` for setup, `80–84` for operations/recovery, and `90-acceptance-scenarios-and-evidence.md` plus `gate.json` for completion.
