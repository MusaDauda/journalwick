# Journalwick capability map

The baseline contains several independently verifiable capabilities. Stable module identifiers below are used in the project plan and task ledger.

| Module id | Responsibility | Depends on |
|---|---|---|
| `platform` | Typed settings, safe errors, database pools, units of work, clocks, identifiers, redaction, telemetry | — |
| `access` | Passkey sessions, enrollment/recovery, current principal, membership and action authorization | `platform` |
| `governance` | Organizations, books, currencies, accounts, periods, configuration versions, setup activation | `platform`, `access` |
| `posting-kernel` | Operation identity, canonical request hashes, proposals, approvals, templates, immutable journal acceptance | `platform`, `access`, `governance` |
| `funds-control` | Reservations, captures/releases, allocations, restrictions, FX, fees, period controls | `posting-kernel`, `governance` |
| `provider-evidence` | Source account profiles, Stripe/Paystack adapters, verified observations, provider-attempt identity | `platform`, `governance`, `posting-kernel` |
| `delivery` | Durable outbox claims, leases, dispatch uncertainty, safe retries, worker lifecycle | `provider-evidence`, `funds-control` |
| `reconciliation` | Statement staging/import, matching, cases, evidence-based resolutions | `provider-evidence`, `posting-kernel`, `funds-control` |
| `reporting` | Scoped reads, history, snapshot reconstruction, audit, encrypted exports | `governance`, `posting-kernel`, `funds-control`, `reconciliation` |
| `console` | React/TypeScript operator, reviewer, integration, auditor, and governor journeys | Public API contracts for all user-facing modules |
| `operations` | Release image, migration identity, managed database access, runbooks, restore and cutover controls | `platform`, `delivery`, `reporting` |

## Dependency order

```text
platform
  └── access ── governance
                   └── posting-kernel
                        ├── funds-control
                        ├── provider-evidence ── delivery
                        └── reconciliation
                             └── reporting
                                  └── operations and release

Console journeys are delivered vertically as each public API capability becomes ready.
```

The console is not a second authority. Provider adapters create verified facts and instructions; they cannot write journal rows directly. Reporting reads accepted state but cannot repair it. All consequential mutations converge on the restricted PostgreSQL kernel.

## First integrated slice

The first end-to-end finance journey will create a synthetic organization/book, configure one currency and spendable account, accept a reviewed opening journal, reserve `8000` integer minor units, capture `5000`, release `3000`, then show posted and available amounts at their actual sequence boundaries. It will include insufficient-funds, stale-review, self-approval, duplicate-capture, and lost-response outcomes before later provider and reconciliation capabilities are enabled.

## Delivery and verification

The [implementation plan](../tasks/plan.md) orders the work by dependency. The [task tracker](../tasks/todo.md) records unfinished behavior, and the [acceptance checklist](acceptance/gate.json) defines the required evidence for each scenario.
