# Database invariants implemented so far

This inventory covers migrations `0001` through `0003` only. The rest of the Day 03 schema and the guarded financial functions are still open; this file is not a claim that the database baseline is complete.

## Migration authority

| Invariant | Enforcement |
|---|---|
| Migrations come from the reviewed, contiguous ID prefix. | `src/journalwick/migrations/manifest.py` and `discover_migrations()` reject unknown IDs and gaps. |
| Previously applied files must retain their exact SHA-256 checksum. | `apply_migrations()` validates every recorded migration before applying pending files. |
| Schema application is serialized and all-or-nothing per migration. | PostgreSQL advisory lock plus one transaction per file, including its `jw.schema_migrations` success record. |
| Only the trusted migrator session may record migration success. | `jw_private.require_migrator_identity_v1()` requires `session_user = journalwick_migrator` and `current_user = journalwick_kernel_owner`. |
| Ordinary roles cannot edit or truncate migration history. | Immutable row and truncate triggers on `jw.schema_migrations`; runtime roles receive read-only status access. |

## Identity, organization, and audit foundations

| Invariant | Enforcement |
|---|---|
| A human-user row can refer only to a human principal. | Generated `principal_kind` plus composite FK to `jw.principals(id, kind)`. |
| Authenticators and browser sessions belong to human principals. | Generated constant kind columns and composite principal FKs. |
| Organization members and owners are human identities. | Composite principal-kind FKs on memberships and owner grantors. |
| Owner assignment stays in the membership's organization. | Composite FK to `jw.organization_memberships(id, organization_id)`. |
| Only one active owner assignment exists per membership. | Partial unique index `organization_owner_assignments_active_membership_uq`. |
| Browser enrollment stores proof digests, has bounded attempts/lifetime, and binds target, organization, approver path, and trusted operator evidence. | `jw.enrollment_requests` checks and FKs. |
| Trusted operator and ordinary audit events are immutable. | Row and truncate triggers using `jw_private.reject_immutable_row_v1()`. |
| Audit actor type matches its principal or trusted operator event. | Actor-reference check plus composite principal-kind FK. |

## Books, currencies, accounts, and setup

| Invariant | Enforcement |
|---|---|
| Book identity remains tied to its organization and UTC accounting timezone. | Composite book/organization keys, UTC check, and `books_identity_immutable` trigger. |
| Financial and evidence boundaries are separate per-book rows. | `jw.book_financial_state` and `jw.book_evidence_state`; financial counters and evidence epochs have independent fields. |
| Currency codes are three uppercase ASCII letters, versions are positive, exponents are 0–6, and retired definitions retain their meaning. | `jw.currency_definitions` checks and `currency_definitions_immutable_meaning` trigger. |
| Each currency code has at most one selected default, and it must reference an active definition. | Primary key on `jw.currency_definition_defaults.code` and `currency_defaults_require_active_definition` trigger. |
| Account-template currency eligibility is relational and versioned. | `jw.account_template_currencies` composite primary key and exact template-version/currency FKs. |
| Published template accounting meaning and currency eligibility cannot be edited. | `account_templates_immutable_after_publication` and `account_template_currencies_draft_only` triggers. |
| Account meaning matches the exact selected template version and eligible currency. | Composite template-identity and eligibility FKs on `jw.accounts`. |
| Active account book, code, currency, template, classification, normal side, and spend policy stay fixed. | `accounts_identity_retained` trigger plus scoped unique/FK constraints. |
| Account balances do not have a writable opening-balance field. | `jw.accounts` contains no `opening_balance`; `jw.account_financial_state` starts with exact zero totals. Opening entries must be implemented through later accepted journal workflows. |
| A reviewer assignment cannot cross organization/book scope. | Composite book/organization and membership/organization FKs on `jw.book_role_assignments`. |
| Review, template, and restriction history cannot be silently rewritten or reactivated. | Append-only transition triggers and partial uniqueness for active role/restriction rows. |
| Accounting periods use start-inclusive/end-exclusive ranges and cannot overlap within a book. | GiST exclusion `accounting_periods_no_overlap` using the verified `jw_support.gist_uuid_ops` class from the `btree_gist` extension. |
| Runtime, worker, and reporter roles cannot create schema objects or directly write these tables. | No table DML grants; explicit revocation of `CREATE` on application/support schemas and `public`. |

## Operations, retries, proposals, and approvals

| Invariant | Enforcement |
|---|---|
| One business identity per book/namespace/key, with its intent hash retained. | `business_operations_book_business_identity_unique`; immutable identity columns and versioned state updates. |
| A step is identified once within its operation and cannot be changed after acceptance. | `operation_steps_operation_key_unique`, scoped operation FK, result-kind/state checks, and `operation_steps_admit_once`. |
| One retry key exists per actor/book/command family; the raw key is not stored. | `command_receipts_scoped_key_unique` stores only 32-byte digests; accepted results become immutable. |
| One recognized economic fact is recorded for its book/source/object/kind/version identity. | `economic_recognitions_identity_unique`; update, delete, and truncate guards. |
| Posting template payloads and proposal versions remain immutable after creation/publication. | Version/hash constraints and row triggers; proposal current-version FK is deferred and must resolve by commit. |
| Each operation step has at most one proposal; a proposal version is bound to the same-book template version and accounting period. | `posting_proposals_one_per_step` and composite proposal/template/period FKs. |
| An approval binds the exact proposal version/hash, book organization, human reviewer membership version, and approval class. | Composite version/hash and organization/membership FKs; unique reviewer/class key; one-way revocation trigger. |

## Verification boundary

The migrations were applied to an isolated PostgreSQL 18.6 verification database. Targeted negative checks observed cross-organization assignment refusal, mismatched template accounting meaning and ineligible currency refusal, active currency/template/account immutability, bounded setup approval expiry, duplicate active restriction refusal, and a concurrent overlapping-period insert failing with SQLSTATE `23P01`. Operation/proposal checks also confirmed request-key uniqueness, unique economic-recognition identity, exact proposal-hash binding, immutable accepted receipts/versions, and one-way approval revocation. Runtime table writes and `CREATE` on support/public schemas were denied. The isolated verification database is local synthetic evidence only.

Migrations `0001`–`0003` are applied to the primary local `journalwick` database from source revisions `424c697035caedde3a8ca5643dfa89366c1d2179`, `9b25ae3ed821880f5dea975291968ea46bf611ce`, and `76093b3e5f3883ca8e32b3972a958b28d2d90326`. The remaining migrations, financial kernel, passkey/API flows, provider workflows, reporting, deployment, and recovery controls are not covered by these checks. All 68 source acceptance scenarios remain `not_run` until their defined evidence is collected.
