"""Baseline schema identities used by the migrator and runtime readiness check."""

MIGRATION_IDS = (
    "0001_identity_organization_and_audit",
    "0002_books_currencies_accounts_and_periods",
    "0003_operations_proposals_and_approvals",
    "0004_journals_postings_and_financial_kernel",
    "0005_reservations_allocations_and_events",
    "0006_provider_attempts_observations_and_outbox",
    "0007_reconciliation_fx_and_reporting",
    "0008_final_constraints_privileges_and_retention",
)

REQUIRED_KERNEL_FUNCTIONS = (
    "admit_operation_v1",
    "activate_reservation_v1",
    "cancel_pending_reservation_v1",
    "allocate_reservation_v1",
    "post_proposal_v1",
    "capture_reservation_v1",
    "release_reservation_v1",
    "expire_reservation_v1",
    "resolve_allocation_v1",
    "reverse_journal_v1",
    "restrict_funds_v1",
    "release_funds_restriction_v1",
    "execute_fx_v1",
)
