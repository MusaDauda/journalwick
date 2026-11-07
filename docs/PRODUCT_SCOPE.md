# Product scope

## Objective

Build an independently deployable, multi-currency accounting ledger and reconciliation product. Operators use it to record financial intent, exact balanced journals, reserved funds, verified external evidence, and exception workflows through a usable finance console.

## People and jobs

| Role | Primary job |
|---|---|
| Finance operator | Prepare supported commands, inspect books/accounts/journals, and investigate outcomes |
| Reviewer | Independently review the exact proposal, amount, evidence, and current authority before approval |
| Integration engineer | Configure provider evidence and investigate retries, unknown outcomes, and source mismatches |
| Auditor | Inspect bounded history, reports, evidence boundaries, and export results without posting money |
| Organization governor | Manage memberships and setup without automatically receiving book-level financial authority |

## Baseline capabilities

- Standalone organization/book governance and passkey-native human sessions.
- Versioned currencies, accounts, templates, periods, and reviewed opening balances.
- Identified operations, idempotent retries, safe result recovery, typed posting proposals, independent review, and immutable balanced journals.
- Corrections, reservations, partial capture/release, provider allocations, FX, fees, and explicit limits on unresolved external exposure.
- Synthetic provider mode plus concrete Stripe and Paystack evidence profiles, verified observations, durable outbox processing, refund/dispute workflows, and statement reconciliation.
- A task-oriented finance console with scoped navigation, exact money entry, current/historical boundary labels, clear stale/conflict/unknown/unavailable states, and keyboard-accessible workflows.
- Bounded reports, append-only audit history, encrypted requester-bound exports, period close, operating runbooks, and protected recovery/projection-rebuild workflows.

The authoritative behavior is specified in Day 03 chapters `00–90` and `gate.json`. The handbook review confirms 68 blocking application scenarios remain `not_run`; it does not claim a built, tested, deployed, or certified product.

## Non-goals and limits

- This project is the finance product itself, not a public personal-portfolio landing page.
- It does not depend on Stripe, Paystack, Keyrill, or another portfolio service at startup.
- The portfolio fixture does not establish actual provider sandbox access, production financial operations, regulatory certification, profitability, or high availability.
- Do not add AI transaction approval, automated account balancing, direct provider movement, or other financial authority beyond the reviewed contracts.
- The initial design deliberately accepts book-level commit serialization and a single API/worker-host availability boundary. Any optimization needs evidence and a reviewed change to the contract.

## Modern implementation choices

The source baseline already calls for current Python/TypeScript tools, strict API contracts, passkeys, exact amount handling, durable asynchronous provider workflows, query-cache scope partitioning, accessible console behavior, encrypted exports, managed database identity, and protected recovery. The project will use maintained dependencies and reproducible locks, then add only user-facing improvements that preserve those financial boundaries.
